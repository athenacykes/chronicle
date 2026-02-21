import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/entities/sync_blocker.dart';
import '../../domain/entities/sync_run_options.dart';
import '../../domain/entities/sync_status.dart';
import '../links/links_controller.dart';
import 'conflicts_controller.dart';

final syncControllerProvider =
    AsyncNotifierProvider<SyncController, SyncStatus>(SyncController.new);

class SyncController extends AsyncNotifier<SyncStatus> {
  Timer? _timer;
  bool _forceDeletionArmed = false;

  @override
  Future<SyncStatus> build() async {
    ref.onDispose(() {
      _timer?.cancel();
    });

    return SyncStatus.idle;
  }

  Future<void> runSyncNow({SyncRunMode mode = SyncRunMode.normal}) async {
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
      ),
    );

    try {
      final result = await ref
          .read(syncRepositoryProvider)
          .syncNow(options: SyncRunOptions(mode: effectiveMode));
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
        ),
      );
    } catch (error) {
      state = AsyncData(
        SyncStatus(
          isRunning: false,
          lastMessage: 'Sync failed: $error',
          lastUpdatedAt: DateTime.now().toUtc(),
          blocker: null,
          forceDeletionArmed: false,
        ),
      );
    }
  }

  void armForceApplyDeletionsOnce() {
    _forceDeletionArmed = true;
    final current = state.valueOrNull ?? SyncStatus.idle;
    state = AsyncData(
      current.copyWith(
        lastMessage: 'Force deletion override is armed for the next sync run.',
        lastUpdatedAt: DateTime.now().toUtc(),
        clearBlocker: true,
        forceDeletionArmed: true,
      ),
    );
  }

  Future<void> runRecoverLocalWins() async {
    await runSyncNow(mode: SyncRunMode.recoverLocalWins);
  }

  Future<void> runRecoverRemoteWins() async {
    await runSyncNow(mode: SyncRunMode.recoverRemoteWins);
  }

  Future<void> startAutoSync(int intervalMinutes) async {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(minutes: intervalMinutes), (_) async {
      final currentStatus = state.valueOrNull;
      if (currentStatus?.blocker != null) {
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
    };
  }
}
