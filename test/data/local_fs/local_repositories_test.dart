import 'dart:io';

import 'package:chronicle/core/clock.dart';
import 'package:chronicle/core/file_system_utils.dart';
import 'package:chronicle/core/id_generator.dart';
import 'package:chronicle/data/local_fs/chronicle_layout.dart';
import 'package:chronicle/data/local_fs/chronicle_storage_initializer.dart';
import 'package:chronicle/data/local_fs/local_matter_repository.dart';
import 'package:chronicle/data/local_fs/local_note_repository.dart';
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
  late LocalMatterRepository matterRepository;
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

    final fileSystemUtils = const FileSystemUtils();
    final storageRootLocator = StorageRootLocator(settingsRepository);
    final storageInitializer = ChronicleStorageInitializer(fileSystemUtils);

    matterRepository = LocalMatterRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: storageInitializer,
      codec: const MatterFileCodec(),
      fileSystemUtils: fileSystemUtils,
      clock: _FixedClock(DateTime.utc(2026, 1, 1, 12)),
      idGenerator: _IncrementalIdGenerator(),
    );

    noteRepository = LocalNoteRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: storageInitializer,
      codec: const NoteFileCodec(),
      fileSystemUtils: fileSystemUtils,
      clock: _FixedClock(DateTime.utc(2026, 1, 1, 13)),
      idGenerator: _IncrementalIdGenerator(start: 100),
      matterRepository: matterRepository,
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
    );

    final orphanNotes = await noteRepository.listOrphanNotes();
    expect(orphanNotes, hasLength(1));
    expect(orphanNotes.first.id, note.id);
    expect(orphanNotes.first.isOrphan, isTrue);

    await noteRepository.moveNote(
      noteId: note.id,
      matterId: matter.id,
      phaseId: matter.phases[1].id,
    );

    final timeline = await noteRepository.listMatterTimeline(matter.id);
    expect(timeline, hasLength(1));
    expect(timeline.first.phaseId, matter.phases[1].id);

    final layout = ChronicleLayout(rootDir);
    expect(await layout.infoFile.exists(), isTrue);
    expect(await layout.matterJsonFile(matter.id).exists(), isTrue);
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
