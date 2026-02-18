import 'dart:io';

import 'package:chronicle/core/file_system_utils.dart';
import 'package:chronicle/data/local_fs/chronicle_storage_initializer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Directory rootDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'chronicle-storage-initializer-test-',
    );
    rootDir = Directory('${tempDir.path}/Chronicle');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('serializes concurrent ensureInitialized calls', () async {
    final fs = _TrackingFileSystemUtils();
    final initializer = ChronicleStorageInitializer(fs);

    await Future.wait(<Future<void>>[
      initializer.ensureInitialized(rootDir),
      initializer.ensureInitialized(rootDir),
    ]);

    expect(fs.maxConcurrentOps, 1);
    expect(await File('${rootDir.path}/info.json').exists(), isTrue);
  });
}

class _TrackingFileSystemUtils extends FileSystemUtils {
  int _activeOps = 0;
  int maxConcurrentOps = 0;

  Future<void> _track(Future<void> Function() action) async {
    _activeOps += 1;
    if (_activeOps > maxConcurrentOps) {
      maxConcurrentOps = _activeOps;
    }
    try {
      await Future<void>.delayed(const Duration(milliseconds: 8));
      await action();
      await Future<void>.delayed(const Duration(milliseconds: 8));
    } finally {
      _activeOps -= 1;
    }
  }

  @override
  Future<void> ensureDirectory(Directory directory) {
    return _track(() => super.ensureDirectory(directory));
  }
}
