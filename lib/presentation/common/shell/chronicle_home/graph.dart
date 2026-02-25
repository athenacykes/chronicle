part of '../chronicle_home_coordinator.dart';

class _MatterGraphWorkspace extends ConsumerWidget {
  const _MatterGraphWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUIContext(context);
    final graphState = ref.watch(graphControllerProvider);
    final selectedNoteId = ref.watch(selectedNoteIdProvider);
    final dragPayloadNotifier = ref.read(
      _activeNoteDragPayloadProvider.notifier,
    );

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
                child: ChronicleGraphCanvas(
                  graph: view.graph,
                  selectedNoteId: selectedNoteId,
                  onTapNode: (noteId) async {
                    await _showGraphNodePreview(
                      context: context,
                      ref: ref,
                      noteId: noteId,
                    );
                  },
                  createDragPayload: (node) => _NoteDragPayload(
                    noteId: node.noteId,
                    matterId: node.matterId,
                    phaseId: node.phaseId,
                  ),
                  onDragStarted: (payload) {
                    dragPayloadNotifier.set(payload as _NoteDragPayload);
                  },
                  onDragEnded: () {
                    dragPayloadNotifier.set(null);
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
                  return ChronicleGraphNodePreviewCard(
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
