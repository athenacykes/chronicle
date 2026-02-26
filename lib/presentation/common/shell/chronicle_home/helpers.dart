part of '../chronicle_home_coordinator.dart';

class _NoteDragPayload {
  const _NoteDragPayload({
    required this.noteId,
    required this.matterId,
    required this.phaseId,
  });

  final String noteId;
  final String? matterId;
  final String? phaseId;
}

class _MatterReassignPayload {
  const _MatterReassignPayload({
    required this.matterId,
    required this.categoryId,
  });

  final String matterId;
  final String? categoryId;
}

final _activeNoteDragPayloadProvider =
    NotifierProvider<
      ValueNotifierController<_NoteDragPayload?>,
      _NoteDragPayload?
    >(() => ValueNotifierController<_NoteDragPayload?>(null));

Future<List<Matter>> _allMattersForMove(WidgetRef ref) async {
  final MatterSections sections =
      ref.read(mattersControllerProvider).asData?.value ??
      await ref.read(mattersControllerProvider.future);
  return _allMattersFromSections(sections);
}

List<Matter> _allMattersFromSections(MatterSections sections) {
  return <Matter>[
    ...sections.pinned,
    ...sections.uncategorized,
    ...sections.categorySections.expand((section) => section.matters),
  ];
}

Matter? _findMatterById(MatterSections? sections, String? matterId) {
  if (sections == null || matterId == null) {
    return null;
  }
  final allMatters = _allMattersFromSections(sections);
  for (final candidate in allMatters) {
    if (candidate.id == matterId) {
      return candidate;
    }
  }
  return null;
}

String _displayMatterTitle(BuildContext context, Matter matter) {
  final trimmed = matter.title.trim();
  if (trimmed.isEmpty) {
    return context.l10n.untitledMatterLabel;
  }
  return trimmed;
}

String _displayCategoryName(BuildContext context, Category category) {
  final trimmed = category.name.trim();
  if (trimmed.isEmpty) {
    return context.l10n.untitledCategoryLabel;
  }
  return trimmed;
}

String _displayNoteTitleForMove(BuildContext context, Note note) {
  final trimmed = note.title.trim();
  if (trimmed.isEmpty) {
    return context.l10n.untitledLabel;
  }
  return trimmed;
}

String _normalizeSearchInput(String value) {
  return value.replaceAll(RegExp(r'[\r\n]+'), ' ');
}

bool _hasSearchText(String value) {
  final normalized = _normalizeSearchInput(value);
  final nonWhitespace = normalized.replaceAll(RegExp(r'\s+'), '');
  return nonWhitespace.length >= 2;
}

String _timeViewLabel(BuildContext context, ChronicleTimeView timeView) {
  final l10n = context.l10n;
  return switch (timeView) {
    ChronicleTimeView.today => l10n.timeViewTodayLabel,
    ChronicleTimeView.yesterday => l10n.timeViewYesterdayLabel,
    ChronicleTimeView.thisWeek => l10n.timeViewThisWeekLabel,
    ChronicleTimeView.lastWeek => l10n.timeViewLastWeekLabel,
  };
}

String _searchResultContextLine({
  required BuildContext context,
  required Note note,
  required MatterSections? sections,
  required List<NotebookFolderTreeNode> notebookTree,
}) {
  final l10n = context.l10n;
  if (note.isInNotebook) {
    final labels = <String, String>{};
    void collect(List<NotebookFolderTreeNode> nodes) {
      for (final node in nodes) {
        labels[node.folder.id] = node.folder.name.trim();
        collect(node.children);
      }
    }

    collect(notebookTree);
    final folderId = note.notebookFolderId;
    if (folderId == null) {
      return '${l10n.notebookLabel} • ${l10n.notebookRootLabel}';
    }
    final folderName = labels[folderId];
    if (folderName == null || folderName.isEmpty) {
      return '${l10n.notebookLabel} • $folderId';
    }
    return '${l10n.notebookLabel} • $folderName';
  }

  Matter? matter;
  if (sections != null) {
    final allMatters = <Matter>[
      ...sections.pinned,
      ...sections.uncategorized,
      ...sections.categorySections.expand((section) => section.matters),
    ];
    for (final candidate in allMatters) {
      if (candidate.id == note.matterId) {
        matter = candidate;
        break;
      }
    }
  }

  final matterTitle = matter == null
      ? l10n.untitledMatterLabel
      : _displayMatterTitle(context, matter);
  final phaseId = note.phaseId;
  if (phaseId == null) {
    return '$matterTitle • ${l10n.notebookLabel}';
  }

  String phaseLabel = phaseId;
  if (matter != null) {
    for (final phase in matter.phases) {
      if (phase.id == phaseId) {
        final trimmed = phase.name.trim();
        phaseLabel = trimmed.isEmpty ? phaseId : trimmed;
        break;
      }
    }
  }
  return '$matterTitle • $phaseLabel';
}

String? _resolvedPhaseForMatter(Matter matter) {
  return matter.currentPhaseId ??
      (matter.phases.isEmpty ? null : matter.phases.first.id);
}

Future<Matter?> _showMoveToMatterDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Note note,
}) async {
  final matters = await _allMattersForMove(ref);
  if (!context.mounted || matters.isEmpty) {
    return null;
  }

  return showDialog<Matter>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      return AlertDialog(
        title: Text(l10n.moveNoteToMatterDialogTitle),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: matters
                  .map((matter) {
                    final selected = note.matterId == matter.id;
                    return ListTile(
                      title: Text(_displayMatterTitle(dialogContext, matter)),
                      subtitle: Text(
                        selected
                            ? l10n.moveNoteCurrentMatterLabel
                            : _matterStatusBadgeLabel(l10n, matter.status),
                      ),
                      trailing: selected ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.of(dialogContext).pop(matter),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancelAction),
          ),
        ],
      );
    },
  );
}

Future<Phase?> _showMoveToPhaseDialog({
  required BuildContext context,
  required Matter matter,
  required Note note,
}) async {
  if (matter.phases.isEmpty) {
    return null;
  }

  final orderedPhases = matter.phases.toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  return showDialog<Phase>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      return AlertDialog(
        title: Text(l10n.moveNoteToPhaseDialogTitle),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: orderedPhases
                  .map((phase) {
                    final selected = note.phaseId == phase.id;
                    return ListTile(
                      title: Text(phase.name),
                      trailing: selected ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.of(dialogContext).pop(phase),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancelAction),
          ),
        ],
      );
    },
  );
}

class _MoveToNotebookSelection {
  const _MoveToNotebookSelection({required this.folderId});

  final String? folderId;
}

Future<_MoveToNotebookSelection?> _showMoveToNotebookDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Note note,
}) async {
  List<NotebookFolder> folders;
  try {
    folders = await ref.read(notebookRepositoryProvider).listFolders();
  } catch (_) {
    return const _MoveToNotebookSelection(folderId: null);
  }
  if (!context.mounted) {
    return null;
  }
  if (folders.isEmpty) {
    return const _MoveToNotebookSelection(folderId: null);
  }
  final tree = buildNotebookFolderTree(folders);
  final currentFolderId = note.isInNotebook ? note.notebookFolderId : null;

  return showDialog<_MoveToNotebookSelection>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      String? selectedFolderId = currentFolderId;

      List<Widget> buildFolderTiles(
        List<NotebookFolderTreeNode> nodes,
        int depth,
        StateSetter setState,
      ) {
        final out = <Widget>[];
        for (final node in nodes) {
          final folder = node.folder;
          final selected = selectedFolderId == folder.id;
          out.add(
            ListTile(
              contentPadding: EdgeInsets.only(
                left: 12 + (depth * 20),
                right: 8,
              ),
              leading: const Icon(Icons.folder_outlined),
              title: Text(folder.name),
              subtitle: selected
                  ? Text(l10n.moveNoteCurrentNotebookLabel)
                  : null,
              trailing: selected ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() {
                  selectedFolderId = folder.id;
                });
              },
            ),
          );
          out.addAll(buildFolderTiles(node.children, depth + 1, setState));
        }
        return out;
      }

      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: Text(l10n.moveToNotebookDialogTitle),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: const Icon(Icons.book_outlined),
                      title: Text(l10n.notebookRootLabel),
                      subtitle: selectedFolderId == null
                          ? Text(l10n.moveNoteCurrentNotebookLabel)
                          : null,
                      trailing: selectedFolderId == null
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        setState(() {
                          selectedFolderId = null;
                        });
                      },
                    ),
                    ...buildFolderTiles(tree, 1, setState),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancelAction),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(
                    dialogContext,
                  ).pop(_MoveToNotebookSelection(folderId: selectedFolderId));
                },
                child: Text(l10n.moveToNotebookAction),
              ),
            ],
          );
        },
      );
    },
  );
}

void _showMoveMessage(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> _moveNoteToMatter({
  required BuildContext context,
  required WidgetRef ref,
  required String noteId,
  required Matter targetMatter,
}) async {
  final l10n = context.l10n;
  final targetPhaseId = _resolvedPhaseForMatter(targetMatter);
  if (targetPhaseId == null) {
    _showMoveMessage(
      context,
      l10n.moveTargetMatterHasNoPhases(
        _displayMatterTitle(context, targetMatter),
      ),
    );
    return false;
  }

  try {
    await ref
        .read(noteEditorControllerProvider.notifier)
        .moveNoteById(
          noteId: noteId,
          matterId: targetMatter.id,
          phaseId: targetPhaseId,
          notebookFolderId: null,
        );
    return true;
  } catch (error) {
    if (!context.mounted) {
      return false;
    }
    _showMoveMessage(context, l10n.moveNoteFailed(error.toString()));
    return false;
  }
}

Future<bool> _moveNoteToPhase({
  required BuildContext context,
  required WidgetRef ref,
  required String noteId,
  required String sourceMatterId,
  required Phase phase,
}) async {
  final l10n = context.l10n;
  if (phase.matterId != sourceMatterId) {
    _showMoveMessage(context, l10n.movePhaseRequiresSameMatterMessage);
    return false;
  }
  try {
    await ref
        .read(noteEditorControllerProvider.notifier)
        .moveNoteById(
          noteId: noteId,
          matterId: phase.matterId,
          phaseId: phase.id,
          notebookFolderId: null,
        );
    return true;
  } catch (error) {
    if (!context.mounted) {
      return false;
    }
    _showMoveMessage(context, l10n.moveNoteFailed(error.toString()));
    return false;
  }
}

Future<bool> _moveNoteToNotebook({
  required BuildContext context,
  required WidgetRef ref,
  required String noteId,
  required String? folderId,
}) async {
  final l10n = context.l10n;
  try {
    await ref
        .read(noteEditorControllerProvider.notifier)
        .moveNoteById(
          noteId: noteId,
          matterId: null,
          phaseId: null,
          notebookFolderId: folderId,
        );
    return true;
  } catch (error) {
    if (!context.mounted) {
      return false;
    }
    _showMoveMessage(context, l10n.moveNoteFailed(error.toString()));
    return false;
  }
}

Future<bool> _moveNoteToNotebookViaDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Note note,
}) async {
  final selection = await _showMoveToNotebookDialog(
    context: context,
    ref: ref,
    note: note,
  );
  if (!context.mounted || selection == null) {
    return false;
  }
  return _moveNoteToNotebook(
    context: context,
    ref: ref,
    noteId: note.id,
    folderId: selection.folderId,
  );
}

const Key _kSidebarRootKey = Key('sidebar_root');
const Key _kSidebarNotebookRootDropTargetKey = Key(
  'sidebar_notebook_root_drop_target',
);
const Key _kMacosConflictsRefreshButtonKey = Key('macos_conflicts_refresh');
const Key _kMacosNoteEditorTagsFieldKey = Key('macos_note_editor_tags');
const Key _kMacosNoteEditorContentFieldKey = Key('macos_note_editor_content');
const Key _kMacosNoteEditorSaveButtonKey = Key('macos_note_editor_save');
const Key _kNoteEditorMarkdownToolbarKey = Key('note_editor_markdown_toolbar');
const Key _kNoteEditorModeToggleKey = Key('note_editor_mode_toggle');
const Key _kNoteEditorUtilityTagsKey = Key('note_editor_utility_tags');
const Key _kNoteEditorUtilityAttachmentsKey = Key(
  'note_editor_utility_attachments',
);
const Key _kNoteEditorUtilityLinkedKey = Key('note_editor_utility_linked');

class _MatterIconOption {
  const _MatterIconOption({required this.key, required this.iconData});

  final String key;
  final IconData iconData;
}

const List<_MatterIconOption> _kMatterIconOptions = <_MatterIconOption>[
  _MatterIconOption(key: 'description', iconData: Icons.description_outlined),
  _MatterIconOption(key: 'folder', iconData: Icons.folder_open),
  _MatterIconOption(key: 'work', iconData: Icons.work_outline),
  _MatterIconOption(key: 'gavel', iconData: Icons.gavel),
  _MatterIconOption(key: 'school', iconData: Icons.school_outlined),
  _MatterIconOption(
    key: 'account_balance',
    iconData: Icons.account_balance_outlined,
  ),
  _MatterIconOption(key: 'home', iconData: Icons.home_outlined),
  _MatterIconOption(key: 'build', iconData: Icons.build_outlined),
  _MatterIconOption(key: 'bolt', iconData: Icons.bolt_outlined),
  _MatterIconOption(key: 'assignment', iconData: Icons.assignment_outlined),
  _MatterIconOption(key: 'event', iconData: Icons.event_outlined),
  _MatterIconOption(key: 'campaign', iconData: Icons.campaign_outlined),
  _MatterIconOption(
    key: 'local_hospital',
    iconData: Icons.local_hospital_outlined,
  ),
  _MatterIconOption(key: 'science', iconData: Icons.science_outlined),
  _MatterIconOption(key: 'terminal', iconData: Icons.terminal_outlined),
];

Widget _adaptiveLoadingIndicator(BuildContext context, {Key? key}) {
  if (_isMacOSNativeUIContext(context)) {
    return ProgressCircle(key: key);
  }
  return CircularProgressIndicator(key: key);
}

BoxDecoration _macosPanelDecoration(BuildContext context) {
  final brightness = MacosTheme.brightnessOf(context);
  return BoxDecoration(
    color: brightness.resolve(const Color(0xFFFDFDFD), const Color(0xFF202327)),
    border: Border.all(color: MacosTheme.of(context).dividerColor),
    borderRadius: BorderRadius.circular(8),
  );
}

CodeThemeData _noteEditorCodeThemeData(BuildContext context) {
  return markdownCodeThemeDataForBrightness(
    markdownEffectiveBrightness(context),
  );
}

TextStyle _macosSectionTitleStyle(BuildContext context) {
  return MacosTheme.of(
    context,
  ).typography.title3.copyWith(fontWeight: MacosFontWeight.w590);
}

bool _isMacOSNativeUIContext(BuildContext context) {
  return MacosTheme.maybeOf(context) != null;
}

String _normalizeHexColor(String value, {String fallback = '#4C956C'}) {
  final normalizedFallback = fallback.trim().toUpperCase();
  final trimmed = value.trim().toUpperCase();
  if (RegExp(r'^#[0-9A-F]{6}$').hasMatch(trimmed)) {
    return trimmed;
  }
  if (RegExp(r'^[0-9A-F]{6}$').hasMatch(trimmed)) {
    return '#$trimmed';
  }
  return RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalizedFallback)
      ? normalizedFallback
      : '#4C956C';
}

Color _colorFromHex(String value, {String fallback = '#4C956C'}) {
  final normalized = _normalizeHexColor(value, fallback: fallback);
  final rgbValue = int.parse(normalized.substring(1), radix: 16);
  return Color(0xFF000000 | rgbValue);
}

_MatterIconOption _matterIconOptionForKey(String iconKey) {
  for (final option in _kMatterIconOptions) {
    if (option.key == iconKey.trim()) {
      return option;
    }
  }
  return _kMatterIconOptions.first;
}

IconData _matterIconDataForKey(String iconKey) {
  return _matterIconOptionForKey(iconKey).iconData;
}

String _matterStatusBadgeLabel(AppLocalizations l10n, MatterStatus status) {
  return switch (status) {
    MatterStatus.active => l10n.matterStatusBadgeActive,
    MatterStatus.paused => l10n.matterStatusBadgePaused,
    MatterStatus.completed => l10n.matterStatusBadgeCompleted,
    MatterStatus.archived => l10n.matterStatusBadgeArchived,
  };
}
