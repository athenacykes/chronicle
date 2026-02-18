import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/localization.dart';

const Set<String> imageAttachmentExtensions = <String>{
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'svg',
  'heic',
  'heif',
};

bool isImageAttachmentPath(String attachmentPath) {
  final extension = p
      .extension(attachmentPath)
      .toLowerCase()
      .replaceFirst('.', '');
  return imageAttachmentExtensions.contains(extension);
}

String attachmentDisplayName(String attachmentPath) {
  final name = p.basename(attachmentPath);
  if (name.isEmpty) {
    return attachmentPath;
  }
  return name;
}

String formatAttachmentBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class NoteAttachmentTile extends StatelessWidget {
  const NoteAttachmentTile({
    super.key,
    required this.relativePath,
    required this.absolutePath,
    required this.onOpen,
    required this.onRemove,
  });

  final String relativePath;
  final String absolutePath;
  final Future<void> Function() onOpen;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    if (isImageAttachmentPath(relativePath)) {
      return _ImageAttachmentTile(
        relativePath: relativePath,
        absolutePath: absolutePath,
        onOpen: onOpen,
        onRemove: onRemove,
      );
    }

    return _FileAttachmentTile(
      relativePath: relativePath,
      absolutePath: absolutePath,
      onOpen: onOpen,
      onRemove: onRemove,
    );
  }
}

class _ImageAttachmentTile extends StatelessWidget {
  const _ImageAttachmentTile({
    required this.relativePath,
    required this.absolutePath,
    required this.onOpen,
    required this.onRemove,
  });

  final String relativePath;
  final String absolutePath;
  final Future<void> Function() onOpen;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    attachmentDisplayName(relativePath),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                _AttachmentActions(onOpen: onOpen, onRemove: onRemove),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(absolutePath),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => SizedBox(
                    height: 120,
                    child: Center(
                      child: Text(l10n.imagePreviewUnavailableMessage),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    relativePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                _AttachmentFileSizeText(absolutePath: absolutePath),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FileAttachmentTile extends StatelessWidget {
  const _FileAttachmentTile({
    required this.relativePath,
    required this.absolutePath,
    required this.onOpen,
    required this.onRemove,
  });

  final String relativePath;
  final String absolutePath;
  final Future<void> Function() onOpen;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.attach_file),
        title: Text(
          attachmentDisplayName(relativePath),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                relativePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _AttachmentFileSizeText(absolutePath: absolutePath),
          ],
        ),
        trailing: _AttachmentActions(onOpen: onOpen, onRemove: onRemove),
      ),
    );
  }
}

class _AttachmentActions extends StatelessWidget {
  const _AttachmentActions({required this.onOpen, required this.onRemove});

  final Future<void> Function() onOpen;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 4,
      children: <Widget>[
        IconButton(
          tooltip: l10n.openAttachmentAction,
          onPressed: () async {
            await onOpen();
          },
          icon: const Icon(Icons.open_in_new, size: 18),
        ),
        IconButton(
          tooltip: l10n.removeAttachmentAction,
          onPressed: () async {
            await onRemove();
          },
          icon: const Icon(Icons.delete_outline, size: 18),
        ),
      ],
    );
  }
}

class _AttachmentFileSizeText extends StatefulWidget {
  const _AttachmentFileSizeText({required this.absolutePath});

  final String absolutePath;

  @override
  State<_AttachmentFileSizeText> createState() =>
      _AttachmentFileSizeTextState();
}

class _AttachmentFileSizeTextState extends State<_AttachmentFileSizeText> {
  late Future<FileStat> _statFuture;

  @override
  void initState() {
    super.initState();
    _statFuture = File(widget.absolutePath).stat();
  }

  @override
  void didUpdateWidget(covariant _AttachmentFileSizeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.absolutePath != widget.absolutePath) {
      _statFuture = File(widget.absolutePath).stat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<FileStat>(
      future: _statFuture,
      builder: (context, snapshot) {
        final style = Theme.of(context).textTheme.bodySmall;
        if (snapshot.connectionState != ConnectionState.done) {
          return Text(l10n.loadingEllipsis, style: style);
        }

        final stat = snapshot.data;
        if (snapshot.hasError ||
            stat == null ||
            stat.type != FileSystemEntityType.file) {
          return Text(l10n.fileMissingLabel, style: style);
        }

        return Text(formatAttachmentBytes(stat.size), style: style);
      },
    );
  }
}
