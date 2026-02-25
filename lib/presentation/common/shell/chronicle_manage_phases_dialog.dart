import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../app/app_providers.dart';
import '../../../domain/entities/matter.dart';
import '../../../domain/entities/phase.dart';
import '../../../l10n/localization.dart';
import '../../matters/matters_controller.dart';
import '../../notes/notes_controller.dart';

class ChronicleManagePhasesDialog extends ConsumerStatefulWidget {
  const ChronicleManagePhasesDialog({super.key, required this.matterId});

  final String matterId;

  @override
  ConsumerState<ChronicleManagePhasesDialog> createState() =>
      _ChronicleManagePhasesDialogState();
}

class _ChronicleManagePhasesDialogState
    extends ConsumerState<ChronicleManagePhasesDialog> {
  final TextEditingController _newPhaseController = TextEditingController();
  List<_EditablePhaseItem>? _items;
  String? _currentPhaseId;
  bool _saving = false;

  @override
  void dispose() {
    _newPhaseController.dispose();
    for (final item in _items ?? const <_EditablePhaseItem>[]) {
      item.nameController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUI(context);
    final sections = ref.watch(mattersControllerProvider).asData?.value;
    Matter? matter;
    if (sections != null) {
      final all = <Matter>{
        ...sections.pinned,
        ...sections.uncategorized,
        ...sections.categorySections.expand((section) => section.matters),
      };
      for (final candidate in all) {
        if (candidate.id == widget.matterId) {
          matter = candidate;
          break;
        }
      }
    }

    if (matter == null) {
      return AlertDialog(
        title: const Text('Manage Phases'),
        content: Text(l10n.matterNoLongerExistsMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.closeAction),
          ),
        ],
      );
    }
    final selectedMatter = matter;

    if (_items == null) {
      final sortedPhases = selectedMatter.phases.toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      _items = sortedPhases
          .map(
            (phase) => _EditablePhaseItem(
              phaseId: phase.id,
              nameController: TextEditingController(text: phase.name),
            ),
          )
          .toList();
    }
    _currentPhaseId ??=
        selectedMatter.currentPhaseId ??
        (_items!.isEmpty ? null : _items!.first.phaseId);

    Future<void> addPhase() async {
      final name = _newPhaseController.text.trim();
      if (name.isEmpty) {
        return;
      }
      setState(() {
        _items!.add(
          _EditablePhaseItem(
            phaseId: ref.read(idGeneratorProvider).newId(),
            nameController: TextEditingController(text: name),
          ),
        );
        _currentPhaseId ??= _items!.first.phaseId;
        _newPhaseController.clear();
      });
    }

    Future<void> save() async {
      if (_saving ||
          _items == null ||
          _items!.isEmpty ||
          _currentPhaseId == null) {
        return;
      }

      final names = _items!
          .map((item) => item.nameController.text.trim())
          .where((name) => name.isNotEmpty)
          .toList();
      if (names.length != _items!.length) {
        return;
      }

      setState(() {
        _saving = true;
      });

      final nextPhases = <Phase>[
        for (var i = 0; i < _items!.length; i++)
          Phase(
            id: _items![i].phaseId,
            matterId: selectedMatter.id,
            name: _items![i].nameController.text.trim(),
            order: i,
          ),
      ];

      final removedPhaseIds = selectedMatter.phases
          .where((phase) => !nextPhases.any((next) => next.id == phase.id))
          .map((phase) => phase.id)
          .toList(growable: false);

      final noteRepository = ref.read(noteRepositoryProvider);
      for (final removedPhaseId in removedPhaseIds) {
        final notes = await noteRepository.listNotesByMatterAndPhase(
          matterId: selectedMatter.id,
          phaseId: removedPhaseId,
        );
        for (final note in notes) {
          await noteRepository.moveNote(
            noteId: note.id,
            matterId: selectedMatter.id,
            phaseId: _currentPhaseId,
            notebookFolderId: null,
          );
        }
      }

      await ref
          .read(mattersControllerProvider.notifier)
          .updateMatterPhases(
            matter: selectedMatter,
            phases: nextPhases,
            currentPhaseId: _currentPhaseId!,
          );
      ref.invalidate(noteListProvider);

      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    Widget buildRow(_EditablePhaseItem item, int index) {
      final selected = item.phaseId == _currentPhaseId;
      final selectCurrentButton = isMacOSNativeUI
          ? SizedBox(
              width: 86,
              child: PushButton(
                controlSize: ControlSize.regular,
                secondary: !selected,
                onPressed: () {
                  setState(() {
                    _currentPhaseId = item.phaseId;
                  });
                },
                child: const Text('Current'),
              ),
            )
          : ChoiceChip(
              label: const Text('Current'),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _currentPhaseId = item.phaseId;
                });
              },
            );
      return Row(
        children: <Widget>[
          selectCurrentButton,
          const SizedBox(width: 8),
          Expanded(
            child: isMacOSNativeUI
                ? MacosTextField(controller: item.nameController)
                : TextField(controller: item.nameController),
          ),
          const SizedBox(width: 6),
          isMacOSNativeUI
              ? _ChronicleMacosCompactIconButton(
                  tooltip: 'Move up',
                  icon: const MacosIcon(CupertinoIcons.arrow_up, size: 12),
                  onPressed: index == 0
                      ? null
                      : () {
                          setState(() {
                            final moved = _items!.removeAt(index);
                            _items!.insert(index - 1, moved);
                          });
                        },
                )
              : IconButton(
                  onPressed: index == 0
                      ? null
                      : () {
                          setState(() {
                            final moved = _items!.removeAt(index);
                            _items!.insert(index - 1, moved);
                          });
                        },
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  tooltip: 'Move up',
                ),
          isMacOSNativeUI
              ? _ChronicleMacosCompactIconButton(
                  tooltip: 'Move down',
                  icon: const MacosIcon(CupertinoIcons.arrow_down, size: 12),
                  onPressed: index == _items!.length - 1
                      ? null
                      : () {
                          setState(() {
                            final moved = _items!.removeAt(index);
                            _items!.insert(index + 1, moved);
                          });
                        },
                )
              : IconButton(
                  onPressed: index == _items!.length - 1
                      ? null
                      : () {
                          setState(() {
                            final moved = _items!.removeAt(index);
                            _items!.insert(index + 1, moved);
                          });
                        },
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  tooltip: 'Move down',
                ),
          isMacOSNativeUI
              ? _ChronicleMacosCompactIconButton(
                  tooltip: l10n.deleteAction,
                  icon: const MacosIcon(CupertinoIcons.delete, size: 12),
                  onPressed: _items!.length <= 1
                      ? null
                      : () {
                          setState(() {
                            _items!.removeAt(index);
                            if (selected) {
                              _currentPhaseId = _items!.isEmpty
                                  ? null
                                  : _items!.first.phaseId;
                            }
                          });
                        },
                )
              : IconButton(
                  onPressed: _items!.length <= 1
                      ? null
                      : () {
                          setState(() {
                            _items!.removeAt(index);
                            if (selected) {
                              _currentPhaseId = _items!.isEmpty
                                  ? null
                                  : _items!.first.phaseId;
                            }
                          });
                        },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: l10n.deleteAction,
                ),
        ],
      );
    }

    final body = SizedBox(
      width: 720,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Current phase is used as default when creating/editing from Phase view.',
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 320,
            child: ListView.separated(
              itemCount: _items!.length,
              separatorBuilder: (_, index) => const SizedBox(height: 6),
              itemBuilder: (_, index) => buildRow(_items![index], index),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: isMacOSNativeUI
                    ? MacosTextField(
                        controller: _newPhaseController,
                        placeholder: 'New phase name',
                      )
                    : TextField(
                        controller: _newPhaseController,
                        decoration: const InputDecoration(
                          labelText: 'New phase name',
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              isMacOSNativeUI
                  ? PushButton(
                      controlSize: ControlSize.regular,
                      onPressed: addPhase,
                      child: const Text('Add'),
                    )
                  : FilledButton(onPressed: addPhase, child: const Text('Add')),
            ],
          ),
        ],
      ),
    );

    if (isMacOSNativeUI) {
      return MacosSheet(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Manage Phases',
                style: MacosTheme.of(context).typography.title2,
              ),
              const SizedBox(height: 12),
              body,
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(l10n.cancelAction),
                  ),
                  const SizedBox(width: 8),
                  PushButton(
                    controlSize: ControlSize.regular,
                    onPressed: _saving ? null : save,
                    child: Text(_saving ? 'Saving...' : l10n.saveAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: const Text('Manage Phases'),
      content: body,
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: _saving ? null : save,
          child: Text(_saving ? 'Saving...' : l10n.saveAction),
        ),
      ],
    );
  }
}

class _EditablePhaseItem {
  const _EditablePhaseItem({
    required this.phaseId,
    required this.nameController,
  });

  final String phaseId;
  final TextEditingController nameController;
}

class _ChronicleMacosCompactIconButton extends StatelessWidget {
  const _ChronicleMacosCompactIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: PushButton(
        controlSize: ControlSize.small,
        secondary: true,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        onPressed: onPressed,
        child: Opacity(opacity: enabled ? 1 : 0.45, child: icon),
      ),
    );
  }
}

bool _isMacOSNativeUI(BuildContext context) {
  return MacosTheme.maybeOf(context) != null;
}
