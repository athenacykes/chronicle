import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';

import '../../core/clock.dart';
import '../../core/file_hash.dart';
import '../../core/file_system_utils.dart';
import '../../core/json_utils.dart';
import '../../domain/entities/sync_bootstrap_assessment.dart';
import '../../domain/entities/sync_blocker.dart';
import '../../domain/entities/sync_conflict.dart';
import '../../domain/entities/sync_progress.dart';
import '../../domain/entities/sync_result.dart';
import '../../domain/entities/sync_run_options.dart';
import '../local_fs/chronicle_layout.dart';
import '../local_fs/chronicle_storage_initializer.dart';
import '../local_fs/conflict_service.dart';
import '../local_fs/storage_root_locator.dart';
import 'local_conflict_history_store.dart';
import 'local_sync_metadata_store.dart';
import 'local_sync_state_store.dart';
import 'webdav_client.dart';
import 'webdav_types.dart';

class WebDavSyncEngine {
  WebDavSyncEngine({
    required StorageRootLocator storageRootLocator,
    required ChronicleStorageInitializer storageInitializer,
    required FileSystemUtils fileSystemUtils,
    required Clock clock,
    required LocalSyncMetadataStore localSyncMetadataStore,
    required LocalSyncStateStore syncStateStore,
    required ConflictService conflictService,
    required LocalConflictHistoryStore conflictHistoryStore,
  }) : _storageRootLocator = storageRootLocator,
       _storageInitializer = storageInitializer,
       _fileSystemUtils = fileSystemUtils,
       _clock = clock,
       _localSyncMetadataStore = localSyncMetadataStore,
       _syncStateStore = syncStateStore,
       _conflictService = conflictService,
       _conflictHistoryStore = conflictHistoryStore;

  final StorageRootLocator _storageRootLocator;
  final ChronicleStorageInitializer _storageInitializer;
  final FileSystemUtils _fileSystemUtils;
  final Clock _clock;
  final LocalSyncMetadataStore _localSyncMetadataStore;
  final LocalSyncStateStore _syncStateStore;
  final ConflictService _conflictService;
  final LocalConflictHistoryStore _conflictHistoryStore;

  static const _activeLockTtlMs = 90000;
  static const _staleLockMs = 120000;
  static const _syncProtocolVersion = 1;
  static const _manifestPath = '.sync/manifest.json';
  static const _pendingSyncPath = '.sync/pending_sync.json';
  static const _infoPath = 'info.json';
  static const _notebookFoldersIndexPath = 'notebook/folders.json';
  static const _auditMaxRuns = 20;
  static final Duration _auditMaxAge = const Duration(hours: 24);

  Future<SyncBootstrapAssessment> assessBootstrap({
    required WebDavClient client,
    required String storageRootPath,
  }) async {
    final layout = ChronicleLayout(Directory(storageRootPath));
    final localEntries = await _listLocalFiles(layout);
    final remoteEntries = await _listRemoteFiles(client);
    final localItemCount = await _countMeaningfulLocalEntries(localEntries);
    final remoteItemCount = await _countMeaningfulRemoteEntries(
      client,
      remoteEntries,
    );
    return SyncBootstrapAssessment.fromCounts(
      localItemCount: localItemCount,
      remoteItemCount: remoteItemCount,
    );
  }

  Future<SyncResult> run({
    required WebDavClient client,
    required String clientId,
    required bool failSafe,
    required SyncRunOptions options,
    required String syncTargetUrl,
    required String syncUsername,
    void Function(SyncProgress progress)? onProgress,
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
    var progress = const SyncProgress(phase: SyncProgressPhase.preparing);
    LocalSyncMetadataSnapshot metadataSnapshot =
        LocalSyncMetadataSnapshot.empty;
    String? metadataNamespace;
    var metadataAuditedThisRun = false;
    var metadataNeedsPersist = false;
    final localAssets = <String, _LocalSyncAsset>{};
    final remoteAssets = <String, _RemoteSyncAsset>{};

    void emitProgress(
      SyncProgressPhase phase, {
      int completed = 0,
      int? total,
      bool clearTotal = false,
    }) {
      progress = progress.copyWith(
        phase: phase,
        completed: completed,
        total: total,
        clearTotal: clearTotal,
        uploadedCount: uploadedCount,
        downloadedCount: downloadedCount,
        deletedCount: deletedCount,
        conflictCount: conflictCount,
        errorCount: errors.length,
      );
      onProgress?.call(progress);
    }

    final layout = await _layout();
    emitProgress(SyncProgressPhase.preparing, clearTotal: true);

    final lockPath = 'locks/sync_desktop_$clientId.json';
    Timer? heartbeat;
    var pendingMarkerWritten = false;
    try {
      await _ensureRemoteSkeleton(client);
      emitProgress(SyncProgressPhase.acquiringLock, clearTotal: true);
      final lockAcquireResult = await _acquireLock(
        client,
        lockPath,
        clientId,
        mode: options.mode,
      );
      if (lockAcquireResult.blocker != null) {
        return SyncResult(
          uploadedCount: 0,
          downloadedCount: 0,
          conflictCount: 0,
          deletedCount: 0,
          startedAt: startedAt,
          endedAt: _clock.nowUtc(),
          errors: const <String>[],
          blocker: lockAcquireResult.blocker,
        );
      }

      heartbeat = Timer.periodic(const Duration(seconds: 30), (_) async {
        await _writeLock(client, lockPath, clientId);
      });

      final localInfo = await _readLocalInfoState(layout);
      final remoteInfo = await _readRemoteInfoState(client);
      final versionBlocker = _buildVersionBlocker(
        mode: options.mode,
        localFormatVersion: localInfo.formatVersion,
        remoteFormatVersion: remoteInfo?.formatVersion,
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
        localFormatVersion: localInfo.formatVersion,
      );
      metadataNamespace = _localSyncMetadataStore.buildNamespace(
        storageRootPath: layout.rootDirectory.path,
        localFormatVersion: localInfo.formatVersion,
      );

      if (options.mode == SyncRunMode.recoverLocalWins ||
          options.mode == SyncRunMode.recoverRemoteWins) {
        await _syncStateStore.clear(namespace: syncStateNamespace);
      }

      emitProgress(SyncProgressPhase.scanning, clearTotal: true);
      final previousState = await _syncStateStore.load(
        namespace: syncStateNamespace,
      );
      final conflictHistory = await _conflictHistoryStore.load(
        layout: layout,
        namespace: syncStateNamespace,
      );
      metadataSnapshot = await _localSyncMetadataStore.load(
        namespace: metadataNamespace,
      );
      final remoteManifestLoad = await _loadRemoteManifest(client);
      final pendingMarkerState = await _readPendingSyncMarker(client);

      final useSlowPath = _shouldUseSlowPath(
        mode: options.mode,
        metadataSnapshot: metadataSnapshot,
        remoteInfo: remoteInfo,
        remoteManifestLoad: remoteManifestLoad,
        pendingMarkerState: pendingMarkerState,
        now: startedAt,
      );

      if (useSlowPath) {
        metadataAuditedThisRun = true;
        localAssets.addAll(await _scanLocalAssets(layout));
        remoteAssets.addAll(await _scanRemoteAssets(client));
      } else {
        localAssets.addAll(_localAssetsFromMetadata(metadataSnapshot));
        remoteAssets.addAll(
          _remoteAssetsFromManifest(remoteManifestLoad.manifest!),
        );
      }
      metadataNeedsPersist = true;
      _debugLog(
        'Prepared sync state using ${useSlowPath ? 'slow' : 'fast'} path: '
        'local=${localAssets.length}, remote=${remoteAssets.length}, '
        'previous=${previousState.length}',
      );

      final allPaths = <String>{
        ...localAssets.keys,
        ...remoteAssets.keys,
      }.where((path) => !layout.isIgnoredSyncPath(path)).toList();

      final uploads = <String>[];
      final downloads = <String>[];
      final deleteLocals = <String>[];
      final deleteRemotes = <String>[];
      final conflicts = <String>[];
      emitProgress(
        SyncProgressPhase.planning,
        completed: 0,
        total: allPaths.length,
      );

      for (var index = 0; index < allPaths.length; index++) {
        final path = allPaths[index];
        final local = localAssets[path];
        final remote = remoteAssets[path];
        final previous = previousState[path];

        if (options.mode == SyncRunMode.recoverLocalWins) {
          _planRecoverLocalWins(
            path: path,
            local: local,
            remote: remote,
            uploads: uploads,
            deleteRemotes: deleteRemotes,
          );
          emitProgress(
            SyncProgressPhase.planning,
            completed: index + 1,
            total: allPaths.length,
          );
          continue;
        }

        if (options.mode == SyncRunMode.recoverRemoteWins) {
          _planRecoverRemoteWins(
            path: path,
            local: local,
            remote: remote,
            downloads: downloads,
            deleteLocals: deleteLocals,
          );
          emitProgress(
            SyncProgressPhase.planning,
            completed: index + 1,
            total: allPaths.length,
          );
          continue;
        }

        if (local != null && remote == null) {
          if (previous != null &&
              previous.remoteHash.isNotEmpty &&
              previous.localHash == local.contentHash) {
            deleteLocals.add(path);
          } else {
            uploads.add(path);
          }
          emitProgress(
            SyncProgressPhase.planning,
            completed: index + 1,
            total: allPaths.length,
          );
          continue;
        }

        if (local == null && remote != null) {
          if (previous != null &&
              previous.localHash.isNotEmpty &&
              previous.remoteHash == remote.contentHash) {
            deleteRemotes.add(path);
          } else {
            downloads.add(path);
          }
          emitProgress(
            SyncProgressPhase.planning,
            completed: index + 1,
            total: allPaths.length,
          );
          continue;
        }

        if (local == null || remote == null) {
          emitProgress(
            SyncProgressPhase.planning,
            completed: index + 1,
            total: allPaths.length,
          );
          continue;
        }

        if (local.contentHash == remote.contentHash) {
          emitProgress(
            SyncProgressPhase.planning,
            completed: index + 1,
            total: allPaths.length,
          );
          continue;
        }

        if (previous == null) {
          if (local.modifiedAt.isAfter(remote.updatedAt)) {
            uploads.add(path);
          } else {
            downloads.add(path);
          }
          emitProgress(
            SyncProgressPhase.planning,
            completed: index + 1,
            total: allPaths.length,
          );
          continue;
        }

        final localChanged = previous.localHash != local.contentHash;
        final remoteChanged = previous.remoteHash != remote.contentHash;

        if (localChanged && !remoteChanged) {
          uploads.add(path);
        } else if (!localChanged && remoteChanged) {
          downloads.add(path);
        } else if (localChanged && remoteChanged) {
          conflicts.add(path);
        }
        emitProgress(
          SyncProgressPhase.planning,
          completed: index + 1,
          total: allPaths.length,
        );
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
            localFormatVersion: localInfo.formatVersion,
            remoteFormatVersion: remoteInfo?.formatVersion,
            message:
                'Sync fail-safe blocked $candidateDeletionCount deletions '
                'out of $trackedCount tracked files',
          ),
        );
      }

      final shouldCommitRemoteMetadata =
          useSlowPath ||
          uploads.isNotEmpty ||
          conflicts.isNotEmpty ||
          deleteRemotes.any((path) {
            final remote = remoteAssets[path];
            return remote != null &&
                !(options.mode == SyncRunMode.normal && remote.isLegacyOrphan);
          });
      String? nextManifestRevision;
      if (shouldCommitRemoteMetadata) {
        nextManifestRevision = _nextManifestRevision(startedAt);
        await _writePendingSyncMarker(
          client,
          revision: nextManifestRevision,
          startedAt: startedAt,
        );
        pendingMarkerWritten = true;
      }

      emitProgress(
        SyncProgressPhase.uploading,
        completed: 0,
        total: uploads.length,
      );
      for (var index = 0; index < uploads.length; index++) {
        final path = uploads[index];
        try {
          final local = localAssets[path];
          if (local == null) {
            emitProgress(
              SyncProgressPhase.uploading,
              completed: index + 1,
              total: uploads.length,
            );
            continue;
          }
          final file = layout.fromRelativePath(local.sourcePath);
          final bytes = await file.readAsBytes();
          await client.uploadFile(path, bytes);
          uploadedCount++;
          remoteAssets[path] = _RemoteSyncAsset(
            canonicalPath: path,
            sourcePath: path,
            contentHash: local.contentHash,
            size: bytes.length,
            updatedAt: _clock.nowUtc(),
            isLegacyOrphan: false,
          );
        } catch (error) {
          errors.add('Upload failed for $path: $error');
        }
        emitProgress(
          SyncProgressPhase.uploading,
          completed: index + 1,
          total: uploads.length,
        );
      }

      emitProgress(
        SyncProgressPhase.downloading,
        completed: 0,
        total: downloads.length,
      );
      for (var index = 0; index < downloads.length; index++) {
        final path = downloads[index];
        try {
          final remote = remoteAssets[path];
          if (remote == null) {
            emitProgress(
              SyncProgressPhase.downloading,
              completed: index + 1,
              total: downloads.length,
            );
            continue;
          }
          final bytes = await client.downloadFile(remote.sourcePath);
          final target = layout.fromRelativePath(path);
          await _fileSystemUtils.atomicWriteBytes(target, bytes);
          final existingLocal = localAssets[path];
          if (existingLocal != null && existingLocal.sourcePath != path) {
            await _fileSystemUtils.deleteIfExists(
              layout.fromRelativePath(existingLocal.sourcePath),
            );
          }
          downloadedCount++;
          localAssets[path] = _LocalSyncAsset(
            canonicalPath: path,
            sourcePath: path,
            contentHash: await sha256ForBytes(bytes),
            size: bytes.length,
            modifiedAt: _clock.nowUtc(),
          );
        } catch (error) {
          errors.add('Download failed for $path: $error');
        }
        emitProgress(
          SyncProgressPhase.downloading,
          completed: index + 1,
          total: downloads.length,
        );
      }

      emitProgress(
        SyncProgressPhase.deletingLocal,
        completed: 0,
        total: deleteLocals.length,
      );
      for (var index = 0; index < deleteLocals.length; index++) {
        final path = deleteLocals[index];
        try {
          final local = localAssets.remove(path);
          await _fileSystemUtils.deleteIfExists(layout.fromRelativePath(path));
          if (local != null && local.sourcePath != path) {
            await _fileSystemUtils.deleteIfExists(
              layout.fromRelativePath(local.sourcePath),
            );
          }
          deletedCount++;
        } catch (error) {
          errors.add('Local delete failed for $path: $error');
        }
        emitProgress(
          SyncProgressPhase.deletingLocal,
          completed: index + 1,
          total: deleteLocals.length,
        );
      }

      emitProgress(
        SyncProgressPhase.deletingRemote,
        completed: 0,
        total: deleteRemotes.length,
      );
      for (var index = 0; index < deleteRemotes.length; index++) {
        final path = deleteRemotes[index];
        try {
          final remote = remoteAssets[path];
          if (remote == null) {
            emitProgress(
              SyncProgressPhase.deletingRemote,
              completed: index + 1,
              total: deleteRemotes.length,
            );
            continue;
          }
          final skipLegacyDelete =
              options.mode == SyncRunMode.normal && remote.isLegacyOrphan;
          if (!skipLegacyDelete) {
            await client.deleteFile(remote.sourcePath);
            remoteAssets.remove(path);
            deletedCount++;
          }
        } catch (error) {
          errors.add('Remote delete failed for $path: $error');
        }
        emitProgress(
          SyncProgressPhase.deletingRemote,
          completed: index + 1,
          total: deleteRemotes.length,
        );
      }

      emitProgress(
        SyncProgressPhase.resolvingConflicts,
        completed: 0,
        total: conflicts.length,
      );
      for (var index = 0; index < conflicts.length; index++) {
        final path = conflicts[index];
        try {
          final local = localAssets[path];
          final remote = remoteAssets[path];
          if (local == null || remote == null) {
            emitProgress(
              SyncProgressPhase.resolvingConflicts,
              completed: index + 1,
              total: conflicts.length,
            );
            continue;
          }

          final localFile = layout.fromRelativePath(local.sourcePath);
          final localBytes = await localFile.readAsBytes();
          final localHash = await sha256ForBytes(localBytes);

          final remoteBytes = await client.downloadFile(remote.sourcePath);
          final remoteHash = await sha256ForBytes(remoteBytes);
          await _fileSystemUtils.atomicWriteBytes(localFile, remoteBytes);
          localAssets[path] = _LocalSyncAsset(
            canonicalPath: path,
            sourcePath: local.sourcePath,
            contentHash: remoteHash,
            size: remoteBytes.length,
            modifiedAt: _clock.nowUtc(),
          );
          remoteAssets[path] = remote.copyWith(
            contentHash: remoteHash,
            size: remoteBytes.length,
            updatedAt: _clock.nowUtc(),
            isLegacyOrphan: false,
            sourcePath: path,
          );

          final fingerprint = buildSyncConflictFingerprint(
            originalPath: path,
            localContentHash: localHash,
            remoteContentHash: remoteHash,
          );
          final duplicateConflict =
              conflictHistory.contains(fingerprint) ||
              await _conflictService.hasMatchingConflict(
                originalPath: path,
                localContentHash: localHash,
                remoteContentHash: remoteHash,
              );
          if (duplicateConflict) {
            emitProgress(
              SyncProgressPhase.resolvingConflicts,
              completed: index + 1,
              total: conflicts.length,
            );
            continue;
          }

          final conflictPath = _buildConflictPath(path, clientId);
          final conflictFile = layout.fromRelativePath(conflictPath);
          final conflictBytes = _buildConflictBytes(
            originalPath: path,
            localDevice: 'desktop-$clientId',
            localBytes: localBytes,
            localContentHash: localHash,
            remoteContentHash: remoteHash,
            conflictFingerprint: fingerprint,
          );
          final conflictHash = await sha256ForBytes(conflictBytes);

          await _fileSystemUtils.atomicWriteBytes(conflictFile, conflictBytes);
          await client.uploadFile(conflictPath, conflictBytes);
          await _conflictHistoryStore.record(
            layout: layout,
            namespace: syncStateNamespace,
            fingerprint: fingerprint,
          );
          conflictHistory.add(fingerprint);
          localAssets[conflictPath] = _LocalSyncAsset(
            canonicalPath: conflictPath,
            sourcePath: conflictPath,
            contentHash: conflictHash,
            size: conflictBytes.length,
            modifiedAt: _clock.nowUtc(),
          );
          remoteAssets[conflictPath] = _RemoteSyncAsset(
            canonicalPath: conflictPath,
            sourcePath: conflictPath,
            contentHash: conflictHash,
            size: conflictBytes.length,
            updatedAt: _clock.nowUtc(),
            isLegacyOrphan: false,
          );
          conflictCount++;
        } catch (error) {
          errors.add('Conflict handling failed for $path: $error');
        }
        emitProgress(
          SyncProgressPhase.resolvingConflicts,
          completed: index + 1,
          total: conflicts.length,
        );
      }

      emitProgress(SyncProgressPhase.finalizing, clearTotal: true);

      if (errors.isEmpty && shouldCommitRemoteMetadata) {
        await _commitRemoteMetadata(
          client: client,
          layout: layout,
          localInfo: localInfo,
          remoteAssets: remoteAssets,
          localAssets: localAssets,
          revision: nextManifestRevision!,
        );
        await _clearPendingSyncMarker(client);
        pendingMarkerWritten = false;
      }

      if (errors.isEmpty) {
        final nextState = <String, SyncFileState>{};
        final finalUnion = <String>{...localAssets.keys, ...remoteAssets.keys};
        for (final path in finalUnion) {
          final local = localAssets[path];
          final remote = remoteAssets[path];
          nextState[path] = SyncFileState(
            path: path,
            localHash: local?.contentHash ?? '',
            remoteHash: remote?.contentHash ?? '',
            updatedAt: _clock.nowUtc(),
          );
        }

        await _syncStateStore.save(
          namespace: syncStateNamespace,
          states: nextState,
        );
      }
    } finally {
      heartbeat?.cancel();
      if (metadataNeedsPersist && metadataNamespace != null) {
        final nextSnapshot = _buildMetadataSnapshot(
          previous: metadataSnapshot,
          currentEntries: localAssets,
          dirty: errors.isNotEmpty,
          auditedThisRun: metadataAuditedThisRun,
        );
        await _localSyncMetadataStore.save(
          namespace: metadataNamespace,
          snapshot: nextSnapshot,
        );
      }
      await _releaseLock(client, lockPath);
      if (pendingMarkerWritten) {
        _debugLog('Pending sync marker left in place for recovery.');
      }
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

  Future<_LockAcquireResult> _acquireLock(
    WebDavClient client,
    String lockPath,
    String clientId, {
    required SyncRunMode mode,
  }) async {
    await _writeLock(client, lockPath, clientId);
    var locks = await _readActiveLocks(client);
    if (locks.isEmpty || locks.first.path == lockPath) {
      return const _LockAcquireResult.acquired();
    }

    var competingLocks = _competingLocks(locks, lockPath);
    if (mode != SyncRunMode.forceBreakRemoteLockOnce) {
      return _LockAcquireResult.blocked(
        _buildActiveLockBlocker(competingLocks),
      );
    }

    for (final competingLock in competingLocks) {
      await client.deleteFile(competingLock.path);
    }

    locks = await _readActiveLocks(client);
    if (locks.isEmpty || locks.first.path == lockPath) {
      return const _LockAcquireResult.acquired();
    }

    competingLocks = _competingLocks(locks, lockPath);
    return _LockAcquireResult.blocked(_buildActiveLockBlocker(competingLocks));
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
    final files = await client.listFilesRecursively('locks');
    final locks = <_SyncLock>[];

    for (final file in files) {
      if (!file.path.startsWith('locks/sync_')) {
        continue;
      }

      final updatedTime = file.updatedAt.millisecondsSinceEpoch;
      final age = now - updatedTime;
      if (age > _staleLockMs) {
        await client.deleteFile(file.path);
        continue;
      }
      if (age > _activeLockTtlMs) {
        continue;
      }

      final filenameData = _parseLockFilename(file.path);
      if (filenameData != null) {
        locks.add(
          _SyncLock(
            path: file.path,
            updatedTime: updatedTime,
            clientId: filenameData.clientId,
            clientType: filenameData.clientType,
          ),
        );
        continue;
      }

      try {
        final bytes = await client.downloadFile(file.path);
        final jsonMap = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
        locks.add(
          _SyncLock(
            path: file.path,
            updatedTime: updatedTime,
            clientId: (jsonMap['clientId'] as String?)?.trim(),
            clientType: (jsonMap['clientType'] as String?)?.trim(),
          ),
        );
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

  _ParsedLockFilename? _parseLockFilename(String path) {
    final match = RegExp(r'^locks/sync_([^_]+)_(.+)\.json$').firstMatch(path);
    if (match == null) {
      return null;
    }
    return _ParsedLockFilename(
      clientType: match.group(1)?.trim(),
      clientId: match.group(2)?.trim(),
    );
  }

  Future<void> _releaseLock(WebDavClient client, String lockPath) async {
    try {
      await client.deleteFile(lockPath);
    } catch (_) {
      // Ignore lock cleanup failures.
    }
  }

  bool _shouldUseSlowPath({
    required SyncRunMode mode,
    required LocalSyncMetadataSnapshot metadataSnapshot,
    required _SyncInfoState? remoteInfo,
    required _RemoteManifestLoadResult remoteManifestLoad,
    required _PendingSyncMarkerState pendingMarkerState,
    required DateTime now,
  }) {
    if (mode != SyncRunMode.normal) {
      return true;
    }
    if (metadataSnapshot.dirty || metadataSnapshot.entries.isEmpty) {
      return true;
    }
    if (pendingMarkerState.exists || pendingMarkerState.corrupt) {
      return true;
    }
    if (remoteInfo == null ||
        remoteInfo.syncProtocolVersion != _syncProtocolVersion) {
      return true;
    }
    if (remoteInfo.syncManifestRevision == null ||
        remoteInfo.syncManifestRevision!.trim().isEmpty) {
      return true;
    }
    if (remoteManifestLoad.missing || remoteManifestLoad.corrupt) {
      return true;
    }
    final manifest = remoteManifestLoad.manifest;
    if (manifest == null ||
        manifest.revision != remoteInfo.syncManifestRevision) {
      return true;
    }
    final lastAuditAt = metadataSnapshot.lastAuditAt;
    if (lastAuditAt == null) {
      return true;
    }
    if (now.difference(lastAuditAt) >= _auditMaxAge) {
      return true;
    }
    if (metadataSnapshot.runsSinceAudit >= _auditMaxRuns) {
      return true;
    }
    return false;
  }

  Future<Map<String, _LocalSyncAsset>> _scanLocalAssets(
    ChronicleLayout layout,
  ) async {
    final files = await _listLocalFiles(layout);
    final out = <String, _LocalSyncAsset>{};
    for (final entry in files.entries) {
      final bytes = await entry.value.file.readAsBytes();
      final stat = await entry.value.file.stat();
      out[entry.key] = _LocalSyncAsset(
        canonicalPath: entry.key,
        sourcePath: entry.value.sourcePath,
        contentHash: await sha256ForBytes(bytes),
        size: bytes.length,
        modifiedAt: stat.modified.toUtc(),
      );
    }
    return out;
  }

  Future<Map<String, _RemoteSyncAsset>> _scanRemoteAssets(
    WebDavClient client,
  ) async {
    final files = await _listRemoteFiles(client);
    final out = <String, _RemoteSyncAsset>{};
    for (final entry in files.entries) {
      out[entry.key] = _RemoteSyncAsset(
        canonicalPath: entry.key,
        sourcePath: entry.value.sourcePath,
        contentHash: _remoteHash(entry.value.metadata),
        size: entry.value.metadata.size,
        updatedAt: entry.value.metadata.updatedAt,
        isLegacyOrphan: entry.value.isLegacyOrphan,
      );
    }
    return out;
  }

  Map<String, _LocalSyncAsset> _localAssetsFromMetadata(
    LocalSyncMetadataSnapshot snapshot,
  ) {
    return {
      for (final entry in snapshot.entries.entries)
        entry.key: _LocalSyncAsset(
          canonicalPath: entry.value.canonicalPath,
          sourcePath: entry.value.sourcePath,
          contentHash: entry.value.contentHash,
          size: entry.value.size,
          modifiedAt: entry.value.modifiedAt,
        ),
    };
  }

  Map<String, _RemoteSyncAsset> _remoteAssetsFromManifest(
    SyncManifest manifest,
  ) {
    return {
      for (final entry in manifest.entries.entries)
        entry.key: _RemoteSyncAsset(
          canonicalPath: entry.value.canonicalPath,
          sourcePath: entry.value.sourcePath,
          contentHash: entry.value.contentHash,
          size: entry.value.size,
          updatedAt: entry.value.updatedAt,
          isLegacyOrphan: entry.value.isLegacyOrphan,
        ),
    };
  }

  Future<_RemoteManifestLoadResult> _loadRemoteManifest(
    WebDavClient client,
  ) async {
    try {
      final bytes = await client.downloadFile(_manifestPath);
      final raw = utf8.decode(bytes, allowMalformed: true);
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return _RemoteManifestLoadResult.available(
        SyncManifest.fromJson(decoded),
      );
    } catch (error) {
      if (_isRemoteFileMissing(error)) {
        return const _RemoteManifestLoadResult.missing();
      }
      if (error is FormatException || error is TypeError) {
        return const _RemoteManifestLoadResult.corrupt();
      }
      final lower = error.toString().toLowerCase();
      if (lower.contains('format') || lower.contains('invalid')) {
        return const _RemoteManifestLoadResult.corrupt();
      }
      rethrow;
    }
  }

  Future<_PendingSyncMarkerState> _readPendingSyncMarker(
    WebDavClient client,
  ) async {
    try {
      final bytes = await client.downloadFile(_pendingSyncPath);
      final raw = utf8.decode(bytes, allowMalformed: true);
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final revision = decoded['revision'] as String?;
      final startedAt = decoded['startedAt'] as String?;
      if (revision == null || revision.trim().isEmpty) {
        return const _PendingSyncMarkerState(corrupt: true);
      }
      if (startedAt == null || startedAt.trim().isEmpty) {
        return const _PendingSyncMarkerState(corrupt: true);
      }
      return const _PendingSyncMarkerState(exists: true);
    } catch (error) {
      if (_isRemoteFileMissing(error)) {
        return const _PendingSyncMarkerState();
      }
      if (error is FormatException || error is TypeError) {
        return const _PendingSyncMarkerState(corrupt: true);
      }
      final lower = error.toString().toLowerCase();
      if (lower.contains('format') || lower.contains('invalid')) {
        return const _PendingSyncMarkerState(corrupt: true);
      }
      rethrow;
    }
  }

  Future<void> _writePendingSyncMarker(
    WebDavClient client, {
    required String revision,
    required DateTime startedAt,
  }) async {
    final payload = prettyJson(<String, dynamic>{
      'revision': revision,
      'startedAt': startedAt.toIso8601String(),
    });
    await client.uploadFile(_pendingSyncPath, utf8.encode(payload));
  }

  Future<void> _clearPendingSyncMarker(WebDavClient client) async {
    await client.deleteFile(_pendingSyncPath);
  }

  Future<void> _commitRemoteMetadata({
    required WebDavClient client,
    required ChronicleLayout layout,
    required _SyncInfoState localInfo,
    required Map<String, _RemoteSyncAsset> remoteAssets,
    required Map<String, _LocalSyncAsset> localAssets,
    required String revision,
  }) async {
    final manifest = SyncManifest(
      revision: revision,
      generatedAt: _clock.nowUtc(),
      entries: {
        for (final entry in remoteAssets.entries)
          entry.key: SyncManifestEntry(
            canonicalPath: entry.value.canonicalPath,
            sourcePath: entry.value.sourcePath,
            contentHash: entry.value.contentHash,
            size: entry.value.size,
            updatedAt: entry.value.updatedAt,
            isLegacyOrphan: entry.value.isLegacyOrphan,
          ),
      },
    );
    final manifestBytes = utf8.encode(prettyJson(manifest.toJson()));
    await client.uploadFile(_manifestPath, manifestBytes);

    final nextInfo = localInfo.withProtocol(
      syncProtocolVersion: _syncProtocolVersion,
      syncManifestRevision: revision,
    );
    final infoBytes = utf8.encode(prettyJson(nextInfo.jsonMap));
    final infoHash = await sha256ForBytes(infoBytes);
    await client.uploadFile('info.json', infoBytes);
    await _fileSystemUtils.atomicWriteBytes(layout.infoFile, infoBytes);

    localAssets['info.json'] = _LocalSyncAsset(
      canonicalPath: 'info.json',
      sourcePath: 'info.json',
      contentHash: infoHash,
      size: infoBytes.length,
      modifiedAt: _clock.nowUtc(),
    );
    remoteAssets['info.json'] = _RemoteSyncAsset(
      canonicalPath: 'info.json',
      sourcePath: 'info.json',
      contentHash: infoHash,
      size: infoBytes.length,
      updatedAt: _clock.nowUtc(),
      isLegacyOrphan: false,
    );
  }

  LocalSyncMetadataSnapshot _buildMetadataSnapshot({
    required LocalSyncMetadataSnapshot previous,
    required Map<String, _LocalSyncAsset> currentEntries,
    required bool dirty,
    required bool auditedThisRun,
  }) {
    return LocalSyncMetadataSnapshot(
      entries: {
        for (final entry in currentEntries.entries)
          entry.key: LocalSyncMetadataEntry(
            canonicalPath: entry.value.canonicalPath,
            sourcePath: entry.value.sourcePath,
            contentHash: entry.value.contentHash,
            size: entry.value.size,
            modifiedAt: entry.value.modifiedAt,
          ),
      },
      dirty: dirty,
      runsSinceAudit: auditedThisRun ? 0 : previous.runsSinceAudit + 1,
      lastAuditAt: auditedThisRun ? _clock.nowUtc() : previous.lastAuditAt,
    );
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
      if (file.path.startsWith('.sync/') || file.path.startsWith('locks/')) {
        continue;
      }
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

  Future<int> _countMeaningfulLocalEntries(
    Map<String, _LocalSyncEntry> entries,
  ) async {
    var count = 0;
    for (final entry in entries.entries) {
      if (await _isMeaningfulLocalEntry(
        canonicalPath: entry.key,
        entry: entry.value,
      )) {
        count += 1;
      }
    }
    return count;
  }

  Future<int> _countMeaningfulRemoteEntries(
    WebDavClient client,
    Map<String, _RemoteSyncEntry> entries,
  ) async {
    var count = 0;
    for (final entry in entries.entries) {
      if (await _isMeaningfulRemoteEntry(
        client: client,
        canonicalPath: entry.key,
        entry: entry.value,
      )) {
        count += 1;
      }
    }
    return count;
  }

  Future<bool> _isMeaningfulLocalEntry({
    required String canonicalPath,
    required _LocalSyncEntry entry,
  }) async {
    if (canonicalPath == _infoPath) {
      return false;
    }
    if (canonicalPath != _notebookFoldersIndexPath) {
      return true;
    }
    try {
      final raw = await entry.file.readAsString();
      return _hasNonEmptyFolderIndex(raw);
    } catch (_) {
      return true;
    }
  }

  Future<bool> _isMeaningfulRemoteEntry({
    required WebDavClient client,
    required String canonicalPath,
    required _RemoteSyncEntry entry,
  }) async {
    if (canonicalPath == _infoPath) {
      return false;
    }
    if (canonicalPath != _notebookFoldersIndexPath) {
      return true;
    }
    try {
      final bytes = await client.downloadFile(entry.sourcePath);
      final raw = utf8.decode(bytes, allowMalformed: true);
      return _hasNonEmptyFolderIndex(raw);
    } catch (_) {
      return true;
    }
  }

  bool _hasNonEmptyFolderIndex(String raw) {
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final folders = decoded['folders'];
      return folders is List && folders.isNotEmpty;
    } catch (_) {
      return true;
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
    required String localContentHash,
    required String remoteContentHash,
    required String conflictFingerprint,
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
localContentHash: "$localContentHash"
remoteContentHash: "$remoteContentHash"
conflictFingerprint: "$conflictFingerprint"
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

  Future<_SyncInfoState> _readLocalInfoState(ChronicleLayout layout) async {
    if (!await layout.infoFile.exists()) {
      return const _SyncInfoState(
        jsonMap: <String, dynamic>{},
        formatVersion: 0,
      );
    }
    try {
      final raw = await layout.infoFile.readAsString();
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return _SyncInfoState.fromJson(decoded);
    } catch (_) {
      return const _SyncInfoState(
        jsonMap: <String, dynamic>{},
        formatVersion: 0,
      );
    }
  }

  Future<_SyncInfoState?> _readRemoteInfoState(WebDavClient client) async {
    try {
      final bytes = await client.downloadFile('info.json');
      final raw = utf8.decode(bytes, allowMalformed: true);
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return _SyncInfoState.fromJson(decoded);
    } catch (error) {
      if (_isRemoteFileMissing(error)) {
        return null;
      }
      rethrow;
    }
  }

  bool _isRemoteFileMissing(Object error) {
    if (error is HttpException && error.message.contains('404')) {
      return true;
    }
    if (error is Exception &&
        error.toString().toLowerCase().contains('file not found')) {
      return true;
    }
    final lower = error.toString().toLowerCase();
    return lower.contains('404') || lower.contains('not found');
  }

  String _nextManifestRevision(DateTime startedAt) {
    return '${startedAt.millisecondsSinceEpoch}';
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

  List<_SyncLock> _competingLocks(List<_SyncLock> locks, String lockPath) {
    return locks.where((lock) => lock.path != lockPath).toList();
  }

  SyncBlocker _buildActiveLockBlocker(List<_SyncLock> competingLocks) {
    final blockingLock = competingLocks.first;
    return SyncBlocker(
      type: SyncBlockerType.activeRemoteLock,
      lockPath: blockingLock.path,
      lockClientId: blockingLock.clientId,
      lockClientType: blockingLock.clientType,
      lockUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
        blockingLock.updatedTime,
        isUtc: true,
      ),
      competingLockCount: competingLocks.length,
      message:
          'Sync is blocked by an active remote lock at ${blockingLock.path}.',
    );
  }

  void _planRecoverLocalWins({
    required String path,
    required _LocalSyncAsset? local,
    required _RemoteSyncAsset? remote,
    required List<String> uploads,
    required List<String> deleteRemotes,
  }) {
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
    if (local.contentHash != remote.contentHash) {
      uploads.add(path);
    }
  }

  void _planRecoverRemoteWins({
    required String path,
    required _LocalSyncAsset? local,
    required _RemoteSyncAsset? remote,
    required List<String> downloads,
    required List<String> deleteLocals,
  }) {
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
    if (local.contentHash != remote.contentHash) {
      downloads.add(path);
    }
  }

  void _debugLog(String message) {
    assert(() {
      // ignore: avoid_print
      print('[WebDAV][Sync] $message');
      return true;
    }());
  }
}

class _SyncLock {
  const _SyncLock({
    required this.path,
    required this.updatedTime,
    this.clientId,
    this.clientType,
  });

  final String path;
  final int updatedTime;
  final String? clientId;
  final String? clientType;
}

class _ParsedLockFilename {
  const _ParsedLockFilename({this.clientType, this.clientId});

  final String? clientType;
  final String? clientId;
}

class _LockAcquireResult {
  const _LockAcquireResult._({this.blocker});

  const _LockAcquireResult.acquired() : this._();

  const _LockAcquireResult.blocked(SyncBlocker blocker)
    : this._(blocker: blocker);

  final SyncBlocker? blocker;
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

class _LocalSyncAsset {
  const _LocalSyncAsset({
    required this.canonicalPath,
    required this.sourcePath,
    required this.contentHash,
    required this.size,
    required this.modifiedAt,
  });

  final String canonicalPath;
  final String sourcePath;
  final String contentHash;
  final int size;
  final DateTime modifiedAt;
}

class _RemoteSyncAsset {
  const _RemoteSyncAsset({
    required this.canonicalPath,
    required this.sourcePath,
    required this.contentHash,
    required this.size,
    required this.updatedAt,
    required this.isLegacyOrphan,
  });

  final String canonicalPath;
  final String sourcePath;
  final String contentHash;
  final int size;
  final DateTime updatedAt;
  final bool isLegacyOrphan;

  _RemoteSyncAsset copyWith({
    String? sourcePath,
    String? contentHash,
    int? size,
    DateTime? updatedAt,
    bool? isLegacyOrphan,
  }) {
    return _RemoteSyncAsset(
      canonicalPath: canonicalPath,
      sourcePath: sourcePath ?? this.sourcePath,
      contentHash: contentHash ?? this.contentHash,
      size: size ?? this.size,
      updatedAt: updatedAt ?? this.updatedAt,
      isLegacyOrphan: isLegacyOrphan ?? this.isLegacyOrphan,
    );
  }
}

class _RemoteManifestLoadResult {
  const _RemoteManifestLoadResult._({
    this.manifest,
    this.missing = false,
    this.corrupt = false,
  });

  const _RemoteManifestLoadResult.available(SyncManifest manifest)
    : this._(manifest: manifest);

  const _RemoteManifestLoadResult.missing() : this._(missing: true);

  const _RemoteManifestLoadResult.corrupt() : this._(corrupt: true);

  final SyncManifest? manifest;
  final bool missing;
  final bool corrupt;
}

class _PendingSyncMarkerState {
  const _PendingSyncMarkerState({this.exists = false, this.corrupt = false});

  final bool exists;
  final bool corrupt;
}

class _SyncInfoState {
  const _SyncInfoState({
    required this.jsonMap,
    required this.formatVersion,
    this.syncProtocolVersion,
    this.syncManifestRevision,
  });

  final Map<String, dynamic> jsonMap;
  final int formatVersion;
  final int? syncProtocolVersion;
  final String? syncManifestRevision;

  _SyncInfoState withProtocol({
    required int syncProtocolVersion,
    required String syncManifestRevision,
  }) {
    final next = Map<String, dynamic>.from(jsonMap);
    next['syncProtocolVersion'] = syncProtocolVersion;
    next['syncManifestRevision'] = syncManifestRevision;
    return _SyncInfoState.fromJson(next);
  }

  static _SyncInfoState fromJson(Map<String, dynamic> json) {
    return _SyncInfoState(
      jsonMap: Map<String, dynamic>.from(json),
      formatVersion: (json['formatVersion'] as num?)?.toInt() ?? 0,
      syncProtocolVersion: (json['syncProtocolVersion'] as num?)?.toInt(),
      syncManifestRevision: (json['syncManifestRevision'] as String?)?.trim(),
    );
  }
}
