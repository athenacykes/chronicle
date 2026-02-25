import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../domain/entities/enums.dart';
import '../../../domain/entities/matter.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/localization.dart';

enum ChronicleMatterAction {
  edit,
  togglePinned,
  setActive,
  setPaused,
  setCompleted,
  setArchived,
  delete,
}

class ChronicleMacosMatterStatusBadge extends StatelessWidget {
  const ChronicleMacosMatterStatusBadge({super.key, required this.status});

  final MatterStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      MatterStatus.active => MacosColors.systemGreenColor,
      MatterStatus.paused => MacosColors.systemOrangeColor,
      MatterStatus.completed => MacosColors.systemBlueColor,
      MatterStatus.archived => MacosColors.systemGrayColor,
    };

    final label = _matterStatusBadgeLetter(context.l10n, status);

    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: MacosTheme.of(context).typography.caption2.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 9,
        ),
      ),
    );
  }
}

class ChronicleMacosCountBadge extends StatelessWidget {
  const ChronicleMacosCountBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: MacosColors.systemGrayColor.withAlpha(32),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: MacosTheme.of(context).typography.caption2.copyWith(
          color: MacosColors.secondaryLabelColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ChronicleMacosMatterActionMenu extends StatelessWidget {
  const ChronicleMacosMatterActionMenu({
    super.key,
    required this.matter,
    required this.onSelected,
  });

  final Matter matter;
  final ValueChanged<ChronicleMatterAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MacosPulldownButton(
      icon: CupertinoIcons.ellipsis_circle,
      items: <MacosPulldownMenuEntry>[
        MacosPulldownMenuItem(
          title: Text(l10n.editAction),
          onTap: () {
            onSelected(ChronicleMatterAction.edit);
          },
        ),
        MacosPulldownMenuItem(
          title: Text(matter.isPinned ? l10n.unpinAction : l10n.pinAction),
          onTap: () {
            onSelected(ChronicleMatterAction.togglePinned);
          },
        ),
        const MacosPulldownMenuDivider(),
        MacosPulldownMenuItem(
          title: Text(l10n.setActiveAction),
          onTap: () {
            onSelected(ChronicleMatterAction.setActive);
          },
        ),
        MacosPulldownMenuItem(
          title: Text(l10n.setPausedAction),
          onTap: () {
            onSelected(ChronicleMatterAction.setPaused);
          },
        ),
        MacosPulldownMenuItem(
          title: Text(l10n.setCompletedAction),
          onTap: () {
            onSelected(ChronicleMatterAction.setCompleted);
          },
        ),
        MacosPulldownMenuItem(
          title: Text(l10n.setArchivedAction),
          onTap: () {
            onSelected(ChronicleMatterAction.setArchived);
          },
        ),
        const MacosPulldownMenuDivider(),
        MacosPulldownMenuItem(
          title: Text(l10n.deleteAction),
          onTap: () {
            onSelected(ChronicleMatterAction.delete);
          },
        ),
      ],
    );
  }
}

class ChronicleMacosCategoryActionMenu extends StatelessWidget {
  const ChronicleMacosCategoryActionMenu({
    super.key,
    required this.onEdit,
    required this.onDelete,
  });

  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return MacosPulldownButton(
      icon: CupertinoIcons.ellipsis,
      items: <MacosPulldownMenuEntry>[
        MacosPulldownMenuItem(
          title: Text(context.l10n.editAction),
          onTap: () {
            unawaited(onEdit());
          },
        ),
        MacosPulldownMenuItem(
          title: Text(context.l10n.deleteAction),
          onTap: () {
            unawaited(onDelete());
          },
        ),
      ],
    );
  }
}

String _matterStatusBadgeLetter(AppLocalizations l10n, MatterStatus status) {
  return switch (status) {
    MatterStatus.active => l10n.matterStatusBadgeLetterActive,
    MatterStatus.paused => l10n.matterStatusBadgeLetterPaused,
    MatterStatus.completed => l10n.matterStatusBadgeLetterCompleted,
    MatterStatus.archived => l10n.matterStatusBadgeLetterArchived,
  };
}
