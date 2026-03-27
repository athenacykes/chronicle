import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/entities/sync_blocker.dart';
import '../../domain/entities/sync_progress.dart';
import '../../domain/entities/sync_result.dart';
import '../../domain/entities/sync_run_options.dart';
import '../../domain/entities/sync_status.dart';
import '../links/links_controller.dart';
import 'conflicts_controller.dart';

final syncControllerProvider =
    AsyncNotifierProvider<SyncController, SyncStatus>(SyncController.new);

class SyncController extends AsyncNotifier<SyncStatus> {
  Timer? _timer;
  Future<void>? _activeSyncRun;
  bool _forceDeletionArmed = false;

  @override
  Future<SyncStatus> build() async {
    ref.onDispose(() {
      _timer?.cancel();
    });

    return SyncStatus.idle;
  }

  Future<void> runSyncNow({SyncRunMode mode = SyncRunMode.normal}) async {
    final activeRun = _activeSyncRun;
    if (activeRun != null) {
      return activeRun;
    }

    late final Future<void> guardedRun;
    guardedRun = _runSyncNow(mode: mode).whenComplete(() {
      if (identical(_activeSyncRun, guardedRun)) {
        _activeSyncRun = null;
      }
    });
    _activeSyncRun = guardedRun;
    return guardedRun;
  }

  Future<void> _runSyncNow({SyncRunMode mode = SyncRunMode.normal}) async {
    final consumeForceOverride = _forceDeletionArmed;
    final effectiveMode = consumeForceOverride && mode == SyncRunMode.normal
        ? SyncRunMode.forceApplyDeletionsOnce
        : mode;
    _forceDeletionArmed = false;

    state = AsyncData(
      SyncStatus(
        isRunning: true,
        lastMessage: 'Sync in progress...',
        lastUpdatedAt: DateTime.now().toUtc(),
        blocker: null,
        forceDeletionArmed: false,
        progress: const SyncProgress(phase: SyncProgressPhase.preparing),
      ),
    );

    try {
      final result = await ref
          .read(syncRepositoryProvider)
          .syncNow(
            options: SyncRunOptions(mode: effectiveMode),
            onProgress: (progress) {
              final current = state.asData?.value ?? SyncStatus.idle;
              state = AsyncData(
                current.copyWith(
                  isRunning: true,
                  lastMessage: _progressStatusMessage(progress),
                  lastUpdatedAt: DateTime.now().toUtc(),
                  clearBlocker: true,
                  forceDeletionArmed: false,
                  progress: progress,
                ),
              );
            },
          );
      await ref.read(searchRepositoryProvider).rebuildIndex();
      await ref.read(conflictsControllerProvider.notifier).reload();
      ref.read(linksControllerProvider).invalidateAll();

      if (result.blocker != null) {
        state = AsyncData(
          SyncStatus(
            isRunning: false,
            lastMessage: _blockerStatusMessage(result.blocker!),
            lastUpdatedAt: result.endedAt,
            blocker: result.blocker,
            forceDeletionArmed: false,
            progress: null,
          ),
        );
        return;
      }

      if (result.errors.isNotEmpty) {
        state = AsyncData(
          SyncStatus(
            isRunning: false,
            lastMessage: 'Sync completed with ${result.errors.length} errors',
            lastUpdatedAt: result.endedAt,
            blocker: null,
            forceDeletionArmed: false,
            progress: _terminalProgress(result),
          ),
        );
        return;
      }

      state = AsyncData(
        SyncStatus(
          isRunning: false,
          lastMessage:
              'Synced: +${result.uploadedCount} / ↓${result.downloadedCount} / !${result.conflictCount}',
          lastUpdatedAt: result.endedAt,
          blocker: null,
          forceDeletionArmed: false,
          progress: _terminalProgress(result),
        ),
      );
    } catch (error) {
      await _reloadConflictsAfterFailure();
      state = AsyncData(
        SyncStatus(
          isRunning: false,
          lastMessage: 'Sync failed: $error',
          lastUpdatedAt: DateTime.now().toUtc(),
          blocker: null,
          forceDeletionArmed: false,
          progress: null,
        ),
      );
    }
  }

  Future<void> _reloadConflictsAfterFailure() async {
    try {
      await ref.read(conflictsControllerProvider.notifier).reload();
    } catch (_) {
      // Preserve the original sync failure as the user-facing terminal state.
    }
  }

  void armForceApplyDeletionsOnce() {
    _forceDeletionArmed = true;
    final current = state.asData?.value ?? SyncStatus.idle;
    state = AsyncData(
      current.copyWith(
        lastMessage: 'Force deletion override is armed for the next sync run.',
        lastUpdatedAt: DateTime.now().toUtc(),
        clearBlocker: true,
        forceDeletionArmed: true,
        clearProgress: true,
      ),
    );
  }

  Future<void> runRecoverLocalWins() async {
    await runSyncNow(mode: SyncRunMode.recoverLocalWins);
  }

  Future<void> runRecoverRemoteWins() async {
    await runSyncNow(mode: SyncRunMode.recoverRemoteWins);
  }

  Future<void> runForceBreakRemoteLockOnce() async {
    await runSyncNow(mode: SyncRunMode.forceBreakRemoteLockOnce);
  }

  Future<void> startAutoSync(int intervalMinutes) async {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(minutes: intervalMinutes), (_) async {
      final currentStatus = state.asData?.value;
      if (currentStatus?.blocker != null || currentStatus?.isRunning == true) {
        return;
      }
      await runSyncNow();
    });
  }

  void stopAutoSync() {
    _timer?.cancel();
    _timer = null;
  }

  String _blockerStatusMessage(SyncBlocker blocker) {
    return switch (blocker.type) {
      SyncBlockerType.versionMismatchRemoteOlder =>
        'Sync blocked: remote format v${blocker.remoteFormatVersion ?? '?'} '
            'is older than local v${blocker.localFormatVersion ?? '?'}. '
            'Use Local Wins recovery.',
      SyncBlockerType.versionMismatchClientTooOld =>
        'Sync blocked: remote format v${blocker.remoteFormatVersion ?? '?'} '
            'is newer than local v${blocker.localFormatVersion ?? '?'}. '
            'Upgrade Chronicle first.',
      SyncBlockerType.failSafeDeletionBlocked =>
        'Sync blocked by fail-safe: '
            '${blocker.candidateDeletionCount ?? '?'} deletions over '
            '${blocker.trackedCount ?? '?'} tracked files.',
      SyncBlockerType.activeRemoteLock =>
        'Sync blocked by active remote lock: '
            '${_lockOwnerLabel(blocker)} '
            'updated ${_lockUpdatedLabel(blocker)}. '
            'Use Override lock and retry only if that sync is no longer running.',
    };
  }

  String _lockOwnerLabel(SyncBlocker blocker) {
    final clientType = blocker.lockClientType?.trim();
    final clientId = blocker.lockClientId?.trim();
    if (clientType != null &&
        clientType.isNotEmpty &&
        clientId != null &&
        clientId.isNotEmpty) {
      return '$clientType:$clientId';
    }
    if (clientId != null && clientId.isNotEmpty) {
      return clientId;
    }
    return blocker.lockPath ?? 'unknown client';
  }

  String _lockUpdatedLabel(SyncBlocker blocker) {
    final updatedAt = blocker.lockUpdatedAt;
    if (updatedAt == null) {
      return 'at an unknown time';
    }
    return updatedAt.toLocal().toString();
  }

  String _progressStatusMessage(SyncProgress progress) {
    return switch (progress.phase) {
      SyncProgressPhase.preparing => 'Preparing sync...',
      SyncProgressPhase.acquiringLock => 'Acquiring sync lock...',
      SyncProgressPhase.scanning => 'Scanning local and remote files...',
      SyncProgressPhase.planning => 'Planning sync actions...',
      SyncProgressPhase.uploading =>
        'Uploading ${progress.completed}/${progress.total ?? 0}...',
      SyncProgressPhase.downloading =>
        'Downloading ${progress.completed}/${progress.total ?? 0}...',
      SyncProgressPhase.deletingLocal =>
        'Deleting local files ${progress.completed}/${progress.total ?? 0}...',
      SyncProgressPhase.deletingRemote =>
        'Deleting remote files ${progress.completed}/${progress.total ?? 0}...',
      SyncProgressPhase.resolvingConflicts =>
        'Resolving conflicts ${progress.completed}/${progress.total ?? 0}...',
      SyncProgressPhase.finalizing => 'Finalizing sync...',
    };
  }

  SyncProgress _terminalProgress(SyncResult result) {
    return SyncProgress(
      phase: SyncProgressPhase.finalizing,
      uploadedCount: result.uploadedCount,
      downloadedCount: result.downloadedCount,
      deletedCount: result.deletedCount,
      conflictCount: result.conflictCount,
      errorCount: result.errors.length,
    );
  }
}
