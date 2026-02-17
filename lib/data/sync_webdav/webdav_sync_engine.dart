import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';

import '../../core/clock.dart';
import '../../core/file_hash.dart';
import '../../core/file_system_utils.dart';
import '../../domain/entities/sync_result.dart';
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
    bool allowMassDeletion = false,
  }) async {
    final startedAt = _clock.nowUtc();
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
      await _acquireLock(client, lockPath, clientId);
      heartbeat = Timer.periodic(const Duration(seconds: 30), (_) async {
        await _writeLock(client, lockPath, clientId);
      });

      final previousState = await _syncStateStore.load();
      final localFiles = await _listLocalFiles(layout);
      final remoteFiles = await _listRemoteFiles(client);

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
        final local = localFiles[path];
        final remote = remoteFiles[path];
        final previous = previousState[path];

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

      final candidateDeletionCount = deleteLocals.length + deleteRemotes.length;
      final trackedCount = allPaths.isEmpty ? 1 : allPaths.length;
      if (failSafe &&
          !allowMassDeletion &&
          candidateDeletionCount / trackedCount > 0.2) {
        throw Exception(
          'Sync fail-safe blocked $candidateDeletionCount deletions '
          'out of $trackedCount tracked files',
        );
      }

      for (final path in uploads) {
        try {
          final localFile = localFiles[path];
          if (localFile == null) {
            continue;
          }
          final bytes = await localFile.readAsBytes();
          await client.uploadFile(path, bytes);
          uploadedCount++;
        } catch (error) {
          errors.add('Upload failed for $path: $error');
        }
      }

      for (final path in downloads) {
        try {
          final bytes = await client.downloadFile(path);
          final target = layout.fromRelativePath(path);
          await _fileSystemUtils.atomicWriteBytes(target, bytes);
          downloadedCount++;
        } catch (error) {
          errors.add('Download failed for $path: $error');
        }
      }

      for (final path in deleteLocals) {
        try {
          final file = layout.fromRelativePath(path);
          await _fileSystemUtils.deleteIfExists(file);
          deletedCount++;
        } catch (error) {
          errors.add('Local delete failed for $path: $error');
        }
      }

      for (final path in deleteRemotes) {
        try {
          await client.deleteFile(path);
          deletedCount++;
        } catch (error) {
          errors.add('Remote delete failed for $path: $error');
        }
      }

      for (final path in conflicts) {
        try {
          final localFile = localFiles[path];
          if (localFile == null) {
            continue;
          }
          final localBytes = await localFile.readAsBytes();

          final remoteBytes = await client.downloadFile(path);
          await _fileSystemUtils.atomicWriteBytes(localFile, remoteBytes);

          final conflictPath = _buildConflictPath(path, clientId);
          final conflictFile = layout.fromRelativePath(conflictPath);
          final conflictContent = _buildConflictContent(
            originalPath: path,
            localDevice: 'desktop-$clientId',
            localBytes: localBytes,
          );

          await _fileSystemUtils.atomicWriteString(
            conflictFile,
            conflictContent,
          );
          await client.uploadFile(conflictPath, utf8.encode(conflictContent));
          conflictCount++;
        } catch (error) {
          errors.add('Conflict handling failed for $path: $error');
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
        final local = finalLocal[path];
        final remote = finalRemote[path];
        nextState[path] = SyncFileState(
          path: path,
          localHash: local == null ? '' : await sha256ForFile(local),
          remoteHash: remote == null ? '' : _remoteHash(remote),
          updatedAt: _clock.nowUtc(),
        );
      }

      await _syncStateStore.save(nextState);
    } finally {
      heartbeat?.cancel();
      await _releaseLock(client, lockPath);
    }

    final endedAt = _clock.nowUtc();
    return SyncResult(
      uploadedCount: uploadedCount,
      downloadedCount: downloadedCount,
      conflictCount: conflictCount,
      deletedCount: deletedCount,
      startedAt: startedAt,
      endedAt: endedAt,
      errors: errors,
    );
  }

  Future<void> _ensureRemoteSkeleton(WebDavClient client) async {
    await client.ensureDirectory('.sync');
    await client.ensureDirectory('locks');
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

  Future<Map<String, File>> _listLocalFiles(ChronicleLayout layout) async {
    final files = await _fileSystemUtils.listFilesRecursively(
      layout.rootDirectory,
    );
    final out = <String, File>{};
    for (final file in files) {
      final relative = layout.relativePath(file);
      if (layout.isIgnoredSyncPath(relative)) {
        continue;
      }
      out[relative] = file;
    }
    return out;
  }

  Future<Map<String, WebDavFileMetadata>> _listRemoteFiles(
    WebDavClient client,
  ) async {
    final files = await client.listFilesRecursively('/');
    final out = <String, WebDavFileMetadata>{};
    for (final file in files) {
      out[file.path] = file;
    }
    return out;
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

  String _buildConflictContent({
    required String originalPath,
    required String localDevice,
    required List<int> localBytes,
  }) {
    if (!originalPath.endsWith('.md')) {
      return utf8.decode(localBytes);
    }

    final now = _clock.nowUtc();
    final body = utf8.decode(localBytes);
    return '''---
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
  }

  Future<ChronicleLayout> _layout() async {
    final root = await _storageRootLocator.requireRootDirectory();
    await _storageInitializer.ensureInitialized(root);
    return ChronicleLayout(root);
  }
}

class _SyncLock {
  const _SyncLock({required this.path, required this.updatedTime});

  final String path;
  final int updatedTime;
}
