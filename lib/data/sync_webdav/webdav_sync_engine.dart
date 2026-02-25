import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';

import '../../core/clock.dart';
import '../../core/file_hash.dart';
import '../../core/file_system_utils.dart';
import '../../domain/entities/sync_blocker.dart';
import '../../domain/entities/sync_result.dart';
import '../../domain/entities/sync_run_options.dart';
import '../local_fs/chronicle_layout.dart';
import '../local_fs/chronicle_storage_initializer.dart';
import '../local_fs/storage_root_locator.dart';
import 'local_sync_state_store.dart';
import 'webdav_client.dart';
import 'webdav_types.dart';

class WebDavSyncEngine {
  WebDavSyncEngine({
    required StorageRootLocator storageRootLocator,
    required ChronicleStorageInitializer storageInitializer,
    required FileSystemUtils fileSystemUtils,
    required Clock clock,
    required LocalSyncStateStore syncStateStore,
  }) : _storageRootLocator = storageRootLocator,
       _storageInitializer = storageInitializer,
       _fileSystemUtils = fileSystemUtils,
       _clock = clock,
       _syncStateStore = syncStateStore;

  final StorageRootLocator _storageRootLocator;
  final ChronicleStorageInitializer _storageInitializer;
  final FileSystemUtils _fileSystemUtils;
  final Clock _clock;
  final LocalSyncStateStore _syncStateStore;

  static const _activeLockTtlMs = 90000;
  static const _staleLockMs = 120000;

  Future<SyncResult> run({
    required WebDavClient client,
    required String clientId,
    required bool failSafe,
    required SyncRunOptions options,
    required String syncTargetUrl,
    required String syncUsername,
  }) async {
    final startedAt = _clock.nowUtc();
    _debugLog(
      'Starting sync run for client=$clientId failSafe=$failSafe '
      'mode=${options.mode.name}',
    );
    final errors = <String>[];
    var uploadedCount = 0;
    var downloadedCount = 0;
    var conflictCount = 0;
    var deletedCount = 0;

    final layout = await _layout();

    final lockPath = 'locks/sync_desktop_$clientId.json';
    Timer? heartbeat;
    try {
      await _ensureRemoteSkeleton(client);
      _debugLog('Remote skeleton ensured.');
      await _acquireLock(client, lockPath, clientId);
      _debugLog('Acquired sync lock: $lockPath');
      heartbeat = Timer.periodic(const Duration(seconds: 30), (_) async {
        await _writeLock(client, lockPath, clientId);
      });

      final localFormatVersion = await _readLocalFormatVersion(layout);
      final remoteFormatVersion = await _readRemoteFormatVersion(client);
      final versionBlocker = _buildVersionBlocker(
        mode: options.mode,
        localFormatVersion: localFormatVersion,
        remoteFormatVersion: remoteFormatVersion,
      );
      if (versionBlocker != null) {
        return SyncResult(
          uploadedCount: 0,
          downloadedCount: 0,
          conflictCount: 0,
          deletedCount: 0,
          startedAt: startedAt,
          endedAt: _clock.nowUtc(),
          errors: const <String>[],
          blocker: versionBlocker,
        );
      }

      final syncStateNamespace = _syncStateStore.buildNamespace(
        syncTargetUrl: syncTargetUrl,
        username: syncUsername,
        storageRootPath: layout.rootDirectory.path,
        localFormatVersion: localFormatVersion,
      );

      if (options.mode == SyncRunMode.recoverLocalWins ||
          options.mode == SyncRunMode.recoverRemoteWins) {
        await _syncStateStore.clear(namespace: syncStateNamespace);
      }

      final previousState = await _syncStateStore.load(
        namespace: syncStateNamespace,
      );
      final localFiles = await _listLocalFiles(layout);
      final remoteFiles = await _listRemoteFiles(client);
      _debugLog(
        'Scanned files: local=${localFiles.length}, remote=${remoteFiles.length}, '
        'previousState=${previousState.length}',
      );

      final allPaths = <String>{
        ...localFiles.keys,
        ...remoteFiles.keys,
      }.where((path) => !layout.isIgnoredSyncPath(path)).toList();

      final uploads = <String>[];
      final downloads = <String>[];
      final deleteLocals = <String>[];
      final deleteRemotes = <String>[];
      final conflicts = <String>[];

      for (final path in allPaths) {
        final local = localFiles[path]?.file;
        final remote = remoteFiles[path]?.metadata;
        final previous = previousState[path];

        if (options.mode == SyncRunMode.recoverLocalWins) {
          await _planRecoverLocalWins(
            path: path,
            local: local,
            remote: remote,
            uploads: uploads,
            deleteRemotes: deleteRemotes,
          );
          continue;
        }

        if (options.mode == SyncRunMode.recoverRemoteWins) {
          await _planRecoverRemoteWins(
            path: path,
            local: local,
            remote: remote,
            downloads: downloads,
            deleteLocals: deleteLocals,
          );
          continue;
        }

        if (local != null && remote == null) {
          final localHash = await sha256ForFile(local);
          if (previous != null &&
              previous.remoteHash.isNotEmpty &&
              previous.localHash == localHash) {
            deleteLocals.add(path);
          } else {
            uploads.add(path);
          }
          continue;
        }

        if (local == null && remote != null) {
          final remoteHash = _remoteHash(remote);
          if (previous != null &&
              previous.localHash.isNotEmpty &&
              previous.remoteHash == remoteHash) {
            deleteRemotes.add(path);
          } else {
            downloads.add(path);
          }
          continue;
        }

        if (local == null || remote == null) {
          continue;
        }

        final localHash = await sha256ForFile(local);
        final remoteHash = _remoteHash(remote);

        if (localHash == remoteHash) {
          continue;
        }

        if (previous == null) {
          final localStat = await local.stat();
          final localModified = localStat.modified.toUtc();
          if (localModified.isAfter(remote.updatedAt)) {
            uploads.add(path);
          } else {
            downloads.add(path);
          }
          continue;
        }

        final localChanged = previous.localHash != localHash;
        final remoteChanged = previous.remoteHash != remoteHash;

        if (localChanged && !remoteChanged) {
          uploads.add(path);
          continue;
        }
        if (!localChanged && remoteChanged) {
          downloads.add(path);
          continue;
        }
        if (!localChanged && !remoteChanged) {
          continue;
        }

        conflicts.add(path);
      }

      _debugLog(
        'Planned actions: uploads=${uploads.length}, downloads=${downloads.length}, '
        'deleteLocals=${deleteLocals.length}, deleteRemotes=${deleteRemotes.length}, '
        'conflicts=${conflicts.length}',
      );

      final candidateDeletionCount = deleteLocals.length + deleteRemotes.length;
      final trackedCount = allPaths.isEmpty ? 1 : allPaths.length;
      final allowMassDeletion =
          options.mode == SyncRunMode.forceApplyDeletionsOnce ||
          options.mode == SyncRunMode.recoverLocalWins ||
          options.mode == SyncRunMode.recoverRemoteWins;
      if (failSafe &&
          !allowMassDeletion &&
          candidateDeletionCount / trackedCount > 0.2) {
        _debugLog(
          'Fail-safe blocked deletions: candidate=$candidateDeletionCount '
          'tracked=$trackedCount',
        );
        return SyncResult(
          uploadedCount: 0,
          downloadedCount: 0,
          conflictCount: 0,
          deletedCount: 0,
          startedAt: startedAt,
          endedAt: _clock.nowUtc(),
          errors: const <String>[],
          blocker: SyncBlocker(
            type: SyncBlockerType.failSafeDeletionBlocked,
            candidateDeletionCount: candidateDeletionCount,
            trackedCount: trackedCount,
            localFormatVersion: localFormatVersion,
            remoteFormatVersion: remoteFormatVersion,
            message:
                'Sync fail-safe blocked $candidateDeletionCount deletions '
                'out of $trackedCount tracked files',
          ),
        );
      }

      for (final path in uploads) {
        try {
          final localEntry = localFiles[path];
          if (localEntry == null) {
            continue;
          }
          final bytes = await localEntry.file.readAsBytes();
          await client.uploadFile(path, bytes);
          uploadedCount++;
          _debugLog('Uploaded: $path (${bytes.length} bytes)');
        } catch (error) {
          errors.add('Upload failed for $path: $error');
          _debugLog('Upload failed: $path error=$error');
        }
      }

      for (final path in downloads) {
        try {
          final remoteEntry = remoteFiles[path];
          if (remoteEntry == null) {
            continue;
          }
          final bytes = await client.downloadFile(remoteEntry.sourcePath);
          final target = layout.fromRelativePath(path);
          await _fileSystemUtils.atomicWriteBytes(target, bytes);
          downloadedCount++;
          _debugLog('Downloaded: $path (${bytes.length} bytes)');
        } catch (error) {
          errors.add('Download failed for $path: $error');
          _debugLog('Download failed: $path error=$error');
        }
      }

      for (final path in deleteLocals) {
        try {
          final localEntry = localFiles[path];
          final file = layout.fromRelativePath(path);
          await _fileSystemUtils.deleteIfExists(file);
          if (localEntry != null && localEntry.sourcePath != path) {
            await _fileSystemUtils.deleteIfExists(
              layout.fromRelativePath(localEntry.sourcePath),
            );
          }
          deletedCount++;
          _debugLog('Deleted local: $path');
        } catch (error) {
          errors.add('Local delete failed for $path: $error');
          _debugLog('Local delete failed: $path error=$error');
        }
      }

      for (final path in deleteRemotes) {
        try {
          final remoteEntry = remoteFiles[path];
          if (remoteEntry == null) {
            continue;
          }
          final skipLegacyDelete =
              options.mode == SyncRunMode.normal && remoteEntry.isLegacyOrphan;
          if (skipLegacyDelete) {
            continue;
          }
          await client.deleteFile(remoteEntry.sourcePath);
          deletedCount++;
          _debugLog('Deleted remote: $path');
        } catch (error) {
          errors.add('Remote delete failed for $path: $error');
          _debugLog('Remote delete failed: $path error=$error');
        }
      }

      for (final path in conflicts) {
        try {
          final localEntry = localFiles[path];
          final remoteEntry = remoteFiles[path];
          if (localEntry == null || remoteEntry == null) {
            continue;
          }
          final localBytes = await localEntry.file.readAsBytes();

          final remoteBytes = await client.downloadFile(remoteEntry.sourcePath);
          await _fileSystemUtils.atomicWriteBytes(localEntry.file, remoteBytes);

          final conflictPath = _buildConflictPath(path, clientId);
          final conflictFile = layout.fromRelativePath(conflictPath);
          final conflictBytes = _buildConflictBytes(
            originalPath: path,
            localDevice: 'desktop-$clientId',
            localBytes: localBytes,
          );

          await _fileSystemUtils.atomicWriteBytes(conflictFile, conflictBytes);
          await client.uploadFile(conflictPath, conflictBytes);
          conflictCount++;
          _debugLog('Resolved conflict: $path -> $conflictPath');
        } catch (error) {
          errors.add('Conflict handling failed for $path: $error');
          _debugLog('Conflict handling failed: $path error=$error');
        }
      }

      final finalLocal = await _listLocalFiles(layout);
      final finalRemote = await _listRemoteFiles(client);
      final finalUnion = <String>{
        ...finalLocal.keys,
        ...finalRemote.keys,
      }.where((path) => !layout.isIgnoredSyncPath(path));

      final nextState = <String, SyncFileState>{};
      for (final path in finalUnion) {
        final local = finalLocal[path]?.file;
        final remote = finalRemote[path]?.metadata;
        nextState[path] = SyncFileState(
          path: path,
          localHash: local == null ? '' : await sha256ForFile(local),
          remoteHash: remote == null ? '' : _remoteHash(remote),
          updatedAt: _clock.nowUtc(),
        );
      }

      await _syncStateStore.save(
        namespace: syncStateNamespace,
        states: nextState,
      );
      _debugLog('Saved sync state for ${nextState.length} paths.');
    } finally {
      heartbeat?.cancel();
      await _releaseLock(client, lockPath);
      _debugLog('Released sync lock: $lockPath');
    }

    final endedAt = _clock.nowUtc();
    _debugLog(
      'Sync completed: uploaded=$uploadedCount downloaded=$downloadedCount '
      'deleted=$deletedCount conflicts=$conflictCount errors=${errors.length}',
    );
    return SyncResult(
      uploadedCount: uploadedCount,
      downloadedCount: downloadedCount,
      conflictCount: conflictCount,
      deletedCount: deletedCount,
      startedAt: startedAt,
      endedAt: endedAt,
      errors: errors,
      blocker: null,
    );
  }

  Future<void> _ensureRemoteSkeleton(WebDavClient client) async {
    await client.ensureDirectory('.sync');
    await client.ensureDirectory('locks');
    await client.ensureDirectory('notebook');
    await client.ensureDirectory('notebook/root');
    await client.ensureDirectory('notebook/folders');
    await client.ensureDirectory('orphans');
    await client.ensureDirectory('matters');
    await client.ensureDirectory('links');
    await client.ensureDirectory('resources');
  }

  Future<void> _acquireLock(
    WebDavClient client,
    String lockPath,
    String clientId,
  ) async {
    var delay = 2;
    for (var attempt = 0; attempt < 20; attempt++) {
      await _writeLock(client, lockPath, clientId);
      final locks = await _readActiveLocks(client);
      if (locks.isEmpty || locks.first.path == lockPath) {
        return;
      }

      await Future<void>.delayed(Duration(seconds: delay));
      delay = (delay * 2).clamp(2, 30);
    }

    throw Exception('Failed to acquire sync lock after multiple retries');
  }

  Future<void> _writeLock(
    WebDavClient client,
    String lockPath,
    String clientId,
  ) async {
    final now = _clock.nowUtc().millisecondsSinceEpoch;
    final payload = json.encode(<String, dynamic>{
      'type': 'sync',
      'clientType': 'desktop',
      'clientId': clientId,
      'updatedTime': now,
    });

    await client.uploadFile(lockPath, utf8.encode(payload));
  }

  Future<List<_SyncLock>> _readActiveLocks(WebDavClient client) async {
    final now = _clock.nowUtc().millisecondsSinceEpoch;
    final files = await client.listFilesRecursively('/');

    final locks = <_SyncLock>[];
    for (final file in files) {
      if (!file.path.startsWith('locks/sync_')) {
        continue;
      }

      try {
        final bytes = await client.downloadFile(file.path);
        final jsonMap = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
        final updated = (jsonMap['updatedTime'] as num).toInt();
        final age = now - updated;
        if (age <= _activeLockTtlMs) {
          locks.add(_SyncLock(path: file.path, updatedTime: updated));
        } else if (age > _staleLockMs) {
          await client.deleteFile(file.path);
        }
      } catch (_) {
        continue;
      }
    }

    locks.sort((a, b) {
      final time = a.updatedTime.compareTo(b.updatedTime);
      if (time != 0) {
        return time;
      }
      return a.path.compareTo(b.path);
    });

    return locks;
  }

  Future<void> _releaseLock(WebDavClient client, String lockPath) async {
    try {
      await client.deleteFile(lockPath);
    } catch (_) {
      // Do not fail sync completion if lock cleanup fails.
    }
  }

  void _debugLog(String message) {
    assert(() {
      // ignore: avoid_print
      print('[WebDAV][Sync] $message');
      return true;
    }());
  }

  Future<Map<String, _LocalSyncEntry>> _listLocalFiles(
    ChronicleLayout layout,
  ) async {
    final files = await _fileSystemUtils.listFilesRecursively(
      layout.rootDirectory,
    );
    final out = <String, _LocalSyncEntry>{};
    for (final file in files) {
      final relative = layout.relativePath(file);
      if (layout.isIgnoredSyncPath(relative)) {
        continue;
      }
      final canonicalPath = _canonicalSyncPath(relative);
      final entry = _LocalSyncEntry(file: file, sourcePath: relative);
      final existing = out[canonicalPath];
      if (existing == null ||
          (_isLegacyOrphanPath(existing.sourcePath) &&
              !_isLegacyOrphanPath(relative))) {
        out[canonicalPath] = entry;
      }
    }
    return out;
  }

  Future<Map<String, _RemoteSyncEntry>> _listRemoteFiles(
    WebDavClient client,
  ) async {
    final files = await client.listFilesRecursively('/');
    final out = <String, _RemoteSyncEntry>{};
    for (final file in files) {
      final canonicalPath = _canonicalSyncPath(file.path);
      final entry = _RemoteSyncEntry(
        metadata: file,
        sourcePath: file.path,
        isLegacyOrphan: _isLegacyOrphanPath(file.path),
      );
      final existing = out[canonicalPath];
      if (existing == null ||
          (existing.isLegacyOrphan && !entry.isLegacyOrphan)) {
        out[canonicalPath] = entry;
      }
    }
    return out;
  }

  String _canonicalSyncPath(String path) {
    if (_isLegacyOrphanPath(path)) {
      final suffix = path.substring('orphans/'.length);
      return 'notebook/root/$suffix';
    }
    return path;
  }

  bool _isLegacyOrphanPath(String path) {
    return path.startsWith('orphans/');
  }

  String _remoteHash(WebDavFileMetadata metadata) {
    if (metadata.etag != null && metadata.etag!.isNotEmpty) {
      return metadata.etag!;
    }
    return '${metadata.updatedAt.millisecondsSinceEpoch}:${metadata.size}';
  }

  String _buildConflictPath(String originalPath, String clientId) {
    final stamp = DateFormat('yyyyMMddHHmmss').format(_clock.nowUtc());
    final dot = originalPath.lastIndexOf('.');
    if (dot <= 0) {
      return '$originalPath.conflict.$stamp.$clientId';
    }
    final base = originalPath.substring(0, dot);
    final ext = originalPath.substring(dot);
    return '$base.conflict.$stamp.$clientId$ext';
  }

  List<int> _buildConflictBytes({
    required String originalPath,
    required String localDevice,
    required List<int> localBytes,
  }) {
    if (!originalPath.endsWith('.md')) {
      return localBytes;
    }

    final now = _clock.nowUtc();
    final body = utf8.decode(localBytes, allowMalformed: true);
    final content =
        '''---
conflictType: "note"
originalPath: "$originalPath"
conflictDetectedAt: "${now.toIso8601String()}"
localDevice: "$localDevice"
remoteDevice: "unknown"
---

# [CONFLICT] $originalPath

This file contains local changes that conflicted with a remote update.

$body
''';
    return utf8.encode(content);
  }

  Future<ChronicleLayout> _layout() async {
    final root = await _storageRootLocator.requireRootDirectory();
    await _storageInitializer.ensureInitialized(root);
    return ChronicleLayout(root);
  }

  Future<int> _readLocalFormatVersion(ChronicleLayout layout) async {
    if (!await layout.infoFile.exists()) {
      return 0;
    }
    try {
      final raw = await layout.infoFile.readAsString();
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return (decoded['formatVersion'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int?> _readRemoteFormatVersion(WebDavClient client) async {
    try {
      final bytes = await client.downloadFile('info.json');
      final raw = utf8.decode(bytes, allowMalformed: true);
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return (decoded['formatVersion'] as num?)?.toInt();
    } catch (error) {
      if (_isRemoteInfoMissing(error)) {
        return null;
      }
      rethrow;
    }
  }

  bool _isRemoteInfoMissing(Object error) {
    if (error is HttpException && error.message.contains('404')) {
      return true;
    }
    if (error is Exception &&
        error.toString().toLowerCase().contains('file not found')) {
      return true;
    }
    if (error is SocketException) {
      return false;
    }
    final lower = error.toString().toLowerCase();
    return lower.contains('404') || lower.contains('not found');
  }

  SyncBlocker? _buildVersionBlocker({
    required SyncRunMode mode,
    required int localFormatVersion,
    required int? remoteFormatVersion,
  }) {
    if (remoteFormatVersion == null) {
      return null;
    }
    if (remoteFormatVersion > localFormatVersion) {
      return SyncBlocker(
        type: SyncBlockerType.versionMismatchClientTooOld,
        localFormatVersion: localFormatVersion,
        remoteFormatVersion: remoteFormatVersion,
        message:
            'Remote format version ($remoteFormatVersion) is newer than local '
            'format version ($localFormatVersion). Upgrade Chronicle first.',
      );
    }
    if (remoteFormatVersion < localFormatVersion &&
        mode != SyncRunMode.recoverLocalWins) {
      return SyncBlocker(
        type: SyncBlockerType.versionMismatchRemoteOlder,
        localFormatVersion: localFormatVersion,
        remoteFormatVersion: remoteFormatVersion,
        message:
            'Remote format version ($remoteFormatVersion) is older than local '
            'format version ($localFormatVersion). Use Local Wins recovery.',
      );
    }
    return null;
  }

  Future<void> _planRecoverLocalWins({
    required String path,
    required File? local,
    required WebDavFileMetadata? remote,
    required List<String> uploads,
    required List<String> deleteRemotes,
  }) async {
    if (local != null && remote == null) {
      uploads.add(path);
      return;
    }
    if (local == null && remote != null) {
      deleteRemotes.add(path);
      return;
    }
    if (local == null || remote == null) {
      return;
    }
    final localHash = await sha256ForFile(local);
    final remoteHash = _remoteHash(remote);
    if (localHash != remoteHash) {
      uploads.add(path);
    }
  }

  Future<void> _planRecoverRemoteWins({
    required String path,
    required File? local,
    required WebDavFileMetadata? remote,
    required List<String> downloads,
    required List<String> deleteLocals,
  }) async {
    if (local != null && remote == null) {
      deleteLocals.add(path);
      return;
    }
    if (local == null && remote != null) {
      downloads.add(path);
      return;
    }
    if (local == null || remote == null) {
      return;
    }
    final localHash = await sha256ForFile(local);
    final remoteHash = _remoteHash(remote);
    if (localHash != remoteHash) {
      downloads.add(path);
    }
  }
}

class _SyncLock {
  const _SyncLock({required this.path, required this.updatedTime});

  final String path;
  final int updatedTime;
}

class _LocalSyncEntry {
  const _LocalSyncEntry({required this.file, required this.sourcePath});

  final File file;
  final String sourcePath;
}

class _RemoteSyncEntry {
  const _RemoteSyncEntry({
    required this.metadata,
    required this.sourcePath,
    required this.isLegacyOrphan,
  });

  final WebDavFileMetadata metadata;
  final String sourcePath;
  final bool isLegacyOrphan;
}
