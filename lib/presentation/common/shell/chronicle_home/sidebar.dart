part of '../chronicle_home_coordinator.dart';

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
              const SizedBox(height: 12),
              _SectionHeader(title: l10n.viewsSectionLabel),
              const SizedBox(height: 12),
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
            ],
          ),
        ),
        const Divider(height: 1),
        const ChronicleSidebarSyncPanel(),
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
          label: Text(
            label,
            style: MacosTheme.of(
              context,
            ).typography.caption1.copyWith(height: 1.2),
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
                ChronicleMacosMatterStatusBadge(status: matter.status),
                const SizedBox(width: 6),
                ChronicleMacosMatterActionMenu(
                  matter: matter,
                  onSelected: (action) => _handleMatterAction(
                    context: context,
                    ref: ref,
                    matter: matter,
                    action: _mapChronicleMatterAction(action),
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
          trailing: ChronicleMacosCategoryActionMenu(
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

    if (selectableEntries.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedKey = showNotebook
        ? (selectedNotebookFolderId == null
              ? 'notebook:root'
              : 'notebook:$selectedNotebookFolderId')
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
        const ChronicleSidebarSyncPanel(),
      ],
    );
  }

  _MatterAction _mapChronicleMatterAction(ChronicleMatterAction action) {
    return switch (action) {
      ChronicleMatterAction.edit => _MatterAction.edit,
      ChronicleMatterAction.togglePinned => _MatterAction.togglePinned,
      ChronicleMatterAction.setActive => _MatterAction.setActive,
      ChronicleMatterAction.setPaused => _MatterAction.setPaused,
      ChronicleMatterAction.setCompleted => _MatterAction.setCompleted,
      ChronicleMatterAction.setArchived => _MatterAction.setArchived,
      ChronicleMatterAction.delete => _MatterAction.delete,
    };
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
    final result = await showDialog<ChronicleCategoryDialogResult>(
      context: context,
      builder: (_) => const ChronicleCategoryDialog(
        mode: ChronicleCategoryDialogMode.create,
      ),
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
    final result = await showDialog<ChronicleCategoryDialogResult>(
      context: context,
      builder: (_) => ChronicleCategoryDialog(
        mode: ChronicleCategoryDialogMode.edit,
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
    final result = await showDialog<ChronicleMatterDialogResult>(
      context: context,
      builder: (_) =>
          const ChronicleMatterDialog(mode: ChronicleMatterDialogMode.create),
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
        final result = await showDialog<ChronicleMatterDialogResult>(
          context: context,
          builder: (_) => ChronicleMatterDialog(
            mode: ChronicleMatterDialogMode.edit,
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
