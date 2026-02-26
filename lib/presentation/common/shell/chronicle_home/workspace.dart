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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      selected.title,
                                      style: isMacOSNativeUI
                                          ? MacosTheme.of(
                                              context,
                                            ).typography.title3
                                          : Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      l10n.conflictTypeRow(
                                        _conflictTypeLabel(selected.type, l10n),
                                      ),
                                    ),
                                    Text(
                                      l10n.conflictFileRow(
                                        selected.conflictPath,
                                      ),
                                    ),
                                    Text(
                                      l10n.conflictOriginalRow(
                                        selected.originalPath,
                                      ),
                                    ),
                                    Text(
                                      l10n.conflictLocalRow(
                                        selected.localDevice,
                                      ),
                                    ),
                                    Text(
                                      l10n.conflictRemoteRow(
                                        selected.remoteDevice,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: <Widget>[
                                        isMacOSNativeUI
                                            ? PushButton(
                                                controlSize:
                                                    ControlSize.regular,
                                                secondary: true,
                                                onPressed:
                                                    selected.originalNoteId ==
                                                        null
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
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: <Widget>[
                                                    const MacosIcon(
                                                      CupertinoIcons
                                                          .arrow_up_right_square,
                                                      size: 13,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      l10n.openMainNoteAction,
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : OutlinedButton.icon(
                                                onPressed:
                                                    selected.originalNoteId ==
                                                        null
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
                                                icon: const Icon(
                                                  Icons.open_in_new,
                                                ),
                                                label: Text(
                                                  l10n.openMainNoteAction,
                                                ),
                                              ),
                                        isMacOSNativeUI
                                            ? PushButton(
                                                controlSize:
                                                    ControlSize.regular,
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
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: <Widget>[
                                                    const MacosIcon(
                                                      CupertinoIcons.check_mark,
                                                      size: 13,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      l10n.markResolvedAction,
                                                    ),
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
                                          child: _adaptiveLoadingIndicator(
                                            context,
                                          ),
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
                                            return Text(
                                              l10n.conflictContentEmpty,
                                            );
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
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                            padding: const EdgeInsets.all(8),
                                            child: selected.isNote
                                                ? ChronicleMarkdown(
                                                    data: content,
                                                  )
                                                : SingleChildScrollView(
                                                    child: SelectableText(
                                                      content,
                                                    ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: ChronicleNoteTitleHeader(
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

    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final useCompactEditorOnly =
            isMacOSNativeUI && constraints.maxWidth < kMacosCompactContentWidth;
        if (useCompactEditorOnly) {
          return const _NoteEditorPane();
        }
        return Row(
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
            ),
            const VerticalDivider(width: 1),
            const Expanded(child: _NoteEditorPane()),
          ],
        );
      },
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
          child: ChronicleNoteTitleHeader(
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
              return Row(
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
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: Text(l10n.cancelAction),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
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
                  ),
                  const VerticalDivider(width: 1),
                  const Expanded(child: _NoteEditorPane()),
                ],
              );
            },
          ),
        ),
      ],
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

    if (isMacOSNativeUI) {
      return ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: notes.length,
        separatorBuilder: (_, index) => const SizedBox(height: 2),
        itemBuilder: (_, index) {
          final note = notes[index];
          final row = ChronicleMacosSelectableRow(
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
