import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/enums.dart';
import '../../domain/entities/matter.dart';
import '../../domain/entities/matter_graph_data.dart';
import '../../domain/entities/matter_graph_edge.dart';
import '../../domain/entities/matter_graph_node.dart';
import '../../domain/entities/matter_sections.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/sync_conflict.dart';
import '../links/graph_controller.dart';
import '../links/links_controller.dart';
import '../matters/matters_controller.dart';
import '../notes/notes_controller.dart';
import '../search/search_controller.dart';
import '../settings/settings_controller.dart';
import '../sync/conflicts_controller.dart';
import '../sync/sync_controller.dart';

class ChronicleHomeScreen extends ConsumerStatefulWidget {
  const ChronicleHomeScreen({super.key});

  @override
  ConsumerState<ChronicleHomeScreen> createState() =>
      _ChronicleHomeScreenState();
}

class _ChronicleHomeScreenState extends ConsumerState<ChronicleHomeScreen> {
  late final TextEditingController _searchController;

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

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(settingsControllerProvider);

    return settingsState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Failed to load settings: $error')),
      ),
      data: (settings) {
        final root = settings.storageRootPath;
        if (root == null || root.isEmpty) {
          return _StorageRootSetupScreen(
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
        final syncState = ref.watch(syncControllerProvider);
        final searchState = ref.watch(searchControllerProvider);
        final conflictCount = ref.watch(conflictCountProvider);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Chronicle'),
            actions: <Widget>[
              SizedBox(
                width: 340,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => ref
                        .read(searchControllerProvider.notifier)
                        .setText(value),
                    decoration: const InputDecoration(
                      hintText: 'Search notes...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Conflicts',
                onPressed: () {
                  ref.read(showConflictsProvider.notifier).state = true;
                  ref.read(showOrphansProvider.notifier).state = false;
                },
                icon: Badge(
                  isLabelVisible: conflictCount > 0,
                  label: Text('$conflictCount'),
                  child: const Icon(Icons.report_problem_outlined),
                ),
              ),
              IconButton(
                tooltip: 'Sync now',
                onPressed: () async {
                  await ref.read(syncControllerProvider.notifier).runSyncNow();
                  await ref.read(settingsControllerProvider.notifier).refresh();
                },
                icon: const Icon(Icons.sync),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () async {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => const _SettingsDialog(),
                  );
                },
                icon: const Icon(Icons.settings),
              ),
            ],
          ),
          body: Row(
            children: <Widget>[
              SizedBox(
                width: 320,
                child: mattersState.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(child: Text('$error')),
                  data: (sections) => _MatterSidebar(sections: sections),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: searchState.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
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
                ),
              ),
            ],
          ),
          bottomNavigationBar: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: syncState.when(
              loading: () => const Text('Sync: working...'),
              error: (error, _) => Text('Sync error: $error'),
              data: (sync) {
                final lastSyncLabel = settings.lastSyncAt == null
                    ? 'never'
                    : settings.lastSyncAt!.toLocal().toString();
                return Text(
                  'Status: ${sync.lastMessage} | Last sync: $lastSyncLabel',
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _StorageRootSetupScreen extends ConsumerStatefulWidget {
  const _StorageRootSetupScreen({required this.onConfirm});

  final Future<void> Function(String path) onConfirm;

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
    if (_loadingDefault) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 520,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Set up Chronicle storage',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Choose where Chronicle stores markdown/json files. '
                    'Default is ~/Chronicle.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: 'Storage root path',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      FilledButton(
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
                        child: const Text('Pick Folder'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () async {
                          await widget.onConfirm(_controller.text.trim());
                        },
                        child: const Text('Continue'),
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
}

class _MatterSidebar extends ConsumerWidget {
  const _MatterSidebar({required this.sections});

  final MatterSections sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMatterId = ref.watch(selectedMatterIdProvider);
    final showOrphans = ref.watch(showOrphansProvider);
    final showConflicts = ref.watch(showConflictsProvider);
    final conflictCount = ref.watch(conflictCountProvider);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        FilledButton.icon(
          onPressed: () async {
            final result = await showDialog<_MatterDialogResult>(
              context: context,
              builder: (_) =>
                  const _MatterDialog(mode: _MatterDialogMode.create),
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
          },
          icon: const Icon(Icons.add),
          label: const Text('New Matter'),
        ),
        const SizedBox(height: 12),
        _SectionHeader(title: 'Pinned'),
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
        _SectionHeader(title: 'Active (${sections.active.length})'),
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
        _SectionHeader(title: 'Paused (${sections.paused.length})'),
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
        _SectionHeader(title: 'Completed (${sections.completed.length})'),
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
        _SectionHeader(title: 'Archived (${sections.archived.length})'),
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
          title: const Text('Orphans'),
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
          title: const Text('Conflicts'),
          onTap: () {
            ref.read(showConflictsProvider.notifier).state = true;
            ref.read(showOrphansProvider.notifier).state = false;
          },
        ),
      ],
    );
  }

  Future<void> _handleMatterAction({
    required BuildContext context,
    required WidgetRef ref,
    required Matter matter,
    required _MatterAction action,
  }) async {
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
          builder: (_) => AlertDialog(
            title: const Text('Delete Matter'),
            content: Text(
              'Delete "${matter.title}" and all notes in this matter?',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
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
    if (matter.phases.isNotEmpty) {
      ref.read(selectedPhaseIdProvider.notifier).state = matter.phases.first.id;
    }
    ref.invalidate(noteListProvider);
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
    if (matters.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: matters
          .map(
            (matter) => ListTile(
              dense: true,
              selected: selectedMatterId == matter.id,
              leading: Icon(
                matter.isPinned ? Icons.push_pin : Icons.folder_open,
                size: 18,
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
                  const PopupMenuItem<_MatterAction>(
                    value: _MatterAction.edit,
                    child: Text('Edit'),
                  ),
                  PopupMenuItem<_MatterAction>(
                    value: _MatterAction.togglePinned,
                    child: Text(matter.isPinned ? 'Unpin' : 'Pin'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<_MatterAction>(
                    value: _MatterAction.setActive,
                    child: Text('Set Active'),
                  ),
                  const PopupMenuItem<_MatterAction>(
                    value: _MatterAction.setPaused,
                    child: Text('Set Paused'),
                  ),
                  const PopupMenuItem<_MatterAction>(
                    value: _MatterAction.setCompleted,
                    child: Text('Set Completed'),
                  ),
                  const PopupMenuItem<_MatterAction>(
                    value: _MatterAction.setArchived,
                    child: Text('Set Archived'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<_MatterAction>(
                    value: _MatterAction.delete,
                    child: Text('Delete'),
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
    final label = switch (status) {
      MatterStatus.active => 'ACTIVE',
      MatterStatus.paused => 'PAUSED',
      MatterStatus.completed => 'DONE',
      MatterStatus.archived => 'ARCHIVED',
    };

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

class _MainWorkspace extends ConsumerWidget {
  const _MainWorkspace({required this.searchHits, required this.searchQuery});

  final List<SearchListItem> searchHits;
  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      return const Center(
        child: Text('Select a Matter, Orphans, or Conflicts to begin.'),
      );
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
      return const Center(child: Text('Matter no longer exists.'));
    }

    return _MatterWorkspace(matter: selected);
  }
}

class _ConflictWorkspace extends ConsumerWidget {
  const _ConflictWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflictsState = ref.watch(conflictsControllerProvider);
    final selected = ref.watch(selectedConflictProvider);
    final selectedContent = ref.watch(selectedConflictContentProvider);

    return conflictsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          Center(child: Text('Conflict load failed: $error')),
      data: (conflicts) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  Text(
                    'Conflicts (${conflicts.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await ref
                          .read(conflictsControllerProvider.notifier)
                          .reload();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
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
                        ? const Center(child: Text('No conflicts detected.'))
                        : ListView.builder(
                            itemCount: conflicts.length,
                            itemBuilder: (_, index) {
                              final conflict = conflicts[index];
                              final isSelected =
                                  selected?.conflictPath ==
                                  conflict.conflictPath;
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
                        ? const Center(
                            child: Text('Select a conflict to review.'),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  selected.title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Type: ${_conflictTypeLabel(selected.type)}',
                                ),
                                Text('Conflict file: ${selected.conflictPath}'),
                                Text('Original: ${selected.originalPath}'),
                                Text('Local: ${selected.localDevice}'),
                                Text('Remote: ${selected.remoteDevice}'),
                                const SizedBox(height: 8),
                                Row(
                                  children: <Widget>[
                                    OutlinedButton.icon(
                                      onPressed: selected.originalNoteId == null
                                          ? null
                                          : () async {
                                              await ref
                                                  .read(
                                                    noteEditorControllerProvider
                                                        .notifier,
                                                  )
                                                  .openNoteInWorkspace(
                                                    selected.originalNoteId!,
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
                                      label: const Text('Open Main Note'),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton.icon(
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
                                      label: const Text('Mark Resolved'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: selectedContent.when(
                                    loading: () => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                    error: (error, stackTrace) =>
                                        Text('Failed to load conflict: $error'),
                                    data: (content) {
                                      if (content == null ||
                                          content.trim().isEmpty) {
                                        return const Text(
                                          'Conflict content is empty.',
                                        );
                                      }
                                      return Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Theme.of(
                                              context,
                                            ).dividerColor,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (matter.description.trim().isNotEmpty)
                      Text(
                        matter.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SegmentedButton<MatterViewMode>(
                segments: const <ButtonSegment<MatterViewMode>>[
                  ButtonSegment<MatterViewMode>(
                    value: MatterViewMode.phase,
                    label: Text('Phase'),
                  ),
                  ButtonSegment<MatterViewMode>(
                    value: MatterViewMode.timeline,
                    label: Text('Timeline'),
                  ),
                  ButtonSegment<MatterViewMode>(
                    value: MatterViewMode.list,
                    label: Text('List'),
                  ),
                  ButtonSegment<MatterViewMode>(
                    value: MatterViewMode.graph,
                    label: Text('Graph'),
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
              FilledButton.icon(
                onPressed: () async {
                  final result = await showDialog<_NoteDialogResult>(
                    context: context,
                    builder: (_) =>
                        const _NoteDialog(mode: _NoteDialogMode.create),
                  );

                  if (result == null || result.title.trim().isEmpty) {
                    return;
                  }

                  await ref
                      .read(noteEditorControllerProvider.notifier)
                      .createCustomNote(
                        title: result.title,
                        content: result.content,
                        tags: result.tags,
                        isPinned: result.isPinned,
                        matterId: matter.id,
                        phaseId:
                            selectedPhaseId ??
                            (matter.phases.isEmpty
                                ? null
                                : matter.phases.first.id),
                      );
                },
                icon: const Icon(Icons.note_add),
                label: const Text('New Note'),
              ),
            ],
          ),
        ),
        if (viewMode == MatterViewMode.phase)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: matter.phases
                  .map(
                    (phase) => ChoiceChip(
                      label: Text(phase.name),
                      selected: selectedPhaseId == phase.id,
                      onSelected: (_) {
                        ref.read(selectedPhaseIdProvider.notifier).state =
                            phase.id;
                        ref.invalidate(noteListProvider);
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: viewMode == MatterViewMode.graph
              ? const _MatterGraphWorkspace()
              : const _MatterNotesWorkspace(),
        ),
      ],
    );
  }
}

class _MatterNotesWorkspace extends ConsumerWidget {
  const _MatterNotesWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(noteListProvider);

    return Row(
      children: <Widget>[
        SizedBox(
          width: 380,
          child: notes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
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
                    title: const Text('Delete note'),
                    content: Text('Delete "${note.title}"?'),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Delete'),
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

class _MatterGraphWorkspace extends ConsumerWidget {
  const _MatterGraphWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graphState = ref.watch(graphControllerProvider);
    final selectedNoteId = ref.watch(selectedNoteIdProvider);

    return graphState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Graph load failed: $error')),
      data: (view) {
        if (view.graph.nodes.isEmpty) {
          return const Center(
            child: Text(
              'No linked notes yet in this matter.\nCreate links from note actions to populate the graph.',
              textAlign: TextAlign.center,
            ),
          );
        }

        return Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (view.isTruncated)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Graph limited to $graphNodeLimit nodes '
                        '(${view.truncatedNodeCount} hidden).',
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: _GraphCanvas(
                        graph: view.graph,
                        selectedNoteId: selectedNoteId,
                        onTapNode: (noteId) async {
                          await ref
                              .read(noteEditorControllerProvider.notifier)
                              .selectNote(noteId);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            const SizedBox(width: 480, child: _NoteEditorPane()),
          ],
        );
      },
    );
  }
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
                    message: node.title.isEmpty ? '(untitled)' : node.title,
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
    final notes = ref.watch(orphanNotesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Text(
                'Orphan Notes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () async {
                  final result = await showDialog<_NoteDialogResult>(
                    context: context,
                    builder: (_) =>
                        const _NoteDialog(mode: _NoteDialogMode.create),
                  );

                  if (result == null || result.title.trim().isEmpty) {
                    return;
                  }

                  await ref
                      .read(noteEditorControllerProvider.notifier)
                      .createCustomNote(
                        title: result.title,
                        content: result.content,
                        tags: result.tags,
                        isPinned: result.isPinned,
                        matterId: null,
                        phaseId: null,
                      );
                },
                icon: const Icon(Icons.add),
                label: const Text('New Orphan Note'),
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
                      const Center(child: CircularProgressIndicator()),
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
                          title: const Text('Delete note'),
                          content: Text('Delete "${note.title}"?'),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Delete'),
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
    final selectedNoteId = ref.watch(selectedNoteIdProvider);
    if (notes.isEmpty) {
      return const Center(child: Text('No notes yet.'));
    }

    return ListView.builder(
      itemCount: notes.length,
      itemBuilder: (_, index) {
        final note = notes[index];
        return ListTile(
          selected: note.id == selectedNoteId,
          title: Text(note.title.isEmpty ? '(untitled)' : note.title),
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
              const PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
              PopupMenuItem<String>(
                value: 'toggle_pin',
                child: Text(note.isPinned ? 'Unpin' : 'Pin'),
              ),
              const PopupMenuItem<String>(
                value: 'link',
                child: Text('Link Note...'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'delete',
                child: Text('Delete'),
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
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  String? _loadedNoteId;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final noteAsync = ref.watch(noteEditorControllerProvider);
    final previewMode = ref.watch(previewModeProvider);
    final selectedMatterId = ref.watch(selectedMatterIdProvider);
    final selectedPhaseId = ref.watch(selectedPhaseIdProvider);

    return noteAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Editor error: $error')),
      data: (note) {
        if (note == null) {
          return const Center(child: Text('Select a note to edit.'));
        }
        final linkedNotesAsync = ref.watch(linkedNotesByNoteProvider(note.id));

        if (_loadedNoteId != note.id) {
          _loadedNoteId = note.id;
          _titleController.text = note.title;
          _contentController.text = note.content;
          _tagsController.text = note.tags.join(', ');
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: note.isPinned ? 'Unpin' : 'Pin',
                    onPressed: () async {
                      await ref
                          .read(noteEditorControllerProvider.notifier)
                          .updateCurrent(isPinned: !note.isPinned);
                    },
                    icon: Icon(
                      note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Link Note',
                    onPressed: () async {
                      await _showLinkNoteDialog(
                        context: context,
                        ref: ref,
                        sourceNote: note,
                      );
                    },
                    icon: const Icon(Icons.link),
                  ),
                  IconButton(
                    tooltip: 'Toggle Preview',
                    onPressed: () {
                      ref.read(previewModeProvider.notifier).state =
                          !previewMode;
                    },
                    icon: Icon(previewMode ? Icons.edit : Icons.preview),
                  ),
                  IconButton(
                    tooltip: 'Delete Note',
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Delete note'),
                          content: Text('Delete "${note.title}"?'),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        await ref
                            .read(noteEditorControllerProvider.notifier)
                            .deleteCurrent();
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma separated)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  OutlinedButton(
                    onPressed: () async {
                      await ref
                          .read(noteEditorControllerProvider.notifier)
                          .moveCurrent(matterId: null, phaseId: null);
                      ref.read(showOrphansProvider.notifier).state = true;
                      ref.read(showConflictsProvider.notifier).state = false;
                    },
                    child: const Text('Move to Orphans'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed:
                        selectedMatterId == null || selectedPhaseId == null
                        ? null
                        : () async {
                            await ref
                                .read(noteEditorControllerProvider.notifier)
                                .moveCurrent(
                                  matterId: selectedMatterId,
                                  phaseId: selectedPhaseId,
                                );
                            ref.read(showOrphansProvider.notifier).state =
                                false;
                          },
                    child: const Text('Assign to Selected Matter'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _LinkedNotesPanel(
                sourceNote: note,
                linkedNotesAsync: linkedNotesAsync,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: previewMode
                    ? Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Markdown(data: _contentController.text),
                      )
                    : TextField(
                        controller: _contentController,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                          hintText: 'Write markdown here...',
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: () async {
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
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Updated: ${note.updatedAt.toLocal()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
    final linkedCount = linkedNotesAsync.valueOrNull?.length ?? 0;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
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
                  'Linked Notes ($linkedCount)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Link Note',
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
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  Text('Failed to load links: $error'),
              data: (items) {
                if (items.isEmpty) {
                  return const Text('No links yet.');
                }

                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final item = items[index];
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
                            ? '(untitled)'
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
                            tooltip: 'Open linked note',
                            onPressed: () async {
                              await ref
                                  .read(noteEditorControllerProvider.notifier)
                                  .selectNote(item.relatedNote.id);
                            },
                            icon: const Icon(Icons.open_in_new, size: 16),
                          ),
                          IconButton(
                            tooltip: 'Remove link',
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
  List<Note> allNotes;
  try {
    allNotes = await ref.read(allNotesForLinkPickerProvider.future);
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Unable to load notes: $error')));
    return;
  }
  final candidates = allNotes
      .where((note) => note.id != sourceNote.id)
      .toList(growable: false);

  if (!context.mounted) {
    return;
  }

  if (candidates.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No notes available to link.')),
    );
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
    ).showSnackBar(const SnackBar(content: Text('Link created')));
  } catch (error) {
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Unable to create link: $error')));
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
    return AlertDialog(
      title: const Text('Link Note'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Source: ${_displayNoteTitle(widget.sourceNote)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _targetNoteId,
              decoration: const InputDecoration(labelText: 'Target note'),
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
            TextField(
              controller: _contextController,
              decoration: const InputDecoration(
                labelText: 'Context (optional)',
                hintText: 'Why are these notes related?',
              ),
              minLines: 2,
              maxLines: 4,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _LinkNoteDialogResult(
                targetNoteId: _targetNoteId,
                context: _contextController.text.trim(),
              ),
            );
          },
          child: const Text('Create Link'),
        ),
      ],
    );
  }

  String _displayNoteTitle(Note note) {
    final title = note.title.trim().isEmpty ? '(untitled)' : note.title.trim();
    if (note.matterId == null || note.phaseId == null) {
      return '$title [Orphan]';
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

String _conflictTypeLabel(SyncConflictType type) {
  return switch (type) {
    SyncConflictType.note => 'Note',
    SyncConflictType.link => 'Link',
    SyncConflictType.unknown => 'Unknown',
  };
}

class _ConflictTypeChip extends StatelessWidget {
  const _ConflictTypeChip({required this.type});

  final SyncConflictType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _conflictTypeLabel(type).toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _SearchResultsView extends ConsumerWidget {
  const _SearchResultsView({required this.results});

  final List<SearchListItem> results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (results.isEmpty) {
      return const Center(child: Text('No search results.'));
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
  const _SettingsDialog();

  @override
  ConsumerState<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<_SettingsDialog> {
  late final TextEditingController _rootPathController;
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _intervalController;
  bool _failSafe = true;
  SyncTargetType _type = SyncTargetType.none;

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
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _rootPathController,
                decoration: const InputDecoration(
                  labelText: 'Storage root path',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<SyncTargetType>(
                initialValue: _type,
                items: SyncTargetType.values
                    .map(
                      (value) => DropdownMenuItem<SyncTargetType>(
                        value: value,
                        child: Text(value.name),
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
                decoration: const InputDecoration(
                  labelText: 'Sync target type',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(labelText: 'WebDAV URL'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'WebDAV Username'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'WebDAV Password'),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _intervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Auto-sync interval (minutes)',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _failSafe,
                onChanged: (value) => setState(() => _failSafe = value),
                title: const Text('Deletion fail-safe'),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
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
                  intervalMinutes:
                      int.tryParse(_intervalController.text.trim()) ?? 5,
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

            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
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
  late final TextEditingController _colorController;
  late final TextEditingController _iconController;
  late MatterStatus _status;
  late bool _isPinned;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _colorController = TextEditingController(text: widget.initialColor);
    _iconController = TextEditingController(text: widget.initialIcon);
    _status = widget.initialStatus;
    _isPinned = widget.initialPinned;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _colorController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == _MatterDialogMode.create
        ? 'Create Matter'
        : 'Edit Matter';

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              DropdownButtonFormField<MatterStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: MatterStatus.values
                    .map(
                      (value) => DropdownMenuItem<MatterStatus>(
                        value: value,
                        child: Text(value.name),
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
              TextField(
                controller: _colorController,
                decoration: const InputDecoration(
                  labelText: 'Color (hex)',
                  hintText: '#4C956C',
                ),
              ),
              TextField(
                controller: _iconController,
                decoration: const InputDecoration(
                  labelText: 'Icon name',
                  hintText: 'description',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isPinned,
                onChanged: (value) => setState(() => _isPinned = value),
                title: const Text('Pinned'),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _MatterDialogResult(
                title: _titleController.text.trim(),
                description: _descriptionController.text.trim(),
                status: _status,
                color: _colorController.text.trim().isEmpty
                    ? '#4C956C'
                    : _colorController.text.trim(),
                icon: _iconController.text.trim().isEmpty
                    ? 'description'
                    : _iconController.text.trim(),
                isPinned: _isPinned,
              ),
            );
          },
          child: Text(
            widget.mode == _MatterDialogMode.create ? 'Create' : 'Save',
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

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _contentController = TextEditingController(
      text: widget.initialContent.isEmpty
          ? '# ${widget.initialTitle.isEmpty ? 'Untitled Note' : widget.initialTitle}\n'
          : widget.initialContent,
    );
    _tagsController = TextEditingController(
      text: widget.initialTags.join(', '),
    );
    _isPinned = widget.initialPinned;
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
    final title = widget.mode == _NoteDialogMode.create
        ? 'Create Note'
        : 'Edit Note';

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma separated)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contentController,
                minLines: 10,
                maxLines: 20,
                decoration: const InputDecoration(
                  labelText: 'Markdown content',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isPinned,
                onChanged: (value) => setState(() => _isPinned = value),
                title: const Text('Pinned'),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
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
          },
          child: Text(
            widget.mode == _NoteDialogMode.create ? 'Create' : 'Save',
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
