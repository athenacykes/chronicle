part of '../chronicle_home_coordinator.dart';

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
        child: ChronicleAttachmentsPanel(
          note: note,
          storageRootPath: storageRootPath,
          useMacOSNativeUI: isMacOSNativeUI,
          onAttach: () => _attachFiles(context),
          onRemoveAttachment: (attachmentPath) =>
              _removeAttachment(context, attachmentPath),
          onOpenAttachment: (absolutePath) =>
              _openAttachment(context, absolutePath),
        ),
      );
    }

    Future<void> showLinkDialog() async {
      await showChronicleLinkNoteDialogFlow(
        context: context,
        sourceNote: note,
        useMacOSNativeUI: isMacOSNativeUI,
        loadAllNotes: () => ref.read(allNotesForLinkPickerProvider.future),
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
    }

    Future<void> showLinkedNotesDialog() async {
      await showUtilityDialog(
        title: l10n.noteLinkedNotesUtilityTitle,
        child: ChronicleLinkedNotesPanel(
          sourceNote: note,
          linkedNotesAsync: linkedNotesAsync,
          useMacOSNativeUI: isMacOSNativeUI,
          onCreateLink: showLinkDialog,
          onOpenLinkedNote: (noteId) async {
            await ref
                .read(noteEditorControllerProvider.notifier)
                .selectNote(noteId);
          },
          onRemoveLink: (item) async {
            await ref
                .read(linksControllerProvider)
                .deleteLink(currentNoteId: note.id, link: item.link);
          },
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
        ? ChronicleMacosCompactIconButton(
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
        ? ChronicleMacosCompactIconButton(
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
        ? ChronicleMacosCompactIconButton(
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
