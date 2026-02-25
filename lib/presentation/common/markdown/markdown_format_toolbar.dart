import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

import '../../../l10n/localization.dart';
import 'markdown_edit_formatter.dart';

class MarkdownFormatToolbar extends StatefulWidget {
  MarkdownFormatToolbar({
    super.key,
    required this.controller,
    required this.isMacOSNativeUI,
    required this.keyPrefix,
    this.showImageAction = true,
    this.onPickAndAttachImagePath,
    MarkdownEditFormatter? formatter,
  }) : formatter = formatter ?? MarkdownEditFormatter();

  final TextEditingController controller;
  final bool isMacOSNativeUI;
  final String keyPrefix;
  final bool showImageAction;
  final Future<String?> Function()? onPickAndAttachImagePath;
  final MarkdownEditFormatter formatter;

  @override
  State<MarkdownFormatToolbar> createState() => _MarkdownFormatToolbarState();
}

class _MarkdownFormatToolbarState extends State<MarkdownFormatToolbar> {
  void _apply(TextEditingValue Function(TextEditingValue value) update) {
    widget.controller.value = update(widget.controller.value);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Key _actionKey(String action) =>
      Key('${widget.keyPrefix}_markdown_toolbar_action_$action');

  Key _dialogFieldKey(String field) =>
      Key('${widget.keyPrefix}_markdown_toolbar_field_$field');

  Key _dialogInsertKey() =>
      Key('${widget.keyPrefix}_markdown_toolbar_dialog_insert');

  Future<void> _showCodeBlockDialog() async {
    final l10n = context.l10n;
    final languageController = TextEditingController();
    final result = await _showSingleFieldDialog(
      title: l10n.markdownToolbarInsertCodeBlockTitle,
      fieldLabel: l10n.markdownToolbarLanguageOptionalLabel,
      controller: languageController,
      fieldKey: _dialogFieldKey('code_language'),
    );
    if (result == null) {
      return;
    }
    _apply((value) => widget.formatter.applyCodeBlock(value, language: result));
  }

  Future<void> _showTableDialog() async {
    final l10n = context.l10n;
    final rowsController = TextEditingController(text: '2');
    final columnsController = TextEditingController(text: '3');

    final result = await _showTwoFieldDialog(
      title: l10n.markdownToolbarInsertTableTitle,
      firstLabel: l10n.markdownToolbarTableRowsLabel,
      secondLabel: l10n.markdownToolbarTableColumnsLabel,
      firstController: rowsController,
      secondController: columnsController,
      firstFieldKey: _dialogFieldKey('table_rows'),
      secondFieldKey: _dialogFieldKey('table_columns'),
    );
    if (result == null) {
      return;
    }

    final rows = int.tryParse(result.first.trim()) ?? 0;
    final columns = int.tryParse(result.second.trim()) ?? 0;
    if (rows < 1 || columns < 1) {
      _showMessage(l10n.markdownToolbarInvalidPositiveNumberMessage);
      return;
    }
    _apply(
      (value) =>
          widget.formatter.applyTable(value, rows: rows, columns: columns),
    );
  }

  Future<void> _showLinkDialog() async {
    final l10n = context.l10n;
    final textController = TextEditingController(text: _selectedText());
    final urlController = TextEditingController();
    final titleController = TextEditingController();

    final result = await _showThreeFieldDialog(
      title: l10n.markdownToolbarInsertLinkTitle,
      firstLabel: l10n.markdownToolbarLinkTextLabel,
      secondLabel: l10n.markdownToolbarLinkUrlLabel,
      thirdLabel: l10n.markdownToolbarLinkTitleOptionalLabel,
      firstController: textController,
      secondController: urlController,
      thirdController: titleController,
      firstFieldKey: _dialogFieldKey('link_text'),
      secondFieldKey: _dialogFieldKey('link_url'),
      thirdFieldKey: _dialogFieldKey('link_title'),
    );
    if (result == null) {
      return;
    }
    if (result.second.trim().isEmpty) {
      _showMessage(l10n.markdownToolbarUrlRequiredMessage);
      return;
    }

    _apply(
      (value) => widget.formatter.applyLink(
        value,
        text: result.first,
        url: result.second,
        title: result.third,
      ),
    );
  }

  Future<void> _showImageDialog() async {
    final l10n = context.l10n;
    final altController = TextEditingController(text: _selectedText());
    final srcController = TextEditingController();
    final titleController = TextEditingController();

    final result = await _showImageFieldDialog(
      title: l10n.markdownToolbarInsertImageTitle,
      altController: altController,
      srcController: srcController,
      titleController: titleController,
      altFieldKey: _dialogFieldKey('image_alt'),
      srcFieldKey: _dialogFieldKey('image_source'),
      titleFieldKey: _dialogFieldKey('image_title'),
    );
    if (result == null) {
      return;
    }
    if (result.src.trim().isEmpty) {
      _showMessage(l10n.markdownToolbarImageSourceRequiredMessage);
      return;
    }

    _apply(
      (value) => widget.formatter.applyImage(
        value,
        alt: result.alt,
        src: result.src,
        title: result.title,
      ),
    );
  }

  String _selectedText() {
    final value = widget.controller.value;
    final selection = value.selection;
    if (!selection.isValid) {
      return '';
    }
    final start = selection.start.clamp(0, value.text.length);
    final end = selection.end.clamp(0, value.text.length);
    if (start == end) {
      return '';
    }
    return value.text.substring(start, end);
  }

  Widget _actionButton({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    if (widget.isMacOSNativeUI) {
      return MacosTooltip(
        message: tooltip,
        child: MacosIconButton(
          key: key,
          semanticLabel: tooltip,
          icon: Icon(icon, size: 16),
          backgroundColor: MacosColors.transparent,
          boxConstraints: const BoxConstraints(
            minHeight: 30,
            minWidth: 30,
            maxHeight: 30,
            maxWidth: 30,
          ),
          padding: const EdgeInsets.all(6),
          onPressed: onPressed,
        ),
      );
    }
    return IconButton(
      key: key,
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(6),
        minimumSize: const Size(30, 30),
        maximumSize: const Size(30, 30),
      ),
    );
  }

  Widget _headingSelector() {
    final l10n = context.l10n;
    if (widget.isMacOSNativeUI) {
      return MacosTooltip(
        message: l10n.markdownToolbarHeadingAction,
        child: MacosPulldownButton(
          key: _actionKey('heading'),
          icon: CupertinoIcons.textformat_size,
          items: <MacosPulldownMenuEntry>[
            for (var i = 1; i <= 6; i++)
              MacosPulldownMenuItem(
                title: Text('H$i'),
                onTap: () {
                  _apply(
                    (value) => widget.formatter.applyHeading(value, level: i),
                  );
                },
              ),
          ],
        ),
      );
    }

    return PopupMenuButton<int>(
      key: _actionKey('heading'),
      tooltip: l10n.markdownToolbarHeadingAction,
      icon: const Icon(Icons.title),
      onSelected: (level) {
        _apply((value) => widget.formatter.applyHeading(value, level: level));
      },
      itemBuilder: (_) => <PopupMenuEntry<int>>[
        for (var i = 1; i <= 6; i++)
          PopupMenuItem<int>(value: i, child: Text('H$i')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _actionButton(
            key: _actionKey('bold'),
            tooltip: l10n.markdownToolbarBoldAction,
            icon: Icons.format_bold,
            onPressed: () => _apply(widget.formatter.applyBold),
          ),
          const SizedBox(width: 6),
          _actionButton(
            key: _actionKey('italic'),
            tooltip: l10n.markdownToolbarItalicAction,
            icon: Icons.format_italic,
            onPressed: () => _apply(widget.formatter.applyItalic),
          ),
          const SizedBox(width: 6),
          _headingSelector(),
          const SizedBox(width: 6),
          _actionButton(
            key: _actionKey('unordered_list'),
            tooltip: l10n.markdownToolbarUnorderedListAction,
            icon: Icons.format_list_bulleted,
            onPressed: () => _apply(widget.formatter.applyUnorderedList),
          ),
          const SizedBox(width: 6),
          _actionButton(
            key: _actionKey('ordered_list'),
            tooltip: l10n.markdownToolbarOrderedListAction,
            icon: Icons.format_list_numbered,
            onPressed: () => _apply(widget.formatter.applyOrderedList),
          ),
          const SizedBox(width: 6),
          _actionButton(
            key: _actionKey('code_block'),
            tooltip: l10n.markdownToolbarCodeBlockAction,
            icon: Icons.code,
            onPressed: _showCodeBlockDialog,
          ),
          const SizedBox(width: 6),
          _actionButton(
            key: _actionKey('table'),
            tooltip: l10n.markdownToolbarTableAction,
            icon: Icons.table_chart_outlined,
            onPressed: _showTableDialog,
          ),
          const SizedBox(width: 6),
          _actionButton(
            key: _actionKey('link'),
            tooltip: l10n.markdownToolbarLinkAction,
            icon: Icons.link,
            onPressed: _showLinkDialog,
          ),
          if (widget.showImageAction) ...<Widget>[
            const SizedBox(width: 6),
            _actionButton(
              key: _actionKey('image'),
              tooltip: l10n.markdownToolbarImageAction,
              icon: Icons.image_outlined,
              onPressed: _showImageDialog,
            ),
          ],
          const SizedBox(width: 6),
          _actionButton(
            key: _actionKey('date'),
            tooltip: l10n.markdownToolbarInsertDateAction,
            icon: Icons.calendar_today_outlined,
            onPressed: () => _apply(widget.formatter.applyCurrentDate),
          ),
        ],
      ),
    );
  }

  Future<String?> _showSingleFieldDialog({
    required String title,
    required String fieldLabel,
    required TextEditingController controller,
    required Key fieldKey,
  }) {
    return _showDialogShell<String>(
      title: title,
      content: _dialogField(
        controller: controller,
        label: fieldLabel,
        fieldKey: fieldKey,
      ),
      onInsert: () => controller.text,
    );
  }

  Future<({String first, String second})?> _showTwoFieldDialog({
    required String title,
    required String firstLabel,
    required String secondLabel,
    required TextEditingController firstController,
    required TextEditingController secondController,
    required Key firstFieldKey,
    required Key secondFieldKey,
  }) {
    return _showDialogShell<({String first, String second})>(
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _dialogField(
            controller: firstController,
            label: firstLabel,
            fieldKey: firstFieldKey,
          ),
          const SizedBox(height: 8),
          _dialogField(
            controller: secondController,
            label: secondLabel,
            fieldKey: secondFieldKey,
          ),
        ],
      ),
      onInsert: () =>
          (first: firstController.text, second: secondController.text),
    );
  }

  Future<({String first, String second, String third})?> _showThreeFieldDialog({
    required String title,
    required String firstLabel,
    required String secondLabel,
    required String thirdLabel,
    required TextEditingController firstController,
    required TextEditingController secondController,
    required TextEditingController thirdController,
    required Key firstFieldKey,
    required Key secondFieldKey,
    required Key thirdFieldKey,
  }) {
    return _showDialogShell<({String first, String second, String third})>(
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _dialogField(
            controller: firstController,
            label: firstLabel,
            fieldKey: firstFieldKey,
          ),
          const SizedBox(height: 8),
          _dialogField(
            controller: secondController,
            label: secondLabel,
            fieldKey: secondFieldKey,
          ),
          const SizedBox(height: 8),
          _dialogField(
            controller: thirdController,
            label: thirdLabel,
            fieldKey: thirdFieldKey,
          ),
        ],
      ),
      onInsert: () => (
        first: firstController.text,
        second: secondController.text,
        third: thirdController.text,
      ),
    );
  }

  Future<_ImageDialogResult?> _showImageFieldDialog({
    required String title,
    required TextEditingController altController,
    required TextEditingController srcController,
    required TextEditingController titleController,
    required Key altFieldKey,
    required Key srcFieldKey,
    required Key titleFieldKey,
  }) {
    final l10n = context.l10n;
    return _showDialogShell<_ImageDialogResult>(
      title: title,
      contentBuilder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _dialogField(
              controller: altController,
              label: l10n.markdownToolbarImageAltTextLabel,
              fieldKey: altFieldKey,
            ),
            const SizedBox(height: 8),
            _dialogField(
              controller: srcController,
              label: l10n.markdownToolbarImageSourceLabel,
              fieldKey: srcFieldKey,
            ),
            const SizedBox(height: 8),
            _dialogField(
              controller: titleController,
              label: l10n.markdownToolbarImageTitleOptionalLabel,
              fieldKey: titleFieldKey,
            ),
            if (widget.onPickAndAttachImagePath != null) ...<Widget>[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _pickImageButton(
                  onPressed: () async {
                    final path = await widget.onPickAndAttachImagePath!.call();
                    if (!dialogContext.mounted || path == null) {
                      return;
                    }
                    setState(() {
                      srcController.text = path;
                      if (altController.text.trim().isEmpty) {
                        altController.text = p.basename(path);
                      }
                    });
                  },
                ),
              ),
            ],
          ],
        );
      },
      onInsert: () => _ImageDialogResult(
        alt: altController.text,
        src: srcController.text,
        title: titleController.text,
      ),
    );
  }

  Widget _pickImageButton({required Future<void> Function() onPressed}) {
    final l10n = context.l10n;
    if (widget.isMacOSNativeUI) {
      return PushButton(
        key: _actionKey('pick_attach_image'),
        controlSize: ControlSize.small,
        secondary: true,
        onPressed: () {
          onPressed();
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.add_photo_alternate_outlined, size: 15),
            const SizedBox(width: 6),
            Text(l10n.markdownToolbarPickAttachImageActionEllipsis),
          ],
        ),
      );
    }
    return OutlinedButton.icon(
      key: _actionKey('pick_attach_image'),
      onPressed: () {
        onPressed();
      },
      icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
      label: Text(l10n.markdownToolbarPickAttachImageActionEllipsis),
    );
  }

  Widget _dialogField({
    required TextEditingController controller,
    required String label,
    required Key fieldKey,
  }) {
    if (widget.isMacOSNativeUI) {
      return MacosTextField(
        key: fieldKey,
        controller: controller,
        placeholder: label,
      );
    }
    return TextField(
      key: fieldKey,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Future<T?> _showDialogShell<T>({
    required String title,
    Widget? content,
    Widget Function(
      BuildContext context,
      void Function(VoidCallback fn) setState,
    )?
    contentBuilder,
    required T Function() onInsert,
  }) {
    final l10n = context.l10n;
    return showDialog<T>(
      context: context,
      builder: (dialogContext) {
        Widget buildBody(void Function(VoidCallback fn) setState) {
          if (contentBuilder != null) {
            return contentBuilder(dialogContext, setState);
          }
          return content ?? const SizedBox.shrink();
        }

        return StatefulBuilder(
          builder: (dialogContext, setState) {
            final body = buildBody(setState);
            if (widget.isMacOSNativeUI) {
              return MacosSheet(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: MacosTheme.of(dialogContext).typography.title3,
                      ),
                      const SizedBox(height: 10),
                      SizedBox(width: 460, child: body),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          PushButton(
                            controlSize: ControlSize.regular,
                            secondary: true,
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: Text(l10n.cancelAction),
                          ),
                          const SizedBox(width: 8),
                          PushButton(
                            key: _dialogInsertKey(),
                            controlSize: ControlSize.regular,
                            onPressed: () {
                              Navigator.of(dialogContext).pop(onInsert());
                            },
                            child: Text(l10n.markdownToolbarInsertAction),
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
              content: SizedBox(width: 460, child: body),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.cancelAction),
                ),
                FilledButton(
                  key: _dialogInsertKey(),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(onInsert());
                  },
                  child: Text(l10n.markdownToolbarInsertAction),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ImageDialogResult {
  const _ImageDialogResult({
    required this.alt,
    required this.src,
    required this.title,
  });

  final String alt;
  final String src;
  final String title;
}
