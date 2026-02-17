import 'dart:convert';
import 'dart:io';

import 'package:chronicle/core/app_directories.dart';
import 'package:chronicle/core/clock.dart';
import 'package:chronicle/core/file_system_utils.dart';
import 'package:chronicle/data/local_fs/chronicle_layout.dart';
import 'package:chronicle/data/local_fs/chronicle_storage_initializer.dart';
import 'package:chronicle/data/local_fs/storage_root_locator.dart';
import 'package:chronicle/data/sync_webdav/in_memory_webdav_client.dart';
import 'package:chronicle/data/sync_webdav/local_sync_state_store.dart';
import 'package:chronicle/data/sync_webdav/webdav_sync_engine.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Directory rootDir;
  late _InMemorySettingsRepository settingsRepository;
  late WebDavSyncEngine syncEngine;
  late InMemoryWebDavClient webDavClient;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chronicle-sync-test-');
    rootDir = Directory('${tempDir.path}/Chronicle');
    settingsRepository = _InMemorySettingsRepository(
      AppSettings(
        storageRootPath: rootDir.path,
        clientId: 'client-sync',
        syncConfig: SyncConfig.initial(),
        lastSyncAt: null,
      ),
    );

    final fs = const FileSystemUtils();
    final initializer = ChronicleStorageInitializer(fs);
    await initializer.ensureInitialized(rootDir);

    syncEngine = WebDavSyncEngine(
      storageRootLocator: StorageRootLocator(settingsRepository),
      storageInitializer: initializer,
      fileSystemUtils: fs,
      clock: _FixedClock(DateTime.utc(2026, 2, 17, 10, 0, 0)),
      syncStateStore: LocalSyncStateStore(
        appDirectories: FixedAppDirectories(
          appSupport: Directory('${tempDir.path}/support'),
          home: tempDir,
        ),
        fileSystemUtils: fs,
      ),
    );

    webDavClient = InMemoryWebDavClient();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('classifies uploads and downloads', () async {
    final layout = ChronicleLayout(rootDir);
    await const FileSystemUtils().atomicWriteString(
      layout.orphanNoteFile('local-note'),
      'local content',
    );

    await webDavClient.uploadFile(
      'orphans/remote-note.md',
      utf8.encode('remote'),
    );

    final result = await syncEngine.run(
      client: webDavClient,
      clientId: 'client-sync',
      failSafe: true,
    );

    expect(result.uploadedCount, greaterThanOrEqualTo(1));
    expect(result.downloadedCount, greaterThanOrEqualTo(1));

    final remoteLocalCopy = layout.fromRelativePath('orphans/remote-note.md');
    expect(await remoteLocalCopy.exists(), isTrue);

    final uploaded = await webDavClient.downloadFile('orphans/local-note.md');
    expect(utf8.decode(uploaded), 'local content');
  });

  test('creates conflict copy when local and remote changed', () async {
    final layout = ChronicleLayout(rootDir);
    final localFile = layout.orphanNoteFile('conflict-note');

    await const FileSystemUtils().atomicWriteString(localFile, 'v1');
    await webDavClient.uploadFile(
      'orphans/conflict-note.md',
      utf8.encode('v1'),
    );

    await syncEngine.run(
      client: webDavClient,
      clientId: 'client-sync',
      failSafe: true,
    );

    await const FileSystemUtils().atomicWriteString(localFile, 'v2-local');
    await webDavClient.uploadFile(
      'orphans/conflict-note.md',
      utf8.encode('v2-remote'),
    );

    final result = await syncEngine.run(
      client: webDavClient,
      clientId: 'client-sync',
      failSafe: true,
    );

    expect(result.conflictCount, 1);

    final localContent = await localFile.readAsString();
    expect(localContent, 'v2-remote');

    final files = await const FileSystemUtils().listFilesRecursively(rootDir);
    final conflictFiles = files.where((f) => f.path.contains('.conflict.'));
    expect(conflictFiles.length, 1);
  });

  test('enforces deletion fail-safe threshold', () async {
    final layout = ChronicleLayout(rootDir);
    for (var i = 0; i < 8; i++) {
      await const FileSystemUtils().atomicWriteString(
        layout.orphanNoteFile('bulk-$i'),
        'bulk-$i',
      );
    }

    await syncEngine.run(
      client: webDavClient,
      clientId: 'client-sync',
      failSafe: true,
    );

    final remoteFiles = await webDavClient.listFilesRecursively('/');
    for (final file in remoteFiles) {
      if (file.path.startsWith('orphans/')) {
        await webDavClient.deleteFile(file.path);
      }
    }

    expect(
      () => syncEngine.run(
        client: webDavClient,
        clientId: 'client-sync',
        failSafe: true,
      ),
      throwsException,
    );
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
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime nowUtc() => _now;
}
