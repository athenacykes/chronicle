part of '../chronicle_home_coordinator.dart';

class _MainWorkspace extends ConsumerWidget {
  const _MainWorkspace({
    required this.searchHits,
    required this.searchQuery,
    required this.showSearchResults,
    required this.onOpenSearchResult,
  });

  final List<SearchListItem> searchHits;
  final String searchQuery;
  final bool showSearchResults;
  final Future<void> Function(String noteId) onOpenSearchResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final showConflicts = ref.watch(showConflictsProvider);
    if (showConflicts) {
      return const _ConflictWorkspace();
    }

    if (_hasSearchText(searchQuery) && showSearchResults) {
      return ChronicleSearchResultsView(
        results: searchHits,
        useMacOSNativeUI: _isMacOSNativeUIContext(context),
        onOpenResult: onOpenSearchResult,
      );
    }

    final selectedTimeView = ref.watch(selectedTimeViewProvider);
    if (selectedTimeView != null) {
      return const _TimeViewWorkspace();
    }

    final showNotebook = ref.watch(showNotebookProvider);
    if (showNotebook) {
      return const _NotebookWorkspace();
    }

    final sections = ref.watch(mattersControllerProvider).asData?.value;
    final selectedMatterId = ref.watch(selectedMatterIdProvider);
    if (selectedMatterId == null) {
      return const _WelcomeTourWorkspace();
    }
    if (sections == null) {
      return Center(child: Text(l10n.selectMatterNotebookOrConflictsPrompt));
    }

    final selected = _findMatterById(sections, selectedMatterId);

    if (selected == null) {
      return Center(child: Text(l10n.matterNoLongerExistsMessage));
    }

    return _MatterWorkspace(matter: selected);
  }
}

class _WelcomeTourWorkspace extends ConsumerWidget {
  const _WelcomeTourWorkspace();

  Future<void> _createMatter(BuildContext context, WidgetRef ref) async {
    final selectedMatterId = ref.read(selectedMatterIdProvider);
    final defaultCategoryId = selectedMatterId == null
        ? null
        : ref
              .read(mattersControllerProvider.notifier)
              .findMatter(selectedMatterId)
              ?.categoryId;
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

  void _openNotebook(WidgetRef ref) {
    unawaited(
      ref
          .read(noteEditorControllerProvider.notifier)
          .openNotebookFolderInWorkspace(null),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final titleStyle = isMacOSNativeUI
        ? MacosTheme.of(
            context,
          ).typography.title2.copyWith(fontWeight: MacosFontWeight.w700)
        : Theme.of(context).textTheme.headlineSmall;
    final subtitleStyle = isMacOSNativeUI
        ? MacosTheme.of(context).typography.body
        : Theme.of(context).textTheme.bodyMedium;
    final panelDecoration = isMacOSNativeUI
        ? _macosPanelDecoration(context)
        : BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
          );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Container(
            key: const Key('welcome_tour_panel'),
            decoration: panelDecoration,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l10n.welcomeTourHeadline, style: titleStyle),
                const SizedBox(height: 10),
                Text(l10n.welcomeTourDescription, style: subtitleStyle),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    _WelcomeTourStepCard(
                      icon: isMacOSNativeUI
                          ? CupertinoIcons.square_grid_2x2
                          : Icons.workspaces_outline,
                      title: l10n.welcomeTourMatterStepTitle,
                      description: l10n.welcomeTourMatterStepDescription,
                    ),
                    _WelcomeTourStepCard(
                      icon: isMacOSNativeUI
                          ? CupertinoIcons.arrow_right_circle
                          : Icons.alt_route,
                      title: l10n.welcomeTourPhaseStepTitle,
                      description: l10n.welcomeTourPhaseStepDescription,
                    ),
                    _WelcomeTourStepCard(
                      icon: isMacOSNativeUI
                          ? CupertinoIcons.doc_text
                          : Icons.sticky_note_2_outlined,
                      title: l10n.welcomeTourNoteStepTitle,
                      description: l10n.welcomeTourNoteStepDescription,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    if (isMacOSNativeUI)
                      PushButton(
                        key: const Key('welcome_tour_create_matter_button'),
                        controlSize: ControlSize.large,
                        onPressed: () async {
                          await _createMatter(context, ref);
                        },
                        child: Text(l10n.welcomeTourCreateMatterAction),
                      )
                    else
                      FilledButton.icon(
                        key: const Key('welcome_tour_create_matter_button'),
                        onPressed: () async {
                          await _createMatter(context, ref);
                        },
                        icon: const Icon(Icons.add_circle_outline),
                        label: Text(l10n.welcomeTourCreateMatterAction),
                      ),
                    if (isMacOSNativeUI)
                      PushButton(
                        key: const Key('welcome_tour_open_notebook_button'),
                        controlSize: ControlSize.large,
                        secondary: true,
                        onPressed: () {
                          _openNotebook(ref);
                        },
                        child: Text(l10n.welcomeTourOpenNotebookAction),
                      )
                    else
                      OutlinedButton.icon(
                        key: const Key('welcome_tour_open_notebook_button'),
                        onPressed: () {
                          _openNotebook(ref);
                        },
                        icon: const Icon(Icons.menu_book_outlined),
                        label: Text(l10n.welcomeTourOpenNotebookAction),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeTourStepCard extends StatelessWidget {
  const _WelcomeTourStepCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final borderColor = isMacOSNativeUI
        ? MacosTheme.of(context).dividerColor
        : Theme.of(context).dividerColor;
    final titleStyle = isMacOSNativeUI
        ? MacosTheme.of(
            context,
          ).typography.headline.copyWith(fontWeight: MacosFontWeight.w600)
        : Theme.of(context).textTheme.titleSmall;
    final bodyStyle = isMacOSNativeUI
        ? MacosTheme.of(context).typography.caption1
        : Theme.of(context).textTheme.bodySmall;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 264),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20),
            const SizedBox(height: 8),
            Text(title, style: titleStyle),
            const SizedBox(height: 6),
            Text(description, style: bodyStyle),
          ],
        ),
      ),
    );
  }
}

class _TimeViewWorkspace extends ConsumerWidget {
  const _TimeViewWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final summaryAsync = ref.watch(timeViewSummaryProvider);
    final sections = ref.watch(mattersControllerProvider).asData?.value;
    final folders =
        ref.watch(notebookFoldersProvider).asData?.value ?? <NotebookFolder>[];
    final matterById = <String, Matter>{};
    if (sections != null) {
      for (final matter in _allMattersFromSections(sections)) {
        matterById[matter.id] = matter;
      }
    }
    final notebookFolderById = <String, NotebookFolder>{
      for (final folder in folders) folder.id: folder,
    };

    return summaryAsync.when(
      loading: () => Center(child: _adaptiveLoadingIndicator(context)),
      error: (error, _) => Center(child: Text('$error')),
      data: (summary) {
        if (summary == null) {
          return Center(
            child: Text(l10n.selectMatterNotebookOrConflictsPrompt),
          );
        }
        return ChronicleTimeViewsWorkspace(
          summary: summary,
          matterById: matterById,
          notebookFolderById: notebookFolderById,
          useMacOSNativeUI: _isMacOSNativeUIContext(context),
          onOpenNote: (noteId) {
            return ref
                .read(noteEditorControllerProvider.notifier)
                .openNoteInWorkspace(noteId, openInReadMode: true);
          },
        );
      },
    );
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
    final selectedDetail = ref.watch(selectedConflictDetailProvider);

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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final listPaneWidth = (constraints.maxWidth * 0.38)
                      .clamp(220.0, 380.0)
                      .toDouble();
                  return Row(
                    children: <Widget>[
                      SizedBox(
                        width: listPaneWidth,
                        child: conflicts.isEmpty
                            ? Center(
                                child: Text(l10n.noConflictsDetectedMessage),
                              )
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
                                      child: ChronicleMacosSelectableRow(
                                        selected: isSelected,
                                        title: Row(
                                          children: <Widget>[
                                            Expanded(
                                              child: Text(conflict.title),
                                            ),
                                            _ConflictTypeChip(
                                              type: conflict.type,
                                            ),
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
                                            conflictsControllerProvider
                                                .notifier,
                                          )
                                          .selectConflict(
                                            conflict.conflictPath,
                                          );
                                    },
                                  );
                                },
                              ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: selected == null
                            ? Center(
                                child: Text(l10n.selectConflictToReviewPrompt),
                              )
                            : Padding(
                                padding: const EdgeInsets.all(12),
                                child: ChronicleConflictReviewPane(
                                  conflict: selected,
                                  detail: selectedDetail,
                                  useMacOSNativeUI: isMacOSNativeUI,
                                  onOpenMainNote:
                                      selected.originalNoteId == null
                                      ? null
                                      : () {
                                          unawaited(
                                            ref
                                                .read(
                                                  noteEditorControllerProvider
                                                      .notifier,
                                                )
                                                .openNoteInWorkspace(
                                                  selected.originalNoteId!,
                                                ),
                                          );
                                          ref
                                              .read(
                                                showConflictsProvider.notifier,
                                              )
                                              .set(false);
                                        },
                                  onAcceptLeft: () {
                                    unawaited(
                                      ref
                                          .read(
                                            conflictsControllerProvider
                                                .notifier,
                                          )
                                          .resolveConflict(
                                            selected.conflictPath,
                                            choice: SyncConflictResolutionChoice
                                                .acceptLeft,
                                          )
                                          .then((_) {
                                            ref
                                                .read(
                                                  conflictsControllerProvider
                                                      .notifier,
                                                )
                                                .selectConflict(null);
                                          }),
                                    );
                                  },
                                  onAcceptRight: () {
                                    unawaited(
                                      ref
                                          .read(
                                            conflictsControllerProvider
                                                .notifier,
                                          )
                                          .resolveConflict(
                                            selected.conflictPath,
                                            choice: SyncConflictResolutionChoice
                                                .acceptRight,
                                          )
                                          .then((_) {
                                            ref
                                                .read(
                                                  conflictsControllerProvider
                                                      .notifier,
                                                )
                                                .selectConflict(null);
                                          }),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
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

class _MatterWorkspace extends ConsumerWidget {
  const _MatterWorkspace({required this.matter});

  final Matter matter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(matterViewModeProvider);
    final currentNote = ref.watch(noteEditorControllerProvider).value;
    final draft = ref.watch(notebookDraftSessionProvider);
    final isResolvingWorkspace = ref.watch(isResolvingWorkspaceNoteProvider);
    final matterDraft = draft != null && draft.matterId == matter.id
        ? draft
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: currentNote == null && matterDraft != null
              ? _NotebookDraftTitleHeader(draft: matterDraft)
              : currentNote == null && isResolvingWorkspace
              ? const _WorkspaceTitleSkeleton()
              : ChronicleNoteTitleHeader(
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

class _MatterNotesWorkspace extends ConsumerWidget {
  const _MatterNotesWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notes = ref.watch(noteListProvider);
    final settings = ref.watch(settingsControllerProvider).asData?.value;

    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final useCompactEditorOnly =
            isMacOSNativeUI && constraints.maxWidth < kMacosCompactContentWidth;
        if (useCompactEditorOnly) {
          return const _NoteEditorPane();
        }
        return _ResizableNoteEditorSplitPane(
          listPaneKey: _kMatterNoteListPaneKey,
          resizeHandleKey: _kMatterNoteListResizeHandleKey,
          storedPaneWidth:
              settings?.matterNoteListPaneWidth ?? _kDefaultNoteListPaneWidth,
          onWidthCommitted: (width) async {
            await ref
                .read(settingsControllerProvider.notifier)
                .setMatterNoteListPaneWidth(width);
          },
          listPane: notes.when(
            loading: () => Center(child: _adaptiveLoadingIndicator(context)),
            error: (error, _) => Center(child: Text('$error')),
            data: (items) => _NoteList(
              notes: items,
              onEdit: (note) async {
                final result = await showDialog<ChronicleNoteDialogResult>(
                  context: context,
                  builder: (_) => ChronicleNoteDialog(
                    mode: ChronicleNoteDialogMode.edit,
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
                return showChronicleLinkNoteDialogFlow(
                  context: context,
                  sourceNote: note,
                  useMacOSNativeUI: _isMacOSNativeUIContext(context),
                  loadAllNotes: () =>
                      ref.read(allNotesForLinkPickerProvider.future),
                  createLink: (result) async {
                    await ref
                        .read(linksControllerProvider)
                        .createLink(
                          sourceNoteId: note.id,
                          targetNoteId: result.targetNoteId,
                          context: result.context,
                        );
                  },
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
        );
      },
    );
  }
}

Future<void> _openNoteInPhaseEditor(WidgetRef ref, Note note) async {
  await ref
      .read(noteEditorControllerProvider.notifier)
      .openNoteInWorkspace(note.id);
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
            Future<void> handleTimelineMenuSelection(String value) async {
              switch (value) {
                case 'move_matter':
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
                  return;
                case 'move_phase':
                  final matterId = note.matterId;
                  if (matterId == null) {
                    return;
                  }
                  final sourceMatter = ref
                      .read(mattersControllerProvider.notifier)
                      .findMatter(matterId);
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
                  return;
                case 'move_notebook':
                  await _moveNoteToNotebookViaDialog(
                    context: context,
                    ref: ref,
                    note: note,
                  );
                  return;
              }
            }

            final card = GestureDetector(
              key: ValueKey<String>('timeline_note_card_${note.id}'),
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: (details) {
                if (isMacOSNativeUI) {
                  unawaited(
                    _showMacosSecondaryClickMenu<String>(
                      context: context,
                      details: details,
                      itemBuilder: (menuContext) => <MacosPulldownMenuEntry>[
                        ChronicleMacosContextMenuItem<String>(
                          value: 'move_matter',
                          title: Text(menuContext.l10n.moveNoteToMatterAction),
                        ),
                        ChronicleMacosContextMenuItem<String>(
                          value: 'move_phase',
                          enabled: note.matterId != null,
                          title: Text(menuContext.l10n.moveNoteToPhaseAction),
                        ),
                        ChronicleMacosContextMenuItem<String>(
                          value: 'move_notebook',
                          title: Text(menuContext.l10n.moveToNotebookAction),
                        ),
                      ],
                      onSelected: handleTimelineMenuSelection,
                    ),
                  );
                  return;
                }
                unawaited(
                  _showSecondaryClickMenu<String>(
                    context: context,
                    details: details,
                    itemBuilder: (menuContext) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'move_matter',
                        child: Text(menuContext.l10n.moveNoteToMatterAction),
                      ),
                      PopupMenuItem<String>(
                        value: 'move_phase',
                        enabled: note.matterId != null,
                        child: Text(menuContext.l10n.moveNoteToPhaseAction),
                      ),
                      PopupMenuItem<String>(
                        value: 'move_notebook',
                        child: Text(menuContext.l10n.moveToNotebookAction),
                      ),
                    ],
                    onSelected: handleTimelineMenuSelection,
                  ),
                );
              },
              child: Container(
                decoration: isMacOSNativeUI
                    ? _macosPanelDecoration(context)
                    : BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
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

class _NotebookWorkspace extends ConsumerWidget {
  const _NotebookWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notes = ref.watch(notebookNoteListProvider);
    final settings = ref.watch(settingsControllerProvider).asData?.value;
    final currentNote = ref.watch(noteEditorControllerProvider).value;
    final allDraft = ref.watch(notebookDraftSessionProvider);
    final isResolvingWorkspace = ref.watch(isResolvingWorkspaceNoteProvider);
    final notebookDraft = allDraft != null && allDraft.matterId == null
        ? allDraft
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: currentNote == null && notebookDraft != null
              ? _NotebookDraftTitleHeader(draft: notebookDraft)
              : currentNote == null && isResolvingWorkspace
              ? const _WorkspaceTitleSkeleton()
              : ChronicleNoteTitleHeader(
                  note: currentNote,
                  canEdit: currentNote?.isInNotebook ?? false,
                ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useCompactEditorOnly =
                  _isMacOSNativeUIContext(context) &&
                  constraints.maxWidth < kMacosCompactContentWidth;
              if (useCompactEditorOnly) {
                return const _NoteEditorPane();
              }
              return _ResizableNoteEditorSplitPane(
                listPaneKey: _kNotebookNoteListPaneKey,
                resizeHandleKey: _kNotebookNoteListResizeHandleKey,
                storedPaneWidth:
                    settings?.notebookNoteListPaneWidth ??
                    _kDefaultNoteListPaneWidth,
                onWidthCommitted: (width) async {
                  await ref
                      .read(settingsControllerProvider.notifier)
                      .setNotebookNoteListPaneWidth(width);
                },
                listPane: notes.when(
                  loading: () =>
                      Center(child: _adaptiveLoadingIndicator(context)),
                  error: (error, _) => Center(child: Text('$error')),
                  data: (items) => _NoteList(
                    notes: items,
                    onEdit: (note) async {
                      final result =
                          await showDialog<ChronicleNoteDialogResult>(
                            context: context,
                            builder: (_) => ChronicleNoteDialog(
                              mode: ChronicleNoteDialogMode.edit,
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
                      return showChronicleLinkNoteDialogFlow(
                        context: context,
                        sourceNote: note,
                        useMacOSNativeUI: _isMacOSNativeUIContext(context),
                        loadAllNotes: () =>
                            ref.read(allNotesForLinkPickerProvider.future),
                        createLink: (result) async {
                          await ref
                              .read(linksControllerProvider)
                              .createLink(
                                sourceNoteId: note.id,
                                targetNoteId: result.targetNoteId,
                                context: result.context,
                              );
                        },
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
              );
            },
          ),
        ),
      ],
    );
  }
}

const double _kDefaultNoteListPaneWidth = 380;
const double _kMinNoteListPaneWidth = 180;
const double _kMinEditorPaneWidth = 360;
const double _kNoteListResizeHandleWidth = 12;
const Key _kMatterNoteListPaneKey = Key('matter_note_list_pane');
const Key _kMatterNoteListResizeHandleKey = Key(
  'matter_note_list_resize_handle',
);
const Key _kNotebookNoteListPaneKey = Key('notebook_note_list_pane');
const Key _kNotebookNoteListResizeHandleKey = Key(
  'notebook_note_list_resize_handle',
);

class _ResizableNoteEditorSplitPane extends StatefulWidget {
  const _ResizableNoteEditorSplitPane({
    required this.listPane,
    required this.storedPaneWidth,
    required this.onWidthCommitted,
    required this.listPaneKey,
    required this.resizeHandleKey,
  });

  final Widget listPane;
  final double storedPaneWidth;
  final Future<void> Function(double width) onWidthCommitted;
  final Key listPaneKey;
  final Key resizeHandleKey;

  @override
  State<_ResizableNoteEditorSplitPane> createState() =>
      _ResizableNoteEditorSplitPaneState();
}

class _ResizableNoteEditorSplitPaneState
    extends State<_ResizableNoteEditorSplitPane> {
  late double _currentPaneWidth;
  double _maxPaneWidthForLayout = _kDefaultNoteListPaneWidth;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _currentPaneWidth = widget.storedPaneWidth;
  }

  @override
  void didUpdateWidget(covariant _ResizableNoteEditorSplitPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isDragging) {
      return;
    }
    if ((widget.storedPaneWidth - oldWidget.storedPaneWidth).abs() > 0.01) {
      _currentPaneWidth = widget.storedPaneWidth;
    }
  }

  double _effectiveMaxPaneWidth(double availableWidth) {
    final maxWidth =
        availableWidth - _kNoteListResizeHandleWidth - _kMinEditorPaneWidth;
    return math.max(_kMinNoteListPaneWidth, maxWidth);
  }

  double _clampPaneWidth(double width, double maxPaneWidth) {
    return width.clamp(_kMinNoteListPaneWidth, maxPaneWidth).toDouble();
  }

  void _updateWidthByDelta(double deltaX) {
    final maxPaneWidth = _maxPaneWidthForLayout;
    final updated = _clampPaneWidth(_currentPaneWidth + deltaX, maxPaneWidth);
    if ((updated - _currentPaneWidth).abs() <= 0.01) {
      return;
    }
    setState(() {
      _currentPaneWidth = updated;
    });
  }

  void _finishDrag() {
    final clamped = _clampPaneWidth(_currentPaneWidth, _maxPaneWidthForLayout);
    if (!_isDragging && (clamped - _currentPaneWidth).abs() <= 0.01) {
      return;
    }
    setState(() {
      _isDragging = false;
      _currentPaneWidth = clamped;
    });
    unawaited(widget.onWidthCommitted(clamped));
  }

  @override
  Widget build(BuildContext context) {
    final dividerColor = _isMacOSNativeUIContext(context)
        ? MacosTheme.of(context).dividerColor
        : Theme.of(context).dividerColor;
    final handleColor = _isDragging
        ? Theme.of(context).colorScheme.primary
        : dividerColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxPaneWidth = _effectiveMaxPaneWidth(constraints.maxWidth);
        _maxPaneWidthForLayout = maxPaneWidth;
        final paneWidth = _clampPaneWidth(_currentPaneWidth, maxPaneWidth);
        return Row(
          children: <Widget>[
            SizedBox(
              key: widget.listPaneKey,
              width: paneWidth,
              child: widget.listPane,
            ),
            SizedBox(
              key: widget.resizeHandleKey,
              width: _kNoteListResizeHandleWidth,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) {
                    setState(() {
                      _isDragging = true;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    _updateWidthByDelta(details.delta.dx);
                  },
                  onHorizontalDragEnd: (_) {
                    _finishDrag();
                  },
                  onHorizontalDragCancel: _finishDrag,
                  child: Center(child: Container(width: 1, color: handleColor)),
                ),
              ),
            ),
            const Expanded(child: _NoteEditorPane()),
          ],
        );
      },
    );
  }
}

const Key _kNotebookDraftTitleFieldKey = Key('notebook_draft_title_field');
const Key _kWorkspaceTitleSkeletonKey = Key('workspace_title_skeleton');

String _draftSessionContextKey(NotebookDraftSession draft) {
  if (draft.matterId != null) {
    return 'matter:${draft.matterId}:${draft.phaseId ?? ''}:${draft.draftSessionToken}';
  }
  return 'notebook:${draft.folderId ?? ''}:${draft.draftSessionToken}';
}

class _WorkspaceTitleSkeleton extends StatelessWidget {
  const _WorkspaceTitleSkeleton();

  @override
  Widget build(BuildContext context) {
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final color = isMacOSNativeUI
        ? MacosTheme.brightnessOf(
            context,
          ).resolve(const Color(0xFFE4E4E4), const Color(0xFF3A3D42))
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final borderColor = isMacOSNativeUI
        ? MacosTheme.of(context).dividerColor
        : Theme.of(context).dividerColor;

    return Container(
      key: _kWorkspaceTitleSkeletonKey,
      height: 34,
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        width: 220,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(7),
        ),
      ),
    );
  }
}

class _NotebookDraftTitleHeader extends ConsumerStatefulWidget {
  const _NotebookDraftTitleHeader({required this.draft});

  final NotebookDraftSession draft;

  @override
  ConsumerState<_NotebookDraftTitleHeader> createState() =>
      _NotebookDraftTitleHeaderState();
}

class _NotebookDraftTitleHeaderState
    extends ConsumerState<_NotebookDraftTitleHeader> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.draft.title;
  }

  @override
  void didUpdateWidget(covariant _NotebookDraftTitleHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contextChanged =
        _draftSessionContextKey(oldWidget.draft) !=
        _draftSessionContextKey(widget.draft);
    if (contextChanged || !_focusNode.hasFocus) {
      final draftTitle = widget.draft.title;
      if (_controller.text != draftTitle) {
        _controller.text = draftTitle;
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    Future<void> saveDraft() async {
      await ref
          .read(noteEditorControllerProvider.notifier)
          .flushNotebookDraftAutosave();
    }

    if (isMacOSNativeUI) {
      return MacosTextField(
        key: _kNotebookDraftTitleFieldKey,
        focusNode: _focusNode,
        controller: _controller,
        placeholder: l10n.titleLabel,
        onChanged: (value) {
          ref
              .read(noteEditorControllerProvider.notifier)
              .updateNotebookDraft(title: value);
        },
        onSubmitted: (_) {
          unawaited(saveDraft());
        },
        onEditingComplete: () {
          unawaited(saveDraft());
        },
      );
    }

    return TextField(
      key: _kNotebookDraftTitleFieldKey,
      focusNode: _focusNode,
      controller: _controller,
      decoration: InputDecoration(
        isDense: true,
        hintText: l10n.titleLabel,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        ref
            .read(noteEditorControllerProvider.notifier)
            .updateNotebookDraft(title: value);
      },
      onSubmitted: (_) {
        unawaited(saveDraft());
      },
      onEditingComplete: () {
        unawaited(saveDraft());
      },
    );
  }
}

const Key _kMacosCompactNotePickerKey = Key('macos_compact_note_picker');

class _CompactPanelNotePicker extends ConsumerWidget {
  const _CompactPanelNotePicker({required this.notesAsync});

  final AsyncValue<List<Note>> notesAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Container(
      key: _kMacosCompactNotePickerKey,
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: BoxDecoration(
        border: Border.all(color: MacosTheme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: notesAsync.when(
        loading: () => Center(child: _adaptiveLoadingIndicator(context)),
        error: (error, _) =>
            Padding(padding: const EdgeInsets.all(8), child: Text('$error')),
        data: (notes) {
          if (notes.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Text(l10n.noNotesYetMessage),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            itemCount: notes.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: MacosTheme.of(context).dividerColor),
            itemBuilder: (context, index) {
              final note = notes[index];
              final title = note.title.trim().isEmpty
                  ? l10n.untitledLabel
                  : note.title.trim();
              final subtitle = note.content.replaceAll('\n', ' ').trim();
              return GestureDetector(
                key: ValueKey<String>('macos_compact_note_picker_${note.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  await ref
                      .read(noteEditorControllerProvider.notifier)
                      .selectNote(note.id);
                  if (context.mounted) {
                    Navigator.of(context).maybePop();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MacosTheme.of(
                          context,
                        ).typography.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (subtitle.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MacosTheme.of(context).typography.caption1,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
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

    Future<void> handleNoteMenuSelection(Note note, String value) async {
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
    }

    List<PopupMenuEntry<String>> buildNoteMenuEntries(
      BuildContext menuContext,
      Note note,
    ) {
      return <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'edit',
          child: Text(menuContext.l10n.editAction),
        ),
        PopupMenuItem<String>(
          value: 'toggle_pin',
          child: Text(
            note.isPinned
                ? menuContext.l10n.unpinAction
                : menuContext.l10n.pinAction,
          ),
        ),
        PopupMenuItem<String>(
          value: 'link',
          child: Text(menuContext.l10n.linkNoteActionEllipsis),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'move_matter',
          child: Text(menuContext.l10n.moveNoteToMatterAction),
        ),
        PopupMenuItem<String>(
          value: 'move_phase',
          enabled: note.matterId != null,
          child: Text(menuContext.l10n.moveNoteToPhaseAction),
        ),
        PopupMenuItem<String>(
          value: 'move_notebook',
          child: Text(menuContext.l10n.moveToNotebookAction),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text(menuContext.l10n.deleteAction),
        ),
      ];
    }

    List<MacosPulldownMenuEntry> buildMacosNoteMenuEntries(
      BuildContext menuContext,
      Note note,
    ) {
      return <MacosPulldownMenuEntry>[
        ChronicleMacosContextMenuItem<String>(
          value: 'edit',
          title: Text(menuContext.l10n.editAction),
        ),
        ChronicleMacosContextMenuItem<String>(
          value: 'toggle_pin',
          title: Text(
            note.isPinned
                ? menuContext.l10n.unpinAction
                : menuContext.l10n.pinAction,
          ),
        ),
        ChronicleMacosContextMenuItem<String>(
          value: 'link',
          title: Text(menuContext.l10n.linkNoteActionEllipsis),
        ),
        const MacosPulldownMenuDivider(),
        ChronicleMacosContextMenuItem<String>(
          value: 'move_matter',
          title: Text(menuContext.l10n.moveNoteToMatterAction),
        ),
        ChronicleMacosContextMenuItem<String>(
          value: 'move_phase',
          enabled: note.matterId != null,
          title: Text(menuContext.l10n.moveNoteToPhaseAction),
        ),
        ChronicleMacosContextMenuItem<String>(
          value: 'move_notebook',
          title: Text(menuContext.l10n.moveToNotebookAction),
        ),
        const MacosPulldownMenuDivider(),
        ChronicleMacosContextMenuItem<String>(
          value: 'delete',
          title: Text(menuContext.l10n.deleteAction),
        ),
      ];
    }

    if (isMacOSNativeUI) {
      return ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: notes.length,
        separatorBuilder: (_, index) => const SizedBox(height: 2),
        itemBuilder: (_, index) {
          final note = notes[index];
          final row = ChronicleMacosSelectableRow(
            key: ValueKey<String>('phase_note_row_${note.id}'),
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
            onSecondaryTapDown: (details) {
              unawaited(
                _showMacosSecondaryClickMenu<String>(
                  context: context,
                  details: details,
                  itemBuilder: (menuContext) =>
                      buildMacosNoteMenuEntries(menuContext, note),
                  onSelected: (value) async {
                    await handleNoteMenuSelection(note, value);
                  },
                ),
              );
            },
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
        final tile = GestureDetector(
          key: ValueKey<String>('phase_note_row_${note.id}'),
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) {
            unawaited(
              _showSecondaryClickMenu<String>(
                context: context,
                details: details,
                itemBuilder: (menuContext) =>
                    buildNoteMenuEntries(menuContext, note),
                onSelected: (value) async {
                  await handleNoteMenuSelection(note, value);
                },
              ),
            );
          },
          child: ListTile(
            selected: note.id == selectedNoteId,
            title: Text(note.title.isEmpty ? l10n.untitledLabel : note.title),
            subtitle: Text(
              note.content.replaceAll('\n', ' '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () async {
              await ref
                  .read(noteEditorControllerProvider.notifier)
                  .selectNote(note.id);
            },
          ),
        );
        return buildDraggable(note: note, scope: 'list_material', child: tile);
      },
    );
  }
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
