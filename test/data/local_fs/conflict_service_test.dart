import 'dart:io';

import 'package:chronicle/core/file_system_utils.dart';
import 'package:chronicle/data/local_fs/chronicle_layout.dart';
import 'package:chronicle/data/local_fs/chronicle_storage_initializer.dart';
import 'package:chronicle/data/local_fs/conflict_service.dart';
import 'package:chronicle/data/local_fs/storage_root_locator.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/entities/sync_conflict.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Directory rootDir;
  late ConflictService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'chronicle-conflicts-test-',
    );
    rootDir = Directory('${tempDir.path}/Chronicle');

    final settings = _InMemorySettingsRepository(
      AppSettings(
        storageRootPath: rootDir.path,
        clientId: 'client-conflict',
        syncConfig: SyncConfig.initial(),
        lastSyncAt: null,
      ),
    );

    final fs = const FileSystemUtils();
    final initializer = ChronicleStorageInitializer(fs);
    await initializer.ensureInitialized(rootDir);

    service = ConflictService(
      storageRootLocator: StorageRootLocator(settings),
      storageInitializer: initializer,
      fileSystemUtils: fs,
    );

    final layout = ChronicleLayout(rootDir);
    final conflict = layout.fromRelativePath(
      'orphans/note-1.conflict.20260217120000.client.md',
    );

    await fs.atomicWriteString(conflict, '''---
conflictType: "note"
originalPath: "orphans/note-1.md"
conflictDetectedAt: "2026-02-17T12:00:00Z"
localDevice: "desktop-a"
remoteDevice: "mobile-b"
---

# [CONFLICT] Note 1

Local conflicting content
''');

    final linkConflict = layout.fromRelativePath(
      'links/link-1.conflict.20260217120500.client.json',
    );
    await fs.atomicWriteString(
      linkConflict,
      '{"id":"link-1","sourceNoteId":"note-1","targetNoteId":"note-2"}',
    );

    final binaryConflict = layout.fromRelativePath(
      'resources/image-1.conflict.20260217121000.client.png',
    );
    await fs.atomicWriteBytes(binaryConflict, <int>[137, 80, 78, 71, 1, 2, 3]);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('lists, reads and resolves conflicts', () async {
    final conflicts = await service.listConflicts();
    expect(conflicts.length, 3);

    final noteConflict = conflicts.firstWhere(
      (conflict) => conflict.type == SyncConflictType.note,
    );
    final linkConflict = conflicts.firstWhere(
      (conflict) => conflict.type == SyncConflictType.link,
    );
    final binaryConflict = conflicts.firstWhere(
      (conflict) => conflict.type == SyncConflictType.unknown,
    );

    expect(noteConflict.originalPath, 'orphans/note-1.md');
    expect(noteConflict.originalNoteId, 'note-1');
    expect(noteConflict.localDevice, 'desktop-a');
    expect(noteConflict.remoteDevice, 'mobile-b');

    expect(linkConflict.originalPath, 'links/link-1.json');
    expect(linkConflict.originalNoteId, isNull);
    expect(linkConflict.type, SyncConflictType.link);

    expect(binaryConflict.originalPath, 'resources/image-1.png');
    expect(binaryConflict.preview, 'Binary conflict file');

    final content = await service.readConflictContent(
      noteConflict.conflictPath,
    );
    expect(content, contains('Local conflicting content'));

    final binaryContent = await service.readConflictContent(
      binaryConflict.conflictPath,
    );
    expect(binaryContent, isNull);

    await service.resolveConflict(linkConflict.conflictPath);
    final afterFirstResolve = await service.listConflicts();
    expect(afterFirstResolve.length, 2);

    await service.resolveConflict(binaryConflict.conflictPath);
    final afterSecondResolve = await service.listConflicts();
    expect(afterSecondResolve.length, 1);
    expect(afterSecondResolve.single.type, SyncConflictType.note);

    await service.resolveConflict(noteConflict.conflictPath);
    final afterThirdResolve = await service.listConflicts();
    expect(afterThirdResolve, isEmpty);
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
