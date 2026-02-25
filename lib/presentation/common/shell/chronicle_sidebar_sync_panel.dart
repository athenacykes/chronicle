import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../domain/entities/sync_blocker.dart';
import '../../../l10n/localization.dart';
import '../../settings/settings_controller.dart';
import '../../sync/sync_controller.dart';

enum ChronicleSyncAdvancedAction {
  recoverLocalWins,
  recoverRemoteWins,
  armForceDeletion,
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
    final remoteRecoveryEnabled =
        blocker == null ||
        blocker.type == SyncBlockerType.failSafeDeletionBlocked;
    final deletionSummary =
        blocker?.type == SyncBlockerType.failSafeDeletionBlocked
        ? l10n.syncForceDeletionSummary(
            blocker?.candidateDeletionCount ?? 0,
            blocker?.trackedCount ?? 0,
          )
        : l10n.syncForceDeletionSummaryUnknown;

    var status = syncState.when(
      loading: () => l10n.syncWorkingStatus,
      error: (error, _) => l10n.syncErrorStatus(error.toString()),
      data: (sync) {
        final lastSyncLabel = settings?.lastSyncAt == null
            ? l10n.neverLabel
            : settings!.lastSyncAt!.toLocal().toString();
        return l10n.syncSummaryStatus(sync.lastMessage, lastSyncLabel);
      },
    );
    if (syncData?.forceDeletionArmed ?? false) {
      status = '$status | ${l10n.syncForceDeletionArmedStatus}';
    }

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

    Future<void> runRecoverLocalWins() async {
      final confirmed = await confirmAction(
        title: l10n.syncRecoverLocalWinsTitle,
        message: l10n.syncRecoverLocalWinsWarning,
      );
      if (!confirmed) {
        return;
      }
      await ref.read(syncControllerProvider.notifier).runRecoverLocalWins();
      await ref.read(settingsControllerProvider.notifier).refresh();
    }

    Future<void> runRecoverRemoteWins() async {
      if (!remoteRecoveryEnabled) {
        return;
      }
      final confirmed = await confirmAction(
        title: l10n.syncRecoverRemoteWinsTitle,
        message: l10n.syncRecoverRemoteWinsWarning,
      );
      if (!confirmed) {
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
      }
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
                    onPressed: () {
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
                        enabled: remoteRecoveryEnabled,
                        onTap: () {
                          unawaited(
                            handleAdvancedAction(
                              ChronicleSyncAdvancedAction.recoverRemoteWins,
                            ),
                          );
                        },
                      ),
                      const MacosPulldownMenuDivider(),
                      MacosPulldownMenuItem(
                        title: Text(l10n.syncForceDeletionNextRunAction),
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
            Text(
              status,
              key: syncStatusKey,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: MacosTheme.of(context).typography.caption2,
            ),
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
                  onPressed: () async {
                    await runSyncNow();
                  },
                  icon: const Icon(Icons.sync),
                  label: Text(l10n.syncNowAction),
                ),
              ),
              if (enableAdvancedSyncRecovery)
                PopupMenuButton<ChronicleSyncAdvancedAction>(
                  key: syncAdvancedButtonKey,
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
                        PopupMenuItem<ChronicleSyncAdvancedAction>(
                          value: ChronicleSyncAdvancedAction.armForceDeletion,
                          child: Text(l10n.syncForceDeletionNextRunAction),
                        ),
                      ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            status,
            key: syncStatusKey,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
