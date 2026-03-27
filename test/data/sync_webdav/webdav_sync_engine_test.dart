import 'dart:convert';
import 'dart:io';

import 'package:chronicle/core/app_directories.dart';
import 'package:chronicle/core/clock.dart';
import 'package:chronicle/core/file_hash.dart';
import 'package:chronicle/core/file_system_utils.dart';
import 'package:chronicle/data/local_fs/chronicle_layout.dart';
import 'package:chronicle/data/local_fs/chronicle_storage_initializer.dart';
import 'package:chronicle/data/local_fs/conflict_service.dart';
import 'package:chronicle/data/local_fs/storage_root_locator.dart';
import 'package:chronicle/data/sync_webdav/in_memory_webdav_client.dart';
import 'package:chronicle/data/sync_webdav/local_conflict_history_store.dart';
import 'package:chronicle/data/sync_webdav/local_sync_metadata_store.dart';
import 'package:chronicle/data/sync_webdav/local_sync_state_store.dart';
import 'package:chronicle/data/sync_webdav/sync_local_metadata_tracker.dart';
import 'package:chronicle/data/sync_webdav/webdav_sync_engine.dart';
import 'package:chronicle/data/sync_webdav/webdav_types.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/sync_blocker.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/entities/sync_conflict.dart';
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
  late LocalSyncStateStore syncStateStore;
  late LocalSyncMetadataStore localSyncMetadataStore;
  late SyncLocalMetadataTracker metadataTracker;
  late LocalConflictHistoryStore conflictHistoryStore;
  late ConflictService conflictService;
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
    syncStateStore = LocalSyncStateStore(
      appDirectories: FixedAppDirectories(
        appSupport: Directory('${tempDir.path}/support'),
        home: tempDir,
      ),
      fileSystemUtils: fs,
    );
    localSyncMetadataStore = LocalSyncMetadataStore(
      appDirectories: FixedAppDirectories(
        appSupport: Directory('${tempDir.path}/support'),
        home: tempDir,
      ),
      fileSystemUtils: fs,
    );
    final fixedClock = _FixedClock(DateTime.utc(2026, 2, 17, 10, 0, 0));
    metadataTracker = SyncLocalMetadataTracker(
      storageRootLocator: StorageRootLocator(settingsRepository),
      storageInitializer: initializer,
      fileSystemUtils: fs,
      clock: fixedClock,
      metadataStore: localSyncMetadataStore,
    );
    conflictHistoryStore = LocalConflictHistoryStore(fileSystemUtils: fs);
    conflictService = ConflictService(
      storageRootLocator: StorageRootLocator(settingsRepository),
      storageInitializer: initializer,
      fileSystemUtils: fs,
    );

    syncEngine = WebDavSyncEngine(
      storageRootLocator: StorageRootLocator(settingsRepository),
      storageInitializer: initializer,
      fileSystemUtils: fs,
      clock: fixedClock,
      localSyncMetadataStore: localSyncMetadataStore,
      syncStateStore: syncStateStore,
      conflictService: conflictService,
      conflictHistoryStore: conflictHistoryStore,
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

  Future<void> rebuildLocalMetadata() {
    return metadataTracker.rebuildFromDisk();
  }

  String currentNamespace() {
    return syncStateStore.buildNamespace(
      syncTargetUrl: syncTargetUrl,
      username: syncUsername,
      storageRootPath: rootDir.path,
      localFormatVersion: 2,
    );
  }

  Future<void> writeRemoteLock({
    required InMemoryWebDavClient client,
    required String path,
    required int updatedTime,
    String clientId = 'other-client',
    String clientType = 'desktop',
  }) {
    return client.uploadFile(
      path,
      utf8.encode(
        json.encode(<String, dynamic>{
          'type': 'sync',
          'clientType': clientType,
          'clientId': clientId,
          'updatedTime': updatedTime,
        }),
      ),
    );
  }

  test('classifies uploads and downloads', () async {
    final layout = ChronicleLayout(rootDir);
    await const FileSystemUtils().atomicWriteString(
      layout.notebookRootNoteFile('local-note'),
      'local content',
    );

    await webDavClient.uploadFile(
      'orphans/remote-note.md',
      utf8.encode('remote'),
    );

    final result = await runSync();

    expect(result.uploadedCount, greaterThanOrEqualTo(1));
    expect(result.downloadedCount, greaterThanOrEqualTo(1));

    final remoteLocalCopy = layout.fromRelativePath(
      'notebook/root/remote-note.md',
    );
    expect(await remoteLocalCopy.exists(), isTrue);

    final uploaded = await webDavClient.downloadFile(
      'notebook/root/local-note.md',
    );
    expect(utf8.decode(uploaded), 'local content');
  });

  test('creates conflict copy when local and remote changed', () async {
    final layout = ChronicleLayout(rootDir);
    final localFile = layout.notebookRootNoteFile('conflict-note');

    await const FileSystemUtils().atomicWriteString(localFile, 'v1');
    await webDavClient.uploadFile(
      'notebook/root/conflict-note.md',
      utf8.encode('v1'),
    );

    await runSync();

    await const FileSystemUtils().atomicWriteString(localFile, 'v2-local');
    await rebuildLocalMetadata();
    await webDavClient.uploadFile(
      'notebook/root/conflict-note.md',
      utf8.encode('v2-remote'),
    );

    final result = await runSync();

    expect(result.conflictCount, 1);

    final localContent = await localFile.readAsString();
    expect(localContent, 'v2-remote');

    final files = await const FileSystemUtils().listFilesRecursively(rootDir);
    final conflictFiles = files.where((f) => f.path.contains('.conflict.'));
    expect(conflictFiles.length, 1);

    final conflictRaw = await conflictFiles.single.readAsString();
    expect(conflictRaw, contains('localContentHash:'));
    expect(conflictRaw, contains('remoteContentHash:'));
    expect(conflictRaw, contains('conflictFingerprint:'));
  });

  test(
    'does not create a duplicate artifact when matching conflict exists',
    () async {
      final layout = ChronicleLayout(rootDir);
      final localFile = layout.notebookRootNoteFile('duplicate-note');

      await const FileSystemUtils().atomicWriteString(localFile, 'v1');
      await webDavClient.uploadFile(
        'notebook/root/duplicate-note.md',
        utf8.encode('v1'),
      );
      await runSync();

      await const FileSystemUtils().atomicWriteString(localFile, 'v2-local');
      await rebuildLocalMetadata();
      await webDavClient.uploadFile(
        'notebook/root/duplicate-note.md',
        utf8.encode('v2-remote'),
      );

      final localHash = sha256ForString('v2-local');
      final remoteHash = sha256ForString('v2-remote');
      final fingerprint = buildSyncConflictFingerprint(
        originalPath: 'notebook/root/duplicate-note.md',
        localContentHash: localHash,
        remoteContentHash: remoteHash,
      );
      final existingConflict = layout.fromRelativePath(
        'notebook/root/duplicate-note.conflict.20260217100000.client-sync.md',
      );
      await const FileSystemUtils().atomicWriteString(existingConflict, '''---
conflictType: "note"
originalPath: "notebook/root/duplicate-note.md"
conflictDetectedAt: "2026-02-17T10:00:00Z"
localDevice: "desktop-client-sync"
remoteDevice: "unknown"
localContentHash: "$localHash"
remoteContentHash: "$remoteHash"
conflictFingerprint: "$fingerprint"
---

# [CONFLICT] notebook/root/duplicate-note.md

This file contains local changes that conflicted with a remote update.

v2-local
''');

      final result = await runSync();

      expect(result.conflictCount, 0);
      final files = await const FileSystemUtils().listFilesRecursively(rootDir);
      final conflictFiles = files.where((f) => f.path.contains('.conflict.'));
      expect(conflictFiles, hasLength(1));
      expect(await localFile.readAsString(), 'v2-remote');
    },
  );

  test(
    'does not recreate a resolved conflict when fingerprint history exists',
    () async {
      final layout = ChronicleLayout(rootDir);
      final localFile = layout.notebookRootNoteFile('history-note');

      await const FileSystemUtils().atomicWriteString(localFile, 'v1');
      await webDavClient.uploadFile(
        'notebook/root/history-note.md',
        utf8.encode('v1'),
      );
      await runSync();

      await const FileSystemUtils().atomicWriteString(localFile, 'v2-local');
      await rebuildLocalMetadata();
      await webDavClient.uploadFile(
        'notebook/root/history-note.md',
        utf8.encode('v2-remote'),
      );

      final fingerprint = buildSyncConflictFingerprint(
        originalPath: 'notebook/root/history-note.md',
        localContentHash: sha256ForString('v2-local'),
        remoteContentHash: sha256ForString('v2-remote'),
      );
      await conflictHistoryStore.record(
        layout: layout,
        namespace: currentNamespace(),
        fingerprint: fingerprint,
      );

      final result = await runSync();

      expect(result.conflictCount, 0);
      final files = await const FileSystemUtils().listFilesRecursively(rootDir);
      expect(files.where((f) => f.path.contains('.conflict.')), isEmpty);
      expect(await localFile.readAsString(), 'v2-remote');
    },
  );

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
    await rebuildLocalMetadata();
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

  test(
    'uses fast path after bootstrap without full remote traversal',
    () async {
      final countingClient = _CountingWebDavClient();
      webDavClient = countingClient;
      final layout = ChronicleLayout(rootDir);

      await const FileSystemUtils().atomicWriteString(
        layout.notebookRootNoteFile('fast-path'),
        'v1',
      );

      await runSync();
      expect(countingClient.rootListCalls, greaterThan(0));

      countingClient.resetCounts();
      await const FileSystemUtils().atomicWriteString(
        layout.notebookRootNoteFile('fast-path'),
        'v2',
      );
      await rebuildLocalMetadata();

      final result = await runSync();

      expect(result.errors, isEmpty);
      expect(countingClient.rootListCalls, 0);
      expect(countingClient.lockListCalls, greaterThan(0));
      expect(
        utf8.decode(
          await countingClient.downloadFile('notebook/root/fast-path.md'),
        ),
        'v2',
      );
    },
  );

  test('blocks sync when another active lock exists', () async {
    await writeRemoteLock(
      client: webDavClient,
      path: 'locks/sync_desktop_other-client.json',
      updatedTime: DateTime.utc(2026, 2, 17, 9, 59, 30).millisecondsSinceEpoch,
    );

    final result = await runSync();

    expect(result.blocker, isNotNull);
    expect(result.blocker!.type, SyncBlockerType.activeRemoteLock);
    expect(result.blocker!.lockClientId, 'other-client');
    expect(result.blocker!.lockClientType, 'desktop');
    expect(result.blocker!.competingLockCount, 1);
  });

  test('prunes stale competing lock and continues sync', () async {
    await writeRemoteLock(
      client: webDavClient,
      path: 'locks/sync_desktop_stale-client.json',
      updatedTime: DateTime.utc(2026, 2, 17, 9, 57, 30).millisecondsSinceEpoch,
      clientId: 'stale-client',
    );

    final result = await runSync();

    expect(result.blocker, isNull);
    expect(
      () => webDavClient.downloadFile('locks/sync_desktop_stale-client.json'),
      throwsException,
    );
  });

  test('force break remote lock removes competing locks and syncs', () async {
    final layout = ChronicleLayout(rootDir);
    await const FileSystemUtils().atomicWriteString(
      layout.notebookRootNoteFile('forced-lock-break'),
      'local content',
    );
    await writeRemoteLock(
      client: webDavClient,
      path: 'locks/sync_desktop_other-client.json',
      updatedTime: DateTime.utc(2026, 2, 17, 9, 59, 30).millisecondsSinceEpoch,
    );

    final result = await runSync(mode: SyncRunMode.forceBreakRemoteLockOnce);

    expect(result.blocker, isNull);
    expect(result.uploadedCount, greaterThanOrEqualTo(1));
    expect(
      () => webDavClient.downloadFile('locks/sync_desktop_other-client.json'),
      throwsException,
    );
  });

  test('force break remote lock aborts when lock deletion fails', () async {
    final blockingClient = _DeleteFailingLockWebDavClient(
      failingPath: 'locks/sync_desktop_other-client.json',
    );
    webDavClient = blockingClient;
    await writeRemoteLock(
      client: blockingClient,
      path: 'locks/sync_desktop_other-client.json',
      updatedTime: DateTime.utc(2026, 2, 17, 9, 59, 30).millisecondsSinceEpoch,
    );

    await expectLater(
      runSync(mode: SyncRunMode.forceBreakRemoteLockOnce),
      throwsA(isA<HttpException>()),
    );
  });

  test('enforces deletion fail-safe threshold', () async {
    final layout = ChronicleLayout(rootDir);
    for (var i = 0; i < 8; i++) {
      await const FileSystemUtils().atomicWriteString(
        layout.notebookRootNoteFile('bulk-$i'),
        'bulk-$i',
      );
    }

    await runSync();

    final remoteFiles = await webDavClient.listFilesRecursively('/');
    for (final file in remoteFiles) {
      if (file.path.startsWith('notebook/root/')) {
        await webDavClient.deleteFile(file.path);
      }
    }

    final result = await runSync();
    expect(result.blocker, isNotNull);
    expect(result.blocker!.type, SyncBlockerType.failSafeDeletionBlocked);
    expect(result.blocker!.candidateDeletionCount, 8);
    expect(result.blocker!.trackedCount, 10);
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
        layout.notebookRootNoteFile('local-note'),
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

  test(
    'prefers canonical notebook path when legacy and canonical remote both exist',
    () async {
      final layout = ChronicleLayout(rootDir);
      await webDavClient.uploadFile('orphans/dup.md', utf8.encode('legacy'));
      await webDavClient.uploadFile(
        'notebook/root/dup.md',
        utf8.encode('canonical'),
      );

      final result = await runSync();
      expect(result.downloadedCount, greaterThanOrEqualTo(1));

      final localFile = layout.notebookRootNoteFile('dup');
      expect(await localFile.exists(), isTrue);
      expect(await localFile.readAsString(), 'canonical');
    },
  );

  test(
    'legacy remote orphan coexistence does not trigger fail-safe deletion block',
    () async {
      final layout = ChronicleLayout(rootDir);
      await const FileSystemUtils().atomicWriteString(
        layout.notebookRootNoteFile('steady'),
        'stable',
      );

      await runSync();

      await webDavClient.uploadFile('orphans/steady.md', utf8.encode('stable'));
      final result = await runSync();

      expect(result.blocker, isNull);
      expect(
        utf8.decode(await webDavClient.downloadFile('orphans/steady.md')),
        'stable',
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
  Future<String?> readSyncProxyPassword() async => null;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> saveSyncPassword(String password) async {}

  @override
  Future<void> saveSyncProxyPassword(String password) async {}

  @override
  Future<void> clearSyncProxyPassword() async {}

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

class _CountingWebDavClient extends InMemoryWebDavClient {
  int rootListCalls = 0;
  int lockListCalls = 0;

  @override
  Future<List<WebDavFileMetadata>> listFilesRecursively(String rootPath) async {
    if (rootPath == '/') {
      rootListCalls += 1;
    }
    if (rootPath == 'locks') {
      lockListCalls += 1;
    }
    return super.listFilesRecursively(rootPath);
  }

  void resetCounts() {
    rootListCalls = 0;
    lockListCalls = 0;
  }
}

class _DeleteFailingLockWebDavClient extends InMemoryWebDavClient {
  _DeleteFailingLockWebDavClient({required this.failingPath});

  final String failingPath;

  @override
  Future<void> deleteFile(String path) async {
    if (path == failingPath) {
      throw const HttpException('failed to delete remote lock');
    }
    await super.deleteFile(path);
  }
}
