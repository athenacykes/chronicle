import 'dart:io';

import '../../core/clock.dart';
import '../../core/file_system_utils.dart';
import '../../core/id_generator.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/note.dart';
import '../../domain/repositories/matter_repository.dart';
import '../../domain/repositories/note_repository.dart';
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
  }) : _storageRootLocator = storageRootLocator,
       _storageInitializer = storageInitializer,
       _codec = codec,
       _fileSystemUtils = fileSystemUtils,
       _clock = clock,
       _idGenerator = idGenerator,
       _matterRepository = matterRepository;

  final StorageRootLocator _storageRootLocator;
  final ChronicleStorageInitializer _storageInitializer;
  final NoteFileCodec _codec;
  final FileSystemUtils _fileSystemUtils;
  final Clock _clock;
  final IdGenerator _idGenerator;
  final MatterRepository _matterRepository;

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
    List<String> tags = const <String>[],
    bool isPinned = false,
    List<String> attachments = const <String>[],
  }) async {
    final now = _clock.nowUtc();
    final note = Note(
      id: _idGenerator.newId(),
      matterId: matterId,
      phaseId: phaseId,
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
    final existing = await _findNoteFile(note.id);
    final updated = note.copyWith(updatedAt: _clock.nowUtc());
    final target = await _targetFileFor(updated);

    await _fileSystemUtils.atomicWriteString(target, _codec.encode(updated));
    if (existing != null && existing.path != target.path) {
      await _fileSystemUtils.deleteIfExists(existing);
    }
  }

  @override
  Future<void> deleteNote(String noteId) async {
    final file = await _findNoteFile(noteId);
    if (file != null) {
      await _fileSystemUtils.deleteIfExists(file);
    }
  }

  @override
  Future<void> moveNote({
    required String noteId,
    required String? matterId,
    required String? phaseId,
  }) async {
    final note = await getNoteById(noteId);
    if (note == null) {
      return;
    }

    final moved = note.copyWith(
      matterId: matterId,
      phaseId: phaseId,
      clearMatterId: matterId == null,
      clearPhaseId: phaseId == null,
      updatedAt: _clock.nowUtc(),
    );

    await updateNote(moved);
  }

  @override
  Future<List<Note>> listOrphanNotes() async {
    final all = await listAllNotes();
    return all.where((note) => note.isOrphan).toList();
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
    final target = await _targetFileFor(note);
    final existing = await _findNoteFile(note.id);

    await _fileSystemUtils.atomicWriteString(target, _codec.encode(note));
    if (existing != null && existing.path != target.path) {
      await _fileSystemUtils.deleteIfExists(existing);
    }
  }

  Future<File> _targetFileFor(Note note) async {
    final layout = await _layout();
    if (note.matterId == null || note.phaseId == null) {
      return layout.orphanNoteFile(note.id);
    }

    final phaseType = await _resolvePhaseType(
      matterId: note.matterId!,
      phaseId: note.phaseId!,
    );
    if (phaseType == null) {
      return layout.orphanNoteFile(note.id);
    }

    return layout.phaseNoteFile(
      matterId: note.matterId!,
      phaseType: phaseType,
      noteId: note.id,
    );
  }

  Future<PhaseType?> _resolvePhaseType({
    required String matterId,
    required String phaseId,
  }) async {
    final matter = await _matterRepository.getMatterById(matterId);
    if (matter == null) {
      return null;
    }

    for (final phase in matter.phases) {
      if (phase.id == phaseId) {
        return phase.type;
      }
    }
    return null;
  }

  Future<List<File>> _noteFiles(ChronicleLayout layout) async {
    final files = <File>[];
    final orphanFiles = await _fileSystemUtils.listFilesRecursively(
      layout.orphansDirectory,
    );
    files.addAll(orphanFiles.where(_isNoteFile));

    final matterFiles = await _fileSystemUtils.listFilesRecursively(
      layout.mattersDirectory,
    );
    files.addAll(matterFiles.where(_isNoteFile));
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
}
