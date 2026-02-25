import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../domain/entities/enums.dart';
import '../../../domain/entities/matter.dart';
import '../../../l10n/localization.dart';
import '../../links/graph_controller.dart';
import '../../matters/matters_controller.dart';
import '../../notes/notes_controller.dart';
import 'chronicle_manage_phases_dialog.dart';

class ChronicleMatterTopControls extends ConsumerWidget {
  const ChronicleMatterTopControls({
    super.key,
    required this.matter,
    this.newNoteButtonKey = const Key('macos_matter_new_note_button'),
    this.phaseMenuButtonKey = const Key('matter_top_phase_menu_button'),
    this.timelineButtonKey = const Key('matter_top_timeline_button'),
    this.graphButtonKey = const Key('matter_top_graph_button'),
  });

  final Matter matter;
  final Key newNoteButtonKey;
  final Key phaseMenuButtonKey;
  final Key timelineButtonKey;
  final Key graphButtonKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = MacosTheme.maybeOf(context) != null;
    final viewMode = ref.watch(matterViewModeProvider);
    final selectedPhaseId = ref.watch(selectedPhaseIdProvider);
    final orderedPhases = matter.phases.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final phaseButtonLabel = () {
      if (selectedPhaseId == null) {
        return 'All Phases';
      }
      for (final phase in orderedPhases) {
        if (phase.id == selectedPhaseId) {
          final trimmed = phase.name.trim();
          return trimmed.isEmpty ? selectedPhaseId : trimmed;
        }
      }
      return selectedPhaseId;
    }();

    Future<void> createNewNote() async {
      await ref
          .read(noteEditorControllerProvider.notifier)
          .createNoteForSelectedMatter();
      ref
          .read(noteEditorViewModeProvider.notifier)
          .set(NoteEditorViewMode.edit);
    }

    Future<void> setViewMode(MatterViewMode mode) async {
      ref.read(matterViewModeProvider.notifier).set(mode);
      if (mode == MatterViewMode.graph) {
        ref.invalidate(graphControllerProvider);
      } else {
        ref.invalidate(noteListProvider);
      }
    }

    Future<void> selectPhase(String? phaseId) async {
      ref.read(matterViewModeProvider.notifier).set(MatterViewMode.phase);
      ref.read(selectedPhaseIdProvider.notifier).set(phaseId);
      if (phaseId != null && phaseId.isNotEmpty) {
        await ref
            .read(mattersControllerProvider.notifier)
            .setMatterCurrentPhase(matter: matter, phaseId: phaseId);
      }
      ref.invalidate(noteListProvider);
    }

    Future<void> openManagePhases() async {
      await showDialog<void>(
        context: context,
        builder: (_) => ChronicleManagePhasesDialog(matterId: matter.id),
      );
    }

    Widget macosLabeledAction({
      required Key buttonKey,
      required String tooltip,
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
      bool selected = false,
    }) {
      final primaryColor = MacosTheme.of(context).primaryColor;
      return MacosTooltip(
        message: tooltip,
        child: PushButton(
          key: buttonKey,
          semanticLabel: tooltip,
          controlSize: ControlSize.regular,
          secondary: true,
          color: selected ? primaryColor.withAlpha(34) : null,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          onPressed: onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              MacosIcon(icon, size: 14),
              const SizedBox(width: 6),
              Text(label),
            ],
          ),
        ),
      );
    }

    Widget materialLabeledAction({
      required Key buttonKey,
      required String tooltip,
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
      bool selected = false,
    }) {
      return TextButton.icon(
        key: buttonKey,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          backgroundColor: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
        ),
        label: Text(label),
        icon: Icon(icon, size: 18),
      );
    }

    Widget phaseSelector() {
      final isPhaseMode = viewMode == MatterViewMode.phase;

      if (isMacOSNativeUI) {
        final items = <MacosPulldownMenuEntry>[
          MacosPulldownMenuItem(
            title: Text(
              selectedPhaseId == null ? '✓ All Phases' : 'All Phases',
            ),
            onTap: () {
              unawaited(selectPhase(null));
            },
          ),
          ...orderedPhases.map(
            (phase) => MacosPulldownMenuItem(
              title: Text(
                phase.id == selectedPhaseId ? '✓ ${phase.name}' : phase.name,
              ),
              onTap: () {
                unawaited(selectPhase(phase.id));
              },
            ),
          ),
          const MacosPulldownMenuDivider(),
          MacosPulldownMenuItem(
            title: const Text('Manage Phases...'),
            onTap: () {
              unawaited(openManagePhases());
            },
          ),
        ];

        return Container(
          decoration: BoxDecoration(
            color: isPhaseMode
                ? MacosTheme.of(context).primaryColor.withAlpha(34)
                : MacosColors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const MacosIcon(
                CupertinoIcons.square_stack_3d_down_right,
                size: 13,
              ),
              const SizedBox(width: 6),
              MacosPulldownButton(
                key: phaseMenuButtonKey,
                title: phaseButtonLabel,
                items: items,
                onTap: () {
                  ref
                      .read(matterViewModeProvider.notifier)
                      .set(MatterViewMode.phase);
                },
              ),
            ],
          ),
        );
      }

      return Container(
        decoration: BoxDecoration(
          color: isPhaseMode
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: PopupMenuButton<String>(
          key: phaseMenuButtonKey,
          tooltip: 'Phases',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.layers_outlined, size: 18),
                const SizedBox(width: 6),
                Text(phaseButtonLabel),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
          onSelected: (value) async {
            if (value == '__manage_phases__') {
              await openManagePhases();
              return;
            }
            await selectPhase(value == '__all_phases__' ? null : value);
          },
          itemBuilder: (menuContext) => <PopupMenuEntry<String>>[
            CheckedPopupMenuItem<String>(
              value: '__all_phases__',
              checked: selectedPhaseId == null,
              child: const Text('All Phases'),
            ),
            ...orderedPhases.map(
              (phase) => CheckedPopupMenuItem<String>(
                value: phase.id,
                checked: phase.id == selectedPhaseId,
                child: Text(phase.name),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: '__manage_phases__',
              child: Text('Manage Phases...'),
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (isMacOSNativeUI)
          macosLabeledAction(
            buttonKey: newNoteButtonKey,
            tooltip: l10n.newNoteAction,
            icon: CupertinoIcons.add,
            label: l10n.newNoteAction,
            onPressed: () {
              unawaited(createNewNote());
            },
          )
        else
          materialLabeledAction(
            buttonKey: newNoteButtonKey,
            tooltip: l10n.newNoteAction,
            icon: Icons.note_add_outlined,
            label: l10n.newNoteAction,
            onPressed: () {
              unawaited(createNewNote());
            },
          ),
        const SizedBox(width: 6),
        phaseSelector(),
        const SizedBox(width: 6),
        if (isMacOSNativeUI)
          macosLabeledAction(
            buttonKey: timelineButtonKey,
            tooltip: l10n.viewModeTimeline,
            icon: CupertinoIcons.clock,
            label: l10n.viewModeTimeline,
            selected: viewMode == MatterViewMode.timeline,
            onPressed: () {
              unawaited(setViewMode(MatterViewMode.timeline));
            },
          )
        else
          materialLabeledAction(
            buttonKey: timelineButtonKey,
            tooltip: l10n.viewModeTimeline,
            icon: Icons.timeline,
            label: l10n.viewModeTimeline,
            selected: viewMode == MatterViewMode.timeline,
            onPressed: () {
              unawaited(setViewMode(MatterViewMode.timeline));
            },
          ),
        const SizedBox(width: 6),
        if (isMacOSNativeUI)
          macosLabeledAction(
            buttonKey: graphButtonKey,
            tooltip: l10n.viewModeGraph,
            icon: CupertinoIcons.chart_bar_circle,
            label: l10n.viewModeGraph,
            selected: viewMode == MatterViewMode.graph,
            onPressed: () {
              unawaited(setViewMode(MatterViewMode.graph));
            },
          )
        else
          materialLabeledAction(
            buttonKey: graphButtonKey,
            tooltip: l10n.viewModeGraph,
            icon: Icons.hub_outlined,
            label: l10n.viewModeGraph,
            selected: viewMode == MatterViewMode.graph,
            onPressed: () {
              unawaited(setViewMode(MatterViewMode.graph));
            },
          ),
      ],
    );
  }
}

class ChronicleNotebookTopControls extends ConsumerWidget {
  const ChronicleNotebookTopControls({
    super.key,
    this.newNoteButtonKey = const Key('macos_notebook_new_note_button'),
  });

  final Key newNoteButtonKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = MacosTheme.maybeOf(context) != null;

    Future<void> createNewNote() async {
      await ref
          .read(noteEditorControllerProvider.notifier)
          .createUntitledNotebookNote();
      ref
          .read(noteEditorViewModeProvider.notifier)
          .set(NoteEditorViewMode.edit);
    }

    if (isMacOSNativeUI) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          MacosTooltip(
            message: l10n.newNoteAction,
            child: PushButton(
              key: newNoteButtonKey,
              semanticLabel: l10n.newNoteAction,
              controlSize: ControlSize.regular,
              secondary: true,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              onPressed: () {
                unawaited(createNewNote());
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const MacosIcon(CupertinoIcons.add, size: 14),
                  const SizedBox(width: 6),
                  Text(l10n.newNoteAction),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextButton.icon(
          key: newNoteButtonKey,
          onPressed: () {
            unawaited(createNewNote());
          },
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
          label: Text(l10n.newNoteAction),
          icon: const Icon(Icons.note_add_outlined, size: 18),
        ),
      ],
    );
  }
}
