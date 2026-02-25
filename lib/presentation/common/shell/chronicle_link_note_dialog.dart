import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../domain/entities/note.dart';
import '../../../l10n/localization.dart';

class ChronicleLinkNoteDialogResult {
  const ChronicleLinkNoteDialogResult({
    required this.targetNoteId,
    required this.context,
  });

  final String targetNoteId;
  final String context;
}

class ChronicleLinkNoteDialog extends StatefulWidget {
  const ChronicleLinkNoteDialog({
    super.key,
    required this.sourceNote,
    required this.candidates,
    required this.useMacOSNativeUI,
  });

  final Note sourceNote;
  final List<Note> candidates;
  final bool useMacOSNativeUI;

  @override
  State<ChronicleLinkNoteDialog> createState() =>
      _ChronicleLinkNoteDialogState();
}

class _ChronicleLinkNoteDialogState extends State<ChronicleLinkNoteDialog> {
  late String _targetNoteId;
  final TextEditingController _contextController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _targetNoteId = widget.candidates.first.id;
  }

  @override
  void dispose() {
    _contextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final useMacOSNativeUI = widget.useMacOSNativeUI;

    final content = SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.linkSourceRow(_displayNoteTitle(widget.sourceNote)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          useMacOSNativeUI
              ? Row(
                  children: <Widget>[
                    Text(l10n.targetNoteLabel),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MacosPopupButton<String>(
                        value: _targetNoteId,
                        onChanged: (value) {
                          if (value == null || value.isEmpty) {
                            return;
                          }
                          setState(() {
                            _targetNoteId = value;
                          });
                        },
                        items: widget.candidates
                            .map(
                              (candidate) => MacosPopupMenuItem<String>(
                                value: candidate.id,
                                child: Text(_displayNoteTitle(candidate)),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                )
              : DropdownButtonFormField<String>(
                  initialValue: _targetNoteId,
                  decoration: InputDecoration(labelText: l10n.targetNoteLabel),
                  items: widget.candidates
                      .map(
                        (candidate) => DropdownMenuItem<String>(
                          value: candidate.id,
                          child: Text(_displayNoteTitle(candidate)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null || value.isEmpty) {
                      return;
                    }
                    setState(() {
                      _targetNoteId = value;
                    });
                  },
                ),
          const SizedBox(height: 8),
          useMacOSNativeUI
              ? MacosTextField(
                  controller: _contextController,
                  placeholder: l10n.contextOptionalLabel,
                  minLines: 2,
                  maxLines: 4,
                )
              : TextField(
                  controller: _contextController,
                  decoration: InputDecoration(
                    labelText: l10n.contextOptionalLabel,
                    hintText: l10n.linkContextHint,
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
        ],
      ),
    );

    void onCreateLink() {
      Navigator.of(context).pop(
        ChronicleLinkNoteDialogResult(
          targetNoteId: _targetNoteId,
          context: _contextController.text.trim(),
        ),
      );
    }

    if (useMacOSNativeUI) {
      return MacosSheet(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.linkNoteDialogTitle,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 12),
              content,
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancelAction),
                  ),
                  const SizedBox(width: 8),
                  PushButton(
                    controlSize: ControlSize.large,
                    onPressed: onCreateLink,
                    child: Text(l10n.createLinkAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(l10n.linkNoteDialogTitle),
      content: content,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: onCreateLink,
          child: Text(l10n.createLinkAction),
        ),
      ],
    );
  }

  String _displayNoteTitle(Note note) {
    final l10n = context.l10n;
    final title = note.title.trim().isEmpty
        ? l10n.untitledLabel
        : note.title.trim();
    if (note.matterId == null || note.phaseId == null) {
      return '$title [${l10n.notebookLabel}]';
    }
    return '$title [${note.matterId}]';
  }
}
