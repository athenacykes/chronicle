import 'dart:io';

import 'package:chronicle/core/app_directories.dart';
import 'package:chronicle/core/clock.dart';
import 'package:chronicle/core/file_system_utils.dart';
import 'package:chronicle/core/id_generator.dart';
import 'package:chronicle/data/cache_sqlite/sqlite_search_repository.dart';
import 'package:chronicle/data/local_fs/chronicle_storage_initializer.dart';
import 'package:chronicle/data/local_fs/local_matter_repository.dart';
import 'package:chronicle/data/local_fs/local_note_repository.dart';
import 'package:chronicle/data/local_fs/matter_file_codec.dart';
import 'package:chronicle/data/local_fs/note_file_codec.dart';
import 'package:chronicle/data/local_fs/storage_root_locator.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/search_query.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Directory rootDir;
  late Directory supportDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chronicle-search-test-');
    rootDir = Directory('${tempDir.path}/Chronicle');
    supportDir = Directory('${tempDir.path}/support');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'rebuilds index and supports complete text matching with 2-char threshold',
    () async {
      final settingsRepository = _InMemorySettingsRepository(
        AppSettings(
          storageRootPath: rootDir.path,
          clientId: 'search-client',
          syncConfig: SyncConfig.initial(),
          lastSyncAt: null,
        ),
      );

      final fs = const FileSystemUtils();
      final storageRootLocator = StorageRootLocator(settingsRepository);
      final storageInitializer = ChronicleStorageInitializer(fs);

      final matterRepository = LocalMatterRepository(
        storageRootLocator: storageRootLocator,
        storageInitializer: storageInitializer,
        codec: const MatterFileCodec(),
        fileSystemUtils: fs,
        clock: _FixedClock(DateTime.utc(2026, 2, 1)),
        idGenerator: _IncrementalIdGenerator(),
      );

      final noteRepository = LocalNoteRepository(
        storageRootLocator: storageRootLocator,
        storageInitializer: storageInitializer,
        codec: const NoteFileCodec(),
        fileSystemUtils: fs,
        clock: _FixedClock(DateTime.utc(2026, 2, 1, 1)),
        idGenerator: _IncrementalIdGenerator(start: 100),
        matterRepository: matterRepository,
      );

      final matter = await matterRepository.createMatter(
        title: 'Research Matter',
        description: 'Search testing',
      );

      await noteRepository.createNote(
        title: 'Alpha discovery',
        content: 'Testing full text alpha token in markdown body.',
        matterId: matter.id,
        phaseId: matter.phases.first.id,
        tags: const <String>['alpha', 'research'],
      );

      await noteRepository.createNote(
        title: 'Beta note',
        content: 'Different content with beta keyword.',
        matterId: matter.id,
        phaseId: matter.phases.first.id,
        tags: const <String>['beta'],
      );

      await noteRepository.createNote(
        title: 'Untitled Note One',
        content: 'First Untitled draft for search testing.',
        matterId: matter.id,
        phaseId: matter.phases.first.id,
        tags: const <String>['draft'],
      );

      await noteRepository.createNote(
        title: 'Roadmap',
        content: 'This note references the Untitled initiative.',
        matterId: matter.id,
        phaseId: matter.phases.first.id,
        tags: const <String>['planning'],
      );

      await noteRepository.createNote(
        title: 'Another Untitled Note',
        content: 'Wrap up Untitled write-up.',
        matterId: matter.id,
        phaseId: matter.phases.first.id,
        tags: const <String>['draft'],
      );

      final searchRepository = SqliteSearchRepository(
        appDirectories: FixedAppDirectories(
          appSupport: supportDir,
          home: tempDir,
        ),
        fileSystemUtils: fs,
        matterRepository: matterRepository,
        noteRepository: noteRepository,
      );

      await searchRepository.rebuildIndex();

      final textHits = await searchRepository.search(
        const SearchQuery(text: 'alpha'),
      );
      expect(textHits.length, 1);
      expect(textHits.first.note.title, 'Alpha discovery');

      final tagHits = await searchRepository.search(
        const SearchQuery(text: '', tags: <String>['beta']),
      );
      expect(tagHits.length, 1);
      expect(tagHits.first.note.title, 'Beta note');

      final tags = await searchRepository.listTags();
      expect(tags, containsAll(<String>['alpha', 'beta', 'research']));

      final untitledHits = await searchRepository.search(
        const SearchQuery(text: 'Untitled'),
      );
      expect(untitledHits.length, 3);
      expect(
        untitledHits.map((hit) => hit.note.title),
        containsAll(<String>[
          'Untitled Note One',
          'Roadmap',
          'Another Untitled Note',
        ]),
      );

      final partialHits = await searchRepository.search(
        const SearchQuery(text: 'unti'),
      );
      expect(partialHits.length, 3);
      expect(
        partialHits.map((hit) => hit.note.title),
        containsAll(<String>[
          'Untitled Note One',
          'Roadmap',
          'Another Untitled Note',
        ]),
      );

      final oneCharWithTagHits = await searchRepository.search(
        const SearchQuery(text: 'u', tags: <String>['beta']),
      );
      expect(oneCharWithTagHits.length, 1);
      expect(oneCharWithTagHits.first.note.title, 'Beta note');
    },
  );
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
  const _FixedClock(this._value);

  final DateTime _value;

  @override
  DateTime nowUtc() => _value;
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
