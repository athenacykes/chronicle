import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:open_filex/open_filex.dart';

import '../../../app/app_providers.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/matter.dart';
import '../../../domain/entities/matter_sections.dart';
import '../../../domain/entities/note.dart';
import '../../../domain/entities/notebook_folder.dart';
import '../../../domain/entities/phase.dart';
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
import 'chronicle_entity_dialogs.dart';
import 'chronicle_graph_canvas.dart';
import 'chronicle_macos_widgets.dart';
import 'chronicle_note_editor_utilities.dart';
import 'chronicle_note_title_header.dart';
import 'chronicle_root_shell.dart';
import 'chronicle_search_results_view.dart';
import 'chronicle_sidebar_matter_actions.dart';
import 'chronicle_sidebar_sync_panel.dart';
import 'chronicle_settings_dialog.dart';
import 'chronicle_shell.dart';
import 'chronicle_shell_contract.dart';
import 'chronicle_top_bar_controls.dart';

part 'chronicle_home/helpers.dart';
part 'chronicle_home/sidebar.dart';
part 'chronicle_home/workspace.dart';
part 'chronicle_home/graph.dart';
part 'chronicle_home/editor.dart';

Future<void> showChronicleSettingsDialog({
  required BuildContext context,
  required bool useMacOSNativeUI,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ChronicleSettingsDialog(useMacOSNativeUI: useMacOSNativeUI),
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
      loading: () =>
          ChronicleLoadingShell(useMacOSNativeUI: widget.useMacOSNativeUI),
      error: (error, _) => ChronicleErrorShell(
        useMacOSNativeUI: widget.useMacOSNativeUI,
        message: l10n.failedToLoadSettings(error.toString()),
      ),
      data: (settings) {
        final root = settings.storageRootPath;
        if (root == null || root.isEmpty) {
          _searchIndexBuiltForRoot = null;
          return ChronicleStorageRootSetupScreen(
            useMacOSNativeUI: widget.useMacOSNativeUI,
            loadSuggestedDefaultPath: () async {
              return ref
                  .read(settingsControllerProvider.notifier)
                  .suggestedDefaultRootPath();
            },
            pickStorageRootPath: () async {
              await ref
                  .read(settingsControllerProvider.notifier)
                  .chooseAndSetStorageRoot();
              return ref
                  .read(settingsControllerProvider)
                  .asData
                  ?.value
                  .storageRootPath;
            },
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
        final matterViewMode = ref.watch(matterViewModeProvider);
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
        Widget? compactHamburgerContent;
        if (!showConflicts && !hasSearchResultsOpen) {
          if (showNotebook) {
            topBarContextActions = const ChronicleNotebookTopControls();
            compactHamburgerContent = _CompactPanelNotePicker(
              notesAsync: ref.watch(notebookNoteListProvider),
            );
          } else if (selectedMatter != null) {
            topBarContextActions = ChronicleMatterTopControls(
              matter: selectedMatter,
            );
            if (matterViewMode == MatterViewMode.phase) {
              compactHamburgerContent = _CompactPanelNotePicker(
                notesAsync: ref.watch(noteListProvider),
              );
            }
          }
        }

        Future<void> openSearchResult(String noteId) async {
          ref.read(searchResultsVisibleProvider.notifier).set(false);
          await ref
              .read(noteEditorControllerProvider.notifier)
              .openNoteInWorkspace(noteId, openInReadMode: true);
        }

        final content = searchState.when(
          loading: () => _MainWorkspace(
            searchHits: const <SearchListItem>[],
            searchQuery: searchQuery.text,
            showSearchResults: searchResultsVisible,
            onOpenSearchResult: openSearchResult,
          ),
          error: (error, stackTrace) => _MainWorkspace(
            searchHits: const <SearchListItem>[],
            searchQuery: searchQuery.text,
            showSearchResults: searchResultsVisible,
            onOpenSearchResult: openSearchResult,
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
              onOpenSearchResult: openSearchResult,
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
            compactHamburgerContent: compactHamburgerContent,
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
