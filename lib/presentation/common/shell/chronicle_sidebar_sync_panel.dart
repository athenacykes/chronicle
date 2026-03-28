import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../app/app_providers.dart';
import '../../../domain/entities/sync_blocker.dart';
import '../../../domain/entities/sync_progress.dart';
import '../../../domain/entities/sync_status.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/localization.dart';
import '../../settings/settings_controller.dart';
import '../../sync/sync_controller.dart';

enum ChronicleSyncAdvancedAction {
  recoverLocalWins,
  recoverRemoteWins,
  armForceDeletion,
  overrideRemoteLock,
}

class ChronicleSidebarSyncPanel extends ConsumerWidget {
  const ChronicleSidebarSyncPanel({
    super.key,
    this.enableAdvancedSyncRecovery = true,
    this.syncNowButtonKey = const Key('sidebar_sync_now_button'),
    this.syncStatusKey = const Key('sidebar_sync_status'),
    this.syncAdvancedButtonKey = const Key('sidebar_sync_advanced_button'),
  });

  final bool enableAdvancedSyncRecovery;
  final Key syncNowButtonKey;
  final Key syncStatusKey;
  final Key syncAdvancedButtonKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = MacosTheme.maybeOf(context) != null;
    final settings = ref.watch(settingsControllerProvider).asData?.value;
    final syncState = ref.watch(syncControllerProvider);
    final syncData = syncState.asData?.value;
    final blocker = syncData?.blocker;
    final isSyncRunning = syncData?.isRunning ?? false;
    final remoteRecoveryEnabled =
        blocker == null ||
        blocker.type == SyncBlockerType.failSafeDeletionBlocked;
    final lockOverrideEnabled =
        blocker?.type == SyncBlockerType.activeRemoteLock;
    final deletionSummary =
        blocker?.type == SyncBlockerType.failSafeDeletionBlocked
        ? l10n.syncForceDeletionSummary(
            blocker?.candidateDeletionCount ?? 0,
            blocker?.trackedCount ?? 0,
          )
        : l10n.syncForceDeletionSummaryUnknown;
    final lastSyncLabel = settings?.lastSyncAt == null
        ? l10n.neverLabel
        : settings!.lastSyncAt!.toLocal().toString();

    final display = syncState.when(
      loading: () => _SyncStatusDisplay(
        state: _SyncDisplayState.running,
        title: l10n.syncWorkingStatus,
        subtitle: l10n.syncStatusPreparing,
      ),
      error: (error, _) => _SyncStatusDisplay(
        state: _SyncDisplayState.failed,
        title: l10n.syncFailedHeadline,
        subtitle: error.toString(),
      ),
      data: (sync) => _buildStatusDisplay(sync, l10n, lastSyncLabel),
    );

    Future<void> runSyncNow() async {
      await ref.read(syncControllerProvider.notifier).runSyncNow();
      await ref.read(settingsControllerProvider.notifier).refresh();
    }

    Future<bool> confirmAction({
      required String title,
      required String message,
    }) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.continueAction),
            ),
          ],
        ),
      );
      return confirmed == true;
    }

    Future<String?> currentBootstrapCountsSummary() async {
      final currentSettings = ref
          .read(settingsControllerProvider)
          .asData
          ?.value;
      final storageRootPath = currentSettings?.storageRootPath?.trim();
      if (currentSettings == null ||
          storageRootPath == null ||
          storageRootPath.isEmpty) {
        return null;
      }

      try {
        final assessment = await ref
            .read(syncRepositoryProvider)
            .assessBootstrap(
              config: currentSettings.syncConfig,
              storageRootPath: storageRootPath,
            );
        return l10n.syncBootstrapCountsSummary(
          assessment.localItemCount,
          assessment.remoteItemCount,
        );
      } catch (_) {
        return null;
      }
    }

    Future<void> runRecoverLocalWins() async {
      final countsSummary = await currentBootstrapCountsSummary();
      final confirmed = await confirmAction(
        title: l10n.syncRecoverLocalWinsTitle,
        message: countsSummary == null
            ? l10n.syncRecoverLocalWinsWarning
            : '${l10n.syncRecoverLocalWinsWarning}\n\n$countsSummary',
      );
      if (!confirmed) {
        return;
      }
      final confirmedAgain = await confirmAction(
        title: l10n.syncRecoverLocalWinsSecondTitle,
        message: l10n.syncRecoverLocalWinsSecondWarning,
      );
      if (!confirmedAgain) {
        return;
      }
      await ref.read(syncControllerProvider.notifier).runRecoverLocalWins();
      await ref.read(settingsControllerProvider.notifier).refresh();
    }

    Future<void> runRecoverRemoteWins() async {
      if (!remoteRecoveryEnabled) {
        return;
      }
      final countsSummary = await currentBootstrapCountsSummary();
      final confirmed = await confirmAction(
        title: l10n.syncRecoverRemoteWinsTitle,
        message: countsSummary == null
            ? l10n.syncRecoverRemoteWinsWarning
            : '${l10n.syncRecoverRemoteWinsWarning}\n\n$countsSummary',
      );
      if (!confirmed) {
        return;
      }
      final confirmedAgain = await confirmAction(
        title: l10n.syncRecoverRemoteWinsSecondTitle,
        message: l10n.syncRecoverRemoteWinsSecondWarning,
      );
      if (!confirmedAgain) {
        return;
      }
      await ref.read(syncControllerProvider.notifier).runRecoverRemoteWins();
      await ref.read(settingsControllerProvider.notifier).refresh();
    }

    Future<void> armForceDeletionOverride() async {
      final confirmed = await confirmAction(
        title: l10n.syncForceDeletionTitle,
        message: l10n.syncForceDeletionWarning(deletionSummary),
      );
      if (!confirmed) {
        return;
      }
      ref.read(syncControllerProvider.notifier).armForceApplyDeletionsOnce();
    }

    Future<void> runOverrideRemoteLock() async {
      if (!lockOverrideEnabled) {
        return;
      }
      final confirmed = await confirmAction(
        title: l10n.syncOverrideRemoteLockTitle,
        message: l10n.syncOverrideRemoteLockWarning(
          _lockOverrideSummary(blocker),
        ),
      );
      if (!confirmed) {
        return;
      }
      await ref
          .read(syncControllerProvider.notifier)
          .runForceBreakRemoteLockOnce();
      await ref.read(settingsControllerProvider.notifier).refresh();
    }

    Future<void> handleAdvancedAction(
      ChronicleSyncAdvancedAction action,
    ) async {
      switch (action) {
        case ChronicleSyncAdvancedAction.recoverLocalWins:
          await runRecoverLocalWins();
          return;
        case ChronicleSyncAdvancedAction.recoverRemoteWins:
          await runRecoverRemoteWins();
          return;
        case ChronicleSyncAdvancedAction.armForceDeletion:
          await armForceDeletionOverride();
          return;
        case ChronicleSyncAdvancedAction.overrideRemoteLock:
          await runOverrideRemoteLock();
          return;
      }
    }

    Widget statusView() {
      return _ChronicleSyncStatusView(
        key: syncStatusKey,
        display: display,
        isMacOSNativeUI: isMacOSNativeUI,
      );
    }

    if (isMacOSNativeUI) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: PushButton(
                    key: syncNowButtonKey,
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: isSyncRunning
                        ? null
                        : () {
                            unawaited(runSyncNow());
                          },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const MacosIcon(
                          CupertinoIcons.arrow_2_circlepath,
                          size: 13,
                        ),
                        const SizedBox(width: 6),
                        Text(l10n.syncNowAction),
                      ],
                    ),
                  ),
                ),
                if (enableAdvancedSyncRecovery) ...<Widget>[
                  const SizedBox(width: 6),
                  MacosPulldownButton(
                    key: syncAdvancedButtonKey,
                    icon: CupertinoIcons.ellipsis_circle,
                    items: <MacosPulldownMenuEntry>[
                      MacosPulldownMenuItem(
                        title: Text(l10n.syncRecoverLocalWinsAction),
                        enabled: !isSyncRunning,
                        onTap: () {
                          unawaited(
                            handleAdvancedAction(
                              ChronicleSyncAdvancedAction.recoverLocalWins,
                            ),
                          );
                        },
                      ),
                      MacosPulldownMenuItem(
                        title: Text(l10n.syncRecoverRemoteWinsAction),
                        enabled: !isSyncRunning && remoteRecoveryEnabled,
                        onTap: () {
                          unawaited(
                            handleAdvancedAction(
                              ChronicleSyncAdvancedAction.recoverRemoteWins,
                            ),
                          );
                        },
                      ),
                      const MacosPulldownMenuDivider(),
                      if (lockOverrideEnabled)
                        MacosPulldownMenuItem(
                          title: Text(l10n.syncOverrideRemoteLockAction),
                          enabled: !isSyncRunning,
                          onTap: () {
                            unawaited(
                              handleAdvancedAction(
                                ChronicleSyncAdvancedAction.overrideRemoteLock,
                              ),
                            );
                          },
                        ),
                      if (lockOverrideEnabled) const MacosPulldownMenuDivider(),
                      MacosPulldownMenuItem(
                        title: Text(l10n.syncForceDeletionNextRunAction),
                        enabled: !isSyncRunning,
                        onTap: () {
                          unawaited(
                            handleAdvancedAction(
                              ChronicleSyncAdvancedAction.armForceDeletion,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            statusView(),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
                  key: syncNowButtonKey,
                  onPressed: isSyncRunning
                      ? null
                      : () async {
                          await runSyncNow();
                        },
                  icon: const Icon(Icons.sync),
                  label: Text(l10n.syncNowAction),
                ),
              ),
              if (enableAdvancedSyncRecovery)
                PopupMenuButton<ChronicleSyncAdvancedAction>(
                  key: syncAdvancedButtonKey,
                  enabled: !isSyncRunning,
                  tooltip: l10n.syncAdvancedActionsTooltip,
                  onSelected: (action) async {
                    await handleAdvancedAction(action);
                  },
                  itemBuilder: (_) =>
                      <PopupMenuEntry<ChronicleSyncAdvancedAction>>[
                        PopupMenuItem<ChronicleSyncAdvancedAction>(
                          value: ChronicleSyncAdvancedAction.recoverLocalWins,
                          child: Text(l10n.syncRecoverLocalWinsAction),
                        ),
                        PopupMenuItem<ChronicleSyncAdvancedAction>(
                          value: ChronicleSyncAdvancedAction.recoverRemoteWins,
                          enabled: remoteRecoveryEnabled,
                          child: Text(l10n.syncRecoverRemoteWinsAction),
                        ),
                        const PopupMenuDivider(),
                        if (lockOverrideEnabled)
                          PopupMenuItem<ChronicleSyncAdvancedAction>(
                            value:
                                ChronicleSyncAdvancedAction.overrideRemoteLock,
                            child: Text(l10n.syncOverrideRemoteLockAction),
                          ),
                        if (lockOverrideEnabled) const PopupMenuDivider(),
                        PopupMenuItem<ChronicleSyncAdvancedAction>(
                          value: ChronicleSyncAdvancedAction.armForceDeletion,
                          child: Text(l10n.syncForceDeletionNextRunAction),
                        ),
                      ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          statusView(),
        ],
      ),
    );
  }

  _SyncStatusDisplay _buildStatusDisplay(
    SyncStatus sync,
    AppLocalizations l10n,
    String lastSyncLabel,
  ) {
    if (sync.isRunning) {
      final progress = sync.progress;
      return _SyncStatusDisplay(
        state: _SyncDisplayState.running,
        title: _progressPhaseLabel(progress?.phase, l10n),
        subtitle: _runningSubtitle(progress, l10n),
      );
    }

    if (sync.forceDeletionArmed) {
      return _SyncStatusDisplay(
        state: _SyncDisplayState.warning,
        title: l10n.syncForceDeletionArmedStatus,
        subtitle: sync.lastMessage,
      );
    }

    if (sync.blocker != null) {
      return _SyncStatusDisplay(
        state: _SyncDisplayState.blocked,
        title: l10n.syncBlockedHeadline,
        subtitle: sync.lastMessage,
      );
    }

    if (sync.lastMessage.startsWith('Sync failed:')) {
      return _SyncStatusDisplay(
        state: _SyncDisplayState.failed,
        title: l10n.syncFailedHeadline,
        subtitle: sync.lastMessage.substring('Sync failed:'.length).trim(),
      );
    }

    final progress = sync.progress;
    final countsLine = _completedSubtitle(progress, l10n, lastSyncLabel);
    if (sync.lastMessage.startsWith('Sync completed with')) {
      return _SyncStatusDisplay(
        state: _SyncDisplayState.warning,
        title: l10n.syncCompletedWithErrorsHeadline,
        subtitle: countsLine,
      );
    }

    if (sync.lastMessage == 'Idle') {
      return _SyncStatusDisplay(
        state: _SyncDisplayState.idle,
        title: l10n.syncReadyHeadline,
        subtitle: l10n.syncLastSyncCaption(lastSyncLabel),
      );
    }

    return _SyncStatusDisplay(
      state: _SyncDisplayState.succeeded,
      title: l10n.syncCompletedHeadline,
      subtitle: countsLine,
    );
  }

  String _progressPhaseLabel(SyncProgressPhase? phase, AppLocalizations l10n) {
    return switch (phase ?? SyncProgressPhase.preparing) {
      SyncProgressPhase.preparing => l10n.syncStatusPreparing,
      SyncProgressPhase.acquiringLock => l10n.syncStatusAcquiringLock,
      SyncProgressPhase.scanning => l10n.syncStatusScanning,
      SyncProgressPhase.planning => l10n.syncStatusPlanning,
      SyncProgressPhase.uploading => l10n.syncStatusUploading,
      SyncProgressPhase.downloading => l10n.syncStatusDownloading,
      SyncProgressPhase.deletingLocal => l10n.syncStatusDeletingLocal,
      SyncProgressPhase.deletingRemote => l10n.syncStatusDeletingRemote,
      SyncProgressPhase.resolvingConflicts => l10n.syncStatusResolvingConflicts,
      SyncProgressPhase.finalizing => l10n.syncStatusFinalizing,
    };
  }

  String _runningSubtitle(SyncProgress? progress, AppLocalizations l10n) {
    final counts = _countsSummary(progress, l10n);
    final total = progress?.total;
    if (total == null) {
      return counts;
    }
    return l10n.syncProgressWithStep(progress?.completed ?? 0, total, counts);
  }

  String _completedSubtitle(
    SyncProgress? progress,
    AppLocalizations l10n,
    String lastSyncLabel,
  ) {
    return '${_countsSummary(progress, l10n)} • ${l10n.syncLastSyncCaption(lastSyncLabel)}';
  }

  String _countsSummary(SyncProgress? progress, AppLocalizations l10n) {
    return l10n.syncLiveCountsSummary(
      progress?.uploadedCount ?? 0,
      progress?.downloadedCount ?? 0,
      progress?.deletedCount ?? 0,
      progress?.conflictCount ?? 0,
      progress?.errorCount ?? 0,
    );
  }

  String _lockOverrideSummary(SyncBlocker? blocker) {
    if (blocker == null) {
      return 'unknown lock';
    }
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
    if (blocker.lockPath != null && blocker.lockPath!.isNotEmpty) {
      return blocker.lockPath!;
    }
    return 'unknown lock';
  }
}

enum _SyncDisplayState { idle, running, succeeded, warning, blocked, failed }

class _SyncStatusDisplay {
  const _SyncStatusDisplay({
    required this.state,
    required this.title,
    required this.subtitle,
  });

  final _SyncDisplayState state;
  final String title;
  final String subtitle;
}

class _ChronicleSyncStatusView extends StatelessWidget {
  const _ChronicleSyncStatusView({
    super.key,
    required this.display,
    required this.isMacOSNativeUI,
  });

  final _SyncStatusDisplay display;
  final bool isMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    final titleStyle = isMacOSNativeUI
        ? MacosTheme.of(
            context,
          ).typography.caption1.copyWith(fontWeight: FontWeight.w600)
        : Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600);
    final subtitleStyle = isMacOSNativeUI
        ? MacosTheme.of(context).typography.caption2
        : Theme.of(context).textTheme.bodySmall;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Row(
        key: ValueKey<String>(
          '${display.state.name}:${display.title}:${display.subtitle}',
        ),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _SyncStatusLeading(
              state: display.state,
              isMacOSNativeUI: isMacOSNativeUI,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  display.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  display.subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: subtitleStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusLeading extends StatelessWidget {
  const _SyncStatusLeading({
    required this.state,
    required this.isMacOSNativeUI,
  });

  final _SyncDisplayState state;
  final bool isMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    if (state == _SyncDisplayState.running) {
      if (isMacOSNativeUI) {
        return const SizedBox(width: 14, height: 14, child: ProgressCircle());
      }
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final iconData = switch (state) {
      _SyncDisplayState.idle => CupertinoIcons.clock,
      _SyncDisplayState.succeeded => CupertinoIcons.check_mark_circled,
      _SyncDisplayState.warning => CupertinoIcons.exclamationmark_triangle,
      _SyncDisplayState.blocked => CupertinoIcons.lock_circle,
      _SyncDisplayState.failed => CupertinoIcons.xmark_octagon,
      _SyncDisplayState.running => CupertinoIcons.arrow_2_circlepath,
    };
    final color = switch (state) {
      _SyncDisplayState.idle => colorScheme.outline,
      _SyncDisplayState.succeeded => Colors.green,
      _SyncDisplayState.warning => Colors.orange,
      _SyncDisplayState.blocked => Colors.orange,
      _SyncDisplayState.failed => colorScheme.error,
      _SyncDisplayState.running => colorScheme.primary,
    };

    if (isMacOSNativeUI) {
      return MacosIcon(iconData, size: 14, color: color);
    }
    return Icon(iconData, size: 14, color: color);
  }
}
