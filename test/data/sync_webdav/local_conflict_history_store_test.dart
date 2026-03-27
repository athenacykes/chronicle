import 'dart:io';

import 'package:chronicle/core/file_system_utils.dart';
import 'package:chronicle/data/local_fs/chronicle_layout.dart';
import 'package:chronicle/data/local_fs/chronicle_storage_initializer.dart';
import 'package:chronicle/data/sync_webdav/local_conflict_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Directory rootDir;
  late ChronicleLayout layout;
  late LocalConflictHistoryStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'chronicle-conflict-history-test-',
    );
    rootDir = Directory('${tempDir.path}/Chronicle');
    await ChronicleStorageInitializer(
      const FileSystemUtils(),
    ).ensureInitialized(rootDir);
    layout = ChronicleLayout(rootDir);
    store = LocalConflictHistoryStore(fileSystemUtils: const FileSystemUtils());
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('records and loads fingerprints for matching namespace', () async {
    await store.record(
      layout: layout,
      namespace: 'namespace-a',
      fingerprint: 'fp-1',
    );
    await store.record(
      layout: layout,
      namespace: 'namespace-a',
      fingerprint: 'fp-2',
    );

    final loaded = await store.load(layout: layout, namespace: 'namespace-a');
    expect(loaded, {'fp-1', 'fp-2'});
  });

  test('namespace mismatch clears stale history', () async {
    await store.record(
      layout: layout,
      namespace: 'namespace-a',
      fingerprint: 'fp-1',
    );

    final loaded = await store.load(layout: layout, namespace: 'namespace-b');
    expect(loaded, isEmpty);
    expect(await store.load(layout: layout, namespace: 'namespace-a'), isEmpty);
  });

  test('clear removes matching namespace history', () async {
    await store.record(
      layout: layout,
      namespace: 'namespace-a',
      fingerprint: 'fp-1',
    );

    await store.clear(layout: layout, namespace: 'namespace-a');
    expect(await store.load(layout: layout, namespace: 'namespace-a'), isEmpty);
  });
}
