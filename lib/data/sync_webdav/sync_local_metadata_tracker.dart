import 'dart:convert';
import 'dart:io';

import '../../core/clock.dart';
import '../../core/file_hash.dart';
import '../../core/file_system_utils.dart';
import '../local_fs/chronicle_layout.dart';
import '../local_fs/chronicle_storage_initializer.dart';
import '../local_fs/storage_root_locator.dart';
import 'local_sync_metadata_store.dart';
import 'webdav_types.dart';

class SyncLocalMetadataTracker {
  SyncLocalMetadataTracker({
    required StorageRootLocator storageRootLocator,
    required ChronicleStorageInitializer storageInitializer,
    required FileSystemUtils fileSystemUtils,
    required Clock clock,
    required LocalSyncMetadataStore metadataStore,
  }) : _storageRootLocator = storageRootLocator,
       _storageInitializer = storageInitializer,
       _fileSystemUtils = fileSystemUtils,
       _clock = clock,
       _metadataStore = metadataStore;

  final StorageRootLocator _storageRootLocator;
  final ChronicleStorageInitializer _storageInitializer;
  final FileSystemUtils _fileSystemUtils;
  final Clock _clock;
  final LocalSyncMetadataStore _metadataStore;

  Future<void> recordStringWrite(File file, String content) {
    final encoded = utf8.encode(content);
    return _recordEntry(
      file,
      contentHash: sha256ForString(content),
      size: encoded.length,
      modifiedAt: _clock.nowUtc(),
    );
  }

  Future<void> recordBytesWrite(File file, List<int> bytes) async {
    await _recordEntry(
      file,
      contentHash: await sha256ForBytes(bytes),
      size: bytes.length,
      modifiedAt: _clock.nowUtc(),
    );
  }

  Future<void> recordFileWrite(File file) async {
    if (!await file.exists()) {
      await recordDelete(file);
      return;
    }
    final bytes = await file.readAsBytes();
    final stat = await file.stat();
    await _recordEntry(
      file,
      contentHash: await sha256ForBytes(bytes),
      size: bytes.length,
      modifiedAt: stat.modified.toUtc(),
    );
  }

  Future<void> recordDelete(File file) async {
    final layout = await _layout();
    final relative = layout.relativePath(file);
    if (layout.isIgnoredSyncPath(relative)) {
      return;
    }

    final namespace = await _namespace(layout);
    final snapshot = await _metadataStore.load(namespace: namespace);
    final nextEntries = Map<String, LocalSyncMetadataEntry>.from(
      snapshot.entries,
    )..remove(_canonicalSyncPath(relative));
    await _metadataStore.save(
      namespace: namespace,
      snapshot: snapshot.copyWith(entries: nextEntries),
    );
  }

  Future<void> rebuildFromDisk() async {
    final layout = await _layout();
    final namespace = await _namespace(layout);
    final files = await _fileSystemUtils.listFilesRecursively(
      layout.rootDirectory,
    );
    final entries = <String, LocalSyncMetadataEntry>{};
    for (final file in files) {
      final relative = layout.relativePath(file);
      if (layout.isIgnoredSyncPath(relative)) {
        continue;
      }
      final bytes = await file.readAsBytes();
      final stat = await file.stat();
      final canonicalPath = _canonicalSyncPath(relative);
      final entry = LocalSyncMetadataEntry(
        canonicalPath: canonicalPath,
        sourcePath: relative,
        contentHash: await sha256ForBytes(bytes),
        size: bytes.length,
        modifiedAt: stat.modified.toUtc(),
      );
      final existing = entries[canonicalPath];
      if (existing == null ||
          (_isLegacyOrphanPath(existing.sourcePath) &&
              !_isLegacyOrphanPath(relative))) {
        entries[canonicalPath] = entry;
      }
    }

    await _metadataStore.save(
      namespace: namespace,
      snapshot: LocalSyncMetadataSnapshot(
        entries: entries,
        dirty: false,
        runsSinceAudit: 0,
        lastAuditAt: _clock.nowUtc(),
      ),
    );
  }

  Future<void> markDirty() async {
    final layout = await _layout();
    final namespace = await _namespace(layout);
    final snapshot = await _metadataStore.load(namespace: namespace);
    await _metadataStore.save(
      namespace: namespace,
      snapshot: snapshot.copyWith(dirty: true),
    );
  }

  Future<void> _recordEntry(
    File file, {
    required String contentHash,
    required int size,
    required DateTime modifiedAt,
  }) async {
    final layout = await _layout();
    final relative = layout.relativePath(file);
    if (layout.isIgnoredSyncPath(relative)) {
      return;
    }

    final namespace = await _namespace(layout);
    final snapshot = await _metadataStore.load(namespace: namespace);
    final canonicalPath = _canonicalSyncPath(relative);
    final nextEntries =
        Map<String, LocalSyncMetadataEntry>.from(snapshot.entries)
          ..[canonicalPath] = LocalSyncMetadataEntry(
            canonicalPath: canonicalPath,
            sourcePath: relative,
            contentHash: contentHash,
            size: size,
            modifiedAt: modifiedAt.toUtc(),
          );
    await _metadataStore.save(
      namespace: namespace,
      snapshot: snapshot.copyWith(entries: nextEntries),
    );
  }

  Future<ChronicleLayout> _layout() async {
    final root = await _storageRootLocator.requireRootDirectory();
    await _storageInitializer.ensureInitialized(root);
    return ChronicleLayout(root);
  }

  Future<String> _namespace(ChronicleLayout layout) async {
    final localFormatVersion = await _readLocalFormatVersion(layout);
    return _metadataStore.buildNamespace(
      storageRootPath: layout.rootDirectory.path,
      localFormatVersion: localFormatVersion,
    );
  }

  Future<int> _readLocalFormatVersion(ChronicleLayout layout) async {
    if (!await layout.infoFile.exists()) {
      return 0;
    }
    try {
      final raw = await layout.infoFile.readAsString();
      final formatVersionMatch = RegExp(
        r'"formatVersion"\s*:\s*(\d+)',
      ).firstMatch(raw);
      return int.parse(formatVersionMatch?.group(1) ?? '0');
    } catch (_) {
      return 0;
    }
  }

  String _canonicalSyncPath(String path) {
    if (_isLegacyOrphanPath(path)) {
      final suffix = path.substring('orphans/'.length);
      return 'notebook/root/$suffix';
    }
    return path;
  }

  bool _isLegacyOrphanPath(String path) => path.startsWith('orphans/');
}
