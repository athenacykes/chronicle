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
import 'package:chronicle/domain/entities/sync_blocker.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/entities/sync_run_options.dart';
import 'package:chronicle/domain/entities/sync_result.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Directory rootDir;
  late _InMemorySettingsRepository settingsRepository;
  late WebDavSyncEngine syncEngine;
  late InMemoryWebDavClient webDavClient;
  const syncTargetUrl = 'https://example.com/dav/Chronicle';
  const syncUsername = 'tester';

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

  Future<SyncResult> runSync({SyncRunMode mode = SyncRunMode.normal}) {
    return syncEngine.run(
      client: webDavClient,
      clientId: 'client-sync',
      failSafe: true,
      options: SyncRunOptions(mode: mode),
      syncTargetUrl: syncTargetUrl,
      syncUsername: syncUsername,
    );
  }

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

    final result = await runSync();

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

    await runSync();

    await const FileSystemUtils().atomicWriteString(localFile, 'v2-local');
    await webDavClient.uploadFile(
      'orphans/conflict-note.md',
      utf8.encode('v2-remote'),
    );

    final result = await runSync();

    expect(result.conflictCount, 1);

    final localContent = await localFile.readAsString();
    expect(localContent, 'v2-remote');

    final files = await const FileSystemUtils().listFilesRecursively(rootDir);
    final conflictFiles = files.where((f) => f.path.contains('.conflict.'));
    expect(conflictFiles.length, 1);
  });

  test('handles binary resource conflicts without UTF-8 decoding', () async {
    final layout = ChronicleLayout(rootDir);
    final localFile = layout.fromRelativePath('resources/photo.png');

    final baseBytes = <int>[137, 80, 78, 71, 0, 0, 0, 1];
    await const FileSystemUtils().atomicWriteBytes(localFile, baseBytes);
    await webDavClient.uploadFile('resources/photo.png', baseBytes);

    await runSync();

    final localVersion = <int>[137, 80, 78, 71, 1, 2, 3, 4];
    final remoteVersion = <int>[137, 80, 78, 71, 9, 8, 7, 6];
    await const FileSystemUtils().atomicWriteBytes(localFile, localVersion);
    await webDavClient.uploadFile('resources/photo.png', remoteVersion);

    final result = await runSync();
    expect(result.conflictCount, 1);

    final localAfterSync = await localFile.readAsBytes();
    expect(localAfterSync, remoteVersion);

    final files = await const FileSystemUtils().listFilesRecursively(rootDir);
    final conflictFile = files.firstWhere(
      (file) =>
          file.path.contains('resources/photo.conflict.') &&
          file.path.endsWith('.png'),
    );
    final conflictBytes = await conflictFile.readAsBytes();
    expect(conflictBytes, localVersion);
  });

  test('enforces deletion fail-safe threshold', () async {
    final layout = ChronicleLayout(rootDir);
    for (var i = 0; i < 8; i++) {
      await const FileSystemUtils().atomicWriteString(
        layout.orphanNoteFile('bulk-$i'),
        'bulk-$i',
      );
    }

    await runSync();

    final remoteFiles = await webDavClient.listFilesRecursively('/');
    for (final file in remoteFiles) {
      if (file.path.startsWith('orphans/')) {
        await webDavClient.deleteFile(file.path);
      }
    }

    final result = await runSync();
    expect(result.blocker, isNotNull);
    expect(result.blocker!.type, SyncBlockerType.failSafeDeletionBlocked);
    expect(result.blocker!.candidateDeletionCount, 8);
    expect(result.blocker!.trackedCount, 9);
  });

  test('blocks normal sync when remote format version is older', () async {
    await webDavClient.uploadFile(
      'info.json',
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
          'app': 'chronicle',
          'formatVersion': 1,
          'createdAt': '2026-02-16T00:00:00Z',
        }),
      ),
    );

    final result = await runSync();
    expect(result.blocker, isNotNull);
    expect(result.blocker!.type, SyncBlockerType.versionMismatchRemoteOlder);
  });

  test(
    'recover local wins upgrades remote format and prunes stale remote files',
    () async {
      final layout = ChronicleLayout(rootDir);
      await const FileSystemUtils().atomicWriteString(
        layout.orphanNoteFile('local-note'),
        'local content',
      );
      await webDavClient.uploadFile(
        'info.json',
        utf8.encode(
          const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
            'app': 'chronicle',
            'formatVersion': 1,
            'createdAt': '2026-02-16T00:00:00Z',
          }),
        ),
      );
      await webDavClient.uploadFile(
        'orphans/stale-remote.md',
        utf8.encode('stale'),
      );

      final result = await runSync(mode: SyncRunMode.recoverLocalWins);
      expect(result.blocker, isNull);
      expect(result.deletedCount, greaterThanOrEqualTo(1));

      final remoteInfoRaw = utf8.decode(
        await webDavClient.downloadFile('info.json'),
      );
      final remoteInfo = json.decode(remoteInfoRaw) as Map<String, dynamic>;
      expect((remoteInfo['formatVersion'] as num).toInt(), 2);
      expect(
        () => webDavClient.downloadFile('orphans/stale-remote.md'),
        throwsException,
      );
    },
  );

  test('recover remote wins is blocked when remote format is older', () async {
    await webDavClient.uploadFile(
      'info.json',
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
          'app': 'chronicle',
          'formatVersion': 1,
          'createdAt': '2026-02-16T00:00:00Z',
        }),
      ),
    );

    final result = await runSync(mode: SyncRunMode.recoverRemoteWins);
    expect(result.blocker, isNotNull);
    expect(result.blocker!.type, SyncBlockerType.versionMismatchRemoteOlder);
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
