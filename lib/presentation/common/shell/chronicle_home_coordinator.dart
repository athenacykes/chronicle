import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../../app/app_providers.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/matter.dart';
import '../../../domain/entities/matter_graph_data.dart';
import '../../../domain/entities/matter_graph_edge.dart';
import '../../../domain/entities/matter_graph_node.dart';
import '../../../domain/entities/matter_sections.dart';
import '../../../domain/entities/note.dart';
import '../../../domain/entities/notebook_folder.dart';
import '../../../domain/entities/phase.dart';
import '../../../domain/entities/sync_blocker.dart';
import '../../../domain/entities/sync_conflict.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/localization.dart';
import '../../links/graph_controller.dart';
import '../../links/links_controller.dart';
import '../../matters/matters_controller.dart';
import '../markdown/chronicle_markdown.dart';
import '../markdown/markdown_code_controller.dart';
import '../markdown/markdown_edit_formatter.dart';
import '../markdown/markdown_format_toolbar.dart';
import '../markdown/markdown_code_highlighting.dart';
import '../state/value_notifier_provider.dart';
import '../../notes/notes_controller.dart';
import '../../notes/note_attachment_widgets.dart';
import '../../search/search_controller.dart';
import '../../settings/settings_controller.dart';
import '../../sync/conflicts_controller.dart';
import '../../sync/sync_controller.dart';
import 'chronicle_shell.dart';
import 'chronicle_shell_contract.dart';

Future<void> showChronicleSettingsDialog({
  required BuildContext context,
  required bool useMacOSNativeUI,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SettingsDialog(useMacOSNativeUI: useMacOSNativeUI),
  );
}

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

class ChronicleHomeScreen extends ConsumerStatefulWidget {
  const ChronicleHomeScreen({super.key, required this.useMacOSNativeUI});

  final bool useMacOSNativeUI;

  @override
  ConsumerState<ChronicleHomeScreen> createState() =>
      _ChronicleHomeScreenState();
}

class _ChronicleHomeScreenState extends ConsumerState<ChronicleHomeScreen> {
  late final TextEditingController _searchController;
  bool _settingsDialogOpen = false;
  String? _searchIndexBuiltForRoot;
  Future<void>? _searchIndexBootstrap;
  String? _lastSelectedMatterIdForAutoOpen;
  String? _pendingAutoOpenMatterId;
  int _autoOpenNoteRequestToken = 0;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_handleSearchControllerChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchControllerChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchControllerChanged() {
    _syncSearchStateFromText(_searchController.text);
  }

  void _syncSearchStateFromText(String value) {
    final normalized = _normalizeSearchInput(value);
    if (normalized != value) {
      final selection = _searchController.selection;
      final baseOffset = selection.baseOffset
          .clamp(0, normalized.length)
          .toInt();
      final extentOffset = selection.extentOffset
          .clamp(0, normalized.length)
          .toInt();
      _searchController.value = _searchController.value.copyWith(
        text: normalized,
        selection: TextSelection(
          baseOffset: baseOffset,
          extentOffset: extentOffset,
        ),
        composing: TextRange.empty,
      );
      return;
    }

    final queryNotifier = ref.read(searchControllerProvider.notifier);
    final currentText = ref.read(searchQueryProvider).text;
    if (currentText != normalized) {
      unawaited(queryNotifier.setText(normalized));
    }

    final visibleNotifier = ref.read(searchResultsVisibleProvider.notifier);
    final shouldShowResults = _hasSearchText(normalized);
    final currentVisibility = ref.read(searchResultsVisibleProvider);
    if (currentVisibility != shouldShowResults) {
      visibleNotifier.set(shouldShowResults);
    }
  }

  void _ensureSearchIndexIsReady(String rootPath) {
    if (_searchIndexBuiltForRoot == rootPath || _searchIndexBootstrap != null) {
      return;
    }
    _searchIndexBootstrap = _rebuildSearchIndexForRoot(rootPath);
  }

  Future<void> _rebuildSearchIndexForRoot(String rootPath) async {
    try {
      await ref.read(searchRepositoryProvider).rebuildIndex();
      if (!mounted) {
        return;
      }
      _searchIndexBuiltForRoot = rootPath;
      ref.invalidate(searchControllerProvider);
    } finally {
      _searchIndexBootstrap = null;
      if (mounted) {
        final activeRoot = ref
            .read(settingsControllerProvider)
            .asData
            ?.value
            .storageRootPath;
        if (activeRoot != null &&
            activeRoot.isNotEmpty &&
            activeRoot != _searchIndexBuiltForRoot) {
          _ensureSearchIndexIsReady(activeRoot);
        }
      }
    }
  }

  Future<void> _openSettingsDialog() async {
    if (!mounted || _settingsDialogOpen) {
      return;
    }
    _settingsDialogOpen = true;
    try {
      await showChronicleSettingsDialog(
        context: context,
        useMacOSNativeUI: widget.useMacOSNativeUI,
      );
    } finally {
      _settingsDialogOpen = false;
    }
  }

  void _queueAutoOpenOnMatterSelectionChange(String? selectedMatterId) {
    if (_lastSelectedMatterIdForAutoOpen == selectedMatterId) {
      return;
    }
    _lastSelectedMatterIdForAutoOpen = selectedMatterId;
    _pendingAutoOpenMatterId = selectedMatterId;
  }

  void _maybeScheduleAutoOpenForPendingMatter({
    required Matter? selectedMatter,
    required bool showNotebook,
    required bool showConflicts,
  }) {
    final pendingMatterId = _pendingAutoOpenMatterId;
    if (pendingMatterId == null ||
        selectedMatter == null ||
        selectedMatter.id != pendingMatterId ||
        showNotebook ||
        showConflicts) {
      return;
    }
    _pendingAutoOpenMatterId = null;
    final requestToken = ++_autoOpenNoteRequestToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _autoOpenFirstNoteForMatter(
          requestToken: requestToken,
          matter: selectedMatter,
        ),
      );
    });
  }

  Future<void> _autoOpenFirstNoteForMatter({
    required int requestToken,
    required Matter matter,
  }) async {
    if (!mounted || requestToken != _autoOpenNoteRequestToken) {
      return;
    }
    if (ref.read(showNotebookProvider) || ref.read(showConflictsProvider)) {
      return;
    }
    if (ref.read(selectedMatterIdProvider) != matter.id) {
      return;
    }

    final selectedPhaseId =
        ref.read(selectedPhaseIdProvider) ??
        matter.currentPhaseId ??
        (matter.phases.isEmpty ? null : matter.phases.first.id);
    final noteEditorState = ref.read(noteEditorControllerProvider);
    final currentNote = noteEditorState.asData?.value;
    final currentNoteMatchesTarget =
        currentNote != null &&
        currentNote.matterId == matter.id &&
        (selectedPhaseId == null || currentNote.phaseId == selectedPhaseId);
    if (currentNoteMatchesTarget) {
      return;
    }

    final noteRepository = ref.read(noteRepositoryProvider);
    final notes = selectedPhaseId == null || selectedPhaseId.isEmpty
        ? await noteRepository.listMatterTimeline(matter.id)
        : await noteRepository.listNotesByMatterAndPhase(
            matterId: matter.id,
            phaseId: selectedPhaseId,
          );

    if (!mounted || requestToken != _autoOpenNoteRequestToken) {
      return;
    }
    if (ref.read(showNotebookProvider) || ref.read(showConflictsProvider)) {
      return;
    }
    if (ref.read(selectedMatterIdProvider) != matter.id) {
      return;
    }
    if (notes.isEmpty) {
      final staleSelectedNote = ref
          .read(noteEditorControllerProvider)
          .asData
          ?.value;
      if (staleSelectedNote != null &&
          (staleSelectedNote.matterId != matter.id ||
              (selectedPhaseId != null &&
                  staleSelectedNote.phaseId != selectedPhaseId))) {
        await ref.read(noteEditorControllerProvider.notifier).selectNote(null);
      }
      return;
    }

    final latestEditorState = ref.read(noteEditorControllerProvider);
    final latestNote = latestEditorState.asData?.value;
    final latestNoteMatchesTarget =
        latestNote != null &&
        latestNote.matterId == matter.id &&
        (selectedPhaseId == null || latestNote.phaseId == selectedPhaseId);
    if (latestNoteMatchesTarget) {
      return;
    }

    await ref
        .read(noteEditorControllerProvider.notifier)
        .selectNote(notes.first.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settingsState = ref.watch(settingsControllerProvider);

    return settingsState.when(
      loading: () => _LoadingShell(useMacOSNativeUI: widget.useMacOSNativeUI),
      error: (error, _) => _ErrorShell(
        useMacOSNativeUI: widget.useMacOSNativeUI,
        message: l10n.failedToLoadSettings(error.toString()),
      ),
      data: (settings) {
        final root = settings.storageRootPath;
        if (root == null || root.isEmpty) {
          _searchIndexBuiltForRoot = null;
          return _StorageRootSetupScreen(
            useMacOSNativeUI: widget.useMacOSNativeUI,
            onConfirm: (path) async {
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setStorageRootPath(path);
              await ref.read(mattersControllerProvider.notifier).reload();
              await ref.read(conflictsControllerProvider.notifier).reload();
            },
          );
        }

        _ensureSearchIndexIsReady(root);

        final mattersState = ref.watch(mattersControllerProvider);
        final matterSections = mattersState.asData?.value;
        final searchState = ref.watch(searchControllerProvider);
        final searchQuery = ref.watch(searchQueryProvider);
        final searchResultsVisible = ref.watch(searchResultsVisibleProvider);
        final hasParkedSearchResults =
            _hasSearchText(searchQuery.text) && !searchResultsVisible;
        final hasSearchResultsOpen =
            _hasSearchText(searchQuery.text) && searchResultsVisible;
        final conflictCount = ref.watch(conflictCountProvider);
        final selectedMatterId = ref.watch(selectedMatterIdProvider);
        final showNotebook = ref.watch(showNotebookProvider);
        final showConflicts = ref.watch(showConflictsProvider);
        final selectedNotebookFolderId = ref.watch(
          selectedNotebookFolderIdProvider,
        );
        final notebookTree = ref.watch(notebookFolderTreeProvider);
        final notebookFolders = ref
            .watch(notebookFoldersProvider)
            .asData
            ?.value;
        NotebookFolder? selectedNotebookFolder;
        if (notebookFolders != null && selectedNotebookFolderId != null) {
          for (final folder in notebookFolders) {
            if (folder.id == selectedNotebookFolderId) {
              selectedNotebookFolder = folder;
              break;
            }
          }
        }
        final selectedMatter = _findMatterById(
          matterSections,
          selectedMatterId,
        );
        _queueAutoOpenOnMatterSelectionChange(selectedMatterId);
        _maybeScheduleAutoOpenForPendingMatter(
          selectedMatter: selectedMatter,
          showNotebook: showNotebook,
          showConflicts: showConflicts,
        );
        final workspaceTitle = showConflicts
            ? l10n.conflictsLabel
            : showNotebook
            ? (selectedNotebookFolder?.name.trim().isNotEmpty == true
                  ? selectedNotebookFolder!.name.trim()
                  : l10n.notebookLabel)
            : selectedMatter != null
            ? _displayMatterTitle(context, selectedMatter)
            : l10n.appTitle;
        Widget? topBarContextActions;
        if (!showConflicts && !hasSearchResultsOpen) {
          if (showNotebook) {
            topBarContextActions = const _NotebookTopControls();
          } else if (selectedMatter != null) {
            topBarContextActions = _MatterTopControls(matter: selectedMatter);
          }
        }

        final content = searchState.when(
          loading: () => _MainWorkspace(
            searchHits: const <SearchListItem>[],
            searchQuery: searchQuery.text,
            showSearchResults: searchResultsVisible,
          ),
          error: (error, stackTrace) => _MainWorkspace(
            searchHits: const <SearchListItem>[],
            searchQuery: searchQuery.text,
            showSearchResults: searchResultsVisible,
          ),
          data: (hits) {
            final mapped = hits
                .map(
                  (hit) => SearchListItem(
                    noteId: hit.note.id,
                    title: hit.note.title,
                    contextLine: _searchResultContextLine(
                      context: context,
                      note: hit.note,
                      sections: matterSections,
                      notebookTree: notebookTree,
                    ),
                    snippet: hit.snippet,
                  ),
                )
                .toList();
            return _MainWorkspace(
              searchHits: mapped,
              searchQuery: searchQuery.text,
              showSearchResults: searchResultsVisible,
            );
          },
        );

        return ChronicleShell(
          useMacOSNativeUI: widget.useMacOSNativeUI,
          viewModel: ChronicleShellViewModel(
            appWindowTitle: l10n.appTitle,
            title: workspaceTitle,
            searchController: _searchController,
            onSearchChanged: (value) {
              _syncSearchStateFromText(value);
            },
            onSearchFieldTap: () {
              final queryText = ref.read(searchQueryProvider).text;
              if (_hasSearchText(queryText)) {
                ref.read(searchResultsVisibleProvider.notifier).set(true);
              } else {
                ref.read(searchResultsVisibleProvider.notifier).set(false);
              }
            },
            onReturnToSearchResults: () {
              final queryText = ref.read(searchQueryProvider).text;
              if (_hasSearchText(queryText)) {
                ref.read(searchResultsVisibleProvider.notifier).set(true);
              } else {
                ref.read(searchResultsVisibleProvider.notifier).set(false);
              }
            },
            hasParkedSearchResults: hasParkedSearchResults,
            onShowConflicts: () {
              ref.read(showConflictsProvider.notifier).set(true);
              ref.read(showNotebookProvider.notifier).set(false);
            },
            onOpenSettings: () async {
              await _openSettingsDialog();
            },
            conflictCount: conflictCount,
            topBarContextActions: topBarContextActions,
            sidebarBuilder: (scrollController) => mattersState.when(
              loading: () => _SidebarMessageView(
                scrollController: scrollController,
                child: widget.useMacOSNativeUI
                    ? const Center(child: ProgressCircle())
                    : const Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _SidebarMessageView(
                scrollController: scrollController,
                child: Center(child: Text('$error')),
              ),
              data: (sections) => _MatterSidebar(
                sections: sections,
                scrollController: scrollController,
              ),
            ),
            content: content,
          ),
        );
      },
    );
  }
}

class _LoadingShell extends StatelessWidget {
  const _LoadingShell({required this.useMacOSNativeUI});

  final bool useMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!useMacOSNativeUI) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return MacosWindow(
      titleBar: TitleBar(title: Text(l10n.appTitle)),
      child: MacosScaffold(
        children: <Widget>[
          ContentArea(
            builder: (context, scrollController) =>
                const Center(child: ProgressCircle()),
          ),
        ],
      ),
    );
  }
}

class _ErrorShell extends StatelessWidget {
  const _ErrorShell({required this.useMacOSNativeUI, required this.message});

  final bool useMacOSNativeUI;
  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!useMacOSNativeUI) {
      return Scaffold(body: Center(child: Text(message)));
    }

    return MacosWindow(
      titleBar: TitleBar(title: Text(l10n.appTitle)),
      child: MacosScaffold(
        children: <Widget>[
          ContentArea(
            builder: (context, scrollController) =>
                Center(child: Text(message)),
          ),
        ],
      ),
    );
  }
}

class _StorageRootSetupScreen extends ConsumerStatefulWidget {
  const _StorageRootSetupScreen({
    required this.onConfirm,
    required this.useMacOSNativeUI,
  });

  final Future<void> Function(String path) onConfirm;
  final bool useMacOSNativeUI;

  @override
  ConsumerState<_StorageRootSetupScreen> createState() =>
      _StorageRootSetupScreenState();
}

class _StorageRootSetupScreenState
    extends ConsumerState<_StorageRootSetupScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _loadingDefault = true;

  @override
  void initState() {
    super.initState();
    _initDefault();
  }

  Future<void> _initDefault() async {
    final value = await ref
        .read(settingsControllerProvider.notifier)
        .suggestedDefaultRootPath();
    if (!mounted) {
      return;
    }
    _controller.text = value;
    setState(() {
      _loadingDefault = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loadingDefault) {
      if (widget.useMacOSNativeUI) {
        return const _LoadingShell(useMacOSNativeUI: true);
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final body = Center(
      child: SizedBox(
        width: 520,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.storageSetupTitle,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(l10n.storageSetupDescription),
                const SizedBox(height: 12),
                widget.useMacOSNativeUI
                    ? MacosTextField(
                        controller: _controller,
                        placeholder: l10n.storageRootPathLabel,
                      )
                    : TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          labelText: l10n.storageRootPathLabel,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    widget.useMacOSNativeUI
                        ? PushButton(
                            controlSize: ControlSize.large,
                            onPressed: () async {
                              await ref
                                  .read(settingsControllerProvider.notifier)
                                  .chooseAndSetStorageRoot();
                              final state = ref
                                  .read(settingsControllerProvider)
                                  .asData
                                  ?.value;
                              if (state?.storageRootPath != null) {
                                _controller.text = state!.storageRootPath!;
                              }
                            },
                            child: Text(l10n.pickFolderAction),
                          )
                        : FilledButton(
                            onPressed: () async {
                              await ref
                                  .read(settingsControllerProvider.notifier)
                                  .chooseAndSetStorageRoot();
                              final state = ref
                                  .read(settingsControllerProvider)
                                  .asData
                                  ?.value;
                              if (state?.storageRootPath != null) {
                                _controller.text = state!.storageRootPath!;
                              }
                            },
                            child: Text(l10n.pickFolderAction),
                          ),
                    const SizedBox(width: 8),
                    widget.useMacOSNativeUI
                        ? PushButton(
                            controlSize: ControlSize.large,
                            onPressed: () async {
                              await widget.onConfirm(_controller.text.trim());
                            },
                            child: Text(l10n.continueAction),
                          )
                        : FilledButton.tonal(
                            onPressed: () async {
                              await widget.onConfirm(_controller.text.trim());
                            },
                            child: Text(l10n.continueAction),
                          ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!widget.useMacOSNativeUI) {
      return Scaffold(body: body);
    }

    return MacosWindow(
      titleBar: TitleBar(title: Text(l10n.chronicleSetupTitle)),
      child: MacosScaffold(
        children: <Widget>[
          ContentArea(builder: (context, scrollController) => body),
        ],
      ),
    );
  }
}

class _MatterSidebar extends ConsumerWidget {
  const _MatterSidebar({required this.sections, this.scrollController});

  final MatterSections sections;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMatterId = ref.watch(selectedMatterIdProvider);
    final showNotebook = ref.watch(showNotebookProvider);
    final selectedNotebookFolderId = ref.watch(
      selectedNotebookFolderIdProvider,
    );
    final notebookTree = ref.watch(notebookFolderTreeProvider);
    final showConflicts = ref.watch(showConflictsProvider);
    final conflictCount = ref.watch(conflictCountProvider);
    final noteDragPayload = ref.watch(_activeNoteDragPayloadProvider);
    final settings = ref.watch(settingsControllerProvider).asData?.value;
    final collapsedCategoryIds =
        settings?.collapsedCategoryIds.toSet() ?? <String>{};

    if (_isMacOSNativeUIContext(context)) {
      return _buildMacOSSidebar(
        context: context,
        ref: ref,
        selectedMatterId: selectedMatterId,
        showNotebook: showNotebook,
        selectedNotebookFolderId: selectedNotebookFolderId,
        notebookTree: notebookTree,
        showConflicts: showConflicts,
        conflictCount: conflictCount,
        noteDragPayload: noteDragPayload,
        collapsedCategoryIds: collapsedCategoryIds,
      );
    }

    return _buildMaterialSidebar(
      context: context,
      ref: ref,
      selectedMatterId: selectedMatterId,
      showNotebook: showNotebook,
      selectedNotebookFolderId: selectedNotebookFolderId,
      notebookTree: notebookTree,
      showConflicts: showConflicts,
      conflictCount: conflictCount,
      noteDragPayload: noteDragPayload,
      collapsedCategoryIds: collapsedCategoryIds,
    );
  }

  Widget _buildMaterialSidebar({
    required BuildContext context,
    required WidgetRef ref,
    required String? selectedMatterId,
    required bool showNotebook,
    required String? selectedNotebookFolderId,
    required List<NotebookFolderTreeNode> notebookTree,
    required bool showConflicts,
    required int conflictCount,
    required _NoteDragPayload? noteDragPayload,
    required Set<String> collapsedCategoryIds,
  }) {
    final l10n = context.l10n;
    return Column(
      key: _kSidebarRootKey,
      children: <Widget>[
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(12),
            children: <Widget>[
              FilledButton.icon(
                onPressed: () => _createMatter(context: context, ref: ref),
                icon: const Icon(Icons.add),
                label: Text(l10n.newMatterAction),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _createCategory(context: context, ref: ref),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: Text(l10n.newCategoryAction),
              ),
              const SizedBox(height: 12),
              _SectionHeader(title: l10n.pinnedLabel),
              _MatterList(
                matters: sections.pinned,
                selectedMatterId: selectedMatterId,
                onSelect: (matter) => _selectMatter(ref, matter),
                onAction: (matter, action) => _handleMatterAction(
                  context: context,
                  ref: ref,
                  matter: matter,
                  action: action,
                ),
                noteDragPayload: noteDragPayload,
                onDropNoteToMatter: (payload, matter) =>
                    _moveDroppedNoteToMatter(
                      context: context,
                      ref: ref,
                      payload: payload,
                      matter: matter,
                    ),
              ),
              for (final section in sections.categorySections)
                _MaterialCategorySection(
                  section: section,
                  collapsed: collapsedCategoryIds.contains(section.category.id),
                  selectedMatterId: selectedMatterId,
                  noteDragPayload: noteDragPayload,
                  onToggleCollapsed: () => _toggleCategoryCollapsed(
                    ref,
                    section.category.id,
                    !collapsedCategoryIds.contains(section.category.id),
                  ),
                  onAction: (matter, action) => _handleMatterAction(
                    context: context,
                    ref: ref,
                    matter: matter,
                    action: action,
                  ),
                  onSelect: (matter) => _selectMatter(ref, matter),
                  onDropNoteToMatter: (payload, matter) =>
                      _moveDroppedNoteToMatter(
                        context: context,
                        ref: ref,
                        payload: payload,
                        matter: matter,
                      ),
                  onDropMatterToCategory: (payload) =>
                      _moveDroppedMatterToCategory(
                        context: context,
                        ref: ref,
                        payload: payload,
                        categoryId: section.category.id,
                      ),
                  onEditCategory: () => _editCategory(
                    context: context,
                    ref: ref,
                    category: section.category,
                  ),
                  onDeleteCategory: () => _deleteCategory(
                    context: context,
                    ref: ref,
                    category: section.category,
                  ),
                ),
              _MaterialUncategorizedSection(
                title: l10n.uncategorizedSectionLabel(
                  sections.uncategorized.length,
                ),
                matters: sections.uncategorized,
                selectedMatterId: selectedMatterId,
                noteDragPayload: noteDragPayload,
                onAction: (matter, action) => _handleMatterAction(
                  context: context,
                  ref: ref,
                  matter: matter,
                  action: action,
                ),
                onSelect: (matter) => _selectMatter(ref, matter),
                onDropNoteToMatter: (payload, matter) =>
                    _moveDroppedNoteToMatter(
                      context: context,
                      ref: ref,
                      payload: payload,
                      matter: matter,
                    ),
                onDropMatterToUncategorized: (payload) =>
                    _moveDroppedMatterToCategory(
                      context: context,
                      ref: ref,
                      payload: payload,
                      categoryId: null,
                    ),
              ),
              const SizedBox(height: 8),
              _SectionHeader(title: l10n.viewsSectionLabel),
              _SectionHeader(title: l10n.notebooksSectionLabel),
              _buildMaterialNotebookRootTile(
                context: context,
                ref: ref,
                showNotebook: showNotebook,
                selectedNotebookFolderId: selectedNotebookFolderId,
              ),
              for (final node in notebookTree)
                _buildMaterialNotebookFolderTile(
                  context: context,
                  ref: ref,
                  node: node,
                  depth: 1,
                  showNotebook: showNotebook,
                  selectedNotebookFolderId: selectedNotebookFolderId,
                ),
              ListTile(
                selected: showConflicts,
                leading: Badge(
                  isLabelVisible: conflictCount > 0,
                  label: Text('$conflictCount'),
                  child: const Icon(Icons.report_problem_outlined),
                ),
                title: Text(l10n.conflictsLabel),
                onTap: () {
                  ref.read(showConflictsProvider.notifier).set(true);
                  ref.read(showNotebookProvider.notifier).set(false);
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        const _SidebarSyncPanel(),
      ],
    );
  }

  Widget _buildMacOSSidebar({
    required BuildContext context,
    required WidgetRef ref,
    required String? selectedMatterId,
    required bool showNotebook,
    required String? selectedNotebookFolderId,
    required List<NotebookFolderTreeNode> notebookTree,
    required bool showConflicts,
    required int conflictCount,
    required _NoteDragPayload? noteDragPayload,
    required Set<String> collapsedCategoryIds,
  }) {
    final l10n = context.l10n;
    final sidebarItems = <SidebarItem>[];
    final selectableEntries = <_MacSidebarSelectableEntry>[];

    void addSection(String label) {
      sidebarItems.add(
        SidebarItem(
          section: true,
          label: Text(label, style: MacosTheme.of(context).typography.caption1),
        ),
      );
    }

    void addMatterItems(List<Matter> matters) {
      for (final matter in matters) {
        selectableEntries.add(
          _MacSidebarSelectableEntry(
            key: 'matter:${matter.id}',
            onSelected: () => _selectMatter(ref, matter),
          ),
        );
        sidebarItems.add(
          SidebarItem(
            leading: DragTarget<_NoteDragPayload>(
              onWillAcceptWithDetails: (details) => matter.phases.isNotEmpty,
              onAcceptWithDetails: (details) {
                unawaited(
                  _moveDroppedNoteToMatter(
                    context: context,
                    ref: ref,
                    payload: details.data,
                    matter: matter,
                  ),
                );
              },
              builder: (targetContext, candidateData, rejectedData) {
                final highlight = candidateData.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: highlight
                        ? MacosTheme.of(context).primaryColor.withAlpha(56)
                        : null,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: _MatterLeadingIcon(
                    iconKey: matter.icon,
                    isPinned: matter.isPinned,
                    isMacOS: true,
                  ),
                );
              },
            ),
            label: DragTarget<_NoteDragPayload>(
              key: ValueKey<String>('sidebar_matter_drop_target_${matter.id}'),
              onWillAcceptWithDetails: (details) => matter.phases.isNotEmpty,
              onAcceptWithDetails: (details) {
                unawaited(
                  _moveDroppedNoteToMatter(
                    context: context,
                    ref: ref,
                    payload: details.data,
                    matter: matter,
                  ),
                );
              },
              builder: (targetContext, candidateData, rejectedData) {
                final canAccept =
                    noteDragPayload != null && matter.phases.isNotEmpty;
                final highlight = candidateData.isNotEmpty;
                return LongPressDraggable<_MatterReassignPayload>(
                  data: _MatterReassignPayload(
                    matterId: matter.id,
                    categoryId: matter.categoryId,
                  ),
                  feedback: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Text(_displayMatterTitle(context, matter)),
                    ),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: highlight
                          ? MacosTheme.of(context).primaryColor.withAlpha(64)
                          : null,
                      borderRadius: BorderRadius.circular(6),
                      border: canAccept && !highlight
                          ? Border.all(
                              color: MacosTheme.of(
                                context,
                              ).primaryColor.withAlpha(30),
                            )
                          : null,
                    ),
                    child: Text(
                      _displayMatterTitle(context, matter),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _MacosMatterStatusBadge(status: matter.status),
                const SizedBox(width: 6),
                _MacosMatterActionMenu(
                  matter: matter,
                  onSelected: (action) => _handleMatterAction(
                    context: context,
                    ref: ref,
                    matter: matter,
                    action: action,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    addSection(l10n.pinnedLabel);
    addMatterItems(sections.pinned);

    for (final section in sections.categorySections) {
      final category = section.category;
      final collapsed = collapsedCategoryIds.contains(category.id);
      selectableEntries.add(
        _MacSidebarSelectableEntry(
          key: 'category:${category.id}',
          onSelected: () =>
              _toggleCategoryCollapsed(ref, category.id, !collapsed),
        ),
      );
      sidebarItems.add(
        SidebarItem(
          leading: MacosIcon(_matterIconDataForKey(category.icon), size: 14),
          label: DragTarget<_MatterReassignPayload>(
            onWillAcceptWithDetails: (details) =>
                details.data.categoryId != category.id,
            onAcceptWithDetails: (details) {
              unawaited(
                _moveDroppedMatterToCategory(
                  context: context,
                  ref: ref,
                  payload: details.data,
                  categoryId: category.id,
                ),
              );
            },
            builder: (targetContext, candidateData, rejectedData) {
              final highlight = candidateData.isNotEmpty;
              return Row(
                children: <Widget>[
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: highlight
                            ? MacosTheme.of(context).primaryColor.withAlpha(64)
                            : null,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_displayCategoryName(context, category)} (${section.matters.length})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    collapsed
                        ? CupertinoIcons.chevron_right
                        : CupertinoIcons.chevron_down,
                    size: 12,
                  ),
                ],
              );
            },
          ),
          trailing: _MacosCategoryActionMenu(
            category: category,
            onEdit: () =>
                _editCategory(context: context, ref: ref, category: category),
            onDelete: () =>
                _deleteCategory(context: context, ref: ref, category: category),
          ),
        ),
      );
      if (!collapsed) {
        addMatterItems(section.matters);
      }
    }

    addSection(l10n.uncategorizedSectionLabel(sections.uncategorized.length));
    addMatterItems(sections.uncategorized);

    addSection(l10n.viewsSectionLabel);
    addSection(l10n.notebooksSectionLabel);
    _addMacNotebookRootItem(
      context: context,
      ref: ref,
      sidebarItems: sidebarItems,
      selectableEntries: selectableEntries,
      showNotebook: showNotebook,
      selectedNotebookFolderId: selectedNotebookFolderId,
    );
    _addMacNotebookFolderItems(
      context: context,
      ref: ref,
      sidebarItems: sidebarItems,
      selectableEntries: selectableEntries,
      nodes: notebookTree,
      depth: 1,
      showNotebook: showNotebook,
      selectedNotebookFolderId: selectedNotebookFolderId,
    );

    selectableEntries.add(
      _MacSidebarSelectableEntry(
        key: 'conflicts',
        onSelected: () {
          ref.read(showConflictsProvider.notifier).set(true);
          ref.read(showNotebookProvider.notifier).set(false);
        },
      ),
    );
    sidebarItems.add(
      SidebarItem(
        leading: const MacosIcon(CupertinoIcons.exclamationmark_triangle),
        label: Text(l10n.conflictsLabel),
        trailing: conflictCount > 0
            ? _MacosCountBadge(label: '$conflictCount')
            : null,
      ),
    );

    if (selectableEntries.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedKey = showNotebook
        ? (selectedNotebookFolderId == null
              ? 'notebook:root'
              : 'notebook:$selectedNotebookFolderId')
        : showConflicts
        ? 'conflicts'
        : selectedMatterId == null
        ? selectableEntries.first.key
        : 'matter:$selectedMatterId';
    var selectedIndex = selectableEntries.indexWhere(
      (entry) => entry.key == selectedKey,
    );
    if (selectedIndex < 0) {
      selectedIndex = 0;
    }

    return Column(
      key: _kSidebarRootKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PushButton(
                controlSize: ControlSize.large,
                onPressed: () => _createMatter(context: context, ref: ref),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const MacosIcon(CupertinoIcons.add, size: 14),
                    const SizedBox(width: 6),
                    Flexible(child: Text(l10n.newMatterAction)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: () => _createCategory(context: context, ref: ref),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const MacosIcon(CupertinoIcons.folder_badge_plus, size: 14),
                    const SizedBox(width: 6),
                    Flexible(child: Text(l10n.newCategoryAction)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: DragTarget<_MatterReassignPayload>(
            onWillAcceptWithDetails: (details) =>
                details.data.categoryId != null,
            onAcceptWithDetails: (details) {
              unawaited(
                _moveDroppedMatterToCategory(
                  context: context,
                  ref: ref,
                  payload: details.data,
                  categoryId: null,
                ),
              );
            },
            builder: (targetContext, candidateData, rejectedData) {
              final highlight = candidateData.isNotEmpty;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: highlight
                      ? MacosTheme.of(context).primaryColor.withAlpha(28)
                      : null,
                ),
                child: SidebarItems(
                  scrollController: scrollController,
                  items: sidebarItems,
                  currentIndex: selectedIndex,
                  onChanged: (index) => selectableEntries[index].onSelected(),
                  itemSize: SidebarItemSize.large,
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        const _SidebarSyncPanel(),
      ],
    );
  }

  Future<void> _moveDroppedNoteToMatter({
    required BuildContext context,
    required WidgetRef ref,
    required _NoteDragPayload payload,
    required Matter matter,
  }) async {
    await _moveNoteToMatter(
      context: context,
      ref: ref,
      noteId: payload.noteId,
      targetMatter: matter,
    );
  }

  void _selectNotebookFolder(WidgetRef ref, String? folderId) {
    ref.read(showNotebookProvider.notifier).set(true);
    ref.read(showConflictsProvider.notifier).set(false);
    ref.read(selectedMatterIdProvider.notifier).set(null);
    ref.read(selectedPhaseIdProvider.notifier).set(null);
    ref.read(selectedNotebookFolderIdProvider.notifier).set(folderId);
    ref.invalidate(notebookNoteListProvider);
  }

  Future<void> _moveDroppedNoteToNotebook({
    required BuildContext context,
    required WidgetRef ref,
    required _NoteDragPayload payload,
    required String? folderId,
  }) async {
    await _moveNoteToNotebook(
      context: context,
      ref: ref,
      noteId: payload.noteId,
      folderId: folderId,
    );
  }

  Future<String?> _showNotebookFolderNameDialog({
    required BuildContext context,
    required String title,
    String initialValue = '',
  }) async {
    final l10n = context.l10n;
    var draftName = initialValue;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initialValue,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.notebookFolderNameLabel,
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) {
            draftName = value;
          },
          onFieldSubmitted: (value) {
            Navigator.of(dialogContext).pop(value.trim());
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(draftName.trim()),
            child: Text(l10n.saveAction),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) {
      return null;
    }
    return result.trim();
  }

  Future<void> _createNotebookFolder({
    required BuildContext context,
    required WidgetRef ref,
    required String? parentId,
  }) async {
    final l10n = context.l10n;
    final name = await _showNotebookFolderNameDialog(
      context: context,
      title: l10n.notebookFolderCreateDialogTitle,
    );
    if (!context.mounted || name == null) {
      return;
    }
    try {
      await ref
          .read(noteEditorControllerProvider.notifier)
          .createNotebookFolder(name: name, parentId: parentId);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMoveMessage(context, l10n.moveNoteFailed(error.toString()));
    }
  }

  Future<void> _renameNotebookFolder({
    required BuildContext context,
    required WidgetRef ref,
    required NotebookFolder folder,
  }) async {
    final l10n = context.l10n;
    final name = await _showNotebookFolderNameDialog(
      context: context,
      title: l10n.notebookFolderRenameDialogTitle,
      initialValue: folder.name,
    );
    if (!context.mounted || name == null) {
      return;
    }
    try {
      await ref
          .read(noteEditorControllerProvider.notifier)
          .renameNotebookFolder(folderId: folder.id, name: name);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMoveMessage(context, l10n.moveNoteFailed(error.toString()));
    }
  }

  Future<void> _deleteNotebookFolder({
    required BuildContext context,
    required WidgetRef ref,
    required NotebookFolder folder,
  }) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.notebookFolderDeleteDialogTitle),
        content: Text(l10n.notebookFolderDeleteConfirmation(folder.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.deleteAction),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) {
      return;
    }
    try {
      await ref
          .read(noteEditorControllerProvider.notifier)
          .deleteNotebookFolder(folder.id);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showMoveMessage(context, l10n.moveNoteFailed(error.toString()));
    }
  }

  Widget _buildMaterialNotebookRootTile({
    required BuildContext context,
    required WidgetRef ref,
    required bool showNotebook,
    required String? selectedNotebookFolderId,
  }) {
    final l10n = context.l10n;
    return DragTarget<_NoteDragPayload>(
      key: _kSidebarNotebookRootDropTargetKey,
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) async {
        await _moveDroppedNoteToNotebook(
          context: context,
          ref: ref,
          payload: details.data,
          folderId: null,
        );
      },
      builder: (targetContext, candidateData, rejectedData) {
        final highlight = candidateData.isNotEmpty;
        return Container(
          decoration: highlight
              ? BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withAlpha(110),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: ListTile(
            selected: showNotebook && selectedNotebookFolderId == null,
            title: Text(l10n.notebookLabel),
            trailing: PopupMenuButton<String>(
              icon: const Icon(CupertinoIcons.ellipsis_circle),
              onSelected: (value) async {
                if (value == 'new_folder') {
                  await _createNotebookFolder(
                    context: context,
                    ref: ref,
                    parentId: null,
                  );
                }
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'new_folder',
                  child: Text(l10n.newFolderAction),
                ),
              ],
            ),
            onTap: () {
              _selectNotebookFolder(ref, null);
            },
          ),
        );
      },
    );
  }

  Widget _buildMaterialNotebookFolderTile({
    required BuildContext context,
    required WidgetRef ref,
    required NotebookFolderTreeNode node,
    required int depth,
    required bool showNotebook,
    required String? selectedNotebookFolderId,
  }) {
    final l10n = context.l10n;
    final folder = node.folder;
    final tile = DragTarget<_NoteDragPayload>(
      key: ValueKey<String>('sidebar_notebook_folder_drop_target_${folder.id}'),
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) async {
        await _moveDroppedNoteToNotebook(
          context: context,
          ref: ref,
          payload: details.data,
          folderId: folder.id,
        );
      },
      builder: (targetContext, candidateData, rejectedData) {
        final highlight = candidateData.isNotEmpty;
        return Container(
          decoration: highlight
              ? BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withAlpha(100),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: ListTile(
            contentPadding: EdgeInsets.only(left: 12 + (depth * 16), right: 8),
            selected: showNotebook && selectedNotebookFolderId == folder.id,
            title: Text(folder.name),
            trailing: PopupMenuButton<String>(
              icon: const Icon(CupertinoIcons.ellipsis_circle),
              onSelected: (value) async {
                switch (value) {
                  case 'new_folder':
                    await _createNotebookFolder(
                      context: context,
                      ref: ref,
                      parentId: folder.id,
                    );
                    return;
                  case 'rename':
                    await _renameNotebookFolder(
                      context: context,
                      ref: ref,
                      folder: folder,
                    );
                    return;
                  case 'delete':
                    await _deleteNotebookFolder(
                      context: context,
                      ref: ref,
                      folder: folder,
                    );
                    return;
                }
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'new_folder',
                  child: Text(l10n.newFolderAction),
                ),
                PopupMenuItem<String>(
                  value: 'rename',
                  child: Text(l10n.renameFolderAction),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text(l10n.deleteFolderAction),
                ),
              ],
            ),
            onTap: () {
              _selectNotebookFolder(ref, folder.id);
            },
          ),
        );
      },
    );

    if (node.children.isEmpty) {
      return tile;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        tile,
        for (final child in node.children)
          _buildMaterialNotebookFolderTile(
            context: context,
            ref: ref,
            node: child,
            depth: depth + 1,
            showNotebook: showNotebook,
            selectedNotebookFolderId: selectedNotebookFolderId,
          ),
      ],
    );
  }

  void _addMacNotebookRootItem({
    required BuildContext context,
    required WidgetRef ref,
    required List<SidebarItem> sidebarItems,
    required List<_MacSidebarSelectableEntry> selectableEntries,
    required bool showNotebook,
    required String? selectedNotebookFolderId,
  }) {
    final l10n = context.l10n;
    selectableEntries.add(
      _MacSidebarSelectableEntry(
        key: 'notebook:root',
        onSelected: () {
          _selectNotebookFolder(ref, null);
        },
      ),
    );
    sidebarItems.add(
      SidebarItem(
        label: DragTarget<_NoteDragPayload>(
          key: _kSidebarNotebookRootDropTargetKey,
          onWillAcceptWithDetails: (details) => true,
          onAcceptWithDetails: (details) {
            unawaited(
              _moveDroppedNoteToNotebook(
                context: context,
                ref: ref,
                payload: details.data,
                folderId: null,
              ),
            );
          },
          builder: (targetContext, candidateData, rejectedData) {
            final highlight = candidateData.isNotEmpty;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: highlight
                    ? MacosTheme.of(context).primaryColor.withAlpha(64)
                    : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                l10n.notebookLabel,
                style: (showNotebook && selectedNotebookFolderId == null)
                    ? MacosTheme.of(
                        context,
                      ).typography.body.copyWith(fontWeight: FontWeight.w700)
                    : null,
              ),
            );
          },
        ),
        trailing: MacosPulldownButton(
          icon: CupertinoIcons.ellipsis_circle,
          items: <MacosPulldownMenuEntry>[
            MacosPulldownMenuItem(
              title: Text(l10n.newFolderAction),
              onTap: () {
                unawaited(
                  _createNotebookFolder(
                    context: context,
                    ref: ref,
                    parentId: null,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addMacNotebookFolderItems({
    required BuildContext context,
    required WidgetRef ref,
    required List<SidebarItem> sidebarItems,
    required List<_MacSidebarSelectableEntry> selectableEntries,
    required List<NotebookFolderTreeNode> nodes,
    required int depth,
    required bool showNotebook,
    required String? selectedNotebookFolderId,
  }) {
    final l10n = context.l10n;
    for (final node in nodes) {
      final folder = node.folder;
      selectableEntries.add(
        _MacSidebarSelectableEntry(
          key: 'notebook:${folder.id}',
          onSelected: () {
            _selectNotebookFolder(ref, folder.id);
          },
        ),
      );
      sidebarItems.add(
        SidebarItem(
          label: DragTarget<_NoteDragPayload>(
            key: ValueKey<String>(
              'sidebar_notebook_folder_drop_target_${folder.id}',
            ),
            onWillAcceptWithDetails: (details) => true,
            onAcceptWithDetails: (details) {
              unawaited(
                _moveDroppedNoteToNotebook(
                  context: context,
                  ref: ref,
                  payload: details.data,
                  folderId: folder.id,
                ),
              );
            },
            builder: (targetContext, candidateData, rejectedData) {
              final highlight = candidateData.isNotEmpty;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding: EdgeInsets.only(
                  left: depth * 12,
                  right: 4,
                  top: 2,
                  bottom: 2,
                ),
                decoration: BoxDecoration(
                  color: highlight
                      ? MacosTheme.of(context).primaryColor.withAlpha(64)
                      : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (showNotebook && selectedNotebookFolderId == folder.id)
                      ? MacosTheme.of(
                          context,
                        ).typography.body.copyWith(fontWeight: FontWeight.w700)
                      : null,
                ),
              );
            },
          ),
          trailing: MacosPulldownButton(
            icon: CupertinoIcons.ellipsis_circle,
            items: <MacosPulldownMenuEntry>[
              MacosPulldownMenuItem(
                title: Text(l10n.newFolderAction),
                onTap: () {
                  unawaited(
                    _createNotebookFolder(
                      context: context,
                      ref: ref,
                      parentId: folder.id,
                    ),
                  );
                },
              ),
              MacosPulldownMenuItem(
                title: Text(l10n.renameFolderAction),
                onTap: () {
                  unawaited(
                    _renameNotebookFolder(
                      context: context,
                      ref: ref,
                      folder: folder,
                    ),
                  );
                },
              ),
              MacosPulldownMenuItem(
                title: Text(l10n.deleteFolderAction),
                onTap: () {
                  unawaited(
                    _deleteNotebookFolder(
                      context: context,
                      ref: ref,
                      folder: folder,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
      _addMacNotebookFolderItems(
        context: context,
        ref: ref,
        sidebarItems: sidebarItems,
        selectableEntries: selectableEntries,
        nodes: node.children,
        depth: depth + 1,
        showNotebook: showNotebook,
        selectedNotebookFolderId: selectedNotebookFolderId,
      );
    }
  }

  Future<void> _moveDroppedMatterToCategory({
    required BuildContext context,
    required WidgetRef ref,
    required _MatterReassignPayload payload,
    required String? categoryId,
  }) async {
    if (payload.categoryId == categoryId) {
      return;
    }
    await ref
        .read(mattersControllerProvider.notifier)
        .setMatterCategory(payload.matterId, categoryId);
  }

  String? _defaultCategoryIdForNewMatter(WidgetRef ref) {
    final selectedMatterId = ref.read(selectedMatterIdProvider);
    if (selectedMatterId == null) {
      return null;
    }
    return ref
        .read(mattersControllerProvider.notifier)
        .findMatter(selectedMatterId)
        ?.categoryId;
  }

  Future<void> _createCategory({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final result = await showDialog<_CategoryDialogResult>(
      context: context,
      builder: (_) => const _CategoryDialog(mode: _CategoryDialogMode.create),
    );
    if (result == null || result.name.trim().isEmpty) {
      return;
    }
    await ref
        .read(mattersControllerProvider.notifier)
        .createCategory(
          name: result.name,
          color: result.color,
          icon: result.icon,
        );
  }

  Future<void> _editCategory({
    required BuildContext context,
    required WidgetRef ref,
    required Category category,
  }) async {
    final result = await showDialog<_CategoryDialogResult>(
      context: context,
      builder: (_) => _CategoryDialog(
        mode: _CategoryDialogMode.edit,
        initialName: category.name,
        initialColor: category.color,
        initialIcon: category.icon,
      ),
    );
    if (result == null || result.name.trim().isEmpty) {
      return;
    }
    await ref
        .read(mattersControllerProvider.notifier)
        .updateCategory(
          category: category,
          name: result.name,
          color: result.color,
          icon: result.icon,
        );
  }

  Future<void> _deleteCategory({
    required BuildContext context,
    required WidgetRef ref,
    required Category category,
  }) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteCategoryTitle),
        content: Text(
          l10n.deleteCategoryConfirmation(
            _displayCategoryName(dialogContext, category),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.deleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref
        .read(mattersControllerProvider.notifier)
        .deleteCategory(category.id);
  }

  void _toggleCategoryCollapsed(
    WidgetRef ref,
    String categoryId,
    bool collapsed,
  ) {
    unawaited(
      ref
          .read(settingsControllerProvider.notifier)
          .setCategoryCollapsed(categoryId, collapsed),
    );
  }

  Future<void> _createMatter({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final defaultCategoryId = _defaultCategoryIdForNewMatter(ref);
    final result = await showDialog<_MatterDialogResult>(
      context: context,
      builder: (_) => const _MatterDialog(mode: _MatterDialogMode.create),
    );

    if (result == null || result.title.trim().isEmpty) {
      return;
    }

    await ref
        .read(mattersControllerProvider.notifier)
        .createMatter(
          title: result.title,
          description: result.description,
          categoryId: defaultCategoryId,
          status: result.status,
          color: result.color,
          icon: result.icon,
          isPinned: result.isPinned,
        );
    ref.invalidate(noteListProvider);
  }

  Future<void> _handleMatterAction({
    required BuildContext context,
    required WidgetRef ref,
    required Matter matter,
    required _MatterAction action,
  }) async {
    final l10n = context.l10n;
    final controller = ref.read(mattersControllerProvider.notifier);

    switch (action) {
      case _MatterAction.edit:
        final result = await showDialog<_MatterDialogResult>(
          context: context,
          builder: (_) => _MatterDialog(
            mode: _MatterDialogMode.edit,
            initialTitle: matter.title,
            initialDescription: matter.description,
            initialStatus: matter.status,
            initialColor: matter.color,
            initialIcon: matter.icon,
            initialPinned: matter.isPinned,
          ),
        );

        if (result == null || result.title.trim().isEmpty) {
          return;
        }

        await controller.updateMatter(
          matter: matter,
          title: result.title,
          description: result.description,
          categoryId: matter.categoryId,
          status: result.status,
          color: result.color,
          icon: result.icon,
          isPinned: result.isPinned,
        );
      case _MatterAction.togglePinned:
        await controller.setMatterPinned(matter.id, !matter.isPinned);
      case _MatterAction.setActive:
        await controller.setMatterStatus(matter.id, MatterStatus.active);
      case _MatterAction.setPaused:
        await controller.setMatterStatus(matter.id, MatterStatus.paused);
      case _MatterAction.setCompleted:
        await controller.setMatterStatus(matter.id, MatterStatus.completed);
      case _MatterAction.setArchived:
        await controller.setMatterStatus(matter.id, MatterStatus.archived);
      case _MatterAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            if (_isMacOSNativeUIContext(dialogContext)) {
              return MacosSheet(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.deleteMatterTitle,
                        style: MacosTheme.of(dialogContext).typography.title2,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.deleteMatterConfirmation(matter.title),
                        style: MacosTheme.of(dialogContext).typography.body,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          PushButton(
                            controlSize: ControlSize.regular,
                            secondary: true,
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: Text(l10n.cancelAction),
                          ),
                          const SizedBox(width: 8),
                          PushButton(
                            controlSize: ControlSize.regular,
                            color: MacosColors.systemRedColor,
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: Text(l10n.deleteAction),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }

            return AlertDialog(
              title: Text(l10n.deleteMatterTitle),
              content: Text(l10n.deleteMatterConfirmation(matter.title)),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.cancelAction),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.deleteAction),
                ),
              ],
            );
          },
        );

        if (confirmed == true) {
          await controller.deleteMatter(matter.id);
          ref.invalidate(noteListProvider);
        }
    }
  }

  void _selectMatter(WidgetRef ref, Matter matter) {
    ref.read(showNotebookProvider.notifier).set(false);
    ref.read(showConflictsProvider.notifier).set(false);
    ref.read(selectedMatterIdProvider.notifier).set(matter.id);
    ref.read(selectedNotebookFolderIdProvider.notifier).set(null);
    ref
        .read(selectedPhaseIdProvider.notifier)
        .set(
          matter.currentPhaseId ??
              (matter.phases.isEmpty ? null : matter.phases.first.id),
        );
    ref.invalidate(noteListProvider);
  }
}

class _MacSidebarSelectableEntry {
  const _MacSidebarSelectableEntry({
    required this.key,
    required this.onSelected,
  });

  final String key;
  final VoidCallback onSelected;
}

class _SidebarSyncPanel extends ConsumerWidget {
  const _SidebarSyncPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final settings = ref.watch(settingsControllerProvider).asData?.value;
    final syncState = ref.watch(syncControllerProvider);
    final syncData = syncState.asData?.value;
    final enableAdvancedSyncRecovery = _kEnableAdvancedSyncRecovery;
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

    Future<void> handleAdvancedAction(_SyncAdvancedAction action) async {
      switch (action) {
        case _SyncAdvancedAction.recoverLocalWins:
          await runRecoverLocalWins();
          return;
        case _SyncAdvancedAction.recoverRemoteWins:
          await runRecoverRemoteWins();
          return;
        case _SyncAdvancedAction.armForceDeletion:
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
                    key: _kSidebarSyncNowButtonKey,
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
                    key: _kSidebarSyncAdvancedButtonKey,
                    icon: CupertinoIcons.ellipsis_circle,
                    items: <MacosPulldownMenuEntry>[
                      MacosPulldownMenuItem(
                        title: Text(l10n.syncRecoverLocalWinsAction),
                        onTap: () {
                          unawaited(
                            handleAdvancedAction(
                              _SyncAdvancedAction.recoverLocalWins,
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
                              _SyncAdvancedAction.recoverRemoteWins,
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
                              _SyncAdvancedAction.armForceDeletion,
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
              key: _kSidebarSyncStatusKey,
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
                  key: _kSidebarSyncNowButtonKey,
                  onPressed: () async {
                    await runSyncNow();
                  },
                  icon: const Icon(Icons.sync),
                  label: Text(l10n.syncNowAction),
                ),
              ),
              if (enableAdvancedSyncRecovery)
                PopupMenuButton<_SyncAdvancedAction>(
                  key: _kSidebarSyncAdvancedButtonKey,
                  tooltip: l10n.syncAdvancedActionsTooltip,
                  onSelected: (action) async {
                    await handleAdvancedAction(action);
                  },
                  itemBuilder: (_) => <PopupMenuEntry<_SyncAdvancedAction>>[
                    PopupMenuItem<_SyncAdvancedAction>(
                      value: _SyncAdvancedAction.recoverLocalWins,
                      child: Text(l10n.syncRecoverLocalWinsAction),
                    ),
                    PopupMenuItem<_SyncAdvancedAction>(
                      value: _SyncAdvancedAction.recoverRemoteWins,
                      enabled: remoteRecoveryEnabled,
                      child: Text(l10n.syncRecoverRemoteWinsAction),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<_SyncAdvancedAction>(
                      value: _SyncAdvancedAction.armForceDeletion,
                      child: Text(l10n.syncForceDeletionNextRunAction),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            status,
            key: _kSidebarSyncStatusKey,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MacosMatterStatusBadge extends StatelessWidget {
  const _MacosMatterStatusBadge({required this.status});

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

class _MacosCountBadge extends StatelessWidget {
  const _MacosCountBadge({required this.label});

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

class _MacosMatterActionMenu extends StatelessWidget {
  const _MacosMatterActionMenu({
    required this.matter,
    required this.onSelected,
  });

  final Matter matter;
  final ValueChanged<_MatterAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MacosPulldownButton(
      icon: CupertinoIcons.ellipsis_circle,
      items: <MacosPulldownMenuEntry>[
        MacosPulldownMenuItem(
          title: Text(l10n.editAction),
          onTap: () {
            onSelected(_MatterAction.edit);
          },
        ),
        MacosPulldownMenuItem(
          title: Text(matter.isPinned ? l10n.unpinAction : l10n.pinAction),
          onTap: () {
            onSelected(_MatterAction.togglePinned);
          },
        ),
        const MacosPulldownMenuDivider(),
        MacosPulldownMenuItem(
          title: Text(l10n.setActiveAction),
          onTap: () {
            onSelected(_MatterAction.setActive);
          },
        ),
        MacosPulldownMenuItem(
          title: Text(l10n.setPausedAction),
          onTap: () {
            onSelected(_MatterAction.setPaused);
          },
        ),
        MacosPulldownMenuItem(
          title: Text(l10n.setCompletedAction),
          onTap: () {
            onSelected(_MatterAction.setCompleted);
          },
        ),
        MacosPulldownMenuItem(
          title: Text(l10n.setArchivedAction),
          onTap: () {
            onSelected(_MatterAction.setArchived);
          },
        ),
        const MacosPulldownMenuDivider(),
        MacosPulldownMenuItem(
          title: Text(l10n.deleteAction),
          onTap: () {
            onSelected(_MatterAction.delete);
          },
        ),
      ],
    );
  }
}

class _MacosCategoryActionMenu extends StatelessWidget {
  const _MacosCategoryActionMenu({
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  final Category category;
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

class _SidebarMessageView extends StatelessWidget {
  const _SidebarMessageView({
    required this.scrollController,
    required this.child,
  });

  final ScrollController? scrollController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: <Widget>[SizedBox(height: 220, child: child)],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Text(title, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

enum _CategoryAction { edit, delete }

class _MaterialCategorySection extends StatelessWidget {
  const _MaterialCategorySection({
    required this.section,
    required this.collapsed,
    required this.selectedMatterId,
    required this.noteDragPayload,
    required this.onToggleCollapsed,
    required this.onSelect,
    required this.onAction,
    required this.onDropNoteToMatter,
    required this.onDropMatterToCategory,
    required this.onEditCategory,
    required this.onDeleteCategory,
  });

  final MatterCategorySection section;
  final bool collapsed;
  final String? selectedMatterId;
  final _NoteDragPayload? noteDragPayload;
  final VoidCallback onToggleCollapsed;
  final void Function(Matter matter) onSelect;
  final Future<void> Function(Matter matter, _MatterAction action) onAction;
  final Future<void> Function(_NoteDragPayload payload, Matter matter)
  onDropNoteToMatter;
  final Future<void> Function(_MatterReassignPayload payload)
  onDropMatterToCategory;
  final Future<void> Function() onEditCategory;
  final Future<void> Function() onDeleteCategory;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_MatterReassignPayload>(
      onWillAcceptWithDetails: (details) =>
          details.data.categoryId != section.category.id,
      onAcceptWithDetails: (details) {
        unawaited(onDropMatterToCategory(details.data));
      },
      builder: (targetContext, candidateData, rejectedData) {
        final highlight = candidateData.isNotEmpty;
        return Container(
          decoration: highlight
              ? BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withAlpha(72),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Column(
            children: <Widget>[
              _MaterialCategoryHeader(
                section: section,
                collapsed: collapsed,
                onToggleCollapsed: onToggleCollapsed,
                onEdit: onEditCategory,
                onDelete: onDeleteCategory,
              ),
              if (!collapsed)
                _MatterList(
                  matters: section.matters,
                  selectedMatterId: selectedMatterId,
                  onSelect: onSelect,
                  onAction: onAction,
                  noteDragPayload: noteDragPayload,
                  onDropNoteToMatter: onDropNoteToMatter,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MaterialUncategorizedSection extends StatelessWidget {
  const _MaterialUncategorizedSection({
    required this.title,
    required this.matters,
    required this.selectedMatterId,
    required this.noteDragPayload,
    required this.onSelect,
    required this.onAction,
    required this.onDropNoteToMatter,
    required this.onDropMatterToUncategorized,
  });

  final String title;
  final List<Matter> matters;
  final String? selectedMatterId;
  final _NoteDragPayload? noteDragPayload;
  final void Function(Matter matter) onSelect;
  final Future<void> Function(Matter matter, _MatterAction action) onAction;
  final Future<void> Function(_NoteDragPayload payload, Matter matter)
  onDropNoteToMatter;
  final Future<void> Function(_MatterReassignPayload payload)
  onDropMatterToUncategorized;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_MatterReassignPayload>(
      onWillAcceptWithDetails: (details) => details.data.categoryId != null,
      onAcceptWithDetails: (details) {
        unawaited(onDropMatterToUncategorized(details.data));
      },
      builder: (targetContext, candidateData, rejectedData) {
        final highlight = candidateData.isNotEmpty;
        return Container(
          decoration: highlight
              ? BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withAlpha(72),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Column(
            children: <Widget>[
              _SectionHeader(title: title),
              _MatterList(
                matters: matters,
                selectedMatterId: selectedMatterId,
                onSelect: onSelect,
                onAction: onAction,
                noteDragPayload: noteDragPayload,
                onDropNoteToMatter: onDropNoteToMatter,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MaterialCategoryHeader extends StatelessWidget {
  const _MaterialCategoryHeader({
    required this.section,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onEdit,
    required this.onDelete,
  });

  final MatterCategorySection section;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final iconData = _matterIconDataForKey(section.category.icon);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 8, right: 0),
      onTap: onToggleCollapsed,
      leading: Icon(iconData, color: _colorFromHex(section.category.color)),
      title: Text(
        '${_displayCategoryName(context, section.category)} (${section.matters.length})',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            collapsed ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_down,
            size: 18,
          ),
          PopupMenuButton<_CategoryAction>(
            onSelected: (value) async {
              switch (value) {
                case _CategoryAction.edit:
                  await onEdit();
                case _CategoryAction.delete:
                  await onDelete();
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<_CategoryAction>>[
              PopupMenuItem<_CategoryAction>(
                value: _CategoryAction.edit,
                child: Text(context.l10n.editAction),
              ),
              PopupMenuItem<_CategoryAction>(
                value: _CategoryAction.delete,
                child: Text(context.l10n.deleteAction),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _MatterAction {
  edit,
  togglePinned,
  setActive,
  setPaused,
  setCompleted,
  setArchived,
  delete,
}

class _MatterList extends StatelessWidget {
  const _MatterList({
    required this.matters,
    required this.selectedMatterId,
    required this.onSelect,
    required this.onAction,
    this.noteDragPayload,
    this.onDropNoteToMatter,
  });

  final List<Matter> matters;
  final String? selectedMatterId;
  final void Function(Matter matter) onSelect;
  final Future<void> Function(Matter matter, _MatterAction action) onAction;
  final _NoteDragPayload? noteDragPayload;
  final Future<void> Function(_NoteDragPayload payload, Matter matter)?
  onDropNoteToMatter;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (matters.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: matters.map((matter) {
        final tile = ListTile(
          dense: true,
          selected: selectedMatterId == matter.id,
          leading: _MatterLeadingIcon(
            iconKey: matter.icon,
            isPinned: matter.isPinned,
            isMacOS: false,
          ),
          title: Row(
            children: <Widget>[
              Expanded(child: Text(matter.title)),
              const SizedBox(width: 4),
              _MatterStatusChip(status: matter.status),
            ],
          ),
          subtitle: matter.description.isEmpty
              ? null
              : Text(
                  matter.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: PopupMenuButton<_MatterAction>(
            icon: const Icon(CupertinoIcons.ellipsis_circle),
            onSelected: (value) async {
              await onAction(matter, value);
            },
            itemBuilder: (_) => <PopupMenuEntry<_MatterAction>>[
              PopupMenuItem<_MatterAction>(
                value: _MatterAction.edit,
                child: Text(l10n.editAction),
              ),
              PopupMenuItem<_MatterAction>(
                value: _MatterAction.togglePinned,
                child: Text(
                  matter.isPinned ? l10n.unpinAction : l10n.pinAction,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<_MatterAction>(
                value: _MatterAction.setActive,
                child: Text(l10n.setActiveAction),
              ),
              PopupMenuItem<_MatterAction>(
                value: _MatterAction.setPaused,
                child: Text(l10n.setPausedAction),
              ),
              PopupMenuItem<_MatterAction>(
                value: _MatterAction.setCompleted,
                child: Text(l10n.setCompletedAction),
              ),
              PopupMenuItem<_MatterAction>(
                value: _MatterAction.setArchived,
                child: Text(l10n.setArchivedAction),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<_MatterAction>(
                value: _MatterAction.delete,
                child: Text(l10n.deleteAction),
              ),
            ],
          ),
          onTap: () => onSelect(matter),
        );

        Widget content = tile;
        if (onDropNoteToMatter != null) {
          content = DragTarget<_NoteDragPayload>(
            key: ValueKey<String>('sidebar_matter_drop_target_${matter.id}'),
            onWillAcceptWithDetails: (details) => matter.phases.isNotEmpty,
            onAcceptWithDetails: (details) {
              unawaited(onDropNoteToMatter!(details.data, matter));
            },
            builder: (targetContext, candidateData, rejectedData) {
              final canAccept =
                  noteDragPayload != null && matter.phases.isNotEmpty;
              final highlight = candidateData.isNotEmpty;
              return Container(
                decoration: highlight
                    ? BoxDecoration(
                        color: Theme.of(
                          targetContext,
                        ).colorScheme.primaryContainer.withAlpha(110),
                        borderRadius: BorderRadius.circular(8),
                      )
                    : canAccept
                    ? BoxDecoration(
                        border: Border.all(
                          color: Theme.of(
                            targetContext,
                          ).colorScheme.primary.withAlpha(40),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: tile,
              );
            },
          );
        }

        return LongPressDraggable<_MatterReassignPayload>(
          data: _MatterReassignPayload(
            matterId: matter.id,
            categoryId: matter.categoryId,
          ),
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Text(_displayMatterTitle(context, matter)),
            ),
          ),
          child: content,
        );
      }).toList(),
    );
  }
}

class _MatterStatusChip extends StatelessWidget {
  const _MatterStatusChip({required this.status});

  final MatterStatus status;

  @override
  Widget build(BuildContext context) {
    final label = _matterStatusBadgeLabel(context.l10n, status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _MatterLeadingIcon extends StatelessWidget {
  const _MatterLeadingIcon({
    required this.iconKey,
    required this.isPinned,
    required this.isMacOS,
  });

  final String iconKey;
  final bool isPinned;
  final bool isMacOS;

  @override
  Widget build(BuildContext context) {
    final iconData = _matterIconDataForKey(iconKey);
    final iconWidget = isMacOS
        ? MacosIcon(iconData, size: 14)
        : Icon(iconData, size: 18);
    if (!isPinned) {
      return iconWidget;
    }

    final pin = isMacOS
        ? const MacosIcon(CupertinoIcons.pin_fill, size: 8)
        : const Icon(Icons.push_pin, size: 10);

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        iconWidget,
        Positioned(right: -5, top: -4, child: pin),
      ],
    );
  }
}

class SearchListItem {
  const SearchListItem({
    required this.noteId,
    required this.title,
    required this.contextLine,
    required this.snippet,
  });

  final String noteId;
  final String title;
  final String contextLine;
  final String snippet;
}

const Key _kSidebarRootKey = Key('sidebar_root');
const Key _kSidebarNotebookRootDropTargetKey = Key(
  'sidebar_notebook_root_drop_target',
);
const Key _kMacosMatterNewNoteButtonKey = Key('macos_matter_new_note_button');
const Key _kMatterTopPhaseMenuButtonKey = Key('matter_top_phase_menu_button');
const Key _kMatterTopTimelineButtonKey = Key('matter_top_timeline_button');
const Key _kMatterTopGraphButtonKey = Key('matter_top_graph_button');
const Key _kMacosNotebookNewNoteButtonKey = Key(
  'macos_notebook_new_note_button',
);
const Key _kMacosConflictsRefreshButtonKey = Key('macos_conflicts_refresh');
const Key _kNoteHeaderTitleDisplayKey = Key('note_header_title_display');
const Key _kNoteHeaderTitleEditFieldKey = Key('note_header_title_edit');
const Key _kMacosNoteEditorTagsFieldKey = Key('macos_note_editor_tags');
const Key _kMacosNoteEditorContentFieldKey = Key('macos_note_editor_content');
const Key _kMacosNoteEditorSaveButtonKey = Key('macos_note_editor_save');
const Key _kNoteEditorMarkdownToolbarKey = Key('note_editor_markdown_toolbar');
const Key _kNoteDialogMarkdownToolbarKey = Key('note_dialog_markdown_toolbar');
const Key _kNoteEditorModeToggleKey = Key('note_editor_mode_toggle');
const Key _kNoteEditorUtilityTagsKey = Key('note_editor_utility_tags');
const Key _kNoteEditorUtilityAttachmentsKey = Key(
  'note_editor_utility_attachments',
);
const Key _kNoteEditorUtilityLinkedKey = Key('note_editor_utility_linked');
const Key _kSidebarSyncNowButtonKey = Key('sidebar_sync_now_button');
const Key _kSidebarSyncStatusKey = Key('sidebar_sync_status');
const Key _kSidebarSyncAdvancedButtonKey = Key('sidebar_sync_advanced_button');
const Key _kSettingsDialogNavPaneKey = Key('settings_dialog_nav_pane');
const Key _kSettingsDialogContentPaneKey = Key('settings_dialog_content_pane');
const Key _kMatterColorCustomButtonKey = Key('matter_color_custom_button');
const Key _kMatterColorPreviewFieldKey = Key('matter_color_preview_field');
const bool _kEnableAdvancedSyncRecovery = true;

const List<String> _kMatterPresetColors = <String>[
  '#EF4444',
  '#F97316',
  '#F59E0B',
  '#EAB308',
  '#84CC16',
  '#22C55E',
  '#10B981',
  '#14B8A6',
  '#06B6D4',
  '#3B82F6',
  '#6366F1',
  '#8B5CF6',
  '#A855F7',
  '#EC4899',
  '#64748B',
];

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

enum _SyncAdvancedAction {
  recoverLocalWins,
  recoverRemoteWins,
  armForceDeletion,
}

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

class _MacosCompactIconButton extends StatelessWidget {
  const _MacosCompactIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return MacosTooltip(
      message: tooltip,
      child: MacosIconButton(
        semanticLabel: tooltip,
        icon: icon,
        backgroundColor: MacosColors.transparent,
        boxConstraints: const BoxConstraints(
          minHeight: 28,
          minWidth: 28,
          maxHeight: 28,
          maxWidth: 28,
        ),
        padding: const EdgeInsets.all(4),
        onPressed: onPressed,
      ),
    );
  }
}

class _MacosSelectableRow extends StatelessWidget {
  const _MacosSelectableRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    required this.onTap,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typography = MacosTheme.of(context).typography;
    final selectedColor = MacosTheme.of(context).primaryColor.withAlpha(26);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? selectedColor : null,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading!,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DefaultTextStyle(
                    style: typography.body.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    child: title,
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style: typography.caption1,
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _MatterTopControls extends ConsumerWidget {
  const _MatterTopControls({required this.matter});

  final Matter matter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
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
        builder: (_) => _ManagePhasesDialog(matterId: matter.id),
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
                key: _kMatterTopPhaseMenuButtonKey,
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
          key: _kMatterTopPhaseMenuButtonKey,
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
            buttonKey: _kMacosMatterNewNoteButtonKey,
            tooltip: l10n.newNoteAction,
            icon: CupertinoIcons.add,
            label: l10n.newNoteAction,
            onPressed: () {
              unawaited(createNewNote());
            },
          )
        else
          materialLabeledAction(
            buttonKey: _kMacosMatterNewNoteButtonKey,
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
            buttonKey: _kMatterTopTimelineButtonKey,
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
            buttonKey: _kMatterTopTimelineButtonKey,
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
            buttonKey: _kMatterTopGraphButtonKey,
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
            buttonKey: _kMatterTopGraphButtonKey,
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

class _NotebookTopControls extends ConsumerWidget {
  const _NotebookTopControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);

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
              key: _kMacosNotebookNewNoteButtonKey,
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
          key: _kMacosNotebookNewNoteButtonKey,
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

class _MainWorkspace extends ConsumerWidget {
  const _MainWorkspace({
    required this.searchHits,
    required this.searchQuery,
    required this.showSearchResults,
  });

  final List<SearchListItem> searchHits;
  final String searchQuery;
  final bool showSearchResults;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final showConflicts = ref.watch(showConflictsProvider);
    if (showConflicts) {
      return const _ConflictWorkspace();
    }

    if (_hasSearchText(searchQuery) && showSearchResults) {
      return _SearchResultsView(results: searchHits);
    }

    final showNotebook = ref.watch(showNotebookProvider);
    if (showNotebook) {
      return const _NotebookWorkspace();
    }

    final sections = ref.watch(mattersControllerProvider).asData?.value;
    final selectedMatterId = ref.watch(selectedMatterIdProvider);
    if (sections == null || selectedMatterId == null) {
      return Center(child: Text(l10n.selectMatterNotebookOrConflictsPrompt));
    }

    final selected = _findMatterById(sections, selectedMatterId);

    if (selected == null) {
      return Center(child: Text(l10n.matterNoLongerExistsMessage));
    }

    return _MatterWorkspace(matter: selected);
  }
}

class _ConflictWorkspace extends ConsumerWidget {
  const _ConflictWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final conflictsState = ref.watch(conflictsControllerProvider);
    final selected = ref.watch(selectedConflictProvider);
    final selectedContent = ref.watch(selectedConflictContentProvider);

    return conflictsState.when(
      loading: () => Center(child: _adaptiveLoadingIndicator(context)),
      error: (error, stackTrace) =>
          Center(child: Text(l10n.conflictLoadFailed(error.toString()))),
      data: (conflicts) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  Text(
                    l10n.conflictsCountTitle(conflicts.length),
                    style: isMacOSNativeUI
                        ? _macosSectionTitleStyle(context)
                        : Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(width: 12),
                  isMacOSNativeUI
                      ? PushButton(
                          key: _kMacosConflictsRefreshButtonKey,
                          controlSize: ControlSize.regular,
                          secondary: true,
                          onPressed: () async {
                            await ref
                                .read(conflictsControllerProvider.notifier)
                                .reload();
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const MacosIcon(
                                CupertinoIcons.refresh_thick,
                                size: 13,
                              ),
                              const SizedBox(width: 6),
                              Text(l10n.refreshAction),
                            ],
                          ),
                        )
                      : FilledButton.tonalIcon(
                          onPressed: () async {
                            await ref
                                .read(conflictsControllerProvider.notifier)
                                .reload();
                          },
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n.refreshAction),
                        ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 380,
                    child: conflicts.isEmpty
                        ? Center(child: Text(l10n.noConflictsDetectedMessage))
                        : ListView.builder(
                            itemCount: conflicts.length,
                            itemBuilder: (_, index) {
                              final conflict = conflicts[index];
                              final isSelected =
                                  selected?.conflictPath ==
                                  conflict.conflictPath;
                              if (isMacOSNativeUI) {
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    2,
                                    10,
                                    2,
                                  ),
                                  child: _MacosSelectableRow(
                                    selected: isSelected,
                                    title: Row(
                                      children: <Widget>[
                                        Expanded(child: Text(conflict.title)),
                                        _ConflictTypeChip(type: conflict.type),
                                      ],
                                    ),
                                    subtitle: Text(
                                      '${conflict.originalPath}\n${DateFormat('yyyy-MM-dd HH:mm').format(conflict.detectedAt.toLocal())}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () {
                                      ref
                                          .read(
                                            conflictsControllerProvider
                                                .notifier,
                                          )
                                          .selectConflict(
                                            conflict.conflictPath,
                                          );
                                    },
                                  ),
                                );
                              }

                              return ListTile(
                                selected: isSelected,
                                title: Row(
                                  children: <Widget>[
                                    Expanded(child: Text(conflict.title)),
                                    _ConflictTypeChip(type: conflict.type),
                                  ],
                                ),
                                subtitle: Text(
                                  '${conflict.originalPath}\n${DateFormat('yyyy-MM-dd HH:mm').format(conflict.detectedAt.toLocal())}',
                                ),
                                isThreeLine: true,
                                onTap: () {
                                  ref
                                      .read(
                                        conflictsControllerProvider.notifier,
                                      )
                                      .selectConflict(conflict.conflictPath);
                                },
                              );
                            },
                          ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: selected == null
                        ? Center(child: Text(l10n.selectConflictToReviewPrompt))
                        : Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  selected.title,
                                  style: isMacOSNativeUI
                                      ? MacosTheme.of(context).typography.title3
                                      : Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.conflictTypeRow(
                                    _conflictTypeLabel(selected.type, l10n),
                                  ),
                                ),
                                Text(
                                  l10n.conflictFileRow(selected.conflictPath),
                                ),
                                Text(
                                  l10n.conflictOriginalRow(
                                    selected.originalPath,
                                  ),
                                ),
                                Text(
                                  l10n.conflictLocalRow(selected.localDevice),
                                ),
                                Text(
                                  l10n.conflictRemoteRow(selected.remoteDevice),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: <Widget>[
                                    isMacOSNativeUI
                                        ? PushButton(
                                            controlSize: ControlSize.regular,
                                            secondary: true,
                                            onPressed:
                                                selected.originalNoteId == null
                                                ? null
                                                : () async {
                                                    await ref
                                                        .read(
                                                          noteEditorControllerProvider
                                                              .notifier,
                                                        )
                                                        .openNoteInWorkspace(
                                                          selected
                                                              .originalNoteId!,
                                                        );
                                                    ref
                                                        .read(
                                                          showConflictsProvider
                                                              .notifier,
                                                        )
                                                        .set(false);
                                                  },
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: <Widget>[
                                                const MacosIcon(
                                                  CupertinoIcons
                                                      .arrow_up_right_square,
                                                  size: 13,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(l10n.openMainNoteAction),
                                              ],
                                            ),
                                          )
                                        : OutlinedButton.icon(
                                            onPressed:
                                                selected.originalNoteId == null
                                                ? null
                                                : () async {
                                                    await ref
                                                        .read(
                                                          noteEditorControllerProvider
                                                              .notifier,
                                                        )
                                                        .openNoteInWorkspace(
                                                          selected
                                                              .originalNoteId!,
                                                        );
                                                    ref
                                                        .read(
                                                          showConflictsProvider
                                                              .notifier,
                                                        )
                                                        .set(false);
                                                  },
                                            icon: const Icon(Icons.open_in_new),
                                            label: Text(
                                              l10n.openMainNoteAction,
                                            ),
                                          ),
                                    const SizedBox(width: 8),
                                    isMacOSNativeUI
                                        ? PushButton(
                                            controlSize: ControlSize.regular,
                                            onPressed: () async {
                                              await ref
                                                  .read(
                                                    conflictsControllerProvider
                                                        .notifier,
                                                  )
                                                  .resolveConflict(
                                                    selected.conflictPath,
                                                  );
                                              ref
                                                  .read(
                                                    conflictsControllerProvider
                                                        .notifier,
                                                  )
                                                  .selectConflict(null);
                                            },
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: <Widget>[
                                                const MacosIcon(
                                                  CupertinoIcons.check_mark,
                                                  size: 13,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(l10n.markResolvedAction),
                                              ],
                                            ),
                                          )
                                        : FilledButton.icon(
                                            onPressed: () async {
                                              await ref
                                                  .read(
                                                    conflictsControllerProvider
                                                        .notifier,
                                                  )
                                                  .resolveConflict(
                                                    selected.conflictPath,
                                                  );
                                              ref
                                                  .read(
                                                    conflictsControllerProvider
                                                        .notifier,
                                                  )
                                                  .selectConflict(null);
                                            },
                                            icon: const Icon(Icons.check),
                                            label: Text(
                                              l10n.markResolvedAction,
                                            ),
                                          ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: selectedContent.when(
                                    loading: () => Center(
                                      child: _adaptiveLoadingIndicator(context),
                                    ),
                                    error: (error, stackTrace) => Text(
                                      l10n.failedToLoadConflict(
                                        error.toString(),
                                      ),
                                    ),
                                    data: (content) {
                                      if (content == null ||
                                          content.trim().isEmpty) {
                                        if (selected.type ==
                                            SyncConflictType.unknown) {
                                          return Text(
                                            l10n.binaryConflictNotPreviewable,
                                          );
                                        }
                                        return Text(l10n.conflictContentEmpty);
                                      }
                                      return Container(
                                        decoration: isMacOSNativeUI
                                            ? _macosPanelDecoration(context)
                                            : BoxDecoration(
                                                border: Border.all(
                                                  color: Theme.of(
                                                    context,
                                                  ).dividerColor,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                        padding: const EdgeInsets.all(8),
                                        child: selected.isNote
                                            ? ChronicleMarkdown(data: content)
                                            : SingleChildScrollView(
                                                child: SelectableText(content),
                                              ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MatterWorkspace extends ConsumerWidget {
  const _MatterWorkspace({required this.matter});

  final Matter matter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(matterViewModeProvider);
    final currentNote = ref.watch(noteEditorControllerProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: _NoteTitleHeader(
            note: currentNote,
            canEdit:
                currentNote != null &&
                currentNote.matterId == matter.id &&
                currentNote.phaseId != null,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (viewMode) {
            MatterViewMode.phase => const _MatterNotesWorkspace(),
            MatterViewMode.timeline => const _MatterTimelineWorkspace(),
            MatterViewMode.graph => const _MatterGraphWorkspace(),
          },
        ),
      ],
    );
  }
}

class _NoteTitleHeader extends ConsumerStatefulWidget {
  const _NoteTitleHeader({required this.note, required this.canEdit});

  final Note? note;
  final bool canEdit;

  @override
  ConsumerState<_NoteTitleHeader> createState() => _NoteTitleHeaderState();
}

class _NoteTitleHeaderState extends ConsumerState<_NoteTitleHeader> {
  final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.note?.title ?? '';
    _titleFocusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _NoteTitleHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final noteChanged =
        oldWidget.note?.id != widget.note?.id ||
        oldWidget.note?.title != widget.note?.title;
    if (noteChanged && !_editing) {
      _titleController.text = widget.note?.title ?? '';
    }
  }

  @override
  void dispose() {
    _titleFocusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _titleController.dispose();
    super.dispose();
  }

  bool get _canEdit => widget.note != null && widget.canEdit;

  Future<void> _startEditing() async {
    if (!_canEdit) {
      return;
    }
    setState(() {
      _editing = true;
      _titleController.text = widget.note?.title ?? '';
    });
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    _titleFocusNode.requestFocus();
    _titleController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _titleController.text.length,
    );
  }

  Future<void> _commitEditing() async {
    if (!_editing) {
      return;
    }
    final note = widget.note;
    if (note != null && widget.canEdit) {
      final nextTitle = _titleController.text.trim();
      if (nextTitle != note.title) {
        await ref
            .read(noteEditorControllerProvider.notifier)
            .updateCurrent(title: nextTitle);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _editing = false;
    });
  }

  void _handleFocusChange() {
    if (!_titleFocusNode.hasFocus && _editing) {
      unawaited(_commitEditing());
    }
  }

  String _displayTitle(AppLocalizations l10n) {
    final note = widget.note;
    if (note == null) {
      return l10n.selectNoteToEditPrompt;
    }
    final trimmed = note.title.trim();
    return trimmed.isEmpty ? l10n.untitledLabel : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final titleStyle = isMacOSNativeUI
        ? MacosTheme.of(context).typography.largeTitle
        : Theme.of(context).textTheme.headlineMedium;

    if (_editing && _canEdit) {
      final field = isMacOSNativeUI
          ? MacosTextField(
              key: _kNoteHeaderTitleEditFieldKey,
              focusNode: _titleFocusNode,
              controller: _titleController,
              placeholder: l10n.titleLabel,
              onEditingComplete: () {
                unawaited(_commitEditing());
              },
              onSubmitted: (_) {
                unawaited(_commitEditing());
              },
            )
          : TextField(
              key: _kNoteHeaderTitleEditFieldKey,
              focusNode: _titleFocusNode,
              controller: _titleController,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.titleLabel,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                unawaited(_commitEditing());
              },
              onEditingComplete: () {
                unawaited(_commitEditing());
              },
            );
      return TapRegion(
        onTapOutside: (_) {
          unawaited(_commitEditing());
        },
        child: field,
      );
    }

    return MouseRegion(
      cursor: _canEdit ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        key: _kNoteHeaderTitleDisplayKey,
        onTap: _canEdit
            ? () {
                unawaited(_startEditing());
              }
            : null,
        child: Text(
          _displayTitle(l10n),
          style: titleStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _MatterNotesWorkspace extends ConsumerWidget {
  const _MatterNotesWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notes = ref.watch(noteListProvider);

    return Row(
      children: <Widget>[
        SizedBox(
          width: 380,
          child: notes.when(
            loading: () => Center(child: _adaptiveLoadingIndicator(context)),
            error: (error, _) => Center(child: Text('$error')),
            data: (items) => _NoteList(
              notes: items,
              onEdit: (note) async {
                final result = await showDialog<_NoteDialogResult>(
                  context: context,
                  builder: (_) => _NoteDialog(
                    mode: _NoteDialogMode.edit,
                    initialTitle: note.title,
                    initialContent: note.content,
                    initialTags: note.tags,
                    initialPinned: note.isPinned,
                  ),
                );

                if (result == null || result.title.trim().isEmpty) {
                  return;
                }

                await ref
                    .read(noteEditorControllerProvider.notifier)
                    .updateNoteById(
                      noteId: note.id,
                      title: result.title,
                      content: result.content,
                      tags: result.tags,
                      isPinned: result.isPinned,
                    );
              },
              onTogglePinned: (note) async {
                await ref
                    .read(noteEditorControllerProvider.notifier)
                    .updateNoteById(noteId: note.id, isPinned: !note.isPinned);
              },
              onDelete: (note) async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(l10n.deleteNoteTitle),
                    content: Text(l10n.deleteNoteConfirmation(note.title)),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(l10n.cancelAction),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(l10n.deleteAction),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  await ref
                      .read(noteEditorControllerProvider.notifier)
                      .deleteNote(note.id);
                }
              },
              onLink: (note) {
                return _showLinkNoteDialog(
                  context: context,
                  ref: ref,
                  sourceNote: note,
                );
              },
              onMoveToMatter: (note) async {
                final targetMatter = await _showMoveToMatterDialog(
                  context: context,
                  ref: ref,
                  note: note,
                );
                if (!context.mounted || targetMatter == null) {
                  return;
                }
                await _moveNoteToMatter(
                  context: context,
                  ref: ref,
                  noteId: note.id,
                  targetMatter: targetMatter,
                );
              },
              onMoveToPhase: (note) async {
                final matterId = note.matterId;
                if (matterId == null) {
                  return;
                }
                Matter? sourceMatter = ref
                    .read(mattersControllerProvider.notifier)
                    .findMatter(matterId);
                if (sourceMatter == null) {
                  final matters = await _allMattersForMove(ref);
                  if (!context.mounted) {
                    return;
                  }
                  for (final candidate in matters) {
                    if (candidate.id == matterId) {
                      sourceMatter = candidate;
                      break;
                    }
                  }
                }
                if (sourceMatter == null) {
                  _showMoveMessage(
                    context,
                    context.l10n.moveSourceMatterMissingMessage,
                  );
                  return;
                }
                final phase = await _showMoveToPhaseDialog(
                  context: context,
                  matter: sourceMatter,
                  note: note,
                );
                if (!context.mounted || phase == null) {
                  return;
                }
                await _moveNoteToPhase(
                  context: context,
                  ref: ref,
                  noteId: note.id,
                  sourceMatterId: sourceMatter.id,
                  phase: phase,
                );
              },
              onMoveToNotebook: (note) async {
                await _moveNoteToNotebookViaDialog(
                  context: context,
                  ref: ref,
                  note: note,
                );
              },
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        const Expanded(child: _NoteEditorPane()),
      ],
    );
  }
}

Future<void> _openNoteInPhaseEditor(WidgetRef ref, Note note) async {
  final showNotebookNotifier = ref.read(showNotebookProvider.notifier);
  final showConflictsNotifier = ref.read(showConflictsProvider.notifier);
  final selectedMatterNotifier = ref.read(selectedMatterIdProvider.notifier);
  final selectedPhaseNotifier = ref.read(selectedPhaseIdProvider.notifier);
  final selectedNotebookFolderNotifier = ref.read(
    selectedNotebookFolderIdProvider.notifier,
  );
  final matterViewModeNotifier = ref.read(matterViewModeProvider.notifier);
  final mattersNotifier = ref.read(mattersControllerProvider.notifier);
  final noteEditorNotifier = ref.read(noteEditorControllerProvider.notifier);

  showNotebookNotifier.set(false);
  showConflictsNotifier.set(false);
  selectedMatterNotifier.set(note.matterId);
  selectedPhaseNotifier.set(note.phaseId);
  selectedNotebookFolderNotifier.set(null);
  matterViewModeNotifier.set(MatterViewMode.phase);
  if (note.matterId != null && note.phaseId != null) {
    final matter = mattersNotifier.findMatter(note.matterId!);
    if (matter != null) {
      unawaited(
        mattersNotifier.setMatterCurrentPhase(
          matter: matter,
          phaseId: note.phaseId!,
        ),
      );
    }
  }
  await noteEditorNotifier.selectNote(note.id);
}

class _MatterTimelineWorkspace extends ConsumerWidget {
  const _MatterTimelineWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final notes = ref.watch(noteListProvider);
    final dragPayloadNotifier = ref.read(
      _activeNoteDragPayloadProvider.notifier,
    );

    return notes.when(
      loading: () => Center(child: _adaptiveLoadingIndicator(context)),
      error: (error, _) => Center(child: Text('$error')),
      data: (items) {
        if (items.isEmpty) {
          return Center(child: Text(l10n.noNotesYetMessage));
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          itemCount: items.length,
          separatorBuilder: (_, index) => const SizedBox(height: 8),
          itemBuilder: (_, index) {
            final note = items[index];
            final dateLabel = DateFormat(
              'yyyy-MM-dd HH:mm',
            ).format(note.createdAt.toLocal());
            final preview = note.content
                .replaceAll('\n', ' ')
                .trim()
                .replaceFirst(RegExp(r'^#+\s*'), '');
            final card = Container(
              decoration: isMacOSNativeUI
                  ? _macosPanelDecoration(context)
                  : BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(10),
                    ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          note.title.trim().isEmpty
                              ? l10n.untitledLabel
                              : note.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: isMacOSNativeUI
                              ? MacosTheme.of(context).typography.headline
                              : Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        dateLabel,
                        style: isMacOSNativeUI
                            ? MacosTheme.of(context).typography.caption1
                            : Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    preview.isEmpty ? l10n.noSearchResultsMessage : preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      isMacOSNativeUI
                          ? MacosPulldownButton(
                              icon: CupertinoIcons.ellipsis_circle,
                              items: <MacosPulldownMenuEntry>[
                                MacosPulldownMenuItem(
                                  title: Text(l10n.moveNoteToMatterAction),
                                  onTap: () async {
                                    final targetMatter =
                                        await _showMoveToMatterDialog(
                                          context: context,
                                          ref: ref,
                                          note: note,
                                        );
                                    if (!context.mounted ||
                                        targetMatter == null) {
                                      return;
                                    }
                                    await _moveNoteToMatter(
                                      context: context,
                                      ref: ref,
                                      noteId: note.id,
                                      targetMatter: targetMatter,
                                    );
                                  },
                                ),
                                MacosPulldownMenuItem(
                                  title: Text(l10n.moveNoteToPhaseAction),
                                  enabled: note.matterId != null,
                                  onTap: () async {
                                    final matterId = note.matterId;
                                    if (matterId == null) {
                                      return;
                                    }
                                    final sourceMatter = ref
                                        .read(
                                          mattersControllerProvider.notifier,
                                        )
                                        .findMatter(matterId);
                                    if (sourceMatter == null) {
                                      _showMoveMessage(
                                        context,
                                        context
                                            .l10n
                                            .moveSourceMatterMissingMessage,
                                      );
                                      return;
                                    }
                                    final phase = await _showMoveToPhaseDialog(
                                      context: context,
                                      matter: sourceMatter,
                                      note: note,
                                    );
                                    if (!context.mounted || phase == null) {
                                      return;
                                    }
                                    await _moveNoteToPhase(
                                      context: context,
                                      ref: ref,
                                      noteId: note.id,
                                      sourceMatterId: sourceMatter.id,
                                      phase: phase,
                                    );
                                  },
                                ),
                                MacosPulldownMenuItem(
                                  title: Text(l10n.moveToNotebookAction),
                                  onTap: () async {
                                    await _moveNoteToNotebookViaDialog(
                                      context: context,
                                      ref: ref,
                                      note: note,
                                    );
                                  },
                                ),
                              ],
                            )
                          : PopupMenuButton<String>(
                              itemBuilder: (_) => <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  value: 'move_matter',
                                  child: Text(l10n.moveNoteToMatterAction),
                                ),
                                PopupMenuItem<String>(
                                  value: 'move_phase',
                                  enabled: note.matterId != null,
                                  child: Text(l10n.moveNoteToPhaseAction),
                                ),
                                PopupMenuItem<String>(
                                  value: 'move_notebook',
                                  child: Text(l10n.moveToNotebookAction),
                                ),
                              ],
                              onSelected: (value) async {
                                switch (value) {
                                  case 'move_matter':
                                    final targetMatter =
                                        await _showMoveToMatterDialog(
                                          context: context,
                                          ref: ref,
                                          note: note,
                                        );
                                    if (!context.mounted ||
                                        targetMatter == null) {
                                      return;
                                    }
                                    await _moveNoteToMatter(
                                      context: context,
                                      ref: ref,
                                      noteId: note.id,
                                      targetMatter: targetMatter,
                                    );
                                    return;
                                  case 'move_phase':
                                    final matterId = note.matterId;
                                    if (matterId == null) {
                                      return;
                                    }
                                    final sourceMatter = ref
                                        .read(
                                          mattersControllerProvider.notifier,
                                        )
                                        .findMatter(matterId);
                                    if (sourceMatter == null) {
                                      _showMoveMessage(
                                        context,
                                        context
                                            .l10n
                                            .moveSourceMatterMissingMessage,
                                      );
                                      return;
                                    }
                                    final phase = await _showMoveToPhaseDialog(
                                      context: context,
                                      matter: sourceMatter,
                                      note: note,
                                    );
                                    if (!context.mounted || phase == null) {
                                      return;
                                    }
                                    await _moveNoteToPhase(
                                      context: context,
                                      ref: ref,
                                      noteId: note.id,
                                      sourceMatterId: sourceMatter.id,
                                      phase: phase,
                                    );
                                    return;
                                  case 'move_notebook':
                                    await _moveNoteToNotebookViaDialog(
                                      context: context,
                                      ref: ref,
                                      note: note,
                                    );
                                    return;
                                }
                              },
                            ),
                      const SizedBox(width: 6),
                      isMacOSNativeUI
                          ? PushButton(
                              controlSize: ControlSize.regular,
                              onPressed: () async {
                                await _openNoteInPhaseEditor(ref, note);
                              },
                              child: const Text('Edit in Phase'),
                            )
                          : OutlinedButton(
                              onPressed: () async {
                                await _openNoteInPhaseEditor(ref, note);
                              },
                              child: const Text('Edit in Phase'),
                            ),
                    ],
                  ),
                ],
              ),
            );

            final payload = _NoteDragPayload(
              noteId: note.id,
              matterId: note.matterId,
              phaseId: note.phaseId,
            );
            return LongPressDraggable<_NoteDragPayload>(
              key: ValueKey<String>('note_drag_timeline_${note.id}'),
              data: payload,
              delay: const Duration(milliseconds: 180),
              onDragStarted: () {
                dragPayloadNotifier.set(payload);
              },
              onDraggableCanceled: (velocity, offset) {
                dragPayloadNotifier.set(null);
              },
              onDragCompleted: () {
                dragPayloadNotifier.set(null);
              },
              onDragEnd: (_) {
                dragPayloadNotifier.set(null);
              },
              feedback: Material(
                type: MaterialType.transparency,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(188),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _displayNoteTitleForMove(context, note),
                    style: const TextStyle(color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.45, child: card),
              child: card,
            );
          },
        );
      },
    );
  }
}

class _MatterGraphWorkspace extends ConsumerWidget {
  const _MatterGraphWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final graphState = ref.watch(graphControllerProvider);
    final selectedNoteId = ref.watch(selectedNoteIdProvider);

    return graphState.when(
      loading: () => Center(child: _adaptiveLoadingIndicator(context)),
      error: (error, _) =>
          Center(child: Text(l10n.graphLoadFailed(error.toString()))),
      data: (view) {
        if (view.graph.nodes.isEmpty) {
          return Center(
            child: Text(
              l10n.noLinkedNotesInMatterMessage,
              textAlign: TextAlign.center,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (view.isTruncated)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                padding: const EdgeInsets.all(10),
                decoration: isMacOSNativeUI
                    ? _macosPanelDecoration(context)
                    : BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                child: Text(
                  l10n.graphLimitedNotice(
                    graphNodeLimit,
                    view.truncatedNodeCount,
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _GraphCanvas(
                  graph: view.graph,
                  selectedNoteId: selectedNoteId,
                  onTapNode: (noteId) async {
                    await _showGraphNodePreview(
                      context: context,
                      ref: ref,
                      noteId: noteId,
                    );
                  },
                ),
              ),
            ),
            SizedBox(
              height: 170,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                scrollDirection: Axis.horizontal,
                itemCount: view.graph.nodes.length,
                separatorBuilder: (_, index) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final node = view.graph.nodes[index];
                  return _GraphNodePreviewCard(
                    node: node,
                    onPreview: () async {
                      await _showGraphNodePreview(
                        context: context,
                        ref: ref,
                        noteId: node.noteId,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GraphNodePreviewCard extends StatelessWidget {
  const _GraphNodePreviewCard({required this.node, required this.onPreview});

  final MatterGraphNode node;
  final Future<void> Function() onPreview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final label = node.title.trim().isEmpty ? l10n.untitledLabel : node.title;
    return Container(
      width: 220,
      decoration: isMacOSNativeUI
          ? _macosPanelDecoration(context)
          : BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(10),
            ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GestureDetector(
                onTap: () async {
                  await onPreview();
                },
                child: CircleAvatar(
                  radius: 14,
                  child: Text(label.substring(0, 1).toUpperCase()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            DateFormat('yyyy-MM-dd').format(node.updatedAt.toLocal()),
            style: isMacOSNativeUI
                ? MacosTheme.of(context).typography.caption1
                : Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: isMacOSNativeUI
                ? PushButton(
                    controlSize: ControlSize.regular,
                    onPressed: () async {
                      await onPreview();
                    },
                    child: const Text('Preview'),
                  )
                : OutlinedButton(
                    onPressed: () async {
                      await onPreview();
                    },
                    child: const Text('Preview'),
                  ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showGraphNodePreview({
  required BuildContext context,
  required WidgetRef ref,
  required String noteId,
}) async {
  final note = await ref.read(noteRepositoryProvider).getNoteById(noteId);
  if (note == null || !context.mounted) {
    return;
  }

  final l10n = context.l10n;
  final isMacOSNativeUI = _isMacOSNativeUIContext(context);
  final preview = note.content
      .replaceAll('\n', ' ')
      .trim()
      .replaceFirst(RegExp(r'^#+\s*'), '');

  if (isMacOSNativeUI) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => MacosSheet(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                note.title.trim().isEmpty ? l10n.untitledLabel : note.title,
                style: MacosTheme.of(dialogContext).typography.title3,
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('yyyy-MM-dd HH:mm').format(note.updatedAt.toLocal()),
                style: MacosTheme.of(dialogContext).typography.caption1,
              ),
              const SizedBox(height: 10),
              Text(
                preview.isEmpty ? 'No preview available.' : preview,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(l10n.closeAction),
                  ),
                  const SizedBox(width: 8),
                  PushButton(
                    controlSize: ControlSize.regular,
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      await _openNoteInPhaseEditor(ref, note);
                    },
                    child: const Text('Edit in Phase'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(note.title.trim().isEmpty ? l10n.untitledLabel : note.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(DateFormat('yyyy-MM-dd HH:mm').format(note.updatedAt.toLocal())),
          const SizedBox(height: 8),
          Text(
            preview.isEmpty ? 'No preview available.' : preview,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.closeAction),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await _openNoteInPhaseEditor(ref, note);
          },
          child: const Text('Edit in Phase'),
        ),
      ],
    ),
  );
}

class _GraphCanvas extends ConsumerWidget {
  const _GraphCanvas({
    required this.graph,
    required this.selectedNoteId,
    required this.onTapNode,
  });

  final MatterGraphData graph;
  final String? selectedNoteId;
  final Future<void> Function(String noteId) onTapNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = _deterministicGraphLayout(graph);
    final theme = Theme.of(context);
    final dragPayloadNotifier = ref.read(
      _activeNoteDragPayloadProvider.notifier,
    );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InteractiveViewer(
        constrained: false,
        minScale: 0.25,
        maxScale: 3.0,
        boundaryMargin: const EdgeInsets.all(220),
        child: SizedBox(
          width: layout.canvasSize.width,
          height: layout.canvasSize.height,
          child: Stack(
            children: <Widget>[
              CustomPaint(
                size: layout.canvasSize,
                painter: _GraphEdgesPainter(
                  edges: graph.edges,
                  positions: layout.positions,
                  selectedNoteId: selectedNoteId,
                  edgeColor: theme.colorScheme.outlineVariant,
                ),
              ),
              ...graph.nodes.map((node) {
                final offset = layout.positions[node.noteId];
                if (offset == null) {
                  return const SizedBox.shrink();
                }

                final isSelected = node.noteId == selectedNoteId;
                final nodeColor = isSelected
                    ? theme.colorScheme.primary
                    : node.isInSelectedMatter
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.secondaryContainer;
                final textColor = isSelected
                    ? theme.colorScheme.onPrimary
                    : node.isInSelectedMatter
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSecondaryContainer;
                final radius = isSelected
                    ? 24.0
                    : node.isPinned
                    ? 20.0
                    : 17.0;

                final nodeWidget = Tooltip(
                  message: node.title.isEmpty
                      ? context.l10n.untitledLabel
                      : node.title,
                  child: InkWell(
                    onTap: () async => onTapNode(node.noteId),
                    borderRadius: BorderRadius.circular(radius),
                    child: Container(
                      width: radius * 2,
                      height: radius * 2,
                      decoration: BoxDecoration(
                        color: nodeColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.outline,
                          width: node.isInSelectedMatter ? 1.2 : 0.8,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _nodeLabel(node),
                        style: TextStyle(
                          color: textColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );

                final payload = _NoteDragPayload(
                  noteId: node.noteId,
                  matterId: node.matterId,
                  phaseId: node.phaseId,
                );

                return Positioned(
                  left: offset.dx - radius,
                  top: offset.dy - radius,
                  child: LongPressDraggable<_NoteDragPayload>(
                    key: ValueKey<String>('note_drag_graph_${node.noteId}'),
                    data: payload,
                    delay: const Duration(milliseconds: 180),
                    onDragStarted: () {
                      dragPayloadNotifier.set(payload);
                    },
                    onDraggableCanceled: (velocity, offset) {
                      dragPayloadNotifier.set(null);
                    },
                    onDragCompleted: () {
                      dragPayloadNotifier.set(null);
                    },
                    onDragEnd: (_) {
                      dragPayloadNotifier.set(null);
                    },
                    feedback: Material(
                      type: MaterialType.transparency,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 280),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(188),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          node.title.trim().isEmpty
                              ? context.l10n.untitledLabel
                              : node.title.trim(),
                          style: const TextStyle(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.35,
                      child: nodeWidget,
                    ),
                    child: nodeWidget,
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  String _nodeLabel(MatterGraphNode node) {
    final title = node.title.trim();
    if (title.isEmpty) {
      return '?';
    }
    return title.substring(0, 1).toUpperCase();
  }
}

class _GraphEdgesPainter extends CustomPainter {
  const _GraphEdgesPainter({
    required this.edges,
    required this.positions,
    required this.selectedNoteId,
    required this.edgeColor,
  });

  final List<MatterGraphEdge> edges;
  final Map<String, Offset> positions;
  final String? selectedNoteId;
  final Color edgeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..color = edgeColor.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final selectedPaint = Paint()
      ..color = edgeColor.withValues(alpha: 0.85)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final source = positions[edge.sourceNoteId];
      final target = positions[edge.targetNoteId];
      if (source == null || target == null) {
        continue;
      }

      final selected =
          selectedNoteId != null &&
          (edge.sourceNoteId == selectedNoteId ||
              edge.targetNoteId == selectedNoteId);
      canvas.drawLine(source, target, selected ? selectedPaint : basePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphEdgesPainter oldDelegate) {
    return oldDelegate.edges != edges ||
        oldDelegate.positions != positions ||
        oldDelegate.selectedNoteId != selectedNoteId ||
        oldDelegate.edgeColor != edgeColor;
  }
}

_GraphLayout _deterministicGraphLayout(MatterGraphData graph) {
  const canvas = Size(1600, 1100);
  final center = Offset(canvas.width / 2, canvas.height / 2);
  final primary = graph.nodes.where((node) => node.isInSelectedMatter).toList();
  final external = graph.nodes
      .where((node) => !node.isInSelectedMatter)
      .toList();

  final positions = <String, Offset>{};
  final primaryNodes = primary.isEmpty ? graph.nodes : primary;
  final externalNodes = primary.isEmpty ? const <MatterGraphNode>[] : external;

  _assignCircular(
    positions: positions,
    nodes: primaryNodes,
    center: center,
    radius: primaryNodes.length <= 1 ? 0 : 280,
    phaseOffset: 0,
  );
  _assignCircular(
    positions: positions,
    nodes: externalNodes,
    center: center,
    radius: 470,
    phaseOffset: math.pi / 6,
  );

  return _GraphLayout(canvasSize: canvas, positions: positions);
}

void _assignCircular({
  required Map<String, Offset> positions,
  required List<MatterGraphNode> nodes,
  required Offset center,
  required double radius,
  required double phaseOffset,
}) {
  if (nodes.isEmpty) {
    return;
  }
  if (nodes.length == 1 || radius == 0) {
    positions[nodes.first.noteId] = center;
    return;
  }

  for (var i = 0; i < nodes.length; i++) {
    final angle = (2 * math.pi * (i / nodes.length)) + phaseOffset;
    final dx = center.dx + (math.cos(angle) * radius);
    final dy = center.dy + (math.sin(angle) * radius);
    positions[nodes[i].noteId] = Offset(dx, dy);
  }
}

class _GraphLayout {
  const _GraphLayout({required this.canvasSize, required this.positions});

  final Size canvasSize;
  final Map<String, Offset> positions;
}

class _NotebookWorkspace extends ConsumerWidget {
  const _NotebookWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notes = ref.watch(notebookNoteListProvider);
    final currentNote = ref.watch(noteEditorControllerProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: _NoteTitleHeader(
            note: currentNote,
            canEdit: currentNote?.isInNotebook ?? false,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 380,
                child: notes.when(
                  loading: () =>
                      Center(child: _adaptiveLoadingIndicator(context)),
                  error: (error, _) => Center(child: Text('$error')),
                  data: (items) => _NoteList(
                    notes: items,
                    onEdit: (note) async {
                      final result = await showDialog<_NoteDialogResult>(
                        context: context,
                        builder: (_) => _NoteDialog(
                          mode: _NoteDialogMode.edit,
                          initialTitle: note.title,
                          initialContent: note.content,
                          initialTags: note.tags,
                          initialPinned: note.isPinned,
                        ),
                      );

                      if (result == null || result.title.trim().isEmpty) {
                        return;
                      }

                      await ref
                          .read(noteEditorControllerProvider.notifier)
                          .updateNoteById(
                            noteId: note.id,
                            title: result.title,
                            content: result.content,
                            tags: result.tags,
                            isPinned: result.isPinned,
                          );
                    },
                    onTogglePinned: (note) async {
                      await ref
                          .read(noteEditorControllerProvider.notifier)
                          .updateNoteById(
                            noteId: note.id,
                            isPinned: !note.isPinned,
                          );
                    },
                    onDelete: (note) async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text(l10n.deleteNoteTitle),
                          content: Text(
                            l10n.deleteNoteConfirmation(note.title),
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: Text(l10n.cancelAction),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: Text(l10n.deleteAction),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        await ref
                            .read(noteEditorControllerProvider.notifier)
                            .deleteNote(note.id);
                      }
                    },
                    onLink: (note) {
                      return _showLinkNoteDialog(
                        context: context,
                        ref: ref,
                        sourceNote: note,
                      );
                    },
                    onMoveToMatter: (note) async {
                      final targetMatter = await _showMoveToMatterDialog(
                        context: context,
                        ref: ref,
                        note: note,
                      );
                      if (!context.mounted || targetMatter == null) {
                        return;
                      }
                      await _moveNoteToMatter(
                        context: context,
                        ref: ref,
                        noteId: note.id,
                        targetMatter: targetMatter,
                      );
                    },
                    onMoveToPhase: (note) async {
                      final matterId = note.matterId;
                      if (matterId == null) {
                        return;
                      }
                      Matter? sourceMatter = ref
                          .read(mattersControllerProvider.notifier)
                          .findMatter(matterId);
                      if (sourceMatter == null) {
                        final matters = await _allMattersForMove(ref);
                        if (!context.mounted) {
                          return;
                        }
                        for (final candidate in matters) {
                          if (candidate.id == matterId) {
                            sourceMatter = candidate;
                            break;
                          }
                        }
                      }
                      if (sourceMatter == null) {
                        _showMoveMessage(
                          context,
                          context.l10n.moveSourceMatterMissingMessage,
                        );
                        return;
                      }
                      final phase = await _showMoveToPhaseDialog(
                        context: context,
                        matter: sourceMatter,
                        note: note,
                      );
                      if (!context.mounted || phase == null) {
                        return;
                      }
                      await _moveNoteToPhase(
                        context: context,
                        ref: ref,
                        noteId: note.id,
                        sourceMatterId: sourceMatter.id,
                        phase: phase,
                      );
                    },
                    onMoveToNotebook: (note) async {
                      await _moveNoteToNotebookViaDialog(
                        context: context,
                        ref: ref,
                        note: note,
                      );
                    },
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              const Expanded(child: _NoteEditorPane()),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoteList extends ConsumerWidget {
  const _NoteList({
    required this.notes,
    required this.onEdit,
    required this.onTogglePinned,
    required this.onDelete,
    required this.onLink,
    required this.onMoveToMatter,
    required this.onMoveToPhase,
    required this.onMoveToNotebook,
  });

  final List<Note> notes;
  final Future<void> Function(Note note) onEdit;
  final Future<void> Function(Note note) onTogglePinned;
  final Future<void> Function(Note note) onDelete;
  final Future<void> Function(Note note) onLink;
  final Future<void> Function(Note note) onMoveToMatter;
  final Future<void> Function(Note note) onMoveToPhase;
  final Future<void> Function(Note note) onMoveToNotebook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final selectedNoteId = ref.watch(selectedNoteIdProvider);
    final dragPayloadNotifier = ref.read(
      _activeNoteDragPayloadProvider.notifier,
    );

    Widget buildDraggable({
      required Note note,
      required String scope,
      required Widget child,
    }) {
      final payload = _NoteDragPayload(
        noteId: note.id,
        matterId: note.matterId,
        phaseId: note.phaseId,
      );
      return LongPressDraggable<_NoteDragPayload>(
        key: ValueKey<String>('note_drag_${scope}_${note.id}'),
        data: payload,
        delay: const Duration(milliseconds: 180),
        onDragStarted: () {
          dragPayloadNotifier.set(payload);
        },
        onDraggableCanceled: (velocity, offset) {
          dragPayloadNotifier.set(null);
        },
        onDragCompleted: () {
          dragPayloadNotifier.set(null);
        },
        onDragEnd: (_) {
          dragPayloadNotifier.set(null);
        },
        feedback: Material(
          type: MaterialType.transparency,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(188),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _displayNoteTitleForMove(context, note),
              style: const TextStyle(color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.45, child: child),
        child: child,
      );
    }

    if (notes.isEmpty) {
      return Center(child: Text(l10n.noNotesYetMessage));
    }

    if (isMacOSNativeUI) {
      return ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: notes.length,
        separatorBuilder: (_, index) => const SizedBox(height: 2),
        itemBuilder: (_, index) {
          final note = notes[index];
          final row = _MacosSelectableRow(
            selected: note.id == selectedNoteId,
            leading: MacosIcon(
              note.isPinned ? CupertinoIcons.pin_fill : CupertinoIcons.doc_text,
              size: 14,
            ),
            title: Text(
              note.title.isEmpty ? l10n.untitledLabel : note.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              note.content.replaceAll('\n', ' '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: MacosPulldownButton(
              icon: CupertinoIcons.ellipsis_circle,
              items: <MacosPulldownMenuEntry>[
                MacosPulldownMenuItem(
                  title: Text(l10n.editAction),
                  onTap: () {
                    unawaited(onEdit(note));
                  },
                ),
                MacosPulldownMenuItem(
                  title: Text(
                    note.isPinned ? l10n.unpinAction : l10n.pinAction,
                  ),
                  onTap: () {
                    unawaited(onTogglePinned(note));
                  },
                ),
                MacosPulldownMenuItem(
                  title: Text(l10n.linkNoteActionEllipsis),
                  onTap: () {
                    unawaited(onLink(note));
                  },
                ),
                const MacosPulldownMenuDivider(),
                MacosPulldownMenuItem(
                  title: Text(l10n.moveNoteToMatterAction),
                  onTap: () {
                    unawaited(onMoveToMatter(note));
                  },
                ),
                MacosPulldownMenuItem(
                  title: Text(l10n.moveNoteToPhaseAction),
                  enabled: note.matterId != null,
                  onTap: () {
                    unawaited(onMoveToPhase(note));
                  },
                ),
                MacosPulldownMenuItem(
                  title: Text(l10n.moveToNotebookAction),
                  onTap: () {
                    unawaited(onMoveToNotebook(note));
                  },
                ),
                const MacosPulldownMenuDivider(),
                MacosPulldownMenuItem(
                  title: Text(l10n.deleteAction),
                  onTap: () {
                    unawaited(onDelete(note));
                  },
                ),
              ],
            ),
            onTap: () async {
              await ref
                  .read(noteEditorControllerProvider.notifier)
                  .selectNote(note.id);
            },
          );
          return buildDraggable(note: note, scope: 'list_macos', child: row);
        },
      );
    }

    return ListView.builder(
      itemCount: notes.length,
      itemBuilder: (_, index) {
        final note = notes[index];
        final tile = ListTile(
          selected: note.id == selectedNoteId,
          title: Text(note.title.isEmpty ? l10n.untitledLabel : note.title),
          subtitle: Text(
            note.content.replaceAll('\n', ' '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'edit':
                  await onEdit(note);
                  return;
                case 'toggle_pin':
                  await onTogglePinned(note);
                  return;
                case 'link':
                  await onLink(note);
                  return;
                case 'move_matter':
                  await onMoveToMatter(note);
                  return;
                case 'move_phase':
                  await onMoveToPhase(note);
                  return;
                case 'move_notebook':
                  await onMoveToNotebook(note);
                  return;
                case 'delete':
                  await onDelete(note);
                  return;
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'edit',
                child: Text(l10n.editAction),
              ),
              PopupMenuItem<String>(
                value: 'toggle_pin',
                child: Text(note.isPinned ? l10n.unpinAction : l10n.pinAction),
              ),
              PopupMenuItem<String>(
                value: 'link',
                child: Text(l10n.linkNoteActionEllipsis),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'move_matter',
                child: Text(l10n.moveNoteToMatterAction),
              ),
              PopupMenuItem<String>(
                value: 'move_phase',
                enabled: note.matterId != null,
                child: Text(l10n.moveNoteToPhaseAction),
              ),
              PopupMenuItem<String>(
                value: 'move_notebook',
                child: Text(l10n.moveToNotebookAction),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'delete',
                child: Text(l10n.deleteAction),
              ),
            ],
            child: note.isPinned
                ? const Icon(Icons.push_pin, size: 16)
                : const Icon(Icons.more_horiz, size: 16),
          ),
          onTap: () async {
            await ref
                .read(noteEditorControllerProvider.notifier)
                .selectNote(note.id);
          },
        );
        return buildDraggable(note: note, scope: 'list_material', child: tile);
      },
    );
  }
}

class _NoteEditorPane extends ConsumerStatefulWidget {
  const _NoteEditorPane();

  @override
  ConsumerState<_NoteEditorPane> createState() => _NoteEditorPaneState();
}

class _NoteEditorPaneState extends ConsumerState<_NoteEditorPane> {
  final TextEditingController _titleController = TextEditingController();
  late final CodeController _contentController;
  final TextEditingController _tagsController = TextEditingController();
  final MarkdownEditFormatter _markdownFormatter = MarkdownEditFormatter();
  String? _loadedNoteId;

  @override
  void initState() {
    super.initState();
    _contentController = MarkdownCodeController(text: '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _attachFiles(BuildContext context) async {
    final l10n = context.l10n;
    try {
      await ref
          .read(noteEditorControllerProvider.notifier)
          .attachFilesToCurrent();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showEditorMessage(context, l10n.failedToAttachFiles(error.toString()));
    }
  }

  Future<String?> _pickAndAttachImageForMarkdown(
    BuildContext context,
    Note note,
  ) async {
    final l10n = context.l10n;
    final beforeAttachments = note.attachments.toSet();

    Note? updated;
    try {
      updated = await ref
          .read(noteEditorControllerProvider.notifier)
          .attachFilesToCurrent();
    } catch (error) {
      if (context.mounted) {
        _showEditorMessage(context, l10n.failedToAttachFiles(error.toString()));
      }
      return null;
    }

    if (updated == null) {
      return null;
    }

    for (final attachment in updated.attachments) {
      if (!beforeAttachments.contains(attachment) &&
          isImageAttachmentPath(attachment)) {
        return attachment;
      }
    }

    if (context.mounted) {
      _showEditorMessage(context, l10n.noNewImageAttachmentSelectedMessage);
    }
    return null;
  }

  Future<void> _removeAttachment(
    BuildContext context,
    String attachmentPath,
  ) async {
    final l10n = context.l10n;
    try {
      await ref
          .read(noteEditorControllerProvider.notifier)
          .removeAttachmentFromCurrent(attachmentPath);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showEditorMessage(
        context,
        l10n.failedToRemoveAttachment(error.toString()),
      );
    }
  }

  Future<void> _openAttachment(
    BuildContext context,
    String absolutePath,
  ) async {
    final l10n = context.l10n;
    final file = File(absolutePath);
    if (!await file.exists()) {
      if (!context.mounted) {
        return;
      }
      _showEditorMessage(context, l10n.attachmentFileNotFoundMessage);
      return;
    }

    try {
      final result = await OpenFilex.open(absolutePath);
      if (!context.mounted) {
        return;
      }
      if (result.type != ResultType.done) {
        final message = result.message.trim().isEmpty
            ? l10n.unableToOpenAttachmentMessage
            : l10n.unableToOpenAttachmentWithReason(result.message);
        _showEditorMessage(context, message);
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showEditorMessage(
        context,
        l10n.unableToOpenAttachmentWithReason(error.toString()),
      );
    }
  }

  void _showEditorMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final noteAsync = ref.watch(noteEditorControllerProvider);
    final editorViewMode = ref.watch(noteEditorViewModeProvider);
    final storageRootPath = ref
        .watch(settingsControllerProvider)
        .asData
        ?.value
        .storageRootPath;
    final note = noteAsync.value;
    final noteError = noteAsync.asError?.error;

    if (noteError != null && note == null) {
      return Center(child: Text(l10n.editorError(noteError.toString())));
    }
    if (note == null) {
      return Center(child: Text(l10n.selectNoteToEditPrompt));
    }
    final linkedNotesAsync = ref.watch(linkedNotesByNoteProvider(note.id));

    if (_loadedNoteId != note.id) {
      _loadedNoteId = note.id;
      _contentController.text = note.content;
      _tagsController.text = note.tags.join(', ');
    }
    if (_titleController.text != note.title) {
      _titleController.text = note.title;
    }

    Future<bool> confirmDelete() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) {
          if (isMacOSNativeUI) {
            return MacosSheet(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.deleteNoteTitle,
                      style: MacosTheme.of(context).typography.title3,
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.deleteNoteConfirmation(note.title)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        PushButton(
                          controlSize: ControlSize.regular,
                          secondary: true,
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(l10n.cancelAction),
                        ),
                        const SizedBox(width: 8),
                        PushButton(
                          controlSize: ControlSize.regular,
                          color: MacosColors.systemRedColor,
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text(l10n.deleteAction),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          return AlertDialog(
            title: Text(l10n.deleteNoteTitle),
            content: Text(l10n.deleteNoteConfirmation(note.title)),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancelAction),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.deleteAction),
              ),
            ],
          );
        },
      );
      return confirmed == true;
    }

    Future<void> saveNote() async {
      final tags = _tagsController.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();

      await ref
          .read(noteEditorControllerProvider.notifier)
          .updateCurrent(
            title: _titleController.text.trim(),
            content: _contentController.text,
            tags: tags,
          );
    }

    bool hasDraftChanges() {
      final currentTags = _tagsController.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (_titleController.text.trim() != note.title) {
        return true;
      }
      if (_contentController.text != note.content) {
        return true;
      }
      if (currentTags.length != note.tags.length) {
        return true;
      }
      for (var i = 0; i < currentTags.length; i++) {
        if (currentTags[i] != note.tags[i]) {
          return true;
        }
      }
      return false;
    }

    Future<void> switchEditorMode(NoteEditorViewMode mode) async {
      if (mode == editorViewMode) {
        return;
      }
      if (editorViewMode == NoteEditorViewMode.edit &&
          mode == NoteEditorViewMode.read) {
        try {
          if (hasDraftChanges()) {
            await saveNote();
          }
        } catch (error) {
          if (!context.mounted) {
            return;
          }
          _showEditorMessage(context, l10n.editorError(error.toString()));
          return;
        }
      }
      ref.read(noteEditorViewModeProvider.notifier).set(mode);
    }

    final currentTags = _tagsController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    Future<void> showUtilityDialog({
      required String title,
      required Widget child,
    }) async {
      if (isMacOSNativeUI) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => MacosSheet(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    title,
                    style: MacosTheme.of(dialogContext).typography.title3,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(height: 360, child: child),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      PushButton(
                        controlSize: ControlSize.regular,
                        secondary: true,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(l10n.closeAction),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: SizedBox(width: 560, child: child),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.closeAction),
            ),
          ],
        ),
      );
    }

    Future<void> showTagsDialog() async {
      final tagsController = TextEditingController(text: _tagsController.text);
      await showUtilityDialog(
        title: l10n.noteTagsUtilityTitle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            isMacOSNativeUI
                ? MacosTextField(
                    key: _kMacosNoteEditorTagsFieldKey,
                    controller: tagsController,
                    placeholder: l10n.tagsCommaSeparatedLabel,
                  )
                : TextField(
                    controller: tagsController,
                    decoration: InputDecoration(
                      labelText: l10n.tagsCommaSeparatedLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: isMacOSNativeUI
                  ? PushButton(
                      controlSize: ControlSize.regular,
                      onPressed: () async {
                        _tagsController.text = tagsController.text;
                        await saveNote();
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      child: Text(l10n.saveAction),
                    )
                  : FilledButton(
                      onPressed: () async {
                        _tagsController.text = tagsController.text;
                        await saveNote();
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      child: Text(l10n.saveAction),
                    ),
            ),
          ],
        ),
      );
      tagsController.dispose();
    }

    Future<void> showAttachmentsDialog() async {
      await showUtilityDialog(
        title: l10n.noteAttachmentsUtilityTitle,
        child: _AttachmentsPanel(
          note: note,
          storageRootPath: storageRootPath,
          onAttach: () => _attachFiles(context),
          onRemoveAttachment: (attachmentPath) =>
              _removeAttachment(context, attachmentPath),
          onOpenAttachment: (absolutePath) =>
              _openAttachment(context, absolutePath),
        ),
      );
    }

    Future<void> showLinkedNotesDialog() async {
      await showUtilityDialog(
        title: l10n.noteLinkedNotesUtilityTitle,
        child: _LinkedNotesPanel(
          sourceNote: note,
          linkedNotesAsync: linkedNotesAsync,
        ),
      );
    }

    Future<void> moveToNotebook() async {
      await _moveNoteToNotebookViaDialog(
        context: context,
        ref: ref,
        note: note,
      );
    }

    Future<void> moveToMatter() async {
      final targetMatter = await _showMoveToMatterDialog(
        context: context,
        ref: ref,
        note: note,
      );
      if (!context.mounted || targetMatter == null) {
        return;
      }
      await _moveNoteToMatter(
        context: context,
        ref: ref,
        noteId: note.id,
        targetMatter: targetMatter,
      );
    }

    Future<void> moveToPhase() async {
      final matterId = note.matterId;
      if (matterId == null) {
        _showMoveMessage(context, l10n.moveSourceMatterMissingMessage);
        return;
      }
      Matter? sourceMatter = ref
          .read(mattersControllerProvider.notifier)
          .findMatter(matterId);
      if (sourceMatter == null) {
        final matters = await _allMattersForMove(ref);
        if (!context.mounted) {
          return;
        }
        for (final candidate in matters) {
          if (candidate.id == matterId) {
            sourceMatter = candidate;
            break;
          }
        }
      }
      if (sourceMatter == null) {
        _showMoveMessage(context, l10n.moveSourceMatterMissingMessage);
        return;
      }
      final phase = await _showMoveToPhaseDialog(
        context: context,
        matter: sourceMatter,
        note: note,
      );
      if (!context.mounted || phase == null) {
        return;
      }
      await _moveNoteToPhase(
        context: context,
        ref: ref,
        noteId: note.id,
        sourceMatterId: sourceMatter.id,
        phase: phase,
      );
    }

    final modeToggle = isMacOSNativeUI
        ? SizedBox(
            width: 130,
            child: CupertinoSlidingSegmentedControl<NoteEditorViewMode>(
              key: _kNoteEditorModeToggleKey,
              groupValue: editorViewMode,
              children: <NoteEditorViewMode, Widget>{
                NoteEditorViewMode.edit: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(l10n.editModeLabel),
                ),
                NoteEditorViewMode.read: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(l10n.readModeLabel),
                ),
              },
              onValueChanged: (value) {
                if (value == null) {
                  return;
                }
                unawaited(switchEditorMode(value));
              },
            ),
          )
        : SizedBox(
            width: 170,
            child: SegmentedButton<NoteEditorViewMode>(
              key: _kNoteEditorModeToggleKey,
              segments: <ButtonSegment<NoteEditorViewMode>>[
                ButtonSegment<NoteEditorViewMode>(
                  value: NoteEditorViewMode.edit,
                  label: Text(l10n.editModeLabel),
                ),
                ButtonSegment<NoteEditorViewMode>(
                  value: NoteEditorViewMode.read,
                  label: Text(l10n.readModeLabel),
                ),
              ],
              selected: <NoteEditorViewMode>{editorViewMode},
              onSelectionChanged: (selection) {
                final selected = selection.first;
                unawaited(switchEditorMode(selected));
              },
            ),
          );

    final saveAction = isMacOSNativeUI
        ? _MacosCompactIconButton(
            key: _kMacosNoteEditorSaveButtonKey,
            tooltip: l10n.saveAction,
            onPressed: saveNote,
            icon: const MacosIcon(CupertinoIcons.floppy_disk),
          )
        : IconButton(
            key: _kMacosNoteEditorSaveButtonKey,
            tooltip: l10n.saveAction,
            onPressed: saveNote,
            icon: const Icon(Icons.save),
          );

    final pinAction = isMacOSNativeUI
        ? _MacosCompactIconButton(
            tooltip: note.isPinned ? l10n.unpinAction : l10n.pinAction,
            onPressed: () async {
              await ref
                  .read(noteEditorControllerProvider.notifier)
                  .updateCurrent(isPinned: !note.isPinned);
            },
            icon: MacosIcon(
              note.isPinned ? CupertinoIcons.pin_fill : CupertinoIcons.pin,
            ),
          )
        : IconButton(
            tooltip: note.isPinned ? l10n.unpinAction : l10n.pinAction,
            onPressed: () async {
              await ref
                  .read(noteEditorControllerProvider.notifier)
                  .updateCurrent(isPinned: !note.isPinned);
            },
            icon: Icon(
              note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            ),
          );

    final deleteAction = isMacOSNativeUI
        ? _MacosCompactIconButton(
            tooltip: l10n.deleteNoteAction,
            onPressed: () async {
              if (await confirmDelete()) {
                await ref
                    .read(noteEditorControllerProvider.notifier)
                    .deleteCurrent();
              }
            },
            icon: const MacosIcon(CupertinoIcons.delete),
          )
        : IconButton(
            tooltip: l10n.deleteNoteAction,
            onPressed: () async {
              if (await confirmDelete()) {
                await ref
                    .read(noteEditorControllerProvider.notifier)
                    .deleteCurrent();
              }
            },
            icon: const Icon(Icons.delete_outline),
          );

    final moreAction = isMacOSNativeUI
        ? MacosPulldownButton(
            icon: CupertinoIcons.ellipsis_circle,
            items: <MacosPulldownMenuEntry>[
              MacosPulldownMenuItem(
                title: Text(l10n.moveNoteToMatterAction),
                onTap: () {
                  unawaited(moveToMatter());
                },
              ),
              MacosPulldownMenuItem(
                title: Text(l10n.moveNoteToPhaseAction),
                enabled: note.matterId != null,
                onTap: () {
                  unawaited(moveToPhase());
                },
              ),
              MacosPulldownMenuItem(
                title: Text(l10n.moveToNotebookAction),
                onTap: () {
                  unawaited(moveToNotebook());
                },
              ),
            ],
          )
        : PopupMenuButton<String>(
            tooltip: l10n.noteMoreActionsTooltip,
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) async {
              switch (value) {
                case 'move_matter':
                  await moveToMatter();
                  return;
                case 'move_phase':
                  await moveToPhase();
                  return;
                case 'move_notebook':
                  await moveToNotebook();
                  return;
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'move_matter',
                child: Text(l10n.moveNoteToMatterAction),
              ),
              PopupMenuItem<String>(
                value: 'move_phase',
                enabled: note.matterId != null,
                child: Text(l10n.moveNoteToPhaseAction),
              ),
              PopupMenuItem<String>(
                value: 'move_notebook',
                child: Text(l10n.moveToNotebookAction),
              ),
            ],
          );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              modeToggle,
              const Spacer(),
              saveAction,
              const SizedBox(width: 4),
              pinAction,
              const SizedBox(width: 4),
              deleteAction,
              const SizedBox(width: 4),
              moreAction,
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: editorViewMode == NoteEditorViewMode.read
                ? Container(
                    decoration: isMacOSNativeUI
                        ? _macosPanelDecoration(context)
                        : BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                    padding: const EdgeInsets.all(10),
                    child: ChronicleMarkdown(data: _contentController.text),
                  )
                : Container(
                    decoration: isMacOSNativeUI
                        ? _macosPanelDecoration(context)
                        : BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: <Widget>[
                        MarkdownFormatToolbar(
                          key: _kNoteEditorMarkdownToolbarKey,
                          controller: _contentController,
                          isMacOSNativeUI: isMacOSNativeUI,
                          keyPrefix: 'note_editor',
                          formatter: _markdownFormatter,
                          showImageAction: true,
                          onPickAndAttachImagePath: () =>
                              _pickAndAttachImageForMarkdown(context, note),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: CodeTheme(
                            data: _noteEditorCodeThemeData(context),
                            child: CodeField(
                              key: _kMacosNoteEditorContentFieldKey,
                              controller: _contentController,
                              expands: true,
                              textStyle: TextStyle(
                                fontFamily: isMacOSNativeUI
                                    ? 'Menlo'
                                    : 'monospace',
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                isMacOSNativeUI
                    ? PushButton(
                        key: _kNoteEditorUtilityTagsKey,
                        controlSize: ControlSize.regular,
                        secondary: true,
                        onPressed: () async {
                          await showTagsDialog();
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const MacosIcon(CupertinoIcons.tag, size: 12),
                            const SizedBox(width: 6),
                            Text(
                              '${l10n.noteTagsUtilityTitle} (${currentTags.length})',
                            ),
                          ],
                        ),
                      )
                    : OutlinedButton.icon(
                        key: _kNoteEditorUtilityTagsKey,
                        onPressed: () async {
                          await showTagsDialog();
                        },
                        icon: const Icon(Icons.tag, size: 16),
                        label: Text(
                          '${l10n.noteTagsUtilityTitle} (${currentTags.length})',
                        ),
                      ),
                const SizedBox(width: 6),
                isMacOSNativeUI
                    ? PushButton(
                        key: _kNoteEditorUtilityAttachmentsKey,
                        controlSize: ControlSize.regular,
                        secondary: true,
                        onPressed: () async {
                          await showAttachmentsDialog();
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const MacosIcon(CupertinoIcons.paperclip, size: 12),
                            const SizedBox(width: 6),
                            Text(
                              '${l10n.noteAttachmentsUtilityTitle} (${note.attachments.length})',
                            ),
                          ],
                        ),
                      )
                    : OutlinedButton.icon(
                        key: _kNoteEditorUtilityAttachmentsKey,
                        onPressed: () async {
                          await showAttachmentsDialog();
                        },
                        icon: const Icon(Icons.attach_file, size: 16),
                        label: Text(
                          '${l10n.noteAttachmentsUtilityTitle} (${note.attachments.length})',
                        ),
                      ),
                const SizedBox(width: 6),
                isMacOSNativeUI
                    ? PushButton(
                        key: _kNoteEditorUtilityLinkedKey,
                        controlSize: ControlSize.regular,
                        secondary: true,
                        onPressed: () async {
                          await showLinkedNotesDialog();
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const MacosIcon(CupertinoIcons.link, size: 12),
                            const SizedBox(width: 6),
                            Text(
                              '${l10n.noteLinkedNotesUtilityTitle} (${linkedNotesAsync.asData?.value.length ?? 0})',
                            ),
                          ],
                        ),
                      )
                    : OutlinedButton.icon(
                        key: _kNoteEditorUtilityLinkedKey,
                        onPressed: () async {
                          await showLinkedNotesDialog();
                        },
                        icon: const Icon(Icons.link, size: 16),
                        label: Text(
                          '${l10n.noteLinkedNotesUtilityTitle} (${linkedNotesAsync.asData?.value.length ?? 0})',
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentsPanel extends StatelessWidget {
  const _AttachmentsPanel({
    required this.note,
    required this.storageRootPath,
    required this.onAttach,
    required this.onOpenAttachment,
    required this.onRemoveAttachment,
  });

  final Note note;
  final String? storageRootPath;
  final Future<void> Function() onAttach;
  final Future<void> Function(String absolutePath) onOpenAttachment;
  final Future<void> Function(String attachmentPath) onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final hasStorageRoot =
        storageRootPath != null && storageRootPath!.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: isMacOSNativeUI
          ? _macosPanelDecoration(context)
          : BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.attachmentsCountTitle(note.attachments.length),
                  style: isMacOSNativeUI
                      ? MacosTheme.of(context).typography.headline
                      : Theme.of(context).textTheme.titleSmall,
                ),
              ),
              isMacOSNativeUI
                  ? PushButton(
                      controlSize: ControlSize.regular,
                      secondary: true,
                      onPressed: () async {
                        await onAttach();
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const MacosIcon(CupertinoIcons.paperclip, size: 13),
                          const SizedBox(width: 6),
                          Text(l10n.attachFilesActionEllipsis),
                        ],
                      ),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: () async {
                        await onAttach();
                      },
                      icon: const Icon(Icons.attach_file),
                      label: Text(l10n.attachFilesActionEllipsis),
                    ),
            ],
          ),
          const SizedBox(height: 6),
          if (note.attachments.isEmpty)
            Text(l10n.noAttachmentsYetMessage)
          else if (!hasStorageRoot)
            Text(l10n.storageRootUnavailableMessage)
          else
            SizedBox(
              height: 220,
              child: ListView.builder(
                itemCount: note.attachments.length,
                itemBuilder: (context, index) {
                  final relativePath = note.attachments[index];
                  final absolutePath = p.normalize(
                    p.join(storageRootPath!, relativePath),
                  );

                  return NoteAttachmentTile(
                    relativePath: relativePath,
                    absolutePath: absolutePath,
                    onOpen: () async {
                      await onOpenAttachment(absolutePath);
                    },
                    onRemove: () async {
                      await onRemoveAttachment(relativePath);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _LinkedNotesPanel extends ConsumerWidget {
  const _LinkedNotesPanel({
    required this.sourceNote,
    required this.linkedNotesAsync,
  });

  final Note sourceNote;
  final AsyncValue<List<LinkedNoteItem>> linkedNotesAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final linkedCount = linkedNotesAsync.asData?.value.length ?? 0;
    return Container(
      width: double.infinity,
      decoration: isMacOSNativeUI
          ? _macosPanelDecoration(context)
          : BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.linkedNotesCountTitle(linkedCount),
                  style: isMacOSNativeUI
                      ? MacosTheme.of(context).typography.headline
                      : Theme.of(context).textTheme.titleSmall,
                ),
              ),
              isMacOSNativeUI
                  ? _MacosCompactIconButton(
                      tooltip: l10n.linkNoteAction,
                      onPressed: () async {
                        await _showLinkNoteDialog(
                          context: context,
                          ref: ref,
                          sourceNote: sourceNote,
                        );
                      },
                      icon: const MacosIcon(CupertinoIcons.link),
                    )
                  : IconButton(
                      tooltip: l10n.linkNoteAction,
                      onPressed: () async {
                        await _showLinkNoteDialog(
                          context: context,
                          ref: ref,
                          sourceNote: sourceNote,
                        );
                      },
                      icon: const Icon(Icons.add_link),
                    ),
            ],
          ),
          SizedBox(
            height: linkedCount == 0 ? 36 : 130,
            child: linkedNotesAsync.when(
              loading: () => Center(child: _adaptiveLoadingIndicator(context)),
              error: (error, stackTrace) =>
                  Text(l10n.failedToLoadLinks(error.toString())),
              data: (items) {
                if (items.isEmpty) {
                  return Text(l10n.noLinksYetMessage);
                }

                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final item = items[index];
                    if (isMacOSNativeUI) {
                      return _MacosSelectableRow(
                        leading: MacosIcon(
                          item.isOutgoing
                              ? CupertinoIcons.arrow_up_right
                              : CupertinoIcons.arrow_down_left,
                          size: 14,
                        ),
                        title: Text(
                          item.relatedNote.title.isEmpty
                              ? l10n.untitledLabel
                              : item.relatedNote.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: item.link.context.trim().isEmpty
                            ? null
                            : Text(
                                item.link.context,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _MacosCompactIconButton(
                              tooltip: l10n.openLinkedNoteAction,
                              onPressed: () async {
                                await ref
                                    .read(noteEditorControllerProvider.notifier)
                                    .selectNote(item.relatedNote.id);
                              },
                              icon: const MacosIcon(
                                CupertinoIcons.arrow_up_right_square,
                                size: 14,
                              ),
                            ),
                            _MacosCompactIconButton(
                              tooltip: l10n.removeLinkAction,
                              onPressed: () async {
                                await ref
                                    .read(linksControllerProvider)
                                    .deleteLink(
                                      currentNoteId: sourceNote.id,
                                      link: item.link,
                                    );
                              },
                              icon: const MacosIcon(
                                CupertinoIcons.link,
                                size: 14,
                              ),
                            ),
                          ],
                        ),
                        onTap: () async {
                          await ref
                              .read(noteEditorControllerProvider.notifier)
                              .selectNote(item.relatedNote.id);
                        },
                      );
                    }

                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        item.isOutgoing
                            ? Icons.north_east_rounded
                            : Icons.south_west_rounded,
                        size: 16,
                      ),
                      title: Text(
                        item.relatedNote.title.isEmpty
                            ? l10n.untitledLabel
                            : item.relatedNote.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: item.link.context.trim().isEmpty
                          ? null
                          : Text(
                              item.link.context,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: Wrap(
                        spacing: 4,
                        children: <Widget>[
                          IconButton(
                            tooltip: l10n.openLinkedNoteAction,
                            onPressed: () async {
                              await ref
                                  .read(noteEditorControllerProvider.notifier)
                                  .selectNote(item.relatedNote.id);
                            },
                            icon: const Icon(Icons.open_in_new, size: 16),
                          ),
                          IconButton(
                            tooltip: l10n.removeLinkAction,
                            onPressed: () async {
                              await ref
                                  .read(linksControllerProvider)
                                  .deleteLink(
                                    currentNoteId: sourceNote.id,
                                    link: item.link,
                                  );
                            },
                            icon: const Icon(Icons.link_off, size: 16),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showLinkNoteDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Note sourceNote,
}) async {
  final l10n = context.l10n;
  List<Note> allNotes;
  try {
    allNotes = await ref.read(allNotesForLinkPickerProvider.future);
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.unableToLoadNotes(error.toString()))),
    );
    return;
  }
  final candidates = allNotes
      .where((note) => note.id != sourceNote.id)
      .toList(growable: false);

  if (!context.mounted) {
    return;
  }

  if (candidates.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.noNotesAvailableToLink)));
    return;
  }

  final result = await showDialog<_LinkNoteDialogResult>(
    context: context,
    builder: (_) =>
        _LinkNoteDialog(sourceNote: sourceNote, candidates: candidates),
  );
  if (result == null) {
    return;
  }

  try {
    await ref
        .read(linksControllerProvider)
        .createLink(
          sourceNoteId: sourceNote.id,
          targetNoteId: result.targetNoteId,
          context: result.context,
        );

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.linkCreatedMessage)));
  } catch (error) {
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.unableToCreateLink(error.toString()))),
    );
  }
}

class _LinkNoteDialog extends StatefulWidget {
  const _LinkNoteDialog({required this.sourceNote, required this.candidates});

  final Note sourceNote;
  final List<Note> candidates;

  @override
  State<_LinkNoteDialog> createState() => _LinkNoteDialogState();
}

class _LinkNoteDialogState extends State<_LinkNoteDialog> {
  late String _targetNoteId;
  final TextEditingController _contextController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _targetNoteId = widget.candidates.first.id;
  }

  @override
  void dispose() {
    _contextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);

    final content = SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.linkSourceRow(_displayNoteTitle(widget.sourceNote)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          isMacOSNativeUI
              ? Row(
                  children: <Widget>[
                    Text(l10n.targetNoteLabel),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MacosPopupButton<String>(
                        value: _targetNoteId,
                        onChanged: (value) {
                          if (value == null || value.isEmpty) {
                            return;
                          }
                          setState(() {
                            _targetNoteId = value;
                          });
                        },
                        items: widget.candidates
                            .map(
                              (candidate) => MacosPopupMenuItem<String>(
                                value: candidate.id,
                                child: Text(_displayNoteTitle(candidate)),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                )
              : DropdownButtonFormField<String>(
                  initialValue: _targetNoteId,
                  decoration: InputDecoration(labelText: l10n.targetNoteLabel),
                  items: widget.candidates
                      .map(
                        (candidate) => DropdownMenuItem<String>(
                          value: candidate.id,
                          child: Text(_displayNoteTitle(candidate)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null || value.isEmpty) {
                      return;
                    }
                    setState(() {
                      _targetNoteId = value;
                    });
                  },
                ),
          const SizedBox(height: 8),
          isMacOSNativeUI
              ? MacosTextField(
                  controller: _contextController,
                  placeholder: l10n.contextOptionalLabel,
                  minLines: 2,
                  maxLines: 4,
                )
              : TextField(
                  controller: _contextController,
                  decoration: InputDecoration(
                    labelText: l10n.contextOptionalLabel,
                    hintText: l10n.linkContextHint,
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
        ],
      ),
    );

    void onCreateLink() {
      Navigator.of(context).pop(
        _LinkNoteDialogResult(
          targetNoteId: _targetNoteId,
          context: _contextController.text.trim(),
        ),
      );
    }

    if (isMacOSNativeUI) {
      return MacosSheet(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.linkNoteDialogTitle,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 12),
              content,
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancelAction),
                  ),
                  const SizedBox(width: 8),
                  PushButton(
                    controlSize: ControlSize.large,
                    onPressed: onCreateLink,
                    child: Text(l10n.createLinkAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(l10n.linkNoteDialogTitle),
      content: content,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: onCreateLink,
          child: Text(l10n.createLinkAction),
        ),
      ],
    );
  }

  String _displayNoteTitle(Note note) {
    final l10n = context.l10n;
    final title = note.title.trim().isEmpty
        ? l10n.untitledLabel
        : note.title.trim();
    if (note.matterId == null || note.phaseId == null) {
      return '$title [${l10n.notebookLabel}]';
    }
    return '$title [${note.matterId}]';
  }
}

class _LinkNoteDialogResult {
  const _LinkNoteDialogResult({
    required this.targetNoteId,
    required this.context,
  });

  final String targetNoteId;
  final String context;
}

bool _isMacOSNativeUIContext(BuildContext context) {
  return MacosTheme.maybeOf(context) != null;
}

String _conflictTypeLabel(SyncConflictType type, AppLocalizations l10n) {
  return switch (type) {
    SyncConflictType.note => l10n.conflictTypeNote,
    SyncConflictType.link => l10n.conflictTypeLink,
    SyncConflictType.unknown => l10n.conflictTypeUnknown,
  };
}

class _ConflictTypeChip extends StatelessWidget {
  const _ConflictTypeChip({required this.type});

  final SyncConflictType type;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isMacOSNativeUI
            ? MacosTheme.of(context).primaryColor.withAlpha(22)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _conflictTypeLabel(type, l10n).toUpperCase(),
        style: isMacOSNativeUI
            ? MacosTheme.of(context).typography.caption2.copyWith(
                color: MacosColors.secondaryLabelColor,
                fontWeight: FontWeight.w700,
              )
            : Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _SearchResultsView extends ConsumerWidget {
  const _SearchResultsView({required this.results});

  final List<SearchListItem> results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    if (results.isEmpty) {
      return Center(child: Text(l10n.noSearchResultsMessage));
    }

    if (isMacOSNativeUI) {
      return ListView.separated(
        padding: const EdgeInsets.all(10),
        itemBuilder: (_, index) {
          final result = results[index];
          return _MacosSelectableRow(
            title: Text(
              result.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${result.contextLine}\n${result.snippet}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const MacosIcon(
              CupertinoIcons.arrow_up_right_square,
              size: 14,
            ),
            onTap: () async {
              ref.read(searchResultsVisibleProvider.notifier).set(false);
              await ref
                  .read(noteEditorControllerProvider.notifier)
                  .openNoteInWorkspace(result.noteId, openInReadMode: true);
            },
          );
        },
        separatorBuilder: (context, index) => const SizedBox(height: 4),
        itemCount: results.length,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemBuilder: (_, index) {
        final result = results[index];
        return ListTile(
          title: Text(result.title),
          subtitle: Text(
            '${result.contextLine}\n${result.snippet}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          onTap: () async {
            ref.read(searchResultsVisibleProvider.notifier).set(false);
            await ref
                .read(noteEditorControllerProvider.notifier)
                .openNoteInWorkspace(result.noteId, openInReadMode: true);
          },
        );
      },
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemCount: results.length,
    );
  }
}

class _SettingsDialog extends ConsumerStatefulWidget {
  const _SettingsDialog({required this.useMacOSNativeUI});

  final bool useMacOSNativeUI;

  @override
  ConsumerState<_SettingsDialog> createState() => _SettingsDialogState();
}

enum _SettingsSection { storage, language, sync }

class _SettingsDialogState extends ConsumerState<_SettingsDialog> {
  late final TextEditingController _rootPathController;
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _intervalController;
  bool _failSafe = true;
  SyncTargetType _type = SyncTargetType.none;
  String _localeTag = 'en';
  _SettingsSection _selectedSection = _SettingsSection.storage;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsControllerProvider).asData?.value;
    _rootPathController = TextEditingController(
      text: settings?.storageRootPath ?? '',
    );
    _urlController = TextEditingController(
      text: settings?.syncConfig.url ?? '',
    );
    _usernameController = TextEditingController(
      text: settings?.syncConfig.username ?? '',
    );
    _passwordController = TextEditingController();
    _intervalController = TextEditingController(
      text: (settings?.syncConfig.intervalMinutes ?? 5).toString(),
    );
    _type = settings?.syncConfig.type ?? SyncTargetType.none;
    _failSafe = settings?.syncConfig.failSafe ?? true;
    _localeTag = appLocaleTag(resolveAppLocale(settings?.localeTag));
  }

  @override
  void dispose() {
    _rootPathController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final useMacOSNativeUI = widget.useMacOSNativeUI;
    final localeItems = AppLocalizations.supportedLocales
        .map((locale) => appLocaleTag(locale))
        .toList(growable: false);
    final viewportSize = MediaQuery.sizeOf(context);
    final sheetBodyWidth = useMacOSNativeUI
        ? math.min(1400.0, math.max(760.0, viewportSize.width - 80))
        : math.min(960.0, math.max(360.0, viewportSize.width - 64));

    String localeDisplayName(String localeTag) {
      final locale = resolveAppLocale(localeTag);
      final localized = lookupAppLocalizations(locale);
      return localized.languageSelfName;
    }

    String sectionLabel(_SettingsSection section) {
      return switch (section) {
        _SettingsSection.storage => l10n.settingsSectionStorage,
        _SettingsSection.language => l10n.settingsSectionLanguage,
        _SettingsSection.sync => l10n.settingsSectionSync,
      };
    }

    Widget sectionNavItem(_SettingsSection section) {
      final selected = _selectedSection == section;
      if (useMacOSNativeUI) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: PushButton(
            controlSize: ControlSize.large,
            secondary: !selected,
            onPressed: () => setState(() => _selectedSection = section),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(sectionLabel(section)),
            ),
          ),
        );
      }

      return ListTile(
        dense: true,
        selected: selected,
        title: Text(sectionLabel(section)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () => setState(() => _selectedSection = section),
      );
    }

    Widget buildStorageSection() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          useMacOSNativeUI
              ? MacosTextField(
                  controller: _rootPathController,
                  placeholder: l10n.storageRootPathLabel,
                )
              : TextField(
                  controller: _rootPathController,
                  decoration: InputDecoration(
                    labelText: l10n.storageRootPathLabel,
                  ),
                ),
        ],
      );
    }

    Widget buildLanguageSection() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          useMacOSNativeUI
              ? Row(
                  children: <Widget>[
                    Text(l10n.languageLabel),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MacosPopupButton<String>(
                        value: _localeTag,
                        onChanged: (value) {
                          if (value == null || value.isEmpty) {
                            return;
                          }
                          setState(() {
                            _localeTag = value;
                          });
                        },
                        items: localeItems
                            .map(
                              (localeTag) => MacosPopupMenuItem<String>(
                                value: localeTag,
                                child: Text(localeDisplayName(localeTag)),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                )
              : DropdownButtonFormField<String>(
                  initialValue: _localeTag,
                  items: localeItems
                      .map(
                        (localeTag) => DropdownMenuItem<String>(
                          value: localeTag,
                          child: Text(localeDisplayName(localeTag)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null || value.isEmpty) {
                      return;
                    }
                    setState(() {
                      _localeTag = value;
                    });
                  },
                  decoration: InputDecoration(labelText: l10n.languageLabel),
                ),
        ],
      );
    }

    Widget buildSyncSection() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          useMacOSNativeUI
              ? Row(
                  children: <Widget>[
                    Text(l10n.syncTargetTypeLabel),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MacosPopupButton<SyncTargetType>(
                        value: _type,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _type = value;
                          });
                        },
                        items: SyncTargetType.values
                            .map(
                              (value) => MacosPopupMenuItem<SyncTargetType>(
                                value: value,
                                child: Text(_syncTargetTypeLabel(value, l10n)),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                )
              : DropdownButtonFormField<SyncTargetType>(
                  initialValue: _type,
                  items: SyncTargetType.values
                      .map(
                        (value) => DropdownMenuItem<SyncTargetType>(
                          value: value,
                          child: Text(_syncTargetTypeLabel(value, l10n)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _type = value;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: l10n.syncTargetTypeLabel,
                  ),
                ),
          const SizedBox(height: 8),
          useMacOSNativeUI
              ? MacosTextField(
                  controller: _urlController,
                  placeholder: l10n.webDavUrlLabel,
                )
              : TextField(
                  controller: _urlController,
                  decoration: InputDecoration(labelText: l10n.webDavUrlLabel),
                ),
          const SizedBox(height: 8),
          useMacOSNativeUI
              ? MacosTextField(
                  controller: _usernameController,
                  placeholder: l10n.webDavUsernameLabel,
                )
              : TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: l10n.webDavUsernameLabel,
                  ),
                ),
          const SizedBox(height: 8),
          useMacOSNativeUI
              ? MacosTextField(
                  controller: _passwordController,
                  placeholder: l10n.webDavPasswordLabel,
                  obscureText: true,
                )
              : TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: l10n.webDavPasswordLabel,
                  ),
                  obscureText: true,
                ),
          const SizedBox(height: 8),
          useMacOSNativeUI
              ? MacosTextField(
                  controller: _intervalController,
                  placeholder: l10n.autoSyncIntervalMinutesLabel,
                  keyboardType: TextInputType.number,
                )
              : TextField(
                  controller: _intervalController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.autoSyncIntervalMinutesLabel,
                  ),
                ),
          const SizedBox(height: 8),
          useMacOSNativeUI
              ? Row(
                  children: <Widget>[
                    MacosSwitch(
                      value: _failSafe,
                      onChanged: (value) => setState(() => _failSafe = value),
                    ),
                    const SizedBox(width: 8),
                    Text(l10n.deletionFailSafeLabel),
                  ],
                )
              : SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _failSafe,
                  onChanged: (value) => setState(() => _failSafe = value),
                  title: Text(l10n.deletionFailSafeLabel),
                ),
        ],
      );
    }

    final sectionContent = switch (_selectedSection) {
      _SettingsSection.storage => buildStorageSection(),
      _SettingsSection.language => buildLanguageSection(),
      _SettingsSection.sync => buildSyncSection(),
    };

    final sectionNav = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        sectionNavItem(_SettingsSection.storage),
        sectionNavItem(_SettingsSection.language),
        sectionNavItem(_SettingsSection.sync),
      ],
    );

    final content = SizedBox(
      width: sheetBodyWidth,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            key: _kSettingsDialogNavPaneKey,
            width: 146,
            child: Align(alignment: Alignment.topLeft, child: sectionNav),
          ),
          const SizedBox(width: 14),
          Expanded(
            key: _kSettingsDialogContentPaneKey,
            child: Container(
              padding: const EdgeInsets.only(left: 14, top: 4),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Align(alignment: Alignment.topLeft, child: sectionContent),
            ),
          ),
        ],
      ),
    );

    final scrollableContent = SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: sheetBodyWidth),
        child: content,
      ),
    );

    Future<void> saveSettings() async {
      await ref
          .read(settingsControllerProvider.notifier)
          .setStorageRootPath(_rootPathController.text.trim());

      final syncConfig = ref
          .read(settingsControllerProvider)
          .asData
          ?.value
          .syncConfig
          .copyWith(
            type: _type,
            url: _urlController.text.trim(),
            username: _usernameController.text.trim(),
            intervalMinutes: int.tryParse(_intervalController.text.trim()) ?? 5,
            failSafe: _failSafe,
          );

      if (syncConfig != null) {
        await ref
            .read(settingsControllerProvider.notifier)
            .saveSyncConfig(
              syncConfig,
              password: _passwordController.text.trim().isEmpty
                  ? null
                  : _passwordController.text.trim(),
            );

        await ref
            .read(syncControllerProvider.notifier)
            .startAutoSync(syncConfig.intervalMinutes);
      }

      await ref
          .read(settingsControllerProvider.notifier)
          .setLocaleTag(_localeTag);

      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    if (widget.useMacOSNativeUI) {
      return MacosSheet(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: sheetBodyWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      l10n.settingsTitle,
                      style: const TextStyle(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    scrollableContent,
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        PushButton(
                          controlSize: ControlSize.large,
                          secondary: true,
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(l10n.cancelAction),
                        ),
                        const SizedBox(width: 8),
                        PushButton(
                          controlSize: ControlSize.large,
                          onPressed: saveSettings,
                          child: Text(l10n.saveAction),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(l10n.settingsTitle),
      content: scrollableContent,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(onPressed: saveSettings, child: Text(l10n.saveAction)),
      ],
    );
  }
}

class _ManagePhasesDialog extends ConsumerStatefulWidget {
  const _ManagePhasesDialog({required this.matterId});

  final String matterId;

  @override
  ConsumerState<_ManagePhasesDialog> createState() =>
      _ManagePhasesDialogState();
}

class _ManagePhasesDialogState extends ConsumerState<_ManagePhasesDialog> {
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
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
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
              ? _MacosCompactIconButton(
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
              ? _MacosCompactIconButton(
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
              ? _MacosCompactIconButton(
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

enum _MatterDialogMode { create, edit }

class _MatterDialog extends StatefulWidget {
  const _MatterDialog({
    required this.mode,
    this.initialTitle = '',
    this.initialDescription = '',
    this.initialStatus = MatterStatus.active,
    this.initialColor = '#4C956C',
    this.initialIcon = 'description',
    this.initialPinned = false,
  });

  final _MatterDialogMode mode;
  final String initialTitle;
  final String initialDescription;
  final MatterStatus initialStatus;
  final String initialColor;
  final String initialIcon;
  final bool initialPinned;

  @override
  State<_MatterDialog> createState() => _MatterDialogState();
}

class _MatterDialogState extends State<_MatterDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _colorPreviewController;
  late MatterStatus _status;
  late bool _isPinned;
  late String _selectedColorHex;
  late String _selectedIconKey;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _selectedColorHex = _normalizeHexColor(widget.initialColor);
    _selectedIconKey = _normalizeMatterIconKey(widget.initialIcon);
    _colorPreviewController = TextEditingController(text: _selectedColorHex);
    _status = widget.initialStatus;
    _isPinned = widget.initialPinned;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _colorPreviewController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomColor(BuildContext context) async {
    var draftColor = _colorFromHex(_selectedColorHex);
    final l10n = context.l10n;
    final selectedColor = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.matterCustomColorAction),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: draftColor,
            onColorChanged: (value) {
              draftColor = value;
            },
            enableAlpha: false,
            labelTypes: const <ColorLabelType>[
              ColorLabelType.hex,
              ColorLabelType.rgb,
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(draftColor),
            child: Text(l10n.matterUseColorAction),
          ),
        ],
      ),
    );
    if (selectedColor == null) {
      return;
    }
    setState(() {
      _selectedColorHex = _colorToHex(selectedColor);
      _colorPreviewController.text = _selectedColorHex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = widget.mode == _MatterDialogMode.create
        ? l10n.createMatterTitle
        : l10n.editMatterTitle;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final viewportSize = MediaQuery.sizeOf(context);
    final macSheetBodyWidth = math.min(
      1400.0,
      math.max(820.0, viewportSize.width - 80),
    );
    final macFormMaxHeight = math.min(
      680.0,
      math.max(340.0, viewportSize.height - 220),
    );

    Widget buildColorSwatch(String hexColor) {
      final selected = _selectedColorHex == hexColor;
      return Tooltip(
        message: hexColor,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedColorHex = hexColor;
                _colorPreviewController.text = _selectedColorHex;
              });
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _colorFromHex(hexColor),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: selected ? 2.5 : 1.2,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget buildIconOption(_MatterIconOption option) {
      final selected = _selectedIconKey == option.key;
      return Tooltip(
        message: _matterIconLabel(l10n, option.key),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => _selectedIconKey = option.key),
            child: Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primary.withAlpha(24)
                    : null,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(option.iconData, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _matterIconLabel(l10n, option.key),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget buildIconGrid() {
      return LayoutBuilder(
        builder: (context, constraints) {
          final gridWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : (isMacOSNativeUI ? macSheetBodyWidth : 660.0);
          final columns = math.max(3, math.min(6, (gridWidth / 170).floor()));
          final iconTileWidth = math.max(
            112.0,
            (gridWidth - ((columns - 1) * 8)) / columns,
          );
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kMatterIconOptions
                .map(
                  (option) => SizedBox(
                    width: iconTileWidth,
                    child: buildIconOption(option),
                  ),
                )
                .toList(),
          );
        },
      );
    }

    final formFields = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        isMacOSNativeUI
            ? MacosTextField(
                controller: _titleController,
                placeholder: l10n.titleLabel,
              )
            : TextField(
                controller: _titleController,
                decoration: InputDecoration(labelText: l10n.titleLabel),
              ),
        const SizedBox(height: 8),
        isMacOSNativeUI
            ? MacosTextField(
                controller: _descriptionController,
                placeholder: l10n.descriptionLabel,
              )
            : TextField(
                controller: _descriptionController,
                decoration: InputDecoration(labelText: l10n.descriptionLabel),
              ),
        const SizedBox(height: 8),
        isMacOSNativeUI
            ? Row(
                children: <Widget>[
                  Text(l10n.statusLabel),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MacosPopupButton<MatterStatus>(
                      value: _status,
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _status = value;
                        });
                      },
                      items: MatterStatus.values
                          .map(
                            (value) => MacosPopupMenuItem<MatterStatus>(
                              value: value,
                              child: Text(_matterStatusLabel(l10n, value)),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              )
            : DropdownButtonFormField<MatterStatus>(
                initialValue: _status,
                decoration: InputDecoration(labelText: l10n.statusLabel),
                items: MatterStatus.values
                    .map(
                      (value) => DropdownMenuItem<MatterStatus>(
                        value: value,
                        child: Text(_matterStatusLabel(l10n, value)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _status = value;
                  });
                },
              ),
        const SizedBox(height: 8),
        Text(l10n.matterPresetColorsLabel),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kMatterPresetColors
              .map((hexColor) => buildColorSwatch(hexColor))
              .toList(),
        ),
        const SizedBox(height: 10),
        isMacOSNativeUI
            ? Row(
                children: <Widget>[
                  PushButton(
                    key: _kMatterColorCustomButtonKey,
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: () => _pickCustomColor(context),
                    child: Text(l10n.matterCustomColorAction),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MacosTextField(
                      key: _kMatterColorPreviewFieldKey,
                      controller: _colorPreviewController,
                      readOnly: true,
                      placeholder: l10n.colorHexLabel,
                    ),
                  ),
                ],
              )
            : Row(
                children: <Widget>[
                  OutlinedButton(
                    key: _kMatterColorCustomButtonKey,
                    onPressed: () => _pickCustomColor(context),
                    child: Text(l10n.matterCustomColorAction),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: _kMatterColorPreviewFieldKey,
                      controller: _colorPreviewController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: l10n.colorHexLabel,
                        hintText: l10n.colorHexHint,
                      ),
                    ),
                  ),
                ],
              ),
        const SizedBox(height: 12),
        Text(l10n.matterIconPickerLabel),
        const SizedBox(height: 8),
        buildIconGrid(),
        const SizedBox(height: 12),
        isMacOSNativeUI
            ? Row(
                children: <Widget>[
                  MacosSwitch(
                    value: _isPinned,
                    onChanged: (value) => setState(() => _isPinned = value),
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.pinnedLabel),
                ],
              )
            : SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isPinned,
                onChanged: (value) => setState(() => _isPinned = value),
                title: Text(l10n.pinnedLabel),
              ),
      ],
    );

    final content = SizedBox(
      width: isMacOSNativeUI ? double.infinity : 660,
      child: isMacOSNativeUI
          ? formFields
          : SingleChildScrollView(child: formFields),
    );

    void onSave() {
      Navigator.of(context).pop(
        _MatterDialogResult(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          status: _status,
          color: _normalizeHexColor(_selectedColorHex),
          icon: _normalizeMatterIconKey(_selectedIconKey),
          isPinned: _isPinned,
        ),
      );
    }

    if (isMacOSNativeUI) {
      return MacosSheet(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: macSheetBodyWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(title, style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: macFormMaxHeight),
                      child: SingleChildScrollView(child: content),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        PushButton(
                          controlSize: ControlSize.large,
                          secondary: true,
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(l10n.cancelAction),
                        ),
                        const SizedBox(width: 8),
                        PushButton(
                          controlSize: ControlSize.large,
                          onPressed: onSave,
                          child: Text(
                            widget.mode == _MatterDialogMode.create
                                ? l10n.createAction
                                : l10n.saveAction,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(title),
      content: content,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: onSave,
          child: Text(
            widget.mode == _MatterDialogMode.create
                ? l10n.createAction
                : l10n.saveAction,
          ),
        ),
      ],
    );
  }
}

class _MatterDialogResult {
  const _MatterDialogResult({
    required this.title,
    required this.description,
    required this.status,
    required this.color,
    required this.icon,
    required this.isPinned,
  });

  final String title;
  final String description;
  final MatterStatus status;
  final String color;
  final String icon;
  final bool isPinned;
}

enum _CategoryDialogMode { create, edit }

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    required this.mode,
    this.initialName = '',
    this.initialColor = '#4C956C',
    this.initialIcon = 'folder',
  });

  final _CategoryDialogMode mode;
  final String initialName;
  final String initialColor;
  final String initialIcon;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _nameController;
  late String _selectedColorHex;
  late String _selectedIconKey;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _selectedColorHex = _normalizeHexColor(widget.initialColor);
    _selectedIconKey = _normalizeMatterIconKey(widget.initialIcon);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final title = widget.mode == _CategoryDialogMode.create
        ? l10n.createCategoryTitle
        : l10n.editCategoryTitle;

    Widget iconOption(_MatterIconOption option) {
      final selected = _selectedIconKey == option.key;
      return GestureDetector(
        onTap: () => setState(() => _selectedIconKey = option.key),
        child: Container(
          width: 108,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary.withAlpha(18)
                : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(option.iconData, size: 18),
              const SizedBox(height: 4),
              Text(
                _matterIconLabel(l10n, option.key),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    Widget colorSwatch(String colorHex) {
      final selected = _selectedColorHex == colorHex;
      return GestureDetector(
        onTap: () => setState(() => _selectedColorHex = colorHex),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _colorFromHex(colorHex),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
        ),
      );
    }

    final content = SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            isMacOSNativeUI
                ? MacosTextField(
                    controller: _nameController,
                    placeholder: l10n.categoryNameLabel,
                  )
                : TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: l10n.categoryNameLabel,
                    ),
                  ),
            const SizedBox(height: 10),
            Text(l10n.matterPresetColorsLabel),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kMatterPresetColors.map(colorSwatch).toList(),
            ),
            const SizedBox(height: 12),
            Text(l10n.categoryIconLabel),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kMatterIconOptions.map(iconOption).toList(),
            ),
          ],
        ),
      ),
    );

    void onSave() {
      Navigator.of(context).pop(
        _CategoryDialogResult(
          name: _nameController.text.trim(),
          color: _selectedColorHex,
          icon: _selectedIconKey,
        ),
      );
    }

    if (isMacOSNativeUI) {
      return MacosSheet(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              content,
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancelAction),
                  ),
                  const SizedBox(width: 8),
                  PushButton(
                    controlSize: ControlSize.large,
                    onPressed: onSave,
                    child: Text(
                      widget.mode == _CategoryDialogMode.create
                          ? l10n.createAction
                          : l10n.saveAction,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(title),
      content: content,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: onSave,
          child: Text(
            widget.mode == _CategoryDialogMode.create
                ? l10n.createAction
                : l10n.saveAction,
          ),
        ),
      ],
    );
  }
}

class _CategoryDialogResult {
  const _CategoryDialogResult({
    required this.name,
    required this.color,
    required this.icon,
  });

  final String name;
  final String color;
  final String icon;
}

enum _NoteDialogMode { create, edit }

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.mode,
    this.initialTitle = '',
    this.initialContent = '',
    this.initialTags = const <String>[],
    this.initialPinned = false,
  });

  final _NoteDialogMode mode;
  final String initialTitle;
  final String initialContent;
  final List<String> initialTags;
  final bool initialPinned;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _tagsController;
  final MarkdownEditFormatter _markdownFormatter = MarkdownEditFormatter();
  late bool _isPinned;
  bool _seededDefaultContent = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _contentController = TextEditingController(text: widget.initialContent);
    _tagsController = TextEditingController(
      text: widget.initialTags.join(', '),
    );
    _isPinned = widget.initialPinned;
    _seededDefaultContent = widget.initialContent.isNotEmpty;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seededDefaultContent) {
      return;
    }
    final l10n = context.l10n;
    _contentController.text =
        '# ${widget.initialTitle.isEmpty ? l10n.defaultUntitledNoteTitle : widget.initialTitle}\n';
    _seededDefaultContent = true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = widget.mode == _NoteDialogMode.create
        ? l10n.createNoteTitle
        : l10n.editNoteTitle;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);

    final content = SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            isMacOSNativeUI
                ? MacosTextField(
                    controller: _titleController,
                    placeholder: l10n.titleLabel,
                  )
                : TextField(
                    controller: _titleController,
                    decoration: InputDecoration(labelText: l10n.titleLabel),
                  ),
            const SizedBox(height: 8),
            isMacOSNativeUI
                ? MacosTextField(
                    controller: _tagsController,
                    placeholder: l10n.tagsCommaSeparatedLabel,
                  )
                : TextField(
                    controller: _tagsController,
                    decoration: InputDecoration(
                      labelText: l10n.tagsCommaSeparatedLabel,
                    ),
                  ),
            const SizedBox(height: 8),
            MarkdownFormatToolbar(
              key: _kNoteDialogMarkdownToolbarKey,
              controller: _contentController,
              isMacOSNativeUI: isMacOSNativeUI,
              keyPrefix: 'note_dialog',
              formatter: _markdownFormatter,
              showImageAction: false,
            ),
            const SizedBox(height: 8),
            isMacOSNativeUI
                ? MacosTextField(
                    controller: _contentController,
                    minLines: 10,
                    maxLines: 20,
                    placeholder: l10n.markdownContentLabel,
                  )
                : TextField(
                    controller: _contentController,
                    minLines: 10,
                    maxLines: 20,
                    decoration: InputDecoration(
                      labelText: l10n.markdownContentLabel,
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
            const SizedBox(height: 8),
            isMacOSNativeUI
                ? Row(
                    children: <Widget>[
                      MacosSwitch(
                        value: _isPinned,
                        onChanged: (value) => setState(() => _isPinned = value),
                      ),
                      const SizedBox(width: 8),
                      Text(l10n.pinnedLabel),
                    ],
                  )
                : SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _isPinned,
                    onChanged: (value) => setState(() => _isPinned = value),
                    title: Text(l10n.pinnedLabel),
                  ),
          ],
        ),
      ),
    );

    void onSave() {
      final tags = _tagsController.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      Navigator.of(context).pop(
        _NoteDialogResult(
          title: _titleController.text.trim(),
          content: _contentController.text,
          tags: tags,
          isPinned: _isPinned,
        ),
      );
    }

    if (isMacOSNativeUI) {
      return MacosSheet(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              content,
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancelAction),
                  ),
                  const SizedBox(width: 8),
                  PushButton(
                    controlSize: ControlSize.large,
                    onPressed: onSave,
                    child: Text(
                      widget.mode == _NoteDialogMode.create
                          ? l10n.createAction
                          : l10n.saveAction,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(title),
      content: content,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: onSave,
          child: Text(
            widget.mode == _NoteDialogMode.create
                ? l10n.createAction
                : l10n.saveAction,
          ),
        ),
      ],
    );
  }
}

class _NoteDialogResult {
  const _NoteDialogResult({
    required this.title,
    required this.content,
    required this.tags,
    required this.isPinned,
  });

  final String title;
  final String content;
  final List<String> tags;
  final bool isPinned;
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

String _colorToHex(Color color) {
  final rgb = color.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

_MatterIconOption _matterIconOptionForKey(String iconKey) {
  for (final option in _kMatterIconOptions) {
    if (option.key == iconKey.trim()) {
      return option;
    }
  }
  return _kMatterIconOptions.first;
}

String _normalizeMatterIconKey(String iconKey) {
  return _matterIconOptionForKey(iconKey).key;
}

IconData _matterIconDataForKey(String iconKey) {
  return _matterIconOptionForKey(iconKey).iconData;
}

String _matterIconLabel(AppLocalizations l10n, String iconKey) {
  return switch (_normalizeMatterIconKey(iconKey)) {
    'description' => l10n.matterIconDescriptionLabel,
    'folder' => l10n.matterIconFolderLabel,
    'work' => l10n.matterIconWorkLabel,
    'gavel' => l10n.matterIconGavelLabel,
    'school' => l10n.matterIconSchoolLabel,
    'account_balance' => l10n.matterIconAccountBalanceLabel,
    'home' => l10n.matterIconHomeLabel,
    'build' => l10n.matterIconBuildLabel,
    'bolt' => l10n.matterIconBoltLabel,
    'assignment' => l10n.matterIconAssignmentLabel,
    'event' => l10n.matterIconEventLabel,
    'campaign' => l10n.matterIconCampaignLabel,
    'local_hospital' => l10n.matterIconLocalHospitalLabel,
    'science' => l10n.matterIconScienceLabel,
    'terminal' => l10n.matterIconTerminalLabel,
    _ => l10n.matterIconDescriptionLabel,
  };
}

String _matterStatusLabel(AppLocalizations l10n, MatterStatus status) {
  return switch (status) {
    MatterStatus.active => l10n.matterStatusActive,
    MatterStatus.paused => l10n.matterStatusPaused,
    MatterStatus.completed => l10n.matterStatusCompleted,
    MatterStatus.archived => l10n.matterStatusArchived,
  };
}

String _matterStatusBadgeLabel(AppLocalizations l10n, MatterStatus status) {
  return switch (status) {
    MatterStatus.active => l10n.matterStatusBadgeActive,
    MatterStatus.paused => l10n.matterStatusBadgePaused,
    MatterStatus.completed => l10n.matterStatusBadgeCompleted,
    MatterStatus.archived => l10n.matterStatusBadgeArchived,
  };
}

String _matterStatusBadgeLetter(AppLocalizations l10n, MatterStatus status) {
  return switch (status) {
    MatterStatus.active => l10n.matterStatusBadgeLetterActive,
    MatterStatus.paused => l10n.matterStatusBadgeLetterPaused,
    MatterStatus.completed => l10n.matterStatusBadgeLetterCompleted,
    MatterStatus.archived => l10n.matterStatusBadgeLetterArchived,
  };
}

String _syncTargetTypeLabel(SyncTargetType type, AppLocalizations l10n) {
  return switch (type) {
    SyncTargetType.none => l10n.syncTargetTypeNone,
    SyncTargetType.filesystem => l10n.syncTargetTypeFilesystem,
    SyncTargetType.webdav => l10n.syncTargetTypeWebdav,
  };
}
