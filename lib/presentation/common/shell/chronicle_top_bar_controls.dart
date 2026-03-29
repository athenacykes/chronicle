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

class ChronicleMatterTopControls extends ConsumerWidget {
  const ChronicleMatterTopControls({
    super.key,
    required this.matter,
    this.notesButtonKey = const Key('matter_top_notes_button'),
    this.kanbanButtonKey = const Key('matter_top_kanban_button'),
    this.graphButtonKey = const Key('matter_top_graph_button'),
  });

  final Matter matter;
  final Key notesButtonKey;
  final Key kanbanButtonKey;
  final Key graphButtonKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = MacosTheme.maybeOf(context) != null;
    final viewMode = ref.watch(matterViewModeProvider);

    Future<void> setViewMode(MatterViewMode mode) async {
      ref.read(matterViewModeProvider.notifier).set(mode);
      if (mode == MatterViewMode.graph) {
        ref.invalidate(graphControllerProvider);
      } else {
        ref.invalidate(noteListProvider);
      }
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Notes view button
        if (isMacOSNativeUI)
          macosLabeledAction(
            buttonKey: notesButtonKey,
            tooltip: 'Notes',
            icon: CupertinoIcons.doc_text,
            label: 'Notes',
            selected: viewMode == MatterViewMode.phase,
            onPressed: () {
              unawaited(setViewMode(MatterViewMode.phase));
            },
          )
        else
          materialLabeledAction(
            buttonKey: notesButtonKey,
            tooltip: 'Notes',
            icon: Icons.notes_outlined,
            label: 'Notes',
            selected: viewMode == MatterViewMode.phase,
            onPressed: () {
              unawaited(setViewMode(MatterViewMode.phase));
            },
          ),
        const SizedBox(width: 6),
        // Board (Kanban) view button
        if (isMacOSNativeUI)
          macosLabeledAction(
            buttonKey: kanbanButtonKey,
            tooltip: l10n.viewModeKanban,
            icon: CupertinoIcons.square_grid_2x2,
            label: l10n.viewModeKanban,
            selected: viewMode == MatterViewMode.kanban,
            onPressed: () {
              unawaited(setViewMode(MatterViewMode.kanban));
            },
          )
        else
          materialLabeledAction(
            buttonKey: kanbanButtonKey,
            tooltip: l10n.viewModeKanban,
            icon: Icons.view_column_outlined,
            label: l10n.viewModeKanban,
            selected: viewMode == MatterViewMode.kanban,
            onPressed: () {
              unawaited(setViewMode(MatterViewMode.kanban));
            },
          ),
        const SizedBox(width: 6),
        // Graph view button
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
