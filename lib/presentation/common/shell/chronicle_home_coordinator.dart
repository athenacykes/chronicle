import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight/languages/markdown.dart' as highlight_markdown;
import 'package:intl/intl.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../../app/app_providers.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/matter.dart';
import '../../../domain/entities/matter_graph_data.dart';
import '../../../domain/entities/matter_graph_edge.dart';
import '../../../domain/entities/matter_graph_node.dart';
import '../../../domain/entities/matter_sections.dart';
import '../../../domain/entities/note.dart';
import '../../../domain/entities/phase.dart';
import '../../../domain/entities/sync_blocker.dart';
import '../../../domain/entities/sync_conflict.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/localization.dart';
import '../../links/graph_controller.dart';
import '../../links/links_controller.dart';
import '../../matters/matters_controller.dart';
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

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

        final mattersState = ref.watch(mattersControllerProvider);
        final searchState = ref.watch(searchControllerProvider);
        final conflictCount = ref.watch(conflictCountProvider);

        final content = searchState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => _MainWorkspace(
            searchHits: const <SearchListItem>[],
            searchQuery: _searchController.text,
          ),
          data: (hits) {
            final mapped = hits
                .map(
                  (hit) => SearchListItem(
                    noteId: hit.note.id,
                    title: hit.note.title,
                    snippet: hit.snippet,
                  ),
                )
                .toList();
            return _MainWorkspace(
              searchHits: mapped,
              searchQuery: _searchController.text,
            );
          },
        );

        return ChronicleShell(
          useMacOSNativeUI: widget.useMacOSNativeUI,
          viewModel: ChronicleShellViewModel(
            title: l10n.appTitle,
            searchController: _searchController,
            onSearchChanged: (value) =>
                ref.read(searchControllerProvider.notifier).setText(value),
            onShowConflicts: () {
              ref.read(showConflictsProvider.notifier).state = true;
              ref.read(showOrphansProvider.notifier).state = false;
            },
            onOpenSettings: () async {
              await _openSettingsDialog();
            },
            conflictCount: conflictCount,
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
                                  .valueOrNull;
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
                                  .valueOrNull;
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
    final l10n = context.l10n;
    final selectedMatterId = ref.watch(selectedMatterIdProvider);
    final showOrphans = ref.watch(showOrphansProvider);
    final showConflicts = ref.watch(showConflictsProvider);
    final conflictCount = ref.watch(conflictCountProvider);

    if (_isMacOSNativeUIContext(context)) {
      return _buildMacOSSidebar(
        context: context,
        ref: ref,
        selectedMatterId: selectedMatterId,
        showOrphans: showOrphans,
        showConflicts: showConflicts,
        conflictCount: conflictCount,
      );
    }

    return Column(
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
              ),
              _SectionHeader(
                title: l10n.activeSectionLabel(sections.active.length),
              ),
              _MatterList(
                matters: sections.active,
                selectedMatterId: selectedMatterId,
                onSelect: (matter) => _selectMatter(ref, matter),
                onAction: (matter, action) => _handleMatterAction(
                  context: context,
                  ref: ref,
                  matter: matter,
                  action: action,
                ),
              ),
              _SectionHeader(
                title: l10n.pausedSectionLabel(sections.paused.length),
              ),
              _MatterList(
                matters: sections.paused,
                selectedMatterId: selectedMatterId,
                onSelect: (matter) => _selectMatter(ref, matter),
                onAction: (matter, action) => _handleMatterAction(
                  context: context,
                  ref: ref,
                  matter: matter,
                  action: action,
                ),
              ),
              _SectionHeader(
                title: l10n.completedSectionLabel(sections.completed.length),
              ),
              _MatterList(
                matters: sections.completed,
                selectedMatterId: selectedMatterId,
                onSelect: (matter) => _selectMatter(ref, matter),
                onAction: (matter, action) => _handleMatterAction(
                  context: context,
                  ref: ref,
                  matter: matter,
                  action: action,
                ),
              ),
              _SectionHeader(
                title: l10n.archivedSectionLabel(sections.archived.length),
              ),
              _MatterList(
                matters: sections.archived,
                selectedMatterId: selectedMatterId,
                onSelect: (matter) => _selectMatter(ref, matter),
                onAction: (matter, action) => _handleMatterAction(
                  context: context,
                  ref: ref,
                  matter: matter,
                  action: action,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                selected: showOrphans,
                leading: const Icon(Icons.note_alt_outlined),
                title: Text(l10n.orphansLabel),
                onTap: () {
                  ref.read(showOrphansProvider.notifier).state = true;
                  ref.read(showConflictsProvider.notifier).state = false;
                  ref.read(selectedMatterIdProvider.notifier).state = null;
                  ref.read(selectedPhaseIdProvider.notifier).state = null;
                  ref.invalidate(noteListProvider);
                },
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
                  ref.read(showConflictsProvider.notifier).state = true;
                  ref.read(showOrphansProvider.notifier).state = false;
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
    required bool showOrphans,
    required bool showConflicts,
    required int conflictCount,
  }) {
    final l10n = context.l10n;
    final sidebarItems = <SidebarItem>[];
    final selectableEntries = <_MacSidebarSelectableEntry>[];

    void addSection(String label) {
      sidebarItems.add(
        SidebarItem(
          section: true,
          label: Text(
            label,
            style: MacosTheme.of(context).typography.caption1.copyWith(
              color: MacosColors.secondaryLabelColor,
            ),
          ),
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
            leading: _MatterLeadingIcon(
              iconKey: matter.icon,
              isPinned: matter.isPinned,
              isMacOS: true,
            ),
            label: Text(
              matter.title.trim().isEmpty
                  ? l10n.untitledMatterLabel
                  : matter.title,
              overflow: TextOverflow.ellipsis,
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

    addSection(l10n.activeSectionLabel(sections.active.length));
    addMatterItems(sections.active);

    addSection(l10n.pausedSectionLabel(sections.paused.length));
    addMatterItems(sections.paused);

    addSection(l10n.completedSectionLabel(sections.completed.length));
    addMatterItems(sections.completed);

    addSection(l10n.archivedSectionLabel(sections.archived.length));
    addMatterItems(sections.archived);

    addSection(l10n.viewsSectionLabel);
    selectableEntries.add(
      _MacSidebarSelectableEntry(
        key: 'orphans',
        onSelected: () {
          ref.read(showOrphansProvider.notifier).state = true;
          ref.read(showConflictsProvider.notifier).state = false;
          ref.read(selectedMatterIdProvider.notifier).state = null;
          ref.read(selectedPhaseIdProvider.notifier).state = null;
          ref.invalidate(noteListProvider);
        },
      ),
    );
    sidebarItems.add(
      SidebarItem(
        leading: const MacosIcon(CupertinoIcons.doc_text),
        label: Text(l10n.orphansLabel),
      ),
    );

    selectableEntries.add(
      _MacSidebarSelectableEntry(
        key: 'conflicts',
        onSelected: () {
          ref.read(showConflictsProvider.notifier).state = true;
          ref.read(showOrphansProvider.notifier).state = false;
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

    final selectedKey = showOrphans
        ? 'orphans'
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: PushButton(
            controlSize: ControlSize.large,
            onPressed: () => _createMatter(context: context, ref: ref),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const MacosIcon(CupertinoIcons.add, size: 14),
                const SizedBox(width: 6),
                Text(l10n.newMatterAction),
              ],
            ),
          ),
        ),
        Expanded(
          child: SidebarItems(
            scrollController: scrollController,
            items: sidebarItems,
            currentIndex: selectedIndex,
            onChanged: (index) => selectableEntries[index].onSelected(),
            itemSize: SidebarItemSize.medium,
          ),
        ),
        const Divider(height: 1),
        const _SidebarSyncPanel(),
      ],
    );
  }

  Future<void> _createMatter({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
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
    ref.read(showOrphansProvider.notifier).state = false;
    ref.read(showConflictsProvider.notifier).state = false;
    ref.read(selectedMatterIdProvider.notifier).state = matter.id;
    ref.read(selectedPhaseIdProvider.notifier).state =
        matter.currentPhaseId ??
        (matter.phases.isEmpty ? null : matter.phases.first.id);
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
    final settings = ref.watch(settingsControllerProvider).valueOrNull;
    final syncState = ref.watch(syncControllerProvider);
    final syncData = syncState.valueOrNull;
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
              style: MacosTheme.of(context).typography.caption2.copyWith(
                color: MacosColors.secondaryLabelColor,
              ),
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
    return MacosIconButton(
      icon: const MacosIcon(CupertinoIcons.ellipsis, size: 12),
      backgroundColor: MacosColors.transparent,
      boxConstraints: const BoxConstraints(
        minHeight: 18,
        minWidth: 18,
        maxHeight: 18,
        maxWidth: 18,
      ),
      padding: const EdgeInsets.all(3),
      onPressed: () async {
        final action = await showDialog<_MatterAction>(
          context: context,
          builder: (dialogContext) => MacosSheet(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    l10n.matterActionsTitle,
                    style: MacosTheme.of(dialogContext).typography.title3,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    matter.title,
                    style: MacosTheme.of(dialogContext).typography.subheadline,
                  ),
                  const SizedBox(height: 12),
                  _ActionSheetButton(
                    label: l10n.editAction,
                    action: _MatterAction.edit,
                  ),
                  _ActionSheetButton(
                    label: matter.isPinned ? l10n.unpinAction : l10n.pinAction,
                    action: _MatterAction.togglePinned,
                  ),
                  _ActionSheetButton(
                    label: l10n.setActiveAction,
                    action: _MatterAction.setActive,
                  ),
                  _ActionSheetButton(
                    label: l10n.setPausedAction,
                    action: _MatterAction.setPaused,
                  ),
                  _ActionSheetButton(
                    label: l10n.setCompletedAction,
                    action: _MatterAction.setCompleted,
                  ),
                  _ActionSheetButton(
                    label: l10n.setArchivedAction,
                    action: _MatterAction.setArchived,
                  ),
                  _ActionSheetButton(
                    label: l10n.deleteAction,
                    action: _MatterAction.delete,
                    destructive: true,
                  ),
                  const SizedBox(height: 8),
                  PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(l10n.cancelAction),
                  ),
                ],
              ),
            ),
          ),
        );
        if (action != null) {
          onSelected(action);
        }
      },
    );
  }
}

class _ActionSheetButton extends StatelessWidget {
  const _ActionSheetButton({
    required this.label,
    required this.action,
    this.destructive = false,
  });

  final String label;
  final _MatterAction action;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: PushButton(
        controlSize: ControlSize.regular,
        color: destructive ? MacosColors.systemRedColor : null,
        secondary: destructive ? null : true,
        onPressed: () => Navigator.of(context).pop(action),
        child: Align(alignment: Alignment.centerLeft, child: Text(label)),
      ),
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
  });

  final List<Matter> matters;
  final String? selectedMatterId;
  final void Function(Matter matter) onSelect;
  final Future<void> Function(Matter matter, _MatterAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (matters.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: matters
          .map(
            (matter) => ListTile(
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
            ),
          )
          .toList(),
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
    required this.snippet,
  });

  final String noteId;
  final String title;
  final String snippet;
}

const Key _kMacosMatterModeSegmentedKey = Key(
  'macos_matter_mode_segmented_control',
);
const Key _kMacosPhaseSegmentedKey = Key('macos_phase_segmented_control');
const Key _kMacosMatterNewNoteButtonKey = Key('macos_matter_new_note_button');
const Key _kMacosOrphanNewNoteButtonKey = Key('macos_orphan_new_note_button');
const Key _kMacosConflictsRefreshButtonKey = Key('macos_conflicts_refresh');
const Key _kMacosNoteEditorTitleFieldKey = Key('macos_note_editor_title');
const Key _kMacosNoteEditorTagsFieldKey = Key('macos_note_editor_tags');
const Key _kMacosNoteEditorContentFieldKey = Key('macos_note_editor_content');
const Key _kMacosNoteEditorSaveButtonKey = Key('macos_note_editor_save');
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

TextStyle _macosSectionTitleStyle(BuildContext context) {
  return MacosTheme.of(
    context,
  ).typography.title3.copyWith(fontWeight: MacosFontWeight.w590);
}

class _MacosCompactIconButton extends StatelessWidget {
  const _MacosCompactIconButton({
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
                      style: typography.caption1.copyWith(
                        color: MacosColors.secondaryLabelColor,
                      ),
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

class _MacosMatterViewModeControl extends StatefulWidget {
  const _MacosMatterViewModeControl({
    required this.selected,
    required this.onChanged,
  });

  final MatterViewMode selected;
  final ValueChanged<MatterViewMode> onChanged;

  @override
  State<_MacosMatterViewModeControl> createState() =>
      _MacosMatterViewModeControlState();
}

class _MacosMatterViewModeControlState
    extends State<_MacosMatterViewModeControl> {
  late final MacosTabController _controller;
  bool _isSyncingController = false;

  @override
  void initState() {
    super.initState();
    _controller = MacosTabController(
      initialIndex: _matterViewModes.indexOf(widget.selected),
      length: _matterViewModes.length,
    )..addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _MacosMatterViewModeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedIndex = _matterViewModes.indexOf(widget.selected);
    if (selectedIndex != _controller.index) {
      _isSyncingController = true;
      try {
        _controller.index = selectedIndex;
      } finally {
        _isSyncingController = false;
      }
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (_isSyncingController) {
      return;
    }
    widget.onChanged(_matterViewModes[_controller.index]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KeyedSubtree(
      key: _kMacosMatterModeSegmentedKey,
      child: MacosSegmentedControl(
        tabs: <MacosTab>[
          MacosTab(label: l10n.viewModePhase),
          MacosTab(label: l10n.viewModeTimeline),
          MacosTab(label: l10n.viewModeGraph),
        ],
        controller: _controller,
      ),
    );
  }
}

class _MacosPhaseControl extends StatefulWidget {
  const _MacosPhaseControl({
    required this.phases,
    required this.selectedPhaseId,
    required this.allPhasesLabel,
    required this.onSelected,
  });

  final List<Phase> phases;
  final String? selectedPhaseId;
  final String allPhasesLabel;
  final ValueChanged<String?> onSelected;

  @override
  State<_MacosPhaseControl> createState() => _MacosPhaseControlState();
}

class _MacosPhaseControlState extends State<_MacosPhaseControl> {
  MacosTabController? _controller;
  bool _isSyncingController = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex();
    final entries = <(String?, String)>[
      (null, widget.allPhasesLabel),
      ...widget.phases.map((phase) => (phase.id, phase.name)),
    ];
    if (entries.length > 5) {
      return SizedBox(
        width: 240,
        child: MacosPopupButton<String>(
          value: entries[selectedIndex].$1 ?? '__all_phases__',
          onChanged: (value) {
            if (value == null) {
              return;
            }
            widget.onSelected(value == '__all_phases__' ? null : value);
          },
          items: entries
              .map(
                (entry) => MacosPopupMenuItem<String>(
                  value: entry.$1 ?? '__all_phases__',
                  child: Text(entry.$2),
                ),
              )
              .toList(),
        ),
      );
    }

    final needRebuild =
        _controller == null || _controller!.length != entries.length;
    if (needRebuild) {
      _controller?.dispose();
      _controller = MacosTabController(
        initialIndex: selectedIndex,
        length: entries.length,
      )..addListener(_onControllerChanged);
    } else if (_controller!.index != selectedIndex) {
      _isSyncingController = true;
      try {
        _controller!.index = selectedIndex;
      } finally {
        _isSyncingController = false;
      }
    }

    return KeyedSubtree(
      key: _kMacosPhaseSegmentedKey,
      child: MacosSegmentedControl(
        tabs: entries
            .map((entry) => MacosTab(label: entry.$2))
            .toList(growable: false),
        controller: _controller!,
      ),
    );
  }

  int _selectedIndex() {
    if (widget.selectedPhaseId == null || widget.selectedPhaseId!.isEmpty) {
      return 0;
    }
    final index = widget.phases.indexWhere(
      (phase) => phase.id == widget.selectedPhaseId,
    );
    if (index < 0) {
      return 0;
    }
    return index + 1;
  }

  void _onControllerChanged() {
    if (_isSyncingController) {
      return;
    }
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (controller.index == 0) {
      widget.onSelected(null);
      return;
    }
    widget.onSelected(widget.phases[controller.index - 1].id);
  }
}

const List<MatterViewMode> _matterViewModes = <MatterViewMode>[
  MatterViewMode.phase,
  MatterViewMode.timeline,
  MatterViewMode.graph,
];

class _MainWorkspace extends ConsumerWidget {
  const _MainWorkspace({required this.searchHits, required this.searchQuery});

  final List<SearchListItem> searchHits;
  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final showConflicts = ref.watch(showConflictsProvider);
    if (showConflicts) {
      return const _ConflictWorkspace();
    }

    if (searchQuery.trim().isNotEmpty) {
      return _SearchResultsView(results: searchHits);
    }

    final showOrphans = ref.watch(showOrphansProvider);
    if (showOrphans) {
      return const _OrphanWorkspace();
    }

    final sections = ref.watch(mattersControllerProvider).valueOrNull;
    final selectedMatterId = ref.watch(selectedMatterIdProvider);
    if (sections == null || selectedMatterId == null) {
      return Center(child: Text(l10n.selectMatterOrphansOrConflictsPrompt));
    }

    Matter? selected;
    final all = <Matter>{
      ...sections.pinned,
      ...sections.active,
      ...sections.paused,
      ...sections.completed,
      ...sections.archived,
    };
    for (final matter in all) {
      if (matter.id == selectedMatterId) {
        selected = matter;
        break;
      }
    }

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
                                                            .state =
                                                        false;
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
                                                            .state =
                                                        false;
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
                                            ? Markdown(data: content)
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
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final viewMode = ref.watch(matterViewModeProvider);
    final selectedPhaseId = ref.watch(selectedPhaseIdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      matter.title,
                      style: isMacOSNativeUI
                          ? MacosTheme.of(context).typography.largeTitle
                          : Theme.of(context).textTheme.titleLarge,
                    ),
                    if (matter.description.trim().isNotEmpty)
                      Text(
                        matter.description,
                        style: isMacOSNativeUI
                            ? MacosTheme.of(
                                context,
                              ).typography.subheadline.copyWith(
                                color: MacosColors.secondaryLabelColor,
                              )
                            : null,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              isMacOSNativeUI
                  ? _MacosMatterViewModeControl(
                      selected: viewMode,
                      onChanged: (selectedMode) {
                        ref.read(matterViewModeProvider.notifier).state =
                            selectedMode;
                        if (selectedMode == MatterViewMode.graph) {
                          ref.invalidate(graphControllerProvider);
                        } else {
                          ref.invalidate(noteListProvider);
                        }
                      },
                    )
                  : SegmentedButton<MatterViewMode>(
                      segments: <ButtonSegment<MatterViewMode>>[
                        ButtonSegment<MatterViewMode>(
                          value: MatterViewMode.phase,
                          label: Text(l10n.viewModePhase),
                        ),
                        ButtonSegment<MatterViewMode>(
                          value: MatterViewMode.timeline,
                          label: Text(l10n.viewModeTimeline),
                        ),
                        ButtonSegment<MatterViewMode>(
                          value: MatterViewMode.graph,
                          label: Text(l10n.viewModeGraph),
                        ),
                      ],
                      selected: <MatterViewMode>{viewMode},
                      onSelectionChanged: (selection) {
                        final selectedMode = selection.first;
                        ref.read(matterViewModeProvider.notifier).state =
                            selectedMode;
                        if (selectedMode == MatterViewMode.graph) {
                          ref.invalidate(graphControllerProvider);
                        } else {
                          ref.invalidate(noteListProvider);
                        }
                      },
                    ),
              const Spacer(),
              isMacOSNativeUI
                  ? PushButton(
                      key: _kMacosMatterNewNoteButtonKey,
                      controlSize: ControlSize.large,
                      onPressed: () async {
                        await ref
                            .read(noteEditorControllerProvider.notifier)
                            .createNoteForSelectedMatter();
                        ref.read(noteEditorViewModeProvider.notifier).state =
                            NoteEditorViewMode.edit;
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const MacosIcon(CupertinoIcons.add, size: 13),
                          const SizedBox(width: 6),
                          Text(l10n.newNoteAction),
                        ],
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: () async {
                        await ref
                            .read(noteEditorControllerProvider.notifier)
                            .createNoteForSelectedMatter();
                        ref.read(noteEditorViewModeProvider.notifier).state =
                            NoteEditorViewMode.edit;
                      },
                      icon: const Icon(Icons.note_add),
                      label: Text(l10n.newNoteAction),
                    ),
            ],
          ),
        ),
        if (viewMode == MatterViewMode.phase)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: isMacOSNativeUI
                      ? _MacosPhaseControl(
                          phases: matter.phases,
                          selectedPhaseId: selectedPhaseId,
                          allPhasesLabel: 'All Phases',
                          onSelected: (phaseId) {
                            ref.read(selectedPhaseIdProvider.notifier).state =
                                phaseId;
                            if (phaseId != null && phaseId.isNotEmpty) {
                              unawaited(
                                ref
                                    .read(mattersControllerProvider.notifier)
                                    .setMatterCurrentPhase(
                                      matter: matter,
                                      phaseId: phaseId,
                                    ),
                              );
                            }
                            ref.invalidate(noteListProvider);
                          },
                        )
                      : Wrap(
                          spacing: 8,
                          children: <Widget>[
                            ChoiceChip(
                              label: const Text('All Phases'),
                              selected:
                                  selectedPhaseId == null ||
                                  selectedPhaseId.isEmpty,
                              onSelected: (_) {
                                ref
                                        .read(selectedPhaseIdProvider.notifier)
                                        .state =
                                    null;
                                ref.invalidate(noteListProvider);
                              },
                            ),
                            ...matter.phases.map(
                              (phase) => ChoiceChip(
                                label: Text(phase.name),
                                selected: selectedPhaseId == phase.id,
                                onSelected: (_) {
                                  ref
                                      .read(selectedPhaseIdProvider.notifier)
                                      .state = phase
                                      .id;
                                  unawaited(
                                    ref
                                        .read(
                                          mattersControllerProvider.notifier,
                                        )
                                        .setMatterCurrentPhase(
                                          matter: matter,
                                          phaseId: phase.id,
                                        ),
                                  );
                                  ref.invalidate(noteListProvider);
                                },
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 8),
                isMacOSNativeUI
                    ? PushButton(
                        controlSize: ControlSize.regular,
                        secondary: true,
                        onPressed: () async {
                          await showDialog<void>(
                            context: context,
                            builder: (_) =>
                                _ManagePhasesDialog(matterId: matter.id),
                          );
                        },
                        child: const Text('Manage Phases'),
                      )
                    : OutlinedButton(
                        onPressed: () async {
                          await showDialog<void>(
                            context: context,
                            builder: (_) =>
                                _ManagePhasesDialog(matterId: matter.id),
                          );
                        },
                        child: const Text('Manage Phases'),
                      ),
              ],
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
  final showOrphansNotifier = ref.read(showOrphansProvider.notifier);
  final showConflictsNotifier = ref.read(showConflictsProvider.notifier);
  final selectedMatterNotifier = ref.read(selectedMatterIdProvider.notifier);
  final selectedPhaseNotifier = ref.read(selectedPhaseIdProvider.notifier);
  final matterViewModeNotifier = ref.read(matterViewModeProvider.notifier);
  final mattersNotifier = ref.read(mattersControllerProvider.notifier);
  final noteEditorNotifier = ref.read(noteEditorControllerProvider.notifier);

  showOrphansNotifier.state = false;
  showConflictsNotifier.state = false;
  selectedMatterNotifier.state = note.matterId;
  selectedPhaseNotifier.state = note.phaseId;
  matterViewModeNotifier.state = MatterViewMode.phase;
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: isMacOSNativeUI
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
                  ),
                ],
              ),
            );

            return card;
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

class _GraphCanvas extends StatelessWidget {
  const _GraphCanvas({
    required this.graph,
    required this.selectedNoteId,
    required this.onTapNode,
  });

  final MatterGraphData graph;
  final String? selectedNoteId;
  final Future<void> Function(String noteId) onTapNode;

  @override
  Widget build(BuildContext context) {
    final layout = _deterministicGraphLayout(graph);
    final theme = Theme.of(context);

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

                return Positioned(
                  left: offset.dx - radius,
                  top: offset.dy - radius,
                  child: Tooltip(
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

class _OrphanWorkspace extends ConsumerWidget {
  const _OrphanWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final notes = ref.watch(orphanNotesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Text(
                l10n.orphanNotesTitle,
                style: isMacOSNativeUI
                    ? _macosSectionTitleStyle(context)
                    : Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              isMacOSNativeUI
                  ? PushButton(
                      key: _kMacosOrphanNewNoteButtonKey,
                      controlSize: ControlSize.large,
                      onPressed: () async {
                        await ref
                            .read(noteEditorControllerProvider.notifier)
                            .createUntitledOrphanNote();
                        ref.read(noteEditorViewModeProvider.notifier).state =
                            NoteEditorViewMode.edit;
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const MacosIcon(CupertinoIcons.add, size: 13),
                          const SizedBox(width: 6),
                          Text(l10n.newOrphanNoteAction),
                        ],
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: () async {
                        await ref
                            .read(noteEditorControllerProvider.notifier)
                            .createUntitledOrphanNote();
                        ref.read(noteEditorViewModeProvider.notifier).state =
                            NoteEditorViewMode.edit;
                      },
                      icon: const Icon(Icons.add),
                      label: Text(l10n.newOrphanNoteAction),
                    ),
            ],
          ),
        ),
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
  });

  final List<Note> notes;
  final Future<void> Function(Note note) onEdit;
  final Future<void> Function(Note note) onTogglePinned;
  final Future<void> Function(Note note) onDelete;
  final Future<void> Function(Note note) onLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final selectedNoteId = ref.watch(selectedNoteIdProvider);
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
          return _MacosSelectableRow(
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
        },
      );
    }

    return ListView.builder(
      itemCount: notes.length,
      itemBuilder: (_, index) {
        final note = notes[index];
        return ListTile(
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
                case 'toggle_pin':
                  await onTogglePinned(note);
                case 'link':
                  await onLink(note);
                case 'delete':
                  await onDelete(note);
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
  String? _loadedNoteId;

  @override
  void initState() {
    super.initState();
    _contentController = CodeController(
      language: highlight_markdown.markdown,
      text: '',
    );
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
    final selectedMatterId = ref.watch(selectedMatterIdProvider);
    final selectedPhaseId = ref.watch(selectedPhaseIdProvider);
    final storageRootPath = ref
        .watch(settingsControllerProvider)
        .valueOrNull
        ?.storageRootPath;

    return noteAsync.when(
      loading: () => Center(child: _adaptiveLoadingIndicator(context)),
      error: (error, _) =>
          Center(child: Text(l10n.editorError(error.toString()))),
      data: (note) {
        if (note == null) {
          return Center(child: Text(l10n.selectNoteToEditPrompt));
        }
        final linkedNotesAsync = ref.watch(linkedNotesByNoteProvider(note.id));

        if (_loadedNoteId != note.id) {
          _loadedNoteId = note.id;
          _titleController.text = note.title;
          _contentController.text = note.content;
          _tagsController.text = note.tags.join(', ');
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
          ref.read(noteEditorViewModeProvider.notifier).state = mode;
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
          final tagsController = TextEditingController(
            text: _tagsController.text,
          );
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

        Future<void> moveToOrphans() async {
          await ref
              .read(noteEditorControllerProvider.notifier)
              .moveCurrent(matterId: null, phaseId: null);
          ref.read(showOrphansProvider.notifier).state = true;
          ref.read(showConflictsProvider.notifier).state = false;
        }

        Future<void> assignToSelectedMatter() async {
          if (selectedMatterId == null || selectedPhaseId == null) {
            return;
          }
          await ref
              .read(noteEditorControllerProvider.notifier)
              .moveCurrent(
                matterId: selectedMatterId,
                phaseId: selectedPhaseId,
              );
          ref.read(showOrphansProvider.notifier).state = false;
        }

        final titleField = isMacOSNativeUI
            ? MacosTextField(
                key: _kMacosNoteEditorTitleFieldKey,
                controller: _titleController,
                placeholder: l10n.titleLabel,
              )
            : TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: l10n.titleLabel,
                  border: const OutlineInputBorder(),
                ),
              );

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: titleField),
                  const SizedBox(width: 8),
                  isMacOSNativeUI
                      ? PushButton(
                          key: _kMacosNoteEditorSaveButtonKey,
                          controlSize: ControlSize.regular,
                          onPressed: saveNote,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const MacosIcon(
                                CupertinoIcons.floppy_disk,
                                size: 13,
                              ),
                              const SizedBox(width: 6),
                              Text(l10n.saveAction),
                            ],
                          ),
                        )
                      : FilledButton.icon(
                          key: _kMacosNoteEditorSaveButtonKey,
                          onPressed: saveNote,
                          icon: const Icon(Icons.save),
                          label: Text(l10n.saveAction),
                        ),
                  const SizedBox(width: 4),
                  isMacOSNativeUI
                      ? _MacosCompactIconButton(
                          tooltip: note.isPinned
                              ? l10n.unpinAction
                              : l10n.pinAction,
                          onPressed: () async {
                            await ref
                                .read(noteEditorControllerProvider.notifier)
                                .updateCurrent(isPinned: !note.isPinned);
                          },
                          icon: MacosIcon(
                            note.isPinned
                                ? CupertinoIcons.pin_fill
                                : CupertinoIcons.pin,
                          ),
                        )
                      : IconButton(
                          tooltip: note.isPinned
                              ? l10n.unpinAction
                              : l10n.pinAction,
                          onPressed: () async {
                            await ref
                                .read(noteEditorControllerProvider.notifier)
                                .updateCurrent(isPinned: !note.isPinned);
                          },
                          icon: Icon(
                            note.isPinned
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                          ),
                        ),
                  isMacOSNativeUI
                      ? SizedBox(
                          width: 130,
                          child:
                              CupertinoSlidingSegmentedControl<
                                NoteEditorViewMode
                              >(
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
                        ),
                  isMacOSNativeUI
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
                        ),
                  isMacOSNativeUI
                      ? MacosPulldownButton(
                          icon: CupertinoIcons.ellipsis_circle,
                          items: <MacosPulldownMenuEntry>[
                            MacosPulldownMenuItem(
                              title: Text(l10n.moveToOrphansAction),
                              onTap: () {
                                unawaited(moveToOrphans());
                              },
                            ),
                            MacosPulldownMenuItem(
                              title: Text(l10n.assignToSelectedMatterAction),
                              onTap: () {
                                unawaited(assignToSelectedMatter());
                              },
                            ),
                          ],
                        )
                      : PopupMenuButton<String>(
                          tooltip: l10n.noteMoreActionsTooltip,
                          icon: const Icon(Icons.more_horiz),
                          onSelected: (value) async {
                            switch (value) {
                              case 'move_orphans':
                                await moveToOrphans();
                              case 'assign_selected':
                                await assignToSelectedMatter();
                            }
                          },
                          itemBuilder: (_) => <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'move_orphans',
                              child: Text(l10n.moveToOrphansAction),
                            ),
                            PopupMenuItem<String>(
                              value: 'assign_selected',
                              enabled:
                                  selectedMatterId != null &&
                                  selectedPhaseId != null,
                              child: Text(l10n.assignToSelectedMatterAction),
                            ),
                          ],
                        ),
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
                        child: Markdown(data: _contentController.text),
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
                        child: CodeField(
                          key: _kMacosNoteEditorContentFieldKey,
                          controller: _contentController,
                          textStyle: TextStyle(
                            fontFamily: isMacOSNativeUI ? 'Menlo' : 'monospace',
                            fontSize: 13,
                          ),
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
                                const MacosIcon(
                                  CupertinoIcons.paperclip,
                                  size: 12,
                                ),
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
                                  '${l10n.noteLinkedNotesUtilityTitle} (${linkedNotesAsync.valueOrNull?.length ?? 0})',
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
                              '${l10n.noteLinkedNotesUtilityTitle} (${linkedNotesAsync.valueOrNull?.length ?? 0})',
                            ),
                          ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
    final linkedCount = linkedNotesAsync.valueOrNull?.length ?? 0;
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
      return '$title [${l10n.orphanLabel}]';
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
              result.snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const MacosIcon(
              CupertinoIcons.arrow_up_right_square,
              size: 14,
            ),
            onTap: () async {
              await ref
                  .read(noteEditorControllerProvider.notifier)
                  .openNoteInWorkspace(result.noteId);
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
          subtitle: Text(result.snippet),
          onTap: () async {
            await ref
                .read(noteEditorControllerProvider.notifier)
                .openNoteInWorkspace(result.noteId);
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
    final settings = ref.read(settingsControllerProvider).valueOrNull;
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
          .valueOrNull
          ?.syncConfig
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
    final sections = ref.watch(mattersControllerProvider).valueOrNull;
    Matter? matter;
    if (sections != null) {
      final all = <Matter>{
        ...sections.pinned,
        ...sections.active,
        ...sections.paused,
        ...sections.completed,
        ...sections.archived,
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
