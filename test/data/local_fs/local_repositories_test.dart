import 'dart:io';

import 'package:chronicle/core/app_exception.dart';
import 'package:chronicle/core/clock.dart';
import 'package:chronicle/core/file_system_utils.dart';
import 'package:chronicle/core/id_generator.dart';
import 'package:chronicle/data/local_fs/chronicle_layout.dart';
import 'package:chronicle/data/local_fs/chronicle_storage_initializer.dart';
import 'package:chronicle/data/local_fs/local_matter_repository.dart';
import 'package:chronicle/data/local_fs/local_note_repository.dart';
import 'package:chronicle/data/local_fs/local_notebook_repository.dart';
import 'package:chronicle/data/local_fs/matter_file_codec.dart';
import 'package:chronicle/data/local_fs/note_file_codec.dart';
import 'package:chronicle/data/local_fs/storage_root_locator.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Directory rootDir;
  late _InMemorySettingsRepository settingsRepository;
  late FileSystemUtils fileSystemUtils;
  late StorageRootLocator storageRootLocator;
  late ChronicleStorageInitializer storageInitializer;
  late LocalMatterRepository matterRepository;
  late LocalNotebookRepository notebookRepository;
  late LocalNoteRepository noteRepository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chronicle-local-fs-test-');
    rootDir = Directory('${tempDir.path}/Chronicle');

    settingsRepository = _InMemorySettingsRepository(
      AppSettings(
        storageRootPath: rootDir.path,
        clientId: 'client-1',
        syncConfig: SyncConfig.initial(),
        lastSyncAt: null,
      ),
    );

    fileSystemUtils = const FileSystemUtils();
    storageRootLocator = StorageRootLocator(settingsRepository);
    storageInitializer = ChronicleStorageInitializer(fileSystemUtils);

    matterRepository = LocalMatterRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: storageInitializer,
      codec: const MatterFileCodec(),
      fileSystemUtils: fileSystemUtils,
      clock: _FixedClock(DateTime.utc(2026, 1, 1, 12)),
      idGenerator: _IncrementalIdGenerator(),
    );

    notebookRepository = LocalNotebookRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: storageInitializer,
      fileSystemUtils: fileSystemUtils,
      clock: _FixedClock(DateTime.utc(2026, 1, 1, 12)),
      idGenerator: _IncrementalIdGenerator(start: 10_000),
      noteCodec: const NoteFileCodec(),
    );

    noteRepository = LocalNoteRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: storageInitializer,
      codec: const NoteFileCodec(),
      fileSystemUtils: fileSystemUtils,
      clock: _FixedClock(DateTime.utc(2026, 1, 1, 13)),
      idGenerator: _IncrementalIdGenerator(start: 100),
      matterRepository: matterRepository,
      notebookRepository: notebookRepository,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('matter and note CRUD with orphan move', () async {
    final matter = await matterRepository.createMatter(
      title: 'Matter A',
      description: 'Test matter',
    );

    expect(matter.phases.length, 3);

    final note = await noteRepository.createNote(
      title: 'Note 1',
      content: '# Body',
      matterId: matter.id,
      phaseId: matter.phases.first.id,
    );

    final phaseNotes = await noteRepository.listNotesByMatterAndPhase(
      matterId: matter.id,
      phaseId: matter.phases.first.id,
    );
    expect(phaseNotes, hasLength(1));
    expect(phaseNotes.first.id, note.id);

    await noteRepository.moveNote(
      noteId: note.id,
      matterId: null,
      phaseId: null,
      notebookFolderId: null,
    );

    final orphanNotes = await noteRepository.listOrphanNotes();
    expect(orphanNotes, hasLength(1));
    expect(orphanNotes.first.id, note.id);
    expect(orphanNotes.first.isOrphan, isTrue);

    await noteRepository.moveNote(
      noteId: note.id,
      matterId: matter.id,
      phaseId: matter.phases[1].id,
      notebookFolderId: null,
    );

    final timeline = await noteRepository.listMatterTimeline(matter.id);
    expect(timeline, hasLength(1));
    expect(timeline.first.phaseId, matter.phases[1].id);

    final layout = ChronicleLayout(rootDir);
    expect(await layout.infoFile.exists(), isTrue);
    expect(await layout.matterJsonFile(matter.id).exists(), isTrue);
  });

  test('adds attachment and stores resource-relative path', () async {
    final matter = await matterRepository.createMatter(
      title: 'Matter Attachments',
      description: 'Attachment testing',
    );
    final note = await noteRepository.createNote(
      title: 'Attachment Note',
      content: '# Attachment',
      matterId: matter.id,
      phaseId: matter.phases.first.id,
    );

    final source = File('${tempDir.path}/source.txt');
    await source.writeAsString('hello attachment');

    final updated = await noteRepository.addAttachments(
      noteId: note.id,
      sourceFilePaths: <String>[source.path],
    );

    expect(updated.attachments, hasLength(1));
    final attachmentPath = updated.attachments.single;
    expect(attachmentPath, startsWith('resources/${note.id}/'));

    final layout = ChronicleLayout(rootDir);
    final stored = layout.fromRelativePath(attachmentPath);
    expect(await stored.exists(), isTrue);
    expect(await stored.readAsString(), 'hello attachment');

    final reloaded = await noteRepository.getNoteById(note.id);
    expect(reloaded?.attachments, equals(<String>[attachmentPath]));
  });

  test('rejects file over maxAttachmentBytes', () async {
    final limitedRepository = LocalNoteRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: storageInitializer,
      codec: const NoteFileCodec(),
      fileSystemUtils: fileSystemUtils,
      clock: _FixedClock(DateTime.utc(2026, 1, 1, 13)),
      idGenerator: _IncrementalIdGenerator(start: 200),
      matterRepository: matterRepository,
      notebookRepository: notebookRepository,
      maxAttachmentBytes: 4,
    );
    final matter = await matterRepository.createMatter(
      title: 'Limit Matter',
      description: 'Max size',
    );
    final note = await limitedRepository.createNote(
      title: 'Tiny Limit Note',
      content: '# tiny',
      matterId: matter.id,
      phaseId: matter.phases.first.id,
    );

    final source = File('${tempDir.path}/too-large.bin');
    await source.writeAsBytes(<int>[1, 2, 3, 4, 5, 6]);

    await expectLater(
      () => limitedRepository.addAttachments(
        noteId: note.id,
        sourceFilePaths: <String>[source.path],
      ),
      throwsA(isA<AppException>()),
    );
  });

  test('removes attachment only after last reference is removed', () async {
    final matter = await matterRepository.createMatter(
      title: 'Shared Resource',
      description: 'Reference counting',
    );
    final noteA = await noteRepository.createNote(
      title: 'A',
      content: '# A',
      matterId: matter.id,
      phaseId: matter.phases.first.id,
    );
    final noteB = await noteRepository.createNote(
      title: 'B',
      content: '# B',
      matterId: matter.id,
      phaseId: matter.phases.first.id,
    );

    final source = File('${tempDir.path}/shared.pdf');
    await source.writeAsString('shared-payload');

    final updatedA = await noteRepository.addAttachments(
      noteId: noteA.id,
      sourceFilePaths: <String>[source.path],
    );
    final sharedPath = updatedA.attachments.single;

    final noteBWithShared = noteB.copyWith(
      attachments: <String>[sharedPath],
      updatedAt: DateTime.utc(2026, 1, 1, 14),
    );
    await noteRepository.updateNote(noteBWithShared);

    final layout = ChronicleLayout(rootDir);
    final sharedFile = layout.fromRelativePath(sharedPath);
    expect(await sharedFile.exists(), isTrue);

    await noteRepository.removeAttachment(
      noteId: noteA.id,
      attachmentPath: sharedPath,
    );
    expect(await sharedFile.exists(), isTrue);

    await noteRepository.removeAttachment(
      noteId: noteB.id,
      attachmentPath: sharedPath,
    );
    expect(await sharedFile.exists(), isFalse);
  });

  test('deleting note cleans attachment when no references remain', () async {
    final matter = await matterRepository.createMatter(
      title: 'Delete Attachment',
      description: 'Delete cleanup',
    );
    final note = await noteRepository.createNote(
      title: 'Delete me',
      content: '# delete',
      matterId: matter.id,
      phaseId: matter.phases.first.id,
    );
    final source = File('${tempDir.path}/delete.txt');
    await source.writeAsString('delete-payload');

    final updated = await noteRepository.addAttachments(
      noteId: note.id,
      sourceFilePaths: <String>[source.path],
    );
    final attachmentPath = updated.attachments.single;
    final layout = ChronicleLayout(rootDir);
    final stored = layout.fromRelativePath(attachmentPath);
    expect(await stored.exists(), isTrue);

    await noteRepository.deleteNote(note.id);
    expect(await stored.exists(), isFalse);
  });
}

class _InMemorySettingsRepository implements SettingsRepository {
  _InMemorySettingsRepository(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<String?> readSyncPassword() async => null;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> saveSyncPassword(String password) async {}

  @override
  Future<void> setLastSyncAt(DateTime value) async {
    _settings = _settings.copyWith(lastSyncAt: value);
  }

  @override
  Future<void> setStorageRootPath(String path) async {
    _settings = _settings.copyWith(storageRootPath: path);
  }
}

class _FixedClock implements Clock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime nowUtc() => value;
}

class _IncrementalIdGenerator implements IdGenerator {
  _IncrementalIdGenerator({int start = 1}) : _counter = start;

  int _counter;

  @override
  String newId() {
    final value = _counter;
    _counter += 1;
    return 'id-$value';
  }
}
