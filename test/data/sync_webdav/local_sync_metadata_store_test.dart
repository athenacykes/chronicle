import 'dart:io';

import 'package:chronicle/core/app_directories.dart';
import 'package:chronicle/core/file_system_utils.dart';
import 'package:chronicle/data/sync_webdav/local_sync_metadata_store.dart';
import 'package:chronicle/data/sync_webdav/webdav_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late LocalSyncMetadataStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'chronicle-local-sync-metadata-test-',
    );
    store = LocalSyncMetadataStore(
      appDirectories: FixedAppDirectories(appSupport: tempDir, home: tempDir),
      fileSystemUtils: const FileSystemUtils(),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('loads saved metadata snapshot for matching namespace', () async {
    final namespace = store.buildNamespace(
      storageRootPath: '/tmp/Chronicle',
      localFormatVersion: 2,
    );
    final snapshot = LocalSyncMetadataSnapshot(
      entries: <String, LocalSyncMetadataEntry>{
        'notebook/root/a.md': LocalSyncMetadataEntry(
          canonicalPath: 'notebook/root/a.md',
          sourcePath: 'notebook/root/a.md',
          contentHash: 'hash-a',
          size: 12,
          modifiedAt: DateTime.utc(2026, 2, 21, 10, 30),
        ),
      },
      dirty: false,
      runsSinceAudit: 3,
      lastAuditAt: DateTime.utc(2026, 2, 21, 10, 0),
    );

    await store.save(namespace: namespace, snapshot: snapshot);
    final loaded = await store.load(namespace: namespace);

    expect(loaded.entries.keys, snapshot.entries.keys);
    expect(loaded.entries['notebook/root/a.md']!.contentHash, 'hash-a');
    expect(loaded.runsSinceAudit, 3);
    expect(loaded.lastAuditAt, DateTime.utc(2026, 2, 21, 10, 0));
  });

  test('namespace mismatch clears stale metadata snapshot', () async {
    final namespaceA = store.buildNamespace(
      storageRootPath: '/tmp/Chronicle',
      localFormatVersion: 2,
    );
    final namespaceB = store.buildNamespace(
      storageRootPath: '/tmp/Chronicle',
      localFormatVersion: 3,
    );

    await store.save(
      namespace: namespaceA,
      snapshot: LocalSyncMetadataSnapshot(
        entries: <String, LocalSyncMetadataEntry>{
          'info.json': LocalSyncMetadataEntry(
            canonicalPath: 'info.json',
            sourcePath: 'info.json',
            contentHash: 'hash-info',
            size: 32,
            modifiedAt: DateTime.utc(2026, 2, 21, 11),
          ),
        },
        dirty: true,
        runsSinceAudit: 8,
        lastAuditAt: DateTime.utc(2026, 2, 21, 10, 0),
      ),
    );

    expect(
      await store.load(namespace: namespaceB),
      LocalSyncMetadataSnapshot.empty,
    );
    expect(
      await store.load(namespace: namespaceA),
      LocalSyncMetadataSnapshot.empty,
    );
  });

  test('clear removes only matching namespace metadata snapshot', () async {
    final namespace = store.buildNamespace(
      storageRootPath: '/tmp/Chronicle',
      localFormatVersion: 2,
    );

    await store.save(
      namespace: namespace,
      snapshot: LocalSyncMetadataSnapshot(
        entries: const <String, LocalSyncMetadataEntry>{},
        dirty: true,
        runsSinceAudit: 1,
        lastAuditAt: null,
      ),
    );

    await store.clear(namespace: namespace);
    expect(
      await store.load(namespace: namespace),
      LocalSyncMetadataSnapshot.empty,
    );
  });
}
