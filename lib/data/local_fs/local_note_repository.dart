import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/app_exception.dart';
import '../../core/clock.dart';
import '../../core/file_system_utils.dart';
import '../../core/id_generator.dart';
import '../../domain/entities/note.dart';
import '../../domain/repositories/matter_repository.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/repositories/notebook_repository.dart';
import 'chronicle_layout.dart';
import 'chronicle_storage_initializer.dart';
import 'note_file_codec.dart';
import 'storage_root_locator.dart';

class LocalNoteRepository implements NoteRepository {
  LocalNoteRepository({
    required StorageRootLocator storageRootLocator,
    required ChronicleStorageInitializer storageInitializer,
    required NoteFileCodec codec,
    required FileSystemUtils fileSystemUtils,
    required Clock clock,
    required IdGenerator idGenerator,
    required MatterRepository matterRepository,
    required NotebookRepository notebookRepository,
    int maxAttachmentBytes = defaultMaxAttachmentBytes,
  }) : _storageRootLocator = storageRootLocator,
       _storageInitializer = storageInitializer,
       _codec = codec,
       _fileSystemUtils = fileSystemUtils,
       _clock = clock,
       _idGenerator = idGenerator,
       _matterRepository = matterRepository,
       _notebookRepository = notebookRepository,
       _maxAttachmentBytes = maxAttachmentBytes;

  static const int defaultMaxAttachmentBytes = 50 * 1024 * 1024;

  final StorageRootLocator _storageRootLocator;
  final ChronicleStorageInitializer _storageInitializer;
  final NoteFileCodec _codec;
  final FileSystemUtils _fileSystemUtils;
  final Clock _clock;
  final IdGenerator _idGenerator;
  final MatterRepository _matterRepository;
  final NotebookRepository _notebookRepository;
  final int _maxAttachmentBytes;

  @override
  Future<List<Note>> listAllNotes() async {
    final layout = await _layout();
    final files = await _noteFiles(layout);
    final notes = <Note>[];
    for (final file in files) {
      final note = await _readNote(file);
      if (note != null) {
        notes.add(note);
      }
    }
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  @override
  Future<Note?> getNoteById(String noteId) async {
    final file = await _findNoteFile(noteId);
    if (file == null) {
      return null;
    }
    return _readNote(file);
  }

  @override
  Future<Note> createNote({
    required String title,
    required String content,
    String? matterId,
    String? phaseId,
    String? notebookFolderId,
    List<String> tags = const <String>[],
    bool isPinned = false,
    List<String> attachments = const <String>[],
  }) async {
    final ownership = await _normalizeOwnership(
      matterId: matterId,
      phaseId: phaseId,
      notebookFolderId: notebookFolderId,
    );
    final now = _clock.nowUtc();
    final note = Note(
      id: _idGenerator.newId(),
      matterId: ownership.matterId,
      phaseId: ownership.phaseId,
      notebookFolderId: ownership.notebookFolderId,
      title: title,
      content: content,
      tags: tags,
      isPinned: isPinned,
      attachments: attachments,
      createdAt: now,
      updatedAt: now,
    );

    await _writeNote(note);
    return note;
  }

  @override
  Future<void> updateNote(Note note) async {
    final previous = await getNoteById(note.id);
    final updated = note.copyWith(updatedAt: _clock.nowUtc());
    await _persistNote(updated);
    if (previous != null) {
      final removed = _removedAttachmentPaths(
        previous.attachments,
        updated.attachments,
      );
      await _cleanupUnreferencedAttachments(removed, excludeNoteId: updated.id);
    }
  }

  @override
  Future<void> deleteNote(String noteId) async {
    final existingNote = await getNoteById(noteId);
    final file = await _findNoteFile(noteId);
    if (file != null) {
      await _fileSystemUtils.deleteIfExists(file);
    }
    if (existingNote != null) {
      await _cleanupUnreferencedAttachments(
        existingNote.attachments,
        excludeNoteId: existingNote.id,
      );
    }
  }

  @override
  Future<void> moveNote({
    required String noteId,
    required String? matterId,
    required String? phaseId,
    required String? notebookFolderId,
  }) async {
    final note = await getNoteById(noteId);
    if (note == null) {
      return;
    }

    final ownership = await _normalizeOwnership(
      matterId: matterId,
      phaseId: phaseId,
      notebookFolderId: notebookFolderId,
    );
    final moved = note.copyWith(
      matterId: ownership.matterId,
      phaseId: ownership.phaseId,
      clearMatterId: ownership.matterId == null,
      clearPhaseId: ownership.phaseId == null,
      notebookFolderId: ownership.notebookFolderId,
      clearNotebookFolderId: ownership.notebookFolderId == null,
      updatedAt: _clock.nowUtc(),
    );

    await updateNote(moved);
  }

  @override
  Future<Note> addAttachments({
    required String noteId,
    required List<String> sourceFilePaths,
  }) async {
    final note = await getNoteById(noteId);
    if (note == null) {
      throw AppException('Note not found: $noteId');
    }

    if (sourceFilePaths.isEmpty) {
      return note;
    }

    final sources = await _validateAttachmentSources(sourceFilePaths);
    if (sources.isEmpty) {
      return note;
    }

    final layout = await _layout();
    final createdPaths = <String>[];
    final createdFiles = <File>[];

    try {
      for (var i = 0; i < sources.length; i++) {
        final source = sources[i];
        final relativePath = await _buildAttachmentRelativePath(
          layout: layout,
          noteId: note.id,
          originalName: source.displayName,
          sequence: i,
        );
        final target = layout.fromRelativePath(relativePath);
        final bytes = await source.file.readAsBytes();
        await _fileSystemUtils.atomicWriteBytes(target, bytes);

        createdFiles.add(target);
        createdPaths.add(_normalizeAttachmentPath(relativePath));
      }

      final updated = note.copyWith(
        attachments: _dedupeAttachmentPaths(<String>[
          ...note.attachments,
          ...createdPaths,
        ]),
        updatedAt: _clock.nowUtc(),
      );
      await updateNote(updated);
      return (await getNoteById(note.id)) ?? updated;
    } catch (error) {
      for (final file in createdFiles.reversed) {
        await _fileSystemUtils.deleteIfExists(file);
      }
      if (error is AppException) {
        rethrow;
      }
      throw AppException('Failed to attach files', cause: error);
    }
  }

  @override
  Future<Note> removeAttachment({
    required String noteId,
    required String attachmentPath,
  }) async {
    final note = await getNoteById(noteId);
    if (note == null) {
      throw AppException('Note not found: $noteId');
    }

    final normalized = _normalizeAttachmentPath(attachmentPath);
    final nextAttachments = note.attachments
        .map(_normalizeAttachmentPath)
        .where((path) => path != normalized)
        .toList();

    if (nextAttachments.length == note.attachments.length) {
      return note;
    }

    final updated = note.copyWith(
      attachments: nextAttachments,
      updatedAt: _clock.nowUtc(),
    );
    await updateNote(updated);
    return (await getNoteById(note.id)) ?? updated;
  }

  @override
  Future<List<Note>> listOrphanNotes() async {
    return listNotebookNotes(folderId: null);
  }

  @override
  Future<List<Note>> listNotebookNotes({String? folderId}) async {
    final all = await listAllNotes();
    return all
        .where((note) => note.isInNotebook && note.notebookFolderId == folderId)
        .toList();
  }

  @override
  Future<List<Note>> listNotesByMatterAndPhase({
    required String matterId,
    required String phaseId,
  }) async {
    final all = await listAllNotes();
    return all
        .where((note) => note.matterId == matterId && note.phaseId == phaseId)
        .toList();
  }

  @override
  Future<List<Note>> listMatterTimeline(String matterId) async {
    final all = await listAllNotes();
    final timeline = all.where((note) => note.matterId == matterId).toList();
    timeline.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return timeline;
  }

  Future<void> _writeNote(Note note) async {
    await _persistNote(note);
  }

  Future<void> _persistNote(Note note) async {
    final target = await _targetFileFor(note);
    final existing = await _findNoteFile(note.id);

    await _fileSystemUtils.atomicWriteString(target, _codec.encode(note));
    if (existing != null && existing.path != target.path) {
      await _fileSystemUtils.deleteIfExists(existing);
    }
  }

  Future<File> _targetFileFor(Note note) async {
    final layout = await _layout();
    if (note.isInMatter) {
      final hasPhase = await _matterHasPhase(
        matterId: note.matterId!,
        phaseId: note.phaseId!,
      );
      if (!hasPhase) {
        return layout.notebookRootNoteFile(note.id);
      }

      return layout.phaseNoteFile(
        matterId: note.matterId!,
        phaseId: note.phaseId!,
        noteId: note.id,
      );
    }

    final folderId = note.notebookFolderId;
    if (folderId == null) {
      return layout.notebookRootNoteFile(note.id);
    }
    final folder = await _notebookRepository.getFolderById(folderId);
    if (folder == null) {
      return layout.notebookRootNoteFile(note.id);
    }
    return layout.notebookFolderNoteFile(folderId: folderId, noteId: note.id);
  }

  Future<bool> _matterHasPhase({
    required String matterId,
    required String phaseId,
  }) async {
    final matter = await _matterRepository.getMatterById(matterId);
    if (matter == null) {
      return false;
    }

    for (final phase in matter.phases) {
      if (phase.id == phaseId) {
        return true;
      }
    }
    return false;
  }

  Future<List<File>> _noteFiles(ChronicleLayout layout) async {
    final files = <File>[];
    final notebookRootFiles = await _fileSystemUtils.listFilesRecursively(
      layout.notebookRootDirectory,
    );
    files.addAll(notebookRootFiles.where(_isNoteFile));

    final notebookFolderFiles = await _fileSystemUtils.listFilesRecursively(
      layout.notebookFoldersDirectory,
    );
    files.addAll(notebookFolderFiles.where(_isNoteFile));

    final matterFiles = await _fileSystemUtils.listFilesRecursively(
      layout.mattersDirectory,
    );
    files.addAll(matterFiles.where(_isNoteFile));

    // Legacy compatibility during migration window.
    final orphanFiles = await _fileSystemUtils.listFilesRecursively(
      layout.orphansDirectory,
    );
    files.addAll(orphanFiles.where(_isNoteFile));
    return files;
  }

  bool _isNoteFile(File file) {
    return file.path.endsWith('.md') && !file.path.contains('.conflict.');
  }

  Future<File?> _findNoteFile(String noteId) async {
    final layout = await _layout();
    final files = await _noteFiles(layout);
    for (final file in files) {
      if (file.uri.pathSegments.last == '$noteId.md') {
        return file;
      }
    }
    return null;
  }

  Future<Note?> _readNote(File file) async {
    try {
      final raw = await file.readAsString();
      return _codec.decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<ChronicleLayout> _layout() async {
    final root = await _storageRootLocator.requireRootDirectory();
    await _storageInitializer.ensureInitialized(root);
    return ChronicleLayout(root);
  }

  Future<_Ownership> _normalizeOwnership({
    required String? matterId,
    required String? phaseId,
    required String? notebookFolderId,
  }) async {
    final hasMatter = matterId != null || phaseId != null;
    if (hasMatter) {
      if (matterId == null || phaseId == null) {
        throw AppException(
          'Matter notes require both matterId and phaseId.',
        );
      }
      if (notebookFolderId != null) {
        throw AppException(
          'A note cannot belong to both Matter and Notebook.',
        );
      }
      return _Ownership(matterId: matterId, phaseId: phaseId, notebookFolderId: null);
    }

    if (notebookFolderId != null) {
      final folder = await _notebookRepository.getFolderById(notebookFolderId);
      if (folder == null) {
        throw AppException('Notebook folder not found: $notebookFolderId');
      }
    }
    return _Ownership(
      matterId: null,
      phaseId: null,
      notebookFolderId: notebookFolderId,
    );
  }

  Set<String> _removedAttachmentPaths(
    List<String> previous,
    List<String> current,
  ) {
    final currentSet = current.map(_normalizeAttachmentPath).toSet();
    return previous
        .map(_normalizeAttachmentPath)
        .where((path) => !currentSet.contains(path))
        .toSet();
  }

  Future<void> _cleanupUnreferencedAttachments(
    Iterable<String> attachmentPaths, {
    String? excludeNoteId,
  }) async {
    final normalizedPaths = attachmentPaths
        .map(_normalizeAttachmentPath)
        .where(_isSafeAttachmentPath)
        .toSet();
    if (normalizedPaths.isEmpty) {
      return;
    }

    final notes = await listAllNotes();
    final referenced = <String>{};
    for (final note in notes) {
      if (excludeNoteId != null && note.id == excludeNoteId) {
        continue;
      }
      for (final attachment in note.attachments) {
        final normalized = _normalizeAttachmentPath(attachment);
        if (normalizedPaths.contains(normalized)) {
          referenced.add(normalized);
        }
      }
    }

    if (referenced.length == normalizedPaths.length) {
      return;
    }

    final layout = await _layout();
    for (final path in normalizedPaths) {
      if (referenced.contains(path)) {
        continue;
      }
      await _fileSystemUtils.deleteIfExists(layout.fromRelativePath(path));
    }
  }

  Future<List<_AttachmentSource>> _validateAttachmentSources(
    List<String> sourceFilePaths,
  ) async {
    final validated = <_AttachmentSource>[];
    for (final sourcePath in sourceFilePaths) {
      final normalizedPath = sourcePath.trim();
      if (normalizedPath.isEmpty) {
        continue;
      }

      final file = File(normalizedPath);
      if (!await file.exists()) {
        throw AppException('Attachment file does not exist: $normalizedPath');
      }

      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        throw AppException('Attachment is not a file: $normalizedPath');
      }

      final fileName = p.basename(file.path);
      if (stat.size > _maxAttachmentBytes) {
        throw AppException(
          'Attachment "$fileName" exceeds max size '
          '(${_formatBytes(_maxAttachmentBytes)}). '
          'Found: ${_formatBytes(stat.size)}.',
        );
      }

      validated.add(_AttachmentSource(file: file, displayName: fileName));
    }

    return validated;
  }

  Future<String> _buildAttachmentRelativePath({
    required ChronicleLayout layout,
    required String noteId,
    required String originalName,
    required int sequence,
  }) async {
    final sanitizedName = _sanitizeFileName(originalName);
    final stamp = _clock.nowUtc().millisecondsSinceEpoch;

    var attempt = 0;
    while (true) {
      final suffix = attempt == 0
          ? '${stamp}_${sequence}_$sanitizedName'
          : '${stamp}_${sequence}_${attempt}_$sanitizedName';
      final relativePath = p.posix.join('resources', noteId, suffix);
      if (!await layout.fromRelativePath(relativePath).exists()) {
        return relativePath;
      }
      attempt += 1;
    }
  }

  String _sanitizeFileName(String input) {
    final base = p.basename(input).trim();
    final sanitized = base
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (sanitized.isEmpty) {
      return 'attachment.bin';
    }
    return sanitized;
  }

  String _normalizeAttachmentPath(String value) {
    final trimmed = value.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty) {
      return '';
    }
    return p.posix.normalize(trimmed);
  }

  bool _isSafeAttachmentPath(String value) {
    if (value.isEmpty) {
      return false;
    }
    if (value == '..' || value.startsWith('../')) {
      return false;
    }
    return value.startsWith('resources/');
  }

  List<String> _dedupeAttachmentPaths(List<String> values) {
    final out = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final normalized = _normalizeAttachmentPath(value);
      if (normalized.isEmpty) {
        continue;
      }
      if (seen.add(normalized)) {
        out.add(normalized);
      }
    }
    return out;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _AttachmentSource {
  const _AttachmentSource({required this.file, required this.displayName});

  final File file;
  final String displayName;
}

class _Ownership {
  const _Ownership({
    required this.matterId,
    required this.phaseId,
    required this.notebookFolderId,
  });

  final String? matterId;
  final String? phaseId;
  final String? notebookFolderId;
}
