part of '../chronicle_home_coordinator.dart';

const String _kSidebarSectionPinnedId = 'pinned';
const String _kSidebarSectionCategoriesId = 'categories';
const String _kSidebarSectionUncategorizedId = 'uncategorized';
const String _kSidebarSectionViewsId = 'views';
const String _kSidebarSectionNotebooksId = 'notebooks';

final selectedSidebarMatterRowKeyProvider =
    NotifierProvider<ValueNotifierController<String?>, String?>(
      () => ValueNotifierController<String?>(null),
    );

String _pinnedMatterRowKey(String matterId) => 'pinned|$matterId';

String _categoryMatterRowKey({
  required String categoryId,
  required String matterId,
}) => 'category|$categoryId|$matterId';

String _uncategorizedMatterRowKey(String matterId) => 'uncategorized|$matterId';

String _matterIdFromSidebarRowKey(String rowKey) => rowKey.split('|').last;

String? _resolveSelectedMatterRowKey({
  required MatterSections sections,
  required String? selectedMatterId,
  required String? preferredRowKey,
}) {
  if (selectedMatterId == null) {
    return null;
  }

  final availableRowKeys = <String>[
    for (final matter in sections.pinned) _pinnedMatterRowKey(matter.id),
    for (final section in sections.categorySections)
      for (final matter in section.matters)
        _categoryMatterRowKey(
          categoryId: section.category.id,
          matterId: matter.id,
        ),
    for (final matter in sections.uncategorized)
      _uncategorizedMatterRowKey(matter.id),
  ];

  if (preferredRowKey != null &&
      availableRowKeys.contains(preferredRowKey) &&
      _matterIdFromSidebarRowKey(preferredRowKey) == selectedMatterId) {
    return preferredRowKey;
  }

  for (final rowKey in availableRowKeys) {
    if (_matterIdFromSidebarRowKey(rowKey) == selectedMatterId) {
      return rowKey;
    }
  }

  return null;
}

class _MatterSidebar extends ConsumerWidget {
  const _MatterSidebar({required this.sections, this.scrollController});

  final MatterSections sections;
  final ScrollController? scrollController;

  Widget _buildMacSidebarSecondaryClickSurface({
    required Key key,
    required Widget child,
  }) {
    return SizedBox.expand(key: key, child: child);
  }

  void _handleMacSidebarSecondaryClick({
    required Offset globalPosition,
    required List<_MacSidebarContextMenuTarget> contextMenuTargets,
  }) {
    for (final target in contextMenuTargets) {
      final targetContext = target.targetKey.currentContext;
      if (targetContext == null) {
        continue;
      }
      final renderObject = targetContext.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (globalPosition.dy < rect.top || globalPosition.dy > rect.bottom) {
        continue;
      }
      unawaited(
        target.onSecondaryTapDown(
          TapDownDetails(
            globalPosition: globalPosition,
            localPosition: renderObject.globalToLocal(globalPosition),
          ),
        ),
      );
      return;
    }
  }

  Future<void> _showCategoryMenu({
    required BuildContext context,
    required WidgetRef ref,
    required Category category,
    required TapDownDetails details,
  }) async {
    await _showMacosSecondaryClickMenu<_CategoryAction>(
      context: context,
      details: details,
      itemBuilder: (menuContext) => <MacosPulldownMenuEntry>[
        ChronicleMacosContextMenuItem<_CategoryAction>(
          value: _CategoryAction.edit,
          title: Text(menuContext.l10n.editAction),
        ),
        ChronicleMacosContextMenuItem<_CategoryAction>(
          value: _CategoryAction.delete,
          title: Text(menuContext.l10n.deleteAction),
        ),
      ],
      onSelected: (value) async {
        switch (value) {
          case _CategoryAction.edit:
            await _editCategory(context: context, ref: ref, category: category);
            return;
          case _CategoryAction.delete:
            await _deleteCategory(
              context: context,
              ref: ref,
              category: category,
            );
            return;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMatterId = ref.watch(selectedMatterIdProvider);
    final preferredSelectedMatterRowKey = ref.watch(
      selectedSidebarMatterRowKeyProvider,
    );
    final selectedTimeView = ref.watch(selectedTimeViewProvider);
    final showNotebook = ref.watch(showNotebookProvider);
    final selectedNotebookFolderId = ref.watch(
      selectedNotebookFolderIdProvider,
    );
    final notebookTree = ref.watch(notebookFolderTreeProvider);
    final noteDragPayload = ref.watch(_activeNoteDragPayloadProvider);
    final settings = ref.watch(settingsControllerProvider).asData?.value;
    final collapsedCategoryIds =
        settings?.collapsedCategoryIds.toSet() ?? <String>{};
    final collapsedSidebarSectionIds =
        settings?.collapsedSidebarSectionIds.toSet() ?? <String>{};
    final selectedMatterRowKey = _resolveSelectedMatterRowKey(
      sections: sections,
      selectedMatterId: selectedMatterId,
      preferredRowKey: preferredSelectedMatterRowKey,
    );

    if (_isMacOSNativeUIContext(context)) {
      return _buildMacOSSidebar(
        context: context,
        ref: ref,
        selectedMatterId: selectedMatterId,
        selectedMatterRowKey: selectedMatterRowKey,
        selectedTimeView: selectedTimeView,
        showNotebook: showNotebook,
        selectedNotebookFolderId: selectedNotebookFolderId,
        notebookTree: notebookTree,
        noteDragPayload: noteDragPayload,
        collapsedCategoryIds: collapsedCategoryIds,
        collapsedSidebarSectionIds: collapsedSidebarSectionIds,
      );
    }

    return _buildMaterialSidebar(
      context: context,
      ref: ref,
      selectedMatterId: selectedMatterId,
      selectedMatterRowKey: selectedMatterRowKey,
      selectedTimeView: selectedTimeView,
      showNotebook: showNotebook,
      selectedNotebookFolderId: selectedNotebookFolderId,
      notebookTree: notebookTree,
      noteDragPayload: noteDragPayload,
      collapsedCategoryIds: collapsedCategoryIds,
      collapsedSidebarSectionIds: collapsedSidebarSectionIds,
    );
  }

  Widget _buildMaterialSidebar({
    required BuildContext context,
    required WidgetRef ref,
    required String? selectedMatterId,
    required String? selectedMatterRowKey,
    required ChronicleTimeView? selectedTimeView,
    required bool showNotebook,
    required String? selectedNotebookFolderId,
    required List<NotebookFolderTreeNode> notebookTree,
    required _NoteDragPayload? noteDragPayload,
    required Set<String> collapsedCategoryIds,
    required Set<String> collapsedSidebarSectionIds,
  }) {
    final l10n = context.l10n;
    final pinnedCollapsed = collapsedSidebarSectionIds.contains(
      _kSidebarSectionPinnedId,
    );
    final categoriesCollapsed = collapsedSidebarSectionIds.contains(
      _kSidebarSectionCategoriesId,
    );
    final uncategorizedCollapsed = collapsedSidebarSectionIds.contains(
      _kSidebarSectionUncategorizedId,
    );
    final viewsCollapsed = collapsedSidebarSectionIds.contains(
      _kSidebarSectionViewsId,
    );
    final notebooksCollapsed = collapsedSidebarSectionIds.contains(
      _kSidebarSectionNotebooksId,
    );
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
              _MaterialSidebarSectionHeader(
                key: const ValueKey<String>('sidebar_section_header_pinned'),
                title: l10n.pinnedLabel,
                collapsed: pinnedCollapsed,
                onToggleCollapsed: () => _toggleSidebarSectionCollapsed(
                  ref,
                  _kSidebarSectionPinnedId,
                  !pinnedCollapsed,
                ),
              ),
              if (!pinnedCollapsed)
                _MatterList(
                  matters: sections.pinned,
                  selectedMatterId: selectedMatterId,
                  selectedMatterRowKey: selectedMatterRowKey,
                  rowKeyOf: (matter) => _pinnedMatterRowKey(matter.id),
                  onSelect: (matter, rowKey) =>
                      _selectMatter(ref, matter, rowKey),
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
              _MaterialSidebarSectionHeader(
                key: const ValueKey<String>(
                  'sidebar_section_header_categories',
                ),
                title: l10n.categoriesSectionLabel,
                collapsed: categoriesCollapsed,
                onToggleCollapsed: () => _toggleSidebarSectionCollapsed(
                  ref,
                  _kSidebarSectionCategoriesId,
                  !categoriesCollapsed,
                ),
              ),
              if (!categoriesCollapsed)
                for (final section in sections.categorySections)
                  _MaterialCategorySection(
                    section: section,
                    collapsed: collapsedCategoryIds.contains(
                      section.category.id,
                    ),
                    selectedMatterId: selectedMatterId,
                    selectedMatterRowKey: selectedMatterRowKey,
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
                    onSelect: (matter, rowKey) =>
                        _selectMatter(ref, matter, rowKey),
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
                collapsed: uncategorizedCollapsed,
                onToggleCollapsed: () => _toggleSidebarSectionCollapsed(
                  ref,
                  _kSidebarSectionUncategorizedId,
                  !uncategorizedCollapsed,
                ),
                matters: sections.uncategorized,
                selectedMatterId: selectedMatterId,
                selectedMatterRowKey: selectedMatterRowKey,
                noteDragPayload: noteDragPayload,
                onAction: (matter, action) => _handleMatterAction(
                  context: context,
                  ref: ref,
                  matter: matter,
                  action: action,
                ),
                onSelect: (matter, rowKey) =>
                    _selectMatter(ref, matter, rowKey),
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
              _MaterialSidebarSectionHeader(
                key: const ValueKey<String>('sidebar_section_header_views'),
                title: l10n.viewsSectionLabel,
                collapsed: viewsCollapsed,
                onToggleCollapsed: () => _toggleSidebarSectionCollapsed(
                  ref,
                  _kSidebarSectionViewsId,
                  !viewsCollapsed,
                ),
              ),
              if (!viewsCollapsed) ...<Widget>[
                _buildMaterialTimeViewTile(
                  context: context,
                  ref: ref,
                  timeView: ChronicleTimeView.today,
                  selectedTimeView: selectedTimeView,
                ),
                _buildMaterialTimeViewTile(
                  context: context,
                  ref: ref,
                  timeView: ChronicleTimeView.yesterday,
                  selectedTimeView: selectedTimeView,
                ),
                _buildMaterialTimeViewTile(
                  context: context,
                  ref: ref,
                  timeView: ChronicleTimeView.thisWeek,
                  selectedTimeView: selectedTimeView,
                ),
                _buildMaterialTimeViewTile(
                  context: context,
                  ref: ref,
                  timeView: ChronicleTimeView.lastWeek,
                  selectedTimeView: selectedTimeView,
                ),
              ],
              _MaterialSidebarSectionHeader(
                key: const ValueKey<String>('sidebar_section_header_notebooks'),
                title: l10n.notebooksSectionLabel,
                collapsed: notebooksCollapsed,
                onToggleCollapsed: () => _toggleSidebarSectionCollapsed(
                  ref,
                  _kSidebarSectionNotebooksId,
                  !notebooksCollapsed,
                ),
              ),
              if (!notebooksCollapsed) ...<Widget>[
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
    required String? selectedMatterRowKey,
    required ChronicleTimeView? selectedTimeView,
    required bool showNotebook,
    required String? selectedNotebookFolderId,
    required List<NotebookFolderTreeNode> notebookTree,
    required _NoteDragPayload? noteDragPayload,
    required Set<String> collapsedCategoryIds,
    required Set<String> collapsedSidebarSectionIds,
  }) {
    final l10n = context.l10n;
    final pinnedCollapsed = collapsedSidebarSectionIds.contains(
      _kSidebarSectionPinnedId,
    );
    final categoriesCollapsed = collapsedSidebarSectionIds.contains(
      _kSidebarSectionCategoriesId,
    );
    final uncategorizedCollapsed = collapsedSidebarSectionIds.contains(
      _kSidebarSectionUncategorizedId,
    );
    final viewsCollapsed = collapsedSidebarSectionIds.contains(
      _kSidebarSectionViewsId,
    );
    final notebooksCollapsed = collapsedSidebarSectionIds.contains(
      _kSidebarSectionNotebooksId,
    );
    final sidebarItems = <SidebarItem>[];
    final selectableEntries = <_MacSidebarSelectableEntry>[];
    final contextMenuTargets = <_MacSidebarContextMenuTarget>[];

    void addSection({
      required String sectionId,
      required String label,
      required bool collapsed,
      required VoidCallback onToggleCollapsed,
    }) {
      sidebarItems.add(
        SidebarItem(
          section: true,
          label: _MacSidebarSectionHeader(
            key: ValueKey<String>('sidebar_section_header_$sectionId'),
            title: label,
            collapsed: collapsed,
            onTap: onToggleCollapsed,
          ),
        ),
      );
    }

    void addMatterItems(
      List<Matter> matters, {
      required String Function(Matter matter) rowKeyOf,
    }) {
      for (final matter in matters) {
        final matterRowKey = rowKeyOf(matter);
        Future<void> showMatterMenu(TapDownDetails details) async {
          await _showMacosSecondaryClickMenu<_MatterAction>(
            context: context,
            details: details,
            itemBuilder: (menuContext) => <MacosPulldownMenuEntry>[
              ChronicleMacosContextMenuItem<_MatterAction>(
                value: _MatterAction.edit,
                title: Text(menuContext.l10n.editAction),
              ),
              ChronicleMacosContextMenuItem<_MatterAction>(
                value: _MatterAction.togglePinned,
                title: Text(
                  matter.isPinned
                      ? menuContext.l10n.unpinAction
                      : menuContext.l10n.pinAction,
                ),
              ),
              const MacosPulldownMenuDivider(),
              ChronicleMacosContextMenuItem<_MatterAction>(
                value: _MatterAction.setActive,
                title: Text(menuContext.l10n.setActiveAction),
              ),
              ChronicleMacosContextMenuItem<_MatterAction>(
                value: _MatterAction.setPaused,
                title: Text(menuContext.l10n.setPausedAction),
              ),
              ChronicleMacosContextMenuItem<_MatterAction>(
                value: _MatterAction.setCompleted,
                title: Text(menuContext.l10n.setCompletedAction),
              ),
              ChronicleMacosContextMenuItem<_MatterAction>(
                value: _MatterAction.setArchived,
                title: Text(menuContext.l10n.setArchivedAction),
              ),
              const MacosPulldownMenuDivider(),
              ChronicleMacosContextMenuItem<_MatterAction>(
                value: _MatterAction.delete,
                title: Text(menuContext.l10n.deleteAction),
              ),
            ],
            onSelected: (action) async {
              await _handleMatterAction(
                context: context,
                ref: ref,
                matter: matter,
                action: action,
              );
            },
          );
        }

        final contextTargetKey = GlobalKey(
          debugLabel: 'sidebar_matter_context_surface_${matter.id}',
        );
        contextMenuTargets.add(
          _MacSidebarContextMenuTarget(
            targetKey: contextTargetKey,
            onSecondaryTapDown: showMatterMenu,
          ),
        );

        selectableEntries.add(
          _MacSidebarSelectableEntry(
            key: matterRowKey,
            onSelected: () => _selectMatter(ref, matter, matterRowKey),
          ),
        );
        sidebarItems.add(
          SidebarItem(
            label: _buildMacSidebarSecondaryClickSurface(
              key: contextTargetKey,
              child: DragTarget<_NoteDragPayload>(
                key: ValueKey<String>(
                  'sidebar_matter_drop_target_${matter.id}',
                ),
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
                    key: ValueKey<String>(
                      'sidebar_matter_reassign_drag_${matter.id}',
                    ),
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
                      key: ValueKey<String>('sidebar_matter_row_$matterRowKey'),
                      duration: const Duration(milliseconds: 100),
                      alignment: Alignment.centerLeft,
                      width: double.infinity,
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
                      child: Row(
                        children: <Widget>[
                          _MatterLeadingIcon(
                            iconKey: matter.icon,
                            isPinned: matter.isPinned,
                            isMacOS: true,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _displayMatterTitle(context, matter),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _macSidebarItemLabelStyle(
                                context,
                                selected:
                                    selectedTimeView == null &&
                                    !showNotebook &&
                                    selectedMatterRowKey == matterRowKey,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ChronicleMacosMatterStatusBadge(
                            status: matter.status,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      }
    }

    addSection(
      sectionId: _kSidebarSectionPinnedId,
      label: l10n.pinnedLabel,
      collapsed: pinnedCollapsed,
      onToggleCollapsed: () => _toggleSidebarSectionCollapsed(
        ref,
        _kSidebarSectionPinnedId,
        !pinnedCollapsed,
      ),
    );
    if (!pinnedCollapsed) {
      addMatterItems(
        sections.pinned,
        rowKeyOf: (matter) => _pinnedMatterRowKey(matter.id),
      );
    }

    addSection(
      sectionId: _kSidebarSectionCategoriesId,
      label: l10n.categoriesSectionLabel,
      collapsed: categoriesCollapsed,
      onToggleCollapsed: () => _toggleSidebarSectionCollapsed(
        ref,
        _kSidebarSectionCategoriesId,
        !categoriesCollapsed,
      ),
    );
    if (!categoriesCollapsed) {
      for (final section in sections.categorySections) {
        final category = section.category;
        final collapsed = collapsedCategoryIds.contains(category.id);
        final contextTargetKey = GlobalKey(
          debugLabel: 'sidebar_category_context_surface_${category.id}',
        );
        contextMenuTargets.add(
          _MacSidebarContextMenuTarget(
            targetKey: contextTargetKey,
            onSecondaryTapDown: (details) => _showCategoryMenu(
              context: context,
              ref: ref,
              category: category,
              details: details,
            ),
          ),
        );
        selectableEntries.add(
          _MacSidebarSelectableEntry(
            key: 'category:${category.id}',
            onSelected: () =>
                _toggleCategoryCollapsed(ref, category.id, !collapsed),
          ),
        );
        sidebarItems.add(
          SidebarItem(
            label: _buildMacSidebarSecondaryClickSurface(
              key: contextTargetKey,
              child: DragTarget<_MatterReassignPayload>(
                key: ValueKey<String>(
                  'sidebar_category_drop_target_macos_${category.id}',
                ),
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
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    alignment: Alignment.centerLeft,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: highlight
                          ? MacosTheme.of(context).primaryColor.withAlpha(64)
                          : null,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: <Widget>[
                        MacosIcon(
                          _matterIconDataForKey(category.icon),
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_displayCategoryName(context, category)} (${section.matters.length})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                    ),
                  );
                },
              ),
            ),
          ),
        );
        if (!collapsed) {
          addMatterItems(
            section.matters,
            rowKeyOf: (matter) => _categoryMatterRowKey(
              categoryId: section.category.id,
              matterId: matter.id,
            ),
          );
        }
      }
    }

    sidebarItems.add(
      SidebarItem(
        section: true,
        label: DragTarget<_MatterReassignPayload>(
          key: const ValueKey<String>(
            'sidebar_uncategorized_drop_target_macos',
          ),
          onWillAcceptWithDetails: (details) => details.data.categoryId != null,
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
            return _MacSidebarSectionHeader(
              key: const ValueKey<String>(
                'sidebar_section_header_uncategorized',
              ),
              title: l10n.uncategorizedSectionLabel(
                sections.uncategorized.length,
              ),
              collapsed: uncategorizedCollapsed,
              highlighted: highlight,
              onTap: () => _toggleSidebarSectionCollapsed(
                ref,
                _kSidebarSectionUncategorizedId,
                !uncategorizedCollapsed,
              ),
            );
          },
        ),
      ),
    );
    if (!uncategorizedCollapsed) {
      addMatterItems(
        sections.uncategorized,
        rowKeyOf: (matter) => _uncategorizedMatterRowKey(matter.id),
      );
    }

    addSection(
      sectionId: _kSidebarSectionViewsId,
      label: l10n.viewsSectionLabel,
      collapsed: viewsCollapsed,
      onToggleCollapsed: () => _toggleSidebarSectionCollapsed(
        ref,
        _kSidebarSectionViewsId,
        !viewsCollapsed,
      ),
    );
    if (!viewsCollapsed) {
      _addMacTimeViewItems(
        context: context,
        ref: ref,
        sidebarItems: sidebarItems,
        selectableEntries: selectableEntries,
        selectedTimeView: selectedTimeView,
      );
    }

    addSection(
      sectionId: _kSidebarSectionNotebooksId,
      label: l10n.notebooksSectionLabel,
      collapsed: notebooksCollapsed,
      onToggleCollapsed: () => _toggleSidebarSectionCollapsed(
        ref,
        _kSidebarSectionNotebooksId,
        !notebooksCollapsed,
      ),
    );
    if (!notebooksCollapsed) {
      _addMacNotebookRootItem(
        context: context,
        ref: ref,
        sidebarItems: sidebarItems,
        selectableEntries: selectableEntries,
        contextMenuTargets: contextMenuTargets,
        showNotebook: showNotebook,
        selectedNotebookFolderId: selectedNotebookFolderId,
      );
      _addMacNotebookFolderItems(
        context: context,
        ref: ref,
        sidebarItems: sidebarItems,
        selectableEntries: selectableEntries,
        contextMenuTargets: contextMenuTargets,
        nodes: notebookTree,
        depth: 1,
        showNotebook: showNotebook,
        selectedNotebookFolderId: selectedNotebookFolderId,
      );
    }

    if (selectableEntries.isEmpty) {
      selectableEntries.add(
        _MacSidebarSelectableEntry(
          key: '__sidebar_placeholder__',
          onSelected: () {},
        ),
      );
      sidebarItems.add(const SidebarItem(label: SizedBox.shrink()));
    }

    final selectedKey = showNotebook
        ? (selectedNotebookFolderId == null
              ? 'notebook:root'
              : 'notebook:$selectedNotebookFolderId')
        : selectedTimeView != null
        ? 'view:${selectedTimeView.name}'
        : selectedMatterRowKey ?? selectableEntries.first.key;
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
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if ((event.buttons & 2) == 0) {
                return;
              }
              _handleMacSidebarSecondaryClick(
                globalPosition: event.position,
                contextMenuTargets: contextMenuTargets,
              );
            },
            child: SidebarItems(
              scrollController: scrollController,
              items: sidebarItems,
              currentIndex: selectedIndex,
              onChanged: (index) => selectableEntries[index].onSelected(),
              itemSize: SidebarItemSize.large,
            ),
          ),
        ),
        const Divider(height: 1),
        const ChronicleSidebarSyncPanel(),
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
    ref.read(selectedSidebarMatterRowKeyProvider.notifier).set(null);
    unawaited(
      ref
          .read(noteEditorControllerProvider.notifier)
          .openNotebookFolderInWorkspace(folderId),
    );
  }

  void _selectTimeView(WidgetRef ref, ChronicleTimeView timeView) {
    unawaited(
      ref
          .read(noteEditorControllerProvider.notifier)
          .flushAndClearNotebookDraftSession(),
    );
    ref.read(showNotebookProvider.notifier).set(false);
    ref.read(showConflictsProvider.notifier).set(false);
    ref.read(selectedSidebarMatterRowKeyProvider.notifier).set(null);
    ref.read(selectedMatterIdProvider.notifier).set(null);
    ref.read(selectedPhaseIdProvider.notifier).set(null);
    ref.read(selectedNotebookFolderIdProvider.notifier).set(null);
    ref.read(selectedTimeViewProvider.notifier).set(timeView);
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

  Widget _buildMaterialTimeViewTile({
    required BuildContext context,
    required WidgetRef ref,
    required ChronicleTimeView timeView,
    required ChronicleTimeView? selectedTimeView,
  }) {
    return ListTile(
      key: ValueKey<String>('sidebar_view_${timeView.name}'),
      dense: true,
      selected: selectedTimeView == timeView,
      title: Text(
        _timeViewLabel(context, timeView),
        style: _materialSidebarItemLabelStyle(
          context,
          selected: selectedTimeView == timeView,
        ),
      ),
      leading: const Icon(Icons.schedule),
      onTap: () => _selectTimeView(ref, timeView),
    );
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
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) {
              unawaited(
                _showSecondaryClickMenu<String>(
                  context: context,
                  details: details,
                  itemBuilder: (menuContext) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'new_folder',
                      child: Text(menuContext.l10n.newFolderAction),
                    ),
                  ],
                  onSelected: (value) async {
                    if (value != 'new_folder') {
                      return;
                    }
                    await _createNotebookFolder(
                      context: context,
                      ref: ref,
                      parentId: null,
                    );
                  },
                ),
              );
            },
            child: ListTile(
              selected: showNotebook && selectedNotebookFolderId == null,
              title: Text(
                l10n.notebookLabel,
                style: _materialSidebarItemLabelStyle(
                  context,
                  selected: showNotebook && selectedNotebookFolderId == null,
                ),
              ),
              onTap: () {
                _selectNotebookFolder(ref, null);
              },
            ),
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
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) {
              unawaited(
                _showSecondaryClickMenu<String>(
                  context: context,
                  details: details,
                  itemBuilder: (menuContext) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'new_folder',
                      child: Text(menuContext.l10n.newFolderAction),
                    ),
                    PopupMenuItem<String>(
                      value: 'rename',
                      child: Text(menuContext.l10n.renameFolderAction),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text(menuContext.l10n.deleteFolderAction),
                    ),
                  ],
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
                ),
              );
            },
            child: ListTile(
              contentPadding: EdgeInsets.only(
                left: 12 + (depth * 16),
                right: 8,
              ),
              selected: showNotebook && selectedNotebookFolderId == folder.id,
              title: Text(
                folder.name,
                style: _materialSidebarItemLabelStyle(
                  context,
                  selected:
                      showNotebook && selectedNotebookFolderId == folder.id,
                ),
              ),
              onTap: () {
                _selectNotebookFolder(ref, folder.id);
              },
            ),
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
    required List<_MacSidebarContextMenuTarget> contextMenuTargets,
    required bool showNotebook,
    required String? selectedNotebookFolderId,
  }) {
    final l10n = context.l10n;
    final contextTargetKey = GlobalKey(
      debugLabel: 'sidebar_notebook_root_context_surface',
    );
    contextMenuTargets.add(
      _MacSidebarContextMenuTarget(
        targetKey: contextTargetKey,
        onSecondaryTapDown: (details) => _showMacosSecondaryClickMenu<String>(
          context: context,
          details: details,
          itemBuilder: (menuContext) => <MacosPulldownMenuEntry>[
            ChronicleMacosContextMenuItem<String>(
              value: 'new_folder',
              title: Text(menuContext.l10n.newFolderAction),
            ),
          ],
          onSelected: (value) async {
            if (value != 'new_folder') {
              return;
            }
            await _createNotebookFolder(
              context: context,
              ref: ref,
              parentId: null,
            );
          },
        ),
      ),
    );
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
        label: _buildMacSidebarSecondaryClickSurface(
          key: contextTargetKey,
          child: DragTarget<_NoteDragPayload>(
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
                  style: _macSidebarItemLabelStyle(
                    context,
                    selected: showNotebook && selectedNotebookFolderId == null,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _addMacTimeViewItems({
    required BuildContext context,
    required WidgetRef ref,
    required List<SidebarItem> sidebarItems,
    required List<_MacSidebarSelectableEntry> selectableEntries,
    required ChronicleTimeView? selectedTimeView,
  }) {
    for (final timeView in ChronicleTimeView.values) {
      selectableEntries.add(
        _MacSidebarSelectableEntry(
          key: 'view:${timeView.name}',
          onSelected: () {
            _selectTimeView(ref, timeView);
          },
        ),
      );
      sidebarItems.add(
        SidebarItem(
          leading: const MacosIcon(CupertinoIcons.calendar, size: 14),
          label: Text(
            _timeViewLabel(context, timeView),
            key: ValueKey<String>('macos_sidebar_view_${timeView.name}'),
            style: _macSidebarItemLabelStyle(
              context,
              selected: selectedTimeView == timeView,
            ),
          ),
        ),
      );
    }
  }

  void _addMacNotebookFolderItems({
    required BuildContext context,
    required WidgetRef ref,
    required List<SidebarItem> sidebarItems,
    required List<_MacSidebarSelectableEntry> selectableEntries,
    required List<_MacSidebarContextMenuTarget> contextMenuTargets,
    required List<NotebookFolderTreeNode> nodes,
    required int depth,
    required bool showNotebook,
    required String? selectedNotebookFolderId,
  }) {
    for (final node in nodes) {
      final folder = node.folder;
      final contextTargetKey = GlobalKey(
        debugLabel: 'sidebar_notebook_folder_context_surface_${folder.id}',
      );
      contextMenuTargets.add(
        _MacSidebarContextMenuTarget(
          targetKey: contextTargetKey,
          onSecondaryTapDown: (details) => _showMacosSecondaryClickMenu<String>(
            context: context,
            details: details,
            itemBuilder: (menuContext) => <MacosPulldownMenuEntry>[
              ChronicleMacosContextMenuItem<String>(
                value: 'new_folder',
                title: Text(menuContext.l10n.newFolderAction),
              ),
              ChronicleMacosContextMenuItem<String>(
                value: 'rename',
                title: Text(menuContext.l10n.renameFolderAction),
              ),
              ChronicleMacosContextMenuItem<String>(
                value: 'delete',
                title: Text(menuContext.l10n.deleteFolderAction),
              ),
            ],
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
          ),
        ),
      );
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
          label: _buildMacSidebarSecondaryClickSurface(
            key: contextTargetKey,
            child: DragTarget<_NoteDragPayload>(
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
                    style: _macSidebarItemLabelStyle(
                      context,
                      selected:
                          showNotebook && selectedNotebookFolderId == folder.id,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      _addMacNotebookFolderItems(
        context: context,
        ref: ref,
        sidebarItems: sidebarItems,
        selectableEntries: selectableEntries,
        contextMenuTargets: contextMenuTargets,
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
    final result = await showChronicleCategoryDialog(
      context: context,
      mode: ChronicleCategoryDialogMode.create,
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
    final result = await showChronicleCategoryDialog(
      context: context,
      mode: ChronicleCategoryDialogMode.edit,
      initialName: category.name,
      initialColor: category.color,
      initialIcon: category.icon,
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

  void _toggleSidebarSectionCollapsed(
    WidgetRef ref,
    String sectionId,
    bool collapsed,
  ) {
    unawaited(
      ref
          .read(settingsControllerProvider.notifier)
          .setSidebarSectionCollapsed(sectionId, collapsed),
    );
  }

  Future<void> _createMatter({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final defaultCategoryId = _defaultCategoryIdForNewMatter(ref);
    final result = await showChronicleMatterDialog(
      context: context,
      mode: ChronicleMatterDialogMode.create,
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
        final result = await showChronicleMatterDialog(
          context: context,
          mode: ChronicleMatterDialogMode.edit,
          initialTitle: matter.title,
          initialDescription: matter.description,
          initialStatus: matter.status,
          initialColor: matter.color,
          initialIcon: matter.icon,
          initialPinned: matter.isPinned,
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
              return ChronicleMacosFixedDialog(
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

  void _selectMatter(WidgetRef ref, Matter matter, String rowKey) {
    final phaseId =
        matter.currentPhaseId ??
        (matter.phases.isEmpty ? null : matter.phases.first.id);
    ref.read(selectedSidebarMatterRowKeyProvider.notifier).set(rowKey);
    unawaited(
      ref
          .read(noteEditorControllerProvider.notifier)
          .openMatterInWorkspace(
            matterId: matter.id,
            phaseId: phaseId,
            matter: matter,
          ),
    );
  }
}

TextStyle _materialSidebarItemLabelStyle(
  BuildContext context, {
  required bool selected,
}) {
  final base =
      Theme.of(context).textTheme.titleMedium ?? const TextStyle(fontSize: 16);
  final baseSize = base.fontSize ?? 16;
  return base.copyWith(
    fontSize: selected ? baseSize + 1 : baseSize - 0.5,
    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
  );
}

TextStyle _macSidebarItemLabelStyle(
  BuildContext context, {
  required bool selected,
}) {
  final base = MacosTheme.of(context).typography.body;
  final baseSize = base.fontSize ?? 14;
  return base.copyWith(
    fontSize: selected ? baseSize + 1 : baseSize - 0.5,
    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
  );
}

class _MacSidebarSelectableEntry {
  const _MacSidebarSelectableEntry({
    required this.key,
    required this.onSelected,
  });

  final String key;
  final VoidCallback onSelected;
}

class _MacSidebarContextMenuTarget {
  const _MacSidebarContextMenuTarget({
    required this.targetKey,
    required this.onSecondaryTapDown,
  });

  final GlobalKey targetKey;
  final Future<void> Function(TapDownDetails details) onSecondaryTapDown;
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

class _MaterialSidebarSectionHeader extends StatelessWidget {
  const _MaterialSidebarSectionHeader({
    super.key,
    required this.title,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final String title;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggleCollapsed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.labelLarge),
            ),
            Icon(
              collapsed
                  ? Icons.keyboard_arrow_right
                  : Icons.keyboard_arrow_down,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _MacSidebarSectionHeader extends StatelessWidget {
  const _MacSidebarSectionHeader({
    super.key,
    required this.title,
    required this.collapsed,
    required this.onTap,
    this.highlighted = false,
  });

  final String title;
  final bool collapsed;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: highlighted
              ? MacosTheme.of(context).primaryColor.withAlpha(40)
              : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MacosTheme.of(
                  context,
                ).typography.caption1.copyWith(height: 1.2),
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
        ),
      ),
    );
  }
}

enum _CategoryAction { edit, delete }

class _MaterialCategorySection extends StatelessWidget {
  const _MaterialCategorySection({
    required this.section,
    required this.collapsed,
    required this.selectedMatterId,
    required this.selectedMatterRowKey,
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
  final String? selectedMatterRowKey;
  final _NoteDragPayload? noteDragPayload;
  final VoidCallback onToggleCollapsed;
  final void Function(Matter matter, String rowKey) onSelect;
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
      key: ValueKey<String>(
        'sidebar_category_drop_target_material_${section.category.id}',
      ),
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
                  selectedMatterRowKey: selectedMatterRowKey,
                  rowKeyOf: (matter) => _categoryMatterRowKey(
                    categoryId: section.category.id,
                    matterId: matter.id,
                  ),
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
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.matters,
    required this.selectedMatterId,
    required this.selectedMatterRowKey,
    required this.noteDragPayload,
    required this.onSelect,
    required this.onAction,
    required this.onDropNoteToMatter,
    required this.onDropMatterToUncategorized,
  });

  final String title;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final List<Matter> matters;
  final String? selectedMatterId;
  final String? selectedMatterRowKey;
  final _NoteDragPayload? noteDragPayload;
  final void Function(Matter matter, String rowKey) onSelect;
  final Future<void> Function(Matter matter, _MatterAction action) onAction;
  final Future<void> Function(_NoteDragPayload payload, Matter matter)
  onDropNoteToMatter;
  final Future<void> Function(_MatterReassignPayload payload)
  onDropMatterToUncategorized;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_MatterReassignPayload>(
      key: const ValueKey<String>('sidebar_uncategorized_drop_target_material'),
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
              _MaterialSidebarSectionHeader(
                key: const ValueKey<String>(
                  'sidebar_section_header_uncategorized',
                ),
                title: title,
                collapsed: collapsed,
                onToggleCollapsed: onToggleCollapsed,
              ),
              if (!collapsed)
                _MatterList(
                  matters: matters,
                  selectedMatterId: selectedMatterId,
                  selectedMatterRowKey: selectedMatterRowKey,
                  rowKeyOf: (matter) => _uncategorizedMatterRowKey(matter.id),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) {
        unawaited(
          _showSecondaryClickMenu<_CategoryAction>(
            context: context,
            details: details,
            itemBuilder: (menuContext) => <PopupMenuEntry<_CategoryAction>>[
              PopupMenuItem<_CategoryAction>(
                value: _CategoryAction.edit,
                child: Text(menuContext.l10n.editAction),
              ),
              PopupMenuItem<_CategoryAction>(
                value: _CategoryAction.delete,
                child: Text(menuContext.l10n.deleteAction),
              ),
            ],
            onSelected: (value) async {
              switch (value) {
                case _CategoryAction.edit:
                  await onEdit();
                  return;
                case _CategoryAction.delete:
                  await onDelete();
                  return;
              }
            },
          ),
        );
      },
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 8, right: 0),
        onTap: onToggleCollapsed,
        leading: Icon(iconData, color: _colorFromHex(section.category.color)),
        title: Text(
          '${_displayCategoryName(context, section.category)} (${section.matters.length})',
        ),
        trailing: Icon(
          collapsed ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_down,
          size: 18,
        ),
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
    required this.selectedMatterRowKey,
    required this.rowKeyOf,
    required this.onSelect,
    required this.onAction,
    this.noteDragPayload,
    this.onDropNoteToMatter,
  });

  final List<Matter> matters;
  final String? selectedMatterId;
  final String? selectedMatterRowKey;
  final String Function(Matter matter) rowKeyOf;
  final void Function(Matter matter, String rowKey) onSelect;
  final Future<void> Function(Matter matter, _MatterAction action) onAction;
  final _NoteDragPayload? noteDragPayload;
  final Future<void> Function(_NoteDragPayload payload, Matter matter)?
  onDropNoteToMatter;

  @override
  Widget build(BuildContext context) {
    if (matters.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: matters.map((matter) {
        final matterRowKey = rowKeyOf(matter);
        final tile = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) {
            unawaited(
              _showSecondaryClickMenu<_MatterAction>(
                context: context,
                details: details,
                itemBuilder: (menuContext) => <PopupMenuEntry<_MatterAction>>[
                  PopupMenuItem<_MatterAction>(
                    value: _MatterAction.edit,
                    child: Text(menuContext.l10n.editAction),
                  ),
                  PopupMenuItem<_MatterAction>(
                    value: _MatterAction.togglePinned,
                    child: Text(
                      matter.isPinned
                          ? menuContext.l10n.unpinAction
                          : menuContext.l10n.pinAction,
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<_MatterAction>(
                    value: _MatterAction.setActive,
                    child: Text(menuContext.l10n.setActiveAction),
                  ),
                  PopupMenuItem<_MatterAction>(
                    value: _MatterAction.setPaused,
                    child: Text(menuContext.l10n.setPausedAction),
                  ),
                  PopupMenuItem<_MatterAction>(
                    value: _MatterAction.setCompleted,
                    child: Text(menuContext.l10n.setCompletedAction),
                  ),
                  PopupMenuItem<_MatterAction>(
                    value: _MatterAction.setArchived,
                    child: Text(menuContext.l10n.setArchivedAction),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<_MatterAction>(
                    value: _MatterAction.delete,
                    child: Text(menuContext.l10n.deleteAction),
                  ),
                ],
                onSelected: (value) async {
                  await onAction(matter, value);
                },
              ),
            );
          },
          child: ListTile(
            key: ValueKey<String>('sidebar_matter_row_$matterRowKey'),
            dense: true,
            selected:
                selectedMatterId == matter.id &&
                selectedMatterRowKey == matterRowKey,
            leading: _MatterLeadingIcon(
              iconKey: matter.icon,
              isPinned: matter.isPinned,
              isMacOS: false,
            ),
            title: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    matter.title,
                    style: _materialSidebarItemLabelStyle(
                      context,
                      selected:
                          selectedMatterId == matter.id &&
                          selectedMatterRowKey == matterRowKey,
                    ),
                  ),
                ),
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
            onTap: () => onSelect(matter, matterRowKey),
          ),
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
          key: ValueKey<String>('sidebar_matter_reassign_drag_${matter.id}'),
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
