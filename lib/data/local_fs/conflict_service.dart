import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/file_hash.dart';
import '../../core/file_system_utils.dart';
import '../../core/markdown_front_matter.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/sync_conflict.dart';
import '../../domain/entities/sync_conflict_detail.dart';
import 'chronicle_layout.dart';
import 'chronicle_storage_initializer.dart';
import 'note_file_codec.dart';
import 'storage_root_locator.dart';

class ConflictService {
  ConflictService({
    required StorageRootLocator storageRootLocator,
    required ChronicleStorageInitializer storageInitializer,
    required FileSystemUtils fileSystemUtils,
  }) : _storageRootLocator = storageRootLocator,
       _storageInitializer = storageInitializer,
       _fileSystemUtils = fileSystemUtils;

  final StorageRootLocator _storageRootLocator;
  final ChronicleStorageInitializer _storageInitializer;
  final FileSystemUtils _fileSystemUtils;
  static const NoteFileCodec _noteCodec = NoteFileCodec();

  Future<List<SyncConflict>> listConflicts() async {
    final layout = await _layout();
    final files = await _fileSystemUtils.listFilesRecursively(
      layout.rootDirectory,
    );

    final conflicts = <SyncConflict>[];
    for (final file in files.where(_isConflictFile)) {
      try {
        final resolved = await _readConflictFile(layout, file);
        if (resolved != null) {
          final detail = await _buildConflictDetail(
            layout: layout,
            conflictFile: file,
            resolved: resolved,
          );
          if (detail != null && !detail.hasActualDiff) {
            await _fileSystemUtils.deleteIfExists(file);
            continue;
          }
          conflicts.add(resolved.summary);
        }
      } catch (_) {
        continue;
      }
    }

    conflicts.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    return conflicts;
  }

  Future<SyncConflictDetail?> readConflictDetail(String conflictPath) async {
    final layout = await _layout();
    final file = layout.fromRelativePath(conflictPath);
    if (!await file.exists()) {
      return null;
    }

    final resolved = await _readConflictFile(layout, file);
    if (resolved == null) {
      return null;
    }

    return _buildConflictDetail(
      layout: layout,
      conflictFile: file,
      resolved: resolved,
    );
  }

  Future<String?> readConflictContent(String conflictPath) async {
    if (!_isTextConflictFile(conflictPath)) {
      return null;
    }

    final layout = await _layout();
    final file = layout.fromRelativePath(conflictPath);
    if (!await file.exists()) {
      return null;
    }

    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasMatchingConflict({
    required String originalPath,
    required String localContentHash,
    required String remoteContentHash,
  }) async {
    final layout = await _layout();
    final files = await _fileSystemUtils.listFilesRecursively(
      layout.rootDirectory,
    );
    final expectedFingerprint = buildSyncConflictFingerprint(
      originalPath: originalPath,
      localContentHash: localContentHash,
      remoteContentHash: remoteContentHash,
    );

    for (final file in files.where(_isConflictFile)) {
      final resolved = await _readConflictFile(layout, file);
      if (resolved == null || resolved.summary.originalPath != originalPath) {
        continue;
      }

      final candidateLocalHash =
          resolved.localSnapshot?.rawContentHash ??
          _readMetadataString(resolved.metadata, 'localContentHash');
      final candidateRemoteHash =
          _readMetadataString(resolved.metadata, 'remoteContentHash') ??
          await _readOriginalFileHash(layout, originalPath);
      final candidateFingerprint =
          _readMetadataString(resolved.metadata, 'conflictFingerprint') ??
          (candidateLocalHash != null &&
                  candidateRemoteHash != null &&
                  candidateRemoteHash.isNotEmpty
              ? buildSyncConflictFingerprint(
                  originalPath: originalPath,
                  localContentHash: candidateLocalHash,
                  remoteContentHash: candidateRemoteHash,
                )
              : null);

      if (candidateFingerprint == expectedFingerprint) {
        return true;
      }
      if (candidateLocalHash == localContentHash &&
          candidateRemoteHash == remoteContentHash) {
        return true;
      }
    }
    return false;
  }

  Future<void> resolveConflict(
    String conflictPath, {
    required SyncConflictResolutionChoice choice,
  }) async {
    final layout = await _layout();
    final conflictFile = layout.fromRelativePath(conflictPath);
    if (!await conflictFile.exists()) {
      return;
    }

    if (choice == SyncConflictResolutionChoice.acceptLeft) {
      final resolved = await _readConflictFile(layout, conflictFile);
      if (resolved != null) {
        final target = layout.fromRelativePath(resolved.summary.originalPath);
        if (resolved.localSnapshot != null &&
            _isTextConflictFile(conflictPath)) {
          await _fileSystemUtils.atomicWriteString(
            target,
            resolved.localSnapshot!.rawContent,
          );
        } else {
          final bytes = await conflictFile.readAsBytes();
          await _fileSystemUtils.atomicWriteBytes(target, bytes);
        }
      }
    }

    await _fileSystemUtils.deleteIfExists(conflictFile);
  }

  bool _isConflictFile(File file) {
    final name = p.basename(file.path);
    return name.contains('.conflict.');
  }

  bool _isTextConflictFile(String path) {
    return path.endsWith('.md') || path.endsWith('.json');
  }

  Future<_ResolvedConflictFile?> _readConflictFile(
    ChronicleLayout layout,
    File file,
  ) async {
    final relative = layout.relativePath(file);
    if (_isTextConflictFile(relative)) {
      final raw = await file.readAsString();
      final parsed = _parseConflictContent(relative, raw);
      final originalPath = _inferOriginalPath(relative, parsed.metadata);
      final conflictType = _deriveType(
        conflictPath: relative,
        metadata: parsed.metadata,
        originalPath: originalPath,
      );
      final detectedAt = await _resolveDetectedAt(file, parsed.metadata);
      final localSnapshot = _buildLocalSnapshot(
        conflictPath: relative,
        originalPath: originalPath,
        conflictType: conflictType,
        parsed: parsed,
      );

      final title =
          localSnapshot?.title ??
          _fallbackConflictTitle(
            conflictPath: relative,
            originalPath: originalPath,
            type: conflictType,
          );
      final preview =
          localSnapshot?.preview ??
          _fallbackConflictPreview(type: conflictType);

      return _ResolvedConflictFile(
        summary: SyncConflict(
          type: conflictType,
          conflictPath: relative,
          originalPath: originalPath,
          detectedAt: detectedAt,
          localDevice:
              _readMetadataString(parsed.metadata, 'localDevice') ?? 'unknown',
          remoteDevice:
              _readMetadataString(parsed.metadata, 'remoteDevice') ?? 'unknown',
          title: title,
          preview: preview,
        ),
        metadata: parsed.metadata,
        localSnapshot: localSnapshot,
      );
    }

    final stat = await file.stat();
    final originalPath = _inferOriginalPath(
      relative,
      const <String, dynamic>{},
    );
    return _ResolvedConflictFile(
      summary: SyncConflict(
        type: SyncConflictType.unknown,
        conflictPath: relative,
        originalPath: originalPath,
        detectedAt: stat.modified.toUtc(),
        localDevice: 'unknown',
        remoteDevice: 'unknown',
        title: _fallbackConflictTitle(
          conflictPath: relative,
          originalPath: originalPath,
          type: SyncConflictType.unknown,
        ),
        preview: _fallbackConflictPreview(type: SyncConflictType.unknown),
      ),
      metadata: const <String, dynamic>{},
      localSnapshot: null,
    );
  }

  String _inferOriginalPath(
    String relativePath,
    Map<String, dynamic> metadata,
  ) {
    final fromMetadata = metadata['originalPath'] as String?;
    if (fromMetadata != null && fromMetadata.trim().isNotEmpty) {
      return fromMetadata.trim();
    }

    final marker = '.conflict.';
    final index = relativePath.indexOf(marker);
    if (index == -1) {
      return relativePath;
    }
    final prefix = relativePath.substring(0, index);
    final ext = p.extension(relativePath);
    if (ext.isNotEmpty && !prefix.endsWith(ext)) {
      return '$prefix$ext';
    }
    return prefix;
  }

  SyncConflictType _deriveType({
    required String conflictPath,
    required Map<String, dynamic> metadata,
    required String originalPath,
  }) {
    final metadataType = (metadata['conflictType'] as String?)?.trim();
    if (metadataType != null && metadataType.isNotEmpty) {
      final normalized = metadataType.toLowerCase();
      if (normalized == 'note') {
        return SyncConflictType.note;
      }
      if (normalized == 'link') {
        return SyncConflictType.link;
      }
    }

    if (originalPath.startsWith('links/') ||
        originalPath.endsWith('.json') ||
        conflictPath.endsWith('.json')) {
      return SyncConflictType.link;
    }
    if (originalPath.endsWith('.md') || conflictPath.endsWith('.md')) {
      return SyncConflictType.note;
    }
    return SyncConflictType.unknown;
  }

  String _fallbackConflictTitle({
    required String conflictPath,
    required String originalPath,
    required SyncConflictType type,
  }) {
    if (type == SyncConflictType.link) {
      final base = p.basenameWithoutExtension(originalPath);
      return base.isEmpty ? 'Link conflict' : 'Link: $base';
    }

    final base = p.basenameWithoutExtension(originalPath);
    if (base.isNotEmpty) {
      return base;
    }

    return p.basenameWithoutExtension(conflictPath);
  }

  String _fallbackConflictPreview({required SyncConflictType type}) {
    if (type == SyncConflictType.link) {
      return 'Link conflict content is empty.';
    }
    if (type == SyncConflictType.unknown) {
      return 'Binary conflict file';
    }
    return 'Conflict content is empty.';
  }

  _ConflictPayload _parseConflictContent(String conflictPath, String raw) {
    if (conflictPath.endsWith('.md')) {
      final parsed = parseMarkdownWithFrontMatter(raw);
      return _ConflictPayload(metadata: parsed.frontMatter, body: parsed.body);
    }

    return _ConflictPayload(metadata: const <String, dynamic>{}, body: raw);
  }

  Future<ChronicleLayout> _layout() async {
    final root = await _storageRootLocator.requireRootDirectory();
    await _storageInitializer.ensureInitialized(root);
    return ChronicleLayout(root);
  }

  Future<DateTime> _resolveDetectedAt(
    File file,
    Map<String, dynamic> metadata,
  ) async {
    final detectedAtRaw = _readMetadataString(metadata, 'conflictDetectedAt');
    if (detectedAtRaw == null) {
      return (await file.stat()).modified.toUtc();
    }
    return DateTime.tryParse(detectedAtRaw)?.toUtc() ??
        (await file.stat()).modified.toUtc();
  }

  _ConflictTextSnapshot? _buildLocalSnapshot({
    required String conflictPath,
    required String originalPath,
    required SyncConflictType conflictType,
    required _ConflictPayload parsed,
  }) {
    if (conflictType == SyncConflictType.note) {
      final rawNote = _normalizeCapturedNotePayload(
        _extractOriginalNotePayload(
          originalPath: originalPath,
          body: parsed.body,
        ),
      );
      final note = _tryDecodeNote(rawNote);
      final title = (note?.title.trim().isNotEmpty ?? false)
          ? note!.title.trim()
          : _fallbackConflictTitle(
              conflictPath: conflictPath,
              originalPath: originalPath,
              type: conflictType,
            );
      final displayContent = note == null
          ? rawNote
          : _formatNoteDisplay(title: note.title, content: note.content);
      final previewSource = note?.content ?? displayContent;
      return _ConflictTextSnapshot(
        rawContent: rawNote,
        displayContent: displayContent,
        rawContentHash:
            _readMetadataString(parsed.metadata, 'localContentHash') ??
            sha256ForString(rawNote),
        title: title,
        preview: _previewText(previewSource),
      );
    }

    if (conflictType == SyncConflictType.link) {
      final displayContent = _prettyJson(parsed.body);
      return _ConflictTextSnapshot(
        rawContent: parsed.body,
        displayContent: displayContent,
        rawContentHash:
            _readMetadataString(parsed.metadata, 'localContentHash') ??
            sha256ForString(parsed.body),
        title: _fallbackConflictTitle(
          conflictPath: conflictPath,
          originalPath: originalPath,
          type: conflictType,
        ),
        preview: _previewText(displayContent),
      );
    }

    if (parsed.body.trim().isEmpty) {
      return null;
    }

    return _ConflictTextSnapshot(
      rawContent: parsed.body,
      displayContent: parsed.body,
      rawContentHash: sha256ForString(parsed.body),
      title: _fallbackConflictTitle(
        conflictPath: conflictPath,
        originalPath: originalPath,
        type: conflictType,
      ),
      preview: _previewText(parsed.body),
    );
  }

  Future<_ConflictTextSnapshot?> _readCurrentSnapshot({
    required ChronicleLayout layout,
    required SyncConflict conflict,
  }) async {
    if (!conflict.isNote && !conflict.isLink) {
      return null;
    }

    final file = layout.fromRelativePath(conflict.originalPath);
    if (!await file.exists()) {
      return null;
    }

    try {
      final raw = await file.readAsString();
      if (conflict.isNote) {
        final note = _tryDecodeNote(raw);
        final displayContent = note == null
            ? raw
            : _formatNoteDisplay(title: note.title, content: note.content);
        return _ConflictTextSnapshot(
          rawContent: raw,
          displayContent: displayContent,
          rawContentHash: sha256ForString(raw),
          title: note?.title.trim().isNotEmpty == true
              ? note!.title.trim()
              : conflict.title,
          preview: _previewText(note?.content ?? displayContent),
        );
      }

      final displayContent = _prettyJson(raw);
      return _ConflictTextSnapshot(
        rawContent: raw,
        displayContent: displayContent,
        rawContentHash: sha256ForString(raw),
        title: conflict.title,
        preview: _previewText(displayContent),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readOriginalFileHash(
    ChronicleLayout layout,
    String originalPath,
  ) async {
    final file = layout.fromRelativePath(originalPath);
    if (!await file.exists()) {
      return null;
    }

    try {
      if (_isTextConflictFile(originalPath)) {
        return sha256ForString(await file.readAsString());
      }
      return await sha256ForFile(file);
    } catch (_) {
      return null;
    }
  }

  Future<SyncConflictDetail?> _buildConflictDetail({
    required ChronicleLayout layout,
    required File conflictFile,
    required _ResolvedConflictFile resolved,
  }) async {
    final currentSnapshot = await _readCurrentSnapshot(
      layout: layout,
      conflict: resolved.summary,
    );
    final remoteHashAtCapture = _readMetadataString(
      resolved.metadata,
      'remoteContentHash',
    );
    final localHash =
        resolved.localSnapshot?.rawContentHash ??
        _readMetadataString(resolved.metadata, 'localContentHash') ??
        await _safeFileHash(conflictFile);
    final currentHash =
        currentSnapshot?.rawContentHash ??
        await _readOriginalFileHash(layout, resolved.summary.originalPath);
    final fingerprint =
        _readMetadataString(resolved.metadata, 'conflictFingerprint') ??
        (localHash != null &&
                remoteHashAtCapture != null &&
                remoteHashAtCapture.isNotEmpty
            ? buildSyncConflictFingerprint(
                originalPath: resolved.summary.originalPath,
                localContentHash: localHash,
                remoteContentHash: remoteHashAtCapture,
              )
            : null);
    final originalExists = await layout
        .fromRelativePath(resolved.summary.originalPath)
        .exists();
    final hasActualDiff = await _hasActualDiff(
      layout: layout,
      conflictFile: conflictFile,
      resolved: resolved,
      currentSnapshot: currentSnapshot,
    );

    return SyncConflictDetail(
      conflict: resolved.summary,
      localContent: resolved.localSnapshot?.displayContent,
      mainFileContent: currentSnapshot?.displayContent,
      localContentHash: localHash,
      mainFileContentHash: currentHash,
      remoteContentHashAtCapture: remoteHashAtCapture,
      conflictFingerprint: fingerprint,
      originalFileMissing: !originalExists,
      mainFileChangedSinceCapture:
          remoteHashAtCapture != null &&
          remoteHashAtCapture.isNotEmpty &&
          currentHash != null &&
          currentHash != remoteHashAtCapture,
      hasActualDiff: hasActualDiff,
    );
  }

  Future<bool> _hasActualDiff({
    required ChronicleLayout layout,
    required File conflictFile,
    required _ResolvedConflictFile resolved,
    required _ConflictTextSnapshot? currentSnapshot,
  }) async {
    final originalFile = layout.fromRelativePath(resolved.summary.originalPath);
    final originalExists = await originalFile.exists();
    if (!originalExists) {
      return true;
    }

    if (resolved.summary.isNote || resolved.summary.isLink) {
      final localDisplay = resolved.localSnapshot?.displayContent;
      final currentDisplay = currentSnapshot?.displayContent;
      if (localDisplay == null || currentDisplay == null) {
        return true;
      }
      return localDisplay != currentDisplay;
    }

    try {
      final localHash = await sha256ForFile(conflictFile);
      final currentHash = await _readOriginalFileHash(
        layout,
        resolved.summary.originalPath,
      );
      if (currentHash == null) {
        return true;
      }
      return localHash != currentHash;
    } catch (_) {
      return true;
    }
  }

  Future<String?> _safeFileHash(File file) async {
    try {
      if (_isTextConflictFile(file.path)) {
        return sha256ForString(await file.readAsString());
      }
      return await sha256ForFile(file);
    } catch (_) {
      return null;
    }
  }

  String _extractOriginalNotePayload({
    required String originalPath,
    required String body,
  }) {
    final normalized = _trimLeadingBlankLines(body.replaceAll('\r\n', '\n'));
    final heading = '# [CONFLICT] $originalPath';
    if (!normalized.startsWith(heading)) {
      return normalized;
    }

    var remainder = normalized.substring(heading.length);
    remainder = _trimLeadingBlankLines(remainder);
    const explanation =
        'This file contains local changes that conflicted with a remote update.';
    if (remainder.startsWith(explanation)) {
      remainder = remainder.substring(explanation.length);
      remainder = _trimLeadingBlankLines(remainder);
    }
    return remainder;
  }

  String _normalizeCapturedNotePayload(String value) {
    if (value.endsWith('\n\n')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }

  String _trimLeadingBlankLines(String value) {
    var out = value;
    while (out.startsWith('\n')) {
      out = out.substring(1);
    }
    return out;
  }

  String _formatNoteDisplay({required String title, required String content}) {
    final trimmedTitle = title.trim();
    final trimmedContent = content.trimRight();
    if (trimmedTitle.isEmpty) {
      return trimmedContent;
    }
    if (trimmedContent.isEmpty) {
      return 'Title: $trimmedTitle';
    }
    return 'Title: $trimmedTitle\n\n$trimmedContent';
  }

  String _prettyJson(String raw) {
    try {
      final decoded = json.decode(raw);
      return const JsonEncoder.withIndent(
        '  ',
      ).convert(_sortJsonValue(decoded));
    } catch (_) {
      return raw;
    }
  }

  Object? _sortJsonValue(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
      return <String, Object?>{
        for (final entry in entries)
          '${entry.key}': _sortJsonValue(entry.value),
      };
    }
    if (value is List) {
      return value.map(_sortJsonValue).toList(growable: false);
    }
    return value;
  }

  String _previewText(String value) {
    final compact = value
        .replaceAll(RegExp(r'[#>*_\-\[\]()!]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (compact.isEmpty) {
      return 'Conflict content is empty.';
    }
    if (compact.length <= 180) {
      return compact;
    }
    return '${compact.substring(0, 180)}...';
  }

  Note? _tryDecodeNote(String raw) {
    try {
      return _noteCodec.decode(raw);
    } catch (_) {
      return null;
    }
  }

  String? _readMetadataString(Map<String, dynamic> metadata, String key) {
    final value = metadata[key];
    if (value == null) {
      return null;
    }
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }
}

class _ResolvedConflictFile {
  const _ResolvedConflictFile({
    required this.summary,
    required this.metadata,
    required this.localSnapshot,
  });

  final SyncConflict summary;
  final Map<String, dynamic> metadata;
  final _ConflictTextSnapshot? localSnapshot;
}

class _ConflictTextSnapshot {
  const _ConflictTextSnapshot({
    required this.rawContent,
    required this.displayContent,
    required this.rawContentHash,
    required this.title,
    required this.preview,
  });

  final String rawContent;
  final String displayContent;
  final String rawContentHash;
  final String title;
  final String preview;
}

class _ConflictPayload {
  const _ConflictPayload({required this.metadata, required this.body});

  final Map<String, dynamic> metadata;
  final String body;
}
