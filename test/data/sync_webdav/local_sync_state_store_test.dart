import 'dart:io';

import 'package:chronicle/core/app_directories.dart';
import 'package:chronicle/core/file_system_utils.dart';
import 'package:chronicle/data/sync_webdav/local_sync_state_store.dart';
import 'package:chronicle/data/sync_webdav/webdav_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late LocalSyncStateStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'chronicle-sync-state-store-test-',
    );
    store = LocalSyncStateStore(
      appDirectories: FixedAppDirectories(appSupport: tempDir, home: tempDir),
      fileSystemUtils: const FileSystemUtils(),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('loads saved state for matching namespace', () async {
    final now = DateTime.utc(2026, 2, 21, 10, 30);
    final namespace = store.buildNamespace(
      syncTargetUrl: 'https://example.com/dav/Chronicle',
      username: 'alice',
      storageRootPath: '/tmp/Chronicle',
      localFormatVersion: 2,
    );

    final input = <String, SyncFileState>{
      'orphans/note-a.md': SyncFileState(
        path: 'orphans/note-a.md',
        localHash: 'local-hash',
        remoteHash: 'remote-hash',
        updatedAt: now,
      ),
    };

    await store.save(namespace: namespace, states: input);
    final loaded = await store.load(namespace: namespace);

    expect(loaded.keys, input.keys);
    expect(loaded['orphans/note-a.md']!.localHash, 'local-hash');
    expect(loaded['orphans/note-a.md']!.remoteHash, 'remote-hash');
  });

  test('namespace mismatch auto-clears stale state', () async {
    final now = DateTime.utc(2026, 2, 21, 10, 31);
    final namespaceA = store.buildNamespace(
      syncTargetUrl: 'https://example.com/dav/Chronicle',
      username: 'alice',
      storageRootPath: '/tmp/Chronicle',
      localFormatVersion: 2,
    );
    final namespaceB = store.buildNamespace(
      syncTargetUrl: 'https://example.com/dav/Chronicle',
      username: 'alice',
      storageRootPath: '/tmp/Chronicle',
      localFormatVersion: 3,
    );

    await store.save(
      namespace: namespaceA,
      states: <String, SyncFileState>{
        'info.json': SyncFileState(
          path: 'info.json',
          localHash: 'a',
          remoteHash: 'a',
          updatedAt: now,
        ),
      },
    );

    final loaded = await store.load(namespace: namespaceB);
    expect(loaded, isEmpty);
    expect(await store.load(namespace: namespaceA), isEmpty);
  });

  test('clear removes only matching namespace state', () async {
    final now = DateTime.utc(2026, 2, 21, 10, 32);
    final namespace = store.buildNamespace(
      syncTargetUrl: 'https://example.com/dav/Chronicle',
      username: 'alice',
      storageRootPath: '/tmp/Chronicle',
      localFormatVersion: 2,
    );

    await store.save(
      namespace: namespace,
      states: <String, SyncFileState>{
        'info.json': SyncFileState(
          path: 'info.json',
          localHash: 'a',
          remoteHash: 'a',
          updatedAt: now,
        ),
      },
    );
    await store.clear(namespace: namespace);
    expect(await store.load(namespace: namespace), isEmpty);
  });
}
