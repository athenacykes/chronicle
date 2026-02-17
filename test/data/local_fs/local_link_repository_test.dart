import 'dart:io';

import 'package:chronicle/core/clock.dart';
import 'package:chronicle/core/file_system_utils.dart';
import 'package:chronicle/core/id_generator.dart';
import 'package:chronicle/data/local_fs/chronicle_layout.dart';
import 'package:chronicle/data/local_fs/chronicle_storage_initializer.dart';
import 'package:chronicle/data/local_fs/link_file_codec.dart';
import 'package:chronicle/data/local_fs/local_link_repository.dart';
import 'package:chronicle/data/local_fs/storage_root_locator.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Directory rootDir;
  late LocalLinkRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'chronicle-link-repo-test-',
    );
    rootDir = Directory('${tempDir.path}/Chronicle');

    final settingsRepository = _InMemorySettingsRepository(
      AppSettings(
        storageRootPath: rootDir.path,
        clientId: 'link-test-client',
        syncConfig: SyncConfig.initial(),
        lastSyncAt: null,
      ),
    );
    final fs = const FileSystemUtils();
    final storageRootLocator = StorageRootLocator(settingsRepository);
    final storageInitializer = ChronicleStorageInitializer(fs);

    repository = LocalLinkRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: storageInitializer,
      codec: const LinkFileCodec(),
      fileSystemUtils: fs,
      clock: _FixedClock(DateTime.utc(2026, 2, 17, 10)),
      idGenerator: _FixedIdGenerator('link-1'),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('roundtrips link create/list/delete', () async {
    final created = await repository.createLink(
      sourceNoteId: 'note-a',
      targetNoteId: 'note-b',
      context: 'related',
    );
    expect(created.id, 'link-1');

    final all = await repository.listLinks();
    expect(all, hasLength(1));
    expect(all.single.sourceNoteId, 'note-a');
    expect(all.single.targetNoteId, 'note-b');

    final byNote = await repository.listLinksForNote('note-a');
    expect(byNote, hasLength(1));
    expect(byNote.single.id, created.id);

    await repository.deleteLink(created.id);
    final afterDelete = await repository.listLinks();
    expect(afterDelete, isEmpty);
  });

  test('skips malformed link files without crashing', () async {
    await repository.createLink(
      sourceNoteId: 'note-a',
      targetNoteId: 'note-b',
      context: '',
    );

    final layout = ChronicleLayout(rootDir);
    final malformed = File('${layout.linksDirectory.path}/broken.json');
    await malformed.writeAsString('{ this-is-invalid-json }');

    final links = await repository.listLinks();
    expect(links, hasLength(1));
    expect(links.single.id, 'link-1');
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
  const _FixedClock(this._value);

  final DateTime _value;

  @override
  DateTime nowUtc() => _value;
}

class _FixedIdGenerator implements IdGenerator {
  const _FixedIdGenerator(this._id);

  final String _id;

  @override
  String newId() => _id;
}
