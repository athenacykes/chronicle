import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../domain/entities/note.dart';
import '../../../l10n/localization.dart';
import '../../notes/notes_controller.dart';

const Key _kNoteHeaderTitleDisplayKey = Key('note_header_title_display');
const Key _kNoteHeaderTitleEditFieldKey = Key('note_header_title_edit');

class ChronicleNoteTitleHeader extends ConsumerStatefulWidget {
  const ChronicleNoteTitleHeader({
    super.key,
    required this.note,
    required this.canEdit,
  });

  final Note? note;
  final bool canEdit;

  @override
  ConsumerState<ChronicleNoteTitleHeader> createState() =>
      _ChronicleNoteTitleHeaderState();
}

class _ChronicleNoteTitleHeaderState
    extends ConsumerState<ChronicleNoteTitleHeader> {
  final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.note?.title ?? '';
    _titleFocusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant ChronicleNoteTitleHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final noteChanged =
        oldWidget.note?.id != widget.note?.id ||
        oldWidget.note?.title != widget.note?.title;
    if (noteChanged && !_editing) {
      _titleController.text = widget.note?.title ?? '';
    }
  }

  @override
  void dispose() {
    _titleFocusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _titleController.dispose();
    super.dispose();
  }

  bool get _canEdit => widget.note != null && widget.canEdit;

  Future<void> _startEditing() async {
    if (!_canEdit) {
      return;
    }
    setState(() {
      _editing = true;
      _titleController.text = widget.note?.title ?? '';
    });
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    _titleFocusNode.requestFocus();
    _titleController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _titleController.text.length,
    );
  }

  Future<void> _commitEditing() async {
    if (!_editing) {
      return;
    }
    final note = widget.note;
    if (note != null && widget.canEdit) {
      final nextTitle = _titleController.text.trim();
      if (nextTitle != note.title) {
        await ref
            .read(noteEditorControllerProvider.notifier)
            .updateCurrent(title: nextTitle);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _editing = false;
    });
  }

  void _handleFocusChange() {
    if (!_titleFocusNode.hasFocus && _editing) {
      unawaited(_commitEditing());
    }
  }

  String _displayTitle(BuildContext context) {
    final l10n = context.l10n;
    final note = widget.note;
    if (note == null) {
      return l10n.selectNoteToEditPrompt;
    }
    final trimmed = note.title.trim();
    return trimmed.isEmpty ? l10n.untitledLabel : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOSNativeUI = MacosTheme.maybeOf(context) != null;
    final titleStyle = isMacOSNativeUI
        ? MacosTheme.of(context).typography.largeTitle
        : Theme.of(context).textTheme.headlineMedium;

    if (_editing && _canEdit) {
      final field = isMacOSNativeUI
          ? MacosTextField(
              key: _kNoteHeaderTitleEditFieldKey,
              focusNode: _titleFocusNode,
              controller: _titleController,
              placeholder: l10n.titleLabel,
              onEditingComplete: () {
                unawaited(_commitEditing());
              },
              onSubmitted: (_) {
                unawaited(_commitEditing());
              },
            )
          : TextField(
              key: _kNoteHeaderTitleEditFieldKey,
              focusNode: _titleFocusNode,
              controller: _titleController,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.titleLabel,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                unawaited(_commitEditing());
              },
              onEditingComplete: () {
                unawaited(_commitEditing());
              },
            );
      return TapRegion(
        onTapOutside: (_) {
          unawaited(_commitEditing());
        },
        child: field,
      );
    }

    return MouseRegion(
      cursor: _canEdit ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        key: _kNoteHeaderTitleDisplayKey,
        onTap: _canEdit
            ? () {
                unawaited(_startEditing());
              }
            : null,
        child: Text(
          _displayTitle(context),
          style: titleStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
