import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

import '../../../domain/entities/note.dart';
import '../../../l10n/localization.dart';
import '../../links/links_controller.dart';
import '../../notes/note_attachment_widgets.dart';
import 'chronicle_link_note_dialog.dart';

class ChronicleAttachmentsPanel extends StatelessWidget {
  const ChronicleAttachmentsPanel({
    super.key,
    required this.note,
    required this.storageRootPath,
    required this.useMacOSNativeUI,
    required this.onAttach,
    required this.onOpenAttachment,
    required this.onRemoveAttachment,
  });

  final Note note;
  final String? storageRootPath;
  final bool useMacOSNativeUI;
  final Future<void> Function() onAttach;
  final Future<void> Function(String absolutePath) onOpenAttachment;
  final Future<void> Function(String attachmentPath) onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasStorageRoot =
        storageRootPath != null && storageRootPath!.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: useMacOSNativeUI
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
                  style: useMacOSNativeUI
                      ? MacosTheme.of(context).typography.headline
                      : Theme.of(context).textTheme.titleSmall,
                ),
              ),
              useMacOSNativeUI
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

class ChronicleLinkedNotesPanel extends StatelessWidget {
  const ChronicleLinkedNotesPanel({
    super.key,
    required this.sourceNote,
    required this.linkedNotesAsync,
    required this.useMacOSNativeUI,
    required this.onCreateLink,
    required this.onOpenLinkedNote,
    required this.onRemoveLink,
  });

  final Note sourceNote;
  final AsyncValue<List<LinkedNoteItem>> linkedNotesAsync;
  final bool useMacOSNativeUI;
  final Future<void> Function() onCreateLink;
  final Future<void> Function(String noteId) onOpenLinkedNote;
  final Future<void> Function(LinkedNoteItem item) onRemoveLink;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final linkedCount = linkedNotesAsync.asData?.value.length ?? 0;

    return Container(
      width: double.infinity,
      decoration: useMacOSNativeUI
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
                  style: useMacOSNativeUI
                      ? MacosTheme.of(context).typography.headline
                      : Theme.of(context).textTheme.titleSmall,
                ),
              ),
              useMacOSNativeUI
                  ? _ChronicleMacosCompactIconButton(
                      tooltip: l10n.linkNoteAction,
                      onPressed: () async {
                        await onCreateLink();
                      },
                      icon: const MacosIcon(CupertinoIcons.link),
                    )
                  : IconButton(
                      tooltip: l10n.linkNoteAction,
                      onPressed: () async {
                        await onCreateLink();
                      },
                      icon: const Icon(Icons.add_link),
                    ),
            ],
          ),
          SizedBox(
            height: linkedCount == 0 ? 36 : 130,
            child: linkedNotesAsync.when(
              loading: () => Center(
                child: useMacOSNativeUI
                    ? const ProgressCircle()
                    : const CircularProgressIndicator(),
              ),
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
                    if (useMacOSNativeUI) {
                      return _ChronicleMacosSelectableRow(
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
                            _ChronicleMacosCompactIconButton(
                              tooltip: l10n.openLinkedNoteAction,
                              onPressed: () async {
                                await onOpenLinkedNote(item.relatedNote.id);
                              },
                              icon: const MacosIcon(
                                CupertinoIcons.arrow_up_right_square,
                                size: 14,
                              ),
                            ),
                            _ChronicleMacosCompactIconButton(
                              tooltip: l10n.removeLinkAction,
                              onPressed: () async {
                                await onRemoveLink(item);
                              },
                              icon: const MacosIcon(
                                CupertinoIcons.link,
                                size: 14,
                              ),
                            ),
                          ],
                        ),
                        onTap: () async {
                          await onOpenLinkedNote(item.relatedNote.id);
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
                              await onOpenLinkedNote(item.relatedNote.id);
                            },
                            icon: const Icon(Icons.open_in_new, size: 16),
                          ),
                          IconButton(
                            tooltip: l10n.removeLinkAction,
                            onPressed: () async {
                              await onRemoveLink(item);
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

Future<void> showChronicleLinkNoteDialogFlow({
  required BuildContext context,
  required Note sourceNote,
  required bool useMacOSNativeUI,
  required Future<List<Note>> Function() loadAllNotes,
  required Future<void> Function(ChronicleLinkNoteDialogResult result)
  createLink,
}) async {
  final l10n = context.l10n;
  List<Note> allNotes;
  try {
    allNotes = await loadAllNotes();
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

  final result = await showDialog<ChronicleLinkNoteDialogResult>(
    context: context,
    builder: (_) => ChronicleLinkNoteDialog(
      sourceNote: sourceNote,
      candidates: candidates,
      useMacOSNativeUI: useMacOSNativeUI,
    ),
  );
  if (result == null) {
    return;
  }

  try {
    await createLink(result);
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

class _ChronicleMacosCompactIconButton extends StatelessWidget {
  const _ChronicleMacosCompactIconButton({
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

class _ChronicleMacosSelectableRow extends StatelessWidget {
  const _ChronicleMacosSelectableRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    required this.onTap,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typography = MacosTheme.of(context).typography;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
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
                      fontWeight: FontWeight.w500,
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

BoxDecoration _macosPanelDecoration(BuildContext context) {
  final brightness = MacosTheme.brightnessOf(context);
  return BoxDecoration(
    color: brightness.resolve(const Color(0xFFFDFDFD), const Color(0xFF202327)),
    border: Border.all(color: MacosTheme.of(context).dividerColor),
    borderRadius: BorderRadius.circular(8),
  );
}
