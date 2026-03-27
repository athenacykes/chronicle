import 'dart:io';

import 'package:chronicle/core/file_hash.dart';
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
  late String localNoteRaw;
  late String remoteNoteRaw;
  late String localLinkRaw;
  late String remoteLinkRaw;
  late List<int> localBinaryBytes;
  late List<int> remoteBinaryBytes;

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
    localNoteRaw = '''---
id: "note-1"
matterId: null
phaseId: null
notebookFolderId: null
title: "Local Note"
createdAt: "2026-02-17T11:59:00Z"
updatedAt: "2026-02-17T12:00:00Z"
tags: []
isPinned: false
attachments: []
---

Local conflicting content
''';
    remoteNoteRaw = '''---
id: "note-1"
matterId: null
phaseId: null
notebookFolderId: null
title: "Current Note"
createdAt: "2026-02-17T11:59:00Z"
updatedAt: "2026-02-17T12:01:00Z"
tags: []
isPinned: false
attachments: []
---

Remote current content
''';
    await fs.atomicWriteString(
      layout.fromRelativePath('notebook/root/note-1.md'),
      remoteNoteRaw,
    );
    localLinkRaw =
        '{"id":"link-1","sourceNoteId":"note-1","targetNoteId":"note-2"}';
    remoteLinkRaw =
        '{"id":"link-1","sourceNoteId":"note-1","targetNoteId":"note-9"}';
    await fs.atomicWriteString(
      layout.fromRelativePath('links/link-1.json'),
      remoteLinkRaw,
    );
    localBinaryBytes = <int>[137, 80, 78, 71, 1, 2, 3];
    remoteBinaryBytes = <int>[137, 80, 78, 71, 7, 8, 9];
    await fs.atomicWriteBytes(
      layout.fromRelativePath('resources/image-1.png'),
      remoteBinaryBytes,
    );

    final localHash = sha256ForString(localNoteRaw);
    final remoteHash = sha256ForString(remoteNoteRaw);
    final conflict = layout.fromRelativePath(
      'notebook/root/note-1.conflict.20260217120000.client.md',
    );

    await fs.atomicWriteString(conflict, '''---
conflictType: "note"
originalPath: "notebook/root/note-1.md"
conflictDetectedAt: "2026-02-17T12:00:00Z"
localDevice: "desktop-a"
remoteDevice: "mobile-b"
localContentHash: "$localHash"
remoteContentHash: "$remoteHash"
conflictFingerprint: "${buildSyncConflictFingerprint(originalPath: 'notebook/root/note-1.md', localContentHash: localHash, remoteContentHash: remoteHash)}"
---

# [CONFLICT] notebook/root/note-1.md

This file contains local changes that conflicted with a remote update.

$localNoteRaw
''');

    final linkConflict = layout.fromRelativePath(
      'links/link-1.conflict.20260217120500.client.json',
    );
    await fs.atomicWriteString(linkConflict, localLinkRaw);

    final binaryConflict = layout.fromRelativePath(
      'resources/image-1.conflict.20260217121000.client.png',
    );
    await fs.atomicWriteBytes(binaryConflict, localBinaryBytes);
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

    expect(noteConflict.originalPath, 'notebook/root/note-1.md');
    expect(noteConflict.originalNoteId, 'note-1');
    expect(noteConflict.localDevice, 'desktop-a');
    expect(noteConflict.remoteDevice, 'mobile-b');
    expect(noteConflict.title, 'Local Note');
    expect(noteConflict.preview, contains('Local conflicting content'));

    expect(linkConflict.originalPath, 'links/link-1.json');
    expect(linkConflict.originalNoteId, isNull);
    expect(linkConflict.type, SyncConflictType.link);

    expect(binaryConflict.originalPath, 'resources/image-1.png');
    expect(binaryConflict.preview, 'Binary conflict file');

    final content = await service.readConflictContent(
      noteConflict.conflictPath,
    );
    expect(content, contains(localNoteRaw));

    final detail = await service.readConflictDetail(noteConflict.conflictPath);
    expect(detail, isNotNull);
    expect(detail!.localContent, contains('Title: Local Note'));
    expect(detail.localContent, contains('Local conflicting content'));
    expect(detail.mainFileContent, contains('Title: Current Note'));
    expect(detail.mainFileContent, contains('Remote current content'));
    expect(detail.originalFileMissing, isFalse);
    expect(detail.mainFileChangedSinceCapture, isFalse);
    expect(detail.hasActualDiff, isTrue);

    expect(
      await service.hasMatchingConflict(
        originalPath: 'notebook/root/note-1.md',
        localContentHash: sha256ForString(localNoteRaw),
        remoteContentHash: sha256ForString(remoteNoteRaw),
      ),
      isTrue,
    );

    await const FileSystemUtils().atomicWriteString(
      ChronicleLayout(rootDir).fromRelativePath('notebook/root/note-1.md'),
      remoteNoteRaw.replaceFirst('Current Note', 'Changed Current Note'),
    );
    final staleDetail = await service.readConflictDetail(
      noteConflict.conflictPath,
    );
    expect(staleDetail!.mainFileChangedSinceCapture, isTrue);

    final binaryContent = await service.readConflictContent(
      binaryConflict.conflictPath,
    );
    expect(binaryContent, isNull);

    await service.resolveConflict(
      linkConflict.conflictPath,
      choice: SyncConflictResolutionChoice.acceptRight,
    );
    final afterFirstResolve = await service.listConflicts();
    expect(afterFirstResolve.length, 2);

    await service.resolveConflict(
      binaryConflict.conflictPath,
      choice: SyncConflictResolutionChoice.acceptRight,
    );
    final afterSecondResolve = await service.listConflicts();
    expect(afterSecondResolve.length, 1);
    expect(afterSecondResolve.single.type, SyncConflictType.note);

    await service.resolveConflict(
      noteConflict.conflictPath,
      choice: SyncConflictResolutionChoice.acceptRight,
    );
    final afterThirdResolve = await service.listConflicts();
    expect(afterThirdResolve, isEmpty);
  });

  test(
    'acceptLeft overwrites original content for note, link, and binary',
    () async {
      final conflicts = await service.listConflicts();
      final noteConflict = conflicts.firstWhere(
        (c) => c.type == SyncConflictType.note,
      );
      final linkConflict = conflicts.firstWhere(
        (c) => c.type == SyncConflictType.link,
      );
      final binaryConflict = conflicts.firstWhere(
        (c) => c.type == SyncConflictType.unknown,
      );

      await service.resolveConflict(
        noteConflict.conflictPath,
        choice: SyncConflictResolutionChoice.acceptLeft,
      );
      await service.resolveConflict(
        linkConflict.conflictPath,
        choice: SyncConflictResolutionChoice.acceptLeft,
      );
      await service.resolveConflict(
        binaryConflict.conflictPath,
        choice: SyncConflictResolutionChoice.acceptLeft,
      );

      final layout = ChronicleLayout(rootDir);
      expect(
        await layout.fromRelativePath('notebook/root/note-1.md').readAsString(),
        localNoteRaw,
      );
      expect(
        await layout.fromRelativePath('links/link-1.json').readAsString(),
        localLinkRaw,
      );
      expect(
        await layout.fromRelativePath('resources/image-1.png').readAsBytes(),
        localBinaryBytes,
      );
      expect(await service.listConflicts(), isEmpty);
    },
  );

  test('auto-cleans conflicts with no actual diff', () async {
    final layout = ChronicleLayout(rootDir);
    final fs = const FileSystemUtils();
    final noOpNoteRaw = remoteNoteRaw.replaceFirst(
      'updatedAt: "2026-02-17T12:01:00Z"',
      'updatedAt: "2026-02-17T12:09:00Z"',
    );
    final noOpNoteConflict = layout.fromRelativePath(
      'notebook/root/note-1-duplicate.conflict.20260217122000.client.md',
    );
    await fs.atomicWriteString(noOpNoteConflict, '''---
conflictType: "note"
originalPath: "notebook/root/note-1.md"
conflictDetectedAt: "2026-02-17T12:20:00Z"
localDevice: "desktop-a"
remoteDevice: "mobile-b"
---

# [CONFLICT] notebook/root/note-1.md

This file contains local changes that conflicted with a remote update.

$noOpNoteRaw
''');
    final noOpLinkConflict = layout.fromRelativePath(
      'links/link-1.conflict.20260217123000.client.json',
    );
    await fs.atomicWriteString(
      noOpLinkConflict,
      '{ "targetNoteId" : "note-9", "sourceNoteId":"note-1", "id":"link-1" }',
    );

    final conflicts = await service.listConflicts();

    expect(
      conflicts.any(
        (conflict) =>
            conflict.conflictPath ==
            'notebook/root/note-1-duplicate.conflict.20260217122000.client.md',
      ),
      isFalse,
    );
    expect(
      conflicts.any(
        (conflict) =>
            conflict.conflictPath ==
            'links/link-1.conflict.20260217123000.client.json',
      ),
      isFalse,
    );
    expect(await noOpNoteConflict.exists(), isFalse);
    expect(await noOpLinkConflict.exists(), isFalse);
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
