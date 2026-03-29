import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../domain/entities/matter.dart';

import '../../matters/matters_controller.dart';
import '../../notes/notes_controller.dart';
import 'chronicle_manage_phases_dialog.dart';

/// A reusable phase selector widget for matters.
/// Displays a dropdown to select a phase, "All Phases", or manage phases.
class ChroniclePhaseSelector extends ConsumerWidget {
  const ChroniclePhaseSelector({
    super.key,
    required this.matter,
    this.buttonKey = const Key('phase_selector_button'),
  });

  final Matter matter;
  final Key buttonKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    Future<void> selectPhase(String? phaseId) async {
      await ref
          .read(noteEditorControllerProvider.notifier)
          .openMatterInWorkspace(
            matterId: matter.id,
            phaseId: phaseId,
            matter: matter,
          );
    }

    Future<void> openManagePhases() async {
      await showDialog<void>(
        context: context,
        builder: (_) => ChronicleManagePhasesDialog(matterId: matter.id),
      );
    }

    final isMacOSNativeUI = MacosTheme.maybeOf(context) != null;

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

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const MacosIcon(
            CupertinoIcons.square_stack_3d_down_right,
            size: 13,
          ),
          const SizedBox(width: 6),
          MacosPulldownButton(
            key: buttonKey,
            title: phaseButtonLabel,
            items: items,
          ),
        ],
      );
    }

    return PopupMenuButton<String>(
      key: buttonKey,
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
    );
  }
}
