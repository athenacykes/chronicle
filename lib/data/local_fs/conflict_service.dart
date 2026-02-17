import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/file_system_utils.dart';
import '../../core/markdown_front_matter.dart';
import '../../domain/entities/sync_conflict.dart';
import 'chronicle_layout.dart';
import 'chronicle_storage_initializer.dart';
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

  Future<List<SyncConflict>> listConflicts() async {
    final layout = await _layout();
    final files = await _fileSystemUtils.listFilesRecursively(
      layout.rootDirectory,
    );

    final conflicts = <SyncConflict>[];
    for (final file in files.where(_isConflictFile)) {
      try {
        final relative = layout.relativePath(file);
        final raw = await file.readAsString();
        final parsed = _parseConflictContent(relative, raw);

        final originalPath = _inferOriginalPath(relative, parsed.metadata);
        final conflictType = _deriveType(
          conflictPath: relative,
          metadata: parsed.metadata,
          originalPath: originalPath,
        );
        final detectedAtRaw = parsed.metadata['conflictDetectedAt'] as String?;
        final detectedAt = detectedAtRaw == null
            ? (await file.stat()).modified.toUtc()
            : DateTime.tryParse(detectedAtRaw)?.toUtc() ??
                  (await file.stat()).modified.toUtc();

        final title = _deriveTitle(
          relative,
          parsed.body,
          originalPath,
          conflictType,
        );
        final preview = _derivePreview(parsed.body, conflictType);

        conflicts.add(
          SyncConflict(
            type: conflictType,
            conflictPath: relative,
            originalPath: originalPath,
            detectedAt: detectedAt,
            localDevice:
                (parsed.metadata['localDevice'] as String?) ?? 'unknown',
            remoteDevice:
                (parsed.metadata['remoteDevice'] as String?) ?? 'unknown',
            title: title,
            preview: preview,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    conflicts.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    return conflicts;
  }

  Future<String?> readConflictContent(String conflictPath) async {
    final layout = await _layout();
    final file = layout.fromRelativePath(conflictPath);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  Future<void> resolveConflict(String conflictPath) async {
    final layout = await _layout();
    final file = layout.fromRelativePath(conflictPath);
    await _fileSystemUtils.deleteIfExists(file);
  }

  bool _isConflictFile(File file) {
    final name = p.basename(file.path);
    if (!name.contains('.conflict.')) {
      return false;
    }
    return name.endsWith('.md') || name.endsWith('.json');
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

  String _deriveTitle(
    String conflictPath,
    String body,
    String originalPath,
    SyncConflictType type,
  ) {
    if (type == SyncConflictType.link) {
      final base = p.basenameWithoutExtension(originalPath);
      return base.isEmpty ? 'Link conflict' : 'Link: $base';
    }

    final heading = body
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.startsWith('# '), orElse: () => '');

    if (heading.isNotEmpty) {
      return heading.substring(2).trim();
    }

    final base = p.basenameWithoutExtension(originalPath);
    if (base.isNotEmpty) {
      return base;
    }

    return p.basenameWithoutExtension(conflictPath);
  }

  String _derivePreview(String body, SyncConflictType type) {
    if (type == SyncConflictType.link) {
      final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (compact.isEmpty) {
        return 'Link conflict content is empty.';
      }
      if (compact.length <= 180) {
        return compact;
      }
      return '${compact.substring(0, 180)}...';
    }

    final cleaned = body
        .replaceAll(RegExp(r'[#>*_\-\[\]()!]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.isEmpty) {
      return 'Conflict content is empty.';
    }

    if (cleaned.length <= 180) {
      return cleaned;
    }

    return '${cleaned.substring(0, 180)}...';
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
}

class _ConflictPayload {
  const _ConflictPayload({required this.metadata, required this.body});

  final Map<String, dynamic> metadata;
  final String body;
}
