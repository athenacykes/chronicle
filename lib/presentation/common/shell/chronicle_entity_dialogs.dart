import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../domain/entities/enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/localization.dart';
import 'chronicle_modal_dialog.dart';
import '../markdown/markdown_edit_formatter.dart';
import '../markdown/markdown_format_toolbar.dart';

enum ChronicleMatterDialogMode { create, edit }

Future<ChronicleMatterDialogResult?> showChronicleMatterDialog({
  required BuildContext context,
  required ChronicleMatterDialogMode mode,
  String initialTitle = '',
  String initialDescription = '',
  MatterStatus initialStatus = MatterStatus.active,
  String initialColor = '#4C956C',
  String initialIcon = 'description',
  bool initialPinned = false,
}) {
  return showChronicleModalDialog<ChronicleMatterDialogResult>(
    context: context,
    builder: (_) => ChronicleMatterDialog(
      mode: mode,
      initialTitle: initialTitle,
      initialDescription: initialDescription,
      initialStatus: initialStatus,
      initialColor: initialColor,
      initialIcon: initialIcon,
      initialPinned: initialPinned,
    ),
  );
}

class ChronicleMatterDialog extends StatefulWidget {
  const ChronicleMatterDialog({
    super.key,
    required this.mode,
    this.initialTitle = '',
    this.initialDescription = '',
    this.initialStatus = MatterStatus.active,
    this.initialColor = '#4C956C',
    this.initialIcon = 'description',
    this.initialPinned = false,
  });

  final ChronicleMatterDialogMode mode;
  final String initialTitle;
  final String initialDescription;
  final MatterStatus initialStatus;
  final String initialColor;
  final String initialIcon;
  final bool initialPinned;

  @override
  State<ChronicleMatterDialog> createState() => _ChronicleMatterDialogState();
}

class _ChronicleMatterDialogState extends State<ChronicleMatterDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _colorPreviewController;
  late MatterStatus _status;
  late bool _isPinned;
  late String _selectedColorHex;
  late String _selectedIconKey;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _selectedColorHex = _normalizeHexColor(widget.initialColor);
    _selectedIconKey = _normalizeMatterIconKey(widget.initialIcon);
    _colorPreviewController = TextEditingController(text: _selectedColorHex);
    _status = widget.initialStatus;
    _isPinned = widget.initialPinned;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _colorPreviewController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomColor(BuildContext context) async {
    var draftColor = _colorFromHex(_selectedColorHex);
    final l10n = context.l10n;
    final selectedColor = await showChronicleModalDialog<Color>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.matterCustomColorAction),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: draftColor,
            onColorChanged: (value) {
              draftColor = value;
            },
            enableAlpha: false,
            labelTypes: const <ColorLabelType>[
              ColorLabelType.hex,
              ColorLabelType.rgb,
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(draftColor),
            child: Text(l10n.matterUseColorAction),
          ),
        ],
      ),
    );
    if (selectedColor == null) {
      return;
    }
    setState(() {
      _selectedColorHex = _colorToHex(selectedColor);
      _colorPreviewController.text = _selectedColorHex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = widget.mode == ChronicleMatterDialogMode.create
        ? l10n.createMatterTitle
        : l10n.editMatterTitle;
    final isMacOSNativeUI = _isMacOSNativeUI(context);
    const dialogWidth = 420.0;
    final colorOptions = _colorOptionsForSelection(_selectedColorHex);
    final selectedIconOption = _matterIconOptionForKey(_selectedIconKey);

    Widget buildColorOption(String hexColor) {
      return Row(
        children: <Widget>[
          _ColorSwatch(hexColor: hexColor),
          const SizedBox(width: 10),
          Text(hexColor),
        ],
      );
    }

    Widget buildIconOption(_MatterIconOption option) {
      return Row(
        children: <Widget>[
          Icon(option.iconData, size: 18),
          const SizedBox(width: 10),
          Text(_matterIconLabel(l10n, option.key)),
        ],
      );
    }

    final formFields = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        isMacOSNativeUI
            ? _MacosLabeledField(
                label: l10n.titleLabel,
                child: MacosTextField(
                  controller: _titleController,
                  placeholder: l10n.titleLabel,
                  placeholderStyle: _macosPlaceholderStyle(context),
                ),
              )
            : TextField(
                controller: _titleController,
                decoration: InputDecoration(labelText: l10n.titleLabel),
              ),
        const SizedBox(height: 8),
        isMacOSNativeUI
            ? _MacosLabeledField(
                label: l10n.descriptionLabel,
                child: MacosTextField(
                  controller: _descriptionController,
                  placeholder: l10n.descriptionLabel,
                  placeholderStyle: _macosPlaceholderStyle(context),
                ),
              )
            : TextField(
                controller: _descriptionController,
                decoration: InputDecoration(labelText: l10n.descriptionLabel),
              ),
        const SizedBox(height: 8),
        isMacOSNativeUI
            ? _MacosLabeledField(
                label: l10n.statusLabel,
                child: MacosPopupButton<MatterStatus>(
                  value: _status,
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _status = value;
                    });
                  },
                  items: MatterStatus.values
                      .map(
                        (value) => MacosPopupMenuItem<MatterStatus>(
                          value: value,
                          child: Text(_matterStatusLabel(l10n, value)),
                        ),
                      )
                      .toList(),
                ),
              )
            : DropdownButtonFormField<MatterStatus>(
                initialValue: _status,
                decoration: InputDecoration(labelText: l10n.statusLabel),
                items: MatterStatus.values
                    .map(
                      (value) => DropdownMenuItem<MatterStatus>(
                        value: value,
                        child: Text(_matterStatusLabel(l10n, value)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _status = value;
                  });
                },
              ),
        const SizedBox(height: 8),
        isMacOSNativeUI
            ? _MacosLabeledField(
                label: l10n.matterPresetColorsLabel,
                child: MacosPopupButton<String>(
                  key: _kMatterColorDropdownKey,
                  value: _selectedColorHex,
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _selectedColorHex = value;
                      _colorPreviewController.text = value;
                    });
                  },
                  items: colorOptions
                      .map(
                        (hexColor) => MacosPopupMenuItem<String>(
                          value: hexColor,
                          child: buildColorOption(hexColor),
                        ),
                      )
                      .toList(),
                ),
              )
            : DropdownButtonFormField<String>(
                key: _kMatterColorDropdownKey,
                initialValue: _selectedColorHex,
                decoration: InputDecoration(
                  labelText: l10n.matterPresetColorsLabel,
                ),
                items: colorOptions
                    .map(
                      (hexColor) => DropdownMenuItem<String>(
                        value: hexColor,
                        child: buildColorOption(hexColor),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedColorHex = value;
                    _colorPreviewController.text = value;
                  });
                },
              ),
        const SizedBox(height: 10),
        isMacOSNativeUI
            ? _MacosLabeledField(
                label: l10n.colorHexLabel,
                child: Row(
                  children: <Widget>[
                    PushButton(
                      key: _kMatterColorCustomButtonKey,
                      controlSize: ControlSize.regular,
                      secondary: true,
                      onPressed: () => _pickCustomColor(context),
                      child: Text(l10n.matterCustomColorAction),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MacosTextField(
                        key: _kMatterColorPreviewFieldKey,
                        controller: _colorPreviewController,
                        readOnly: true,
                        placeholder: l10n.colorHexLabel,
                        placeholderStyle: _macosPlaceholderStyle(context),
                      ),
                    ),
                  ],
                ),
              )
            : Row(
                children: <Widget>[
                  OutlinedButton(
                    key: _kMatterColorCustomButtonKey,
                    onPressed: () => _pickCustomColor(context),
                    child: Text(l10n.matterCustomColorAction),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: _kMatterColorPreviewFieldKey,
                      controller: _colorPreviewController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: l10n.colorHexLabel,
                        hintText: l10n.colorHexHint,
                      ),
                    ),
                  ),
                ],
              ),
        const SizedBox(height: 12),
        isMacOSNativeUI
            ? _MacosLabeledField(
                label: l10n.matterIconPickerLabel,
                child: MacosPopupButton<String>(
                  key: _kMatterIconDropdownKey,
                  value: selectedIconOption.key,
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _selectedIconKey = value);
                  },
                  items: _kMatterIconOptions
                      .map(
                        (option) => MacosPopupMenuItem<String>(
                          value: option.key,
                          child: buildIconOption(option),
                        ),
                      )
                      .toList(),
                ),
              )
            : DropdownButtonFormField<String>(
                key: _kMatterIconDropdownKey,
                initialValue: selectedIconOption.key,
                decoration: InputDecoration(
                  labelText: l10n.matterIconPickerLabel,
                ),
                items: _kMatterIconOptions
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option.key,
                        child: buildIconOption(option),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => _selectedIconKey = value);
                },
              ),
        const SizedBox(height: 12),
        isMacOSNativeUI
            ? Row(
                children: <Widget>[
                  MacosSwitch(
                    value: _isPinned,
                    onChanged: (value) => setState(() => _isPinned = value),
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.pinnedLabel),
                ],
              )
            : SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isPinned,
                onChanged: (value) => setState(() => _isPinned = value),
                title: Text(l10n.pinnedLabel),
              ),
      ],
    );

    final content = SizedBox(
      width: dialogWidth,
      child: SingleChildScrollView(child: formFields),
    );

    void onSave() {
      Navigator.of(context).pop(
        ChronicleMatterDialogResult(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          status: _status,
          color: _normalizeHexColor(_selectedColorHex),
          icon: _normalizeMatterIconKey(_selectedIconKey),
          isPinned: _isPinned,
        ),
      );
    }

    if (isMacOSNativeUI) {
      return MacosSheet(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(title, style: const TextStyle(fontSize: 18)),
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
                        onPressed: onSave,
                        child: Text(
                          widget.mode == ChronicleMatterDialogMode.create
                              ? l10n.createAction
                              : l10n.saveAction,
                        ),
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

    return AlertDialog(
      title: Text(title),
      content: content,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: onSave,
          child: Text(
            widget.mode == ChronicleMatterDialogMode.create
                ? l10n.createAction
                : l10n.saveAction,
          ),
        ),
      ],
    );
  }
}

class ChronicleMatterDialogResult {
  const ChronicleMatterDialogResult({
    required this.title,
    required this.description,
    required this.status,
    required this.color,
    required this.icon,
    required this.isPinned,
  });

  final String title;
  final String description;
  final MatterStatus status;
  final String color;
  final String icon;
  final bool isPinned;
}

enum ChronicleCategoryDialogMode { create, edit }

Future<ChronicleCategoryDialogResult?> showChronicleCategoryDialog({
  required BuildContext context,
  required ChronicleCategoryDialogMode mode,
  String initialName = '',
  String initialColor = '#4C956C',
  String initialIcon = 'folder',
}) {
  return showChronicleModalDialog<ChronicleCategoryDialogResult>(
    context: context,
    builder: (_) => ChronicleCategoryDialog(
      mode: mode,
      initialName: initialName,
      initialColor: initialColor,
      initialIcon: initialIcon,
    ),
  );
}

class ChronicleCategoryDialog extends StatefulWidget {
  const ChronicleCategoryDialog({
    super.key,
    required this.mode,
    this.initialName = '',
    this.initialColor = '#4C956C',
    this.initialIcon = 'folder',
  });

  final ChronicleCategoryDialogMode mode;
  final String initialName;
  final String initialColor;
  final String initialIcon;

  @override
  State<ChronicleCategoryDialog> createState() =>
      _ChronicleCategoryDialogState();
}

class _ChronicleCategoryDialogState extends State<ChronicleCategoryDialog> {
  late final TextEditingController _nameController;
  late String _selectedColorHex;
  late String _selectedIconKey;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _selectedColorHex = _normalizeHexColor(widget.initialColor);
    _selectedIconKey = _normalizeMatterIconKey(widget.initialIcon);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUI(context);
    final title = widget.mode == ChronicleCategoryDialogMode.create
        ? l10n.createCategoryTitle
        : l10n.editCategoryTitle;
    const dialogWidth = 380.0;
    final colorOptions = _colorOptionsForSelection(_selectedColorHex);
    final selectedIconOption = _matterIconOptionForKey(_selectedIconKey);

    Widget buildColorOption(String hexColor) {
      return Row(
        children: <Widget>[
          _ColorSwatch(hexColor: hexColor),
          const SizedBox(width: 10),
          Text(hexColor),
        ],
      );
    }

    Widget buildIconOption(_MatterIconOption option) {
      return Row(
        children: <Widget>[
          Icon(option.iconData, size: 18),
          const SizedBox(width: 10),
          Text(_matterIconLabel(l10n, option.key)),
        ],
      );
    }

    final content = SizedBox(
      width: dialogWidth,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
              isMacOSNativeUI
                  ? _MacosLabeledField(
                      label: l10n.categoryNameLabel,
                      child: MacosTextField(
                        controller: _nameController,
                        placeholder: l10n.categoryNameLabel,
                        placeholderStyle: _macosPlaceholderStyle(context),
                      ),
                    )
                  : TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: l10n.categoryNameLabel,
                      ),
                    ),
              const SizedBox(height: 10),
              isMacOSNativeUI
                  ? _MacosLabeledField(
                      label: l10n.matterPresetColorsLabel,
                      child: MacosPopupButton<String>(
                        key: _kCategoryColorDropdownKey,
                        value: _selectedColorHex,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() => _selectedColorHex = value);
                        },
                        items: colorOptions
                            .map(
                              (hexColor) => MacosPopupMenuItem<String>(
                                value: hexColor,
                                child: buildColorOption(hexColor),
                              ),
                            )
                            .toList(),
                      ),
                    )
                  : DropdownButtonFormField<String>(
                      key: _kCategoryColorDropdownKey,
                      initialValue: _selectedColorHex,
                      decoration: InputDecoration(
                        labelText: l10n.matterPresetColorsLabel,
                      ),
                      items: colorOptions
                          .map(
                            (hexColor) => DropdownMenuItem<String>(
                              value: hexColor,
                              child: buildColorOption(hexColor),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => _selectedColorHex = value);
                      },
                    ),
              const SizedBox(height: 12),
              isMacOSNativeUI
                  ? _MacosLabeledField(
                      label: l10n.categoryIconLabel,
                      child: MacosPopupButton<String>(
                        key: _kCategoryIconDropdownKey,
                        value: selectedIconOption.key,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() => _selectedIconKey = value);
                        },
                        items: _kMatterIconOptions
                            .map(
                              (option) => MacosPopupMenuItem<String>(
                                value: option.key,
                                child: buildIconOption(option),
                              ),
                            )
                            .toList(),
                      ),
                    )
                  : DropdownButtonFormField<String>(
                      key: _kCategoryIconDropdownKey,
                      initialValue: selectedIconOption.key,
                      decoration: InputDecoration(
                        labelText: l10n.categoryIconLabel,
                      ),
                      items: _kMatterIconOptions
                          .map(
                            (option) => DropdownMenuItem<String>(
                              value: option.key,
                              child: buildIconOption(option),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => _selectedIconKey = value);
                      },
                    ),
            ],
          ),
        ),
      );

    void onSave() {
      Navigator.of(context).pop(
        ChronicleCategoryDialogResult(
          name: _nameController.text.trim(),
          color: _selectedColorHex,
          icon: _selectedIconKey,
        ),
      );
    }

    if (isMacOSNativeUI) {
      return MacosSheet(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title, style: const TextStyle(fontSize: 18)),
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
                    onPressed: onSave,
                    child: Text(
                      widget.mode == ChronicleCategoryDialogMode.create
                          ? l10n.createAction
                          : l10n.saveAction,
                    ),
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
      content: content,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: onSave,
          child: Text(
            widget.mode == ChronicleCategoryDialogMode.create
                ? l10n.createAction
                : l10n.saveAction,
          ),
        ),
      ],
    );
  }
}

class ChronicleCategoryDialogResult {
  const ChronicleCategoryDialogResult({
    required this.name,
    required this.color,
    required this.icon,
  });

  final String name;
  final String color;
  final String icon;
}

enum ChronicleNoteDialogMode { create, edit }

class ChronicleNoteDialog extends StatefulWidget {
  const ChronicleNoteDialog({
    super.key,
    required this.mode,
    this.initialTitle = '',
    this.initialContent = '',
    this.initialTags = const <String>[],
    this.initialPinned = false,
  });

  final ChronicleNoteDialogMode mode;
  final String initialTitle;
  final String initialContent;
  final List<String> initialTags;
  final bool initialPinned;

  @override
  State<ChronicleNoteDialog> createState() => _ChronicleNoteDialogState();
}

class _ChronicleNoteDialogState extends State<ChronicleNoteDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _tagsController;
  final MarkdownEditFormatter _markdownFormatter = MarkdownEditFormatter();
  late bool _isPinned;
  bool _seededDefaultContent = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _contentController = TextEditingController(text: widget.initialContent);
    _tagsController = TextEditingController(
      text: widget.initialTags.join(', '),
    );
    _isPinned = widget.initialPinned;
    _seededDefaultContent = widget.initialContent.isNotEmpty;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seededDefaultContent) {
      return;
    }
    final l10n = context.l10n;
    _contentController.text =
        '# ${widget.initialTitle.isEmpty ? l10n.defaultUntitledNoteTitle : widget.initialTitle}\n';
    _seededDefaultContent = true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = widget.mode == ChronicleNoteDialogMode.create
        ? l10n.createNoteTitle
        : l10n.editNoteTitle;
    final isMacOSNativeUI = _isMacOSNativeUI(context);
    const dialogWidth = 560.0;

    final content = SizedBox(
      width: dialogWidth,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            isMacOSNativeUI
                ? MacosTextField(
                    controller: _titleController,
                    placeholder: l10n.titleLabel,
                  )
                : TextField(
                    controller: _titleController,
                    decoration: InputDecoration(labelText: l10n.titleLabel),
                  ),
            const SizedBox(height: 8),
            isMacOSNativeUI
                ? MacosTextField(
                    controller: _tagsController,
                    placeholder: l10n.tagsCommaSeparatedLabel,
                  )
                : TextField(
                    controller: _tagsController,
                    decoration: InputDecoration(
                      labelText: l10n.tagsCommaSeparatedLabel,
                    ),
                  ),
            const SizedBox(height: 8),
            MarkdownFormatToolbar(
              key: _kNoteDialogMarkdownToolbarKey,
              controller: _contentController,
              isMacOSNativeUI: isMacOSNativeUI,
              keyPrefix: 'note_dialog',
              formatter: _markdownFormatter,
              showImageAction: false,
            ),
            const SizedBox(height: 8),
            isMacOSNativeUI
                ? MacosTextField(
                    controller: _contentController,
                    minLines: 10,
                    maxLines: 20,
                    placeholder: l10n.markdownContentLabel,
                  )
                : TextField(
                    controller: _contentController,
                    minLines: 10,
                    maxLines: 20,
                    decoration: InputDecoration(
                      labelText: l10n.markdownContentLabel,
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
            const SizedBox(height: 8),
            isMacOSNativeUI
                ? Row(
                    children: <Widget>[
                      MacosSwitch(
                        value: _isPinned,
                        onChanged: (value) => setState(() => _isPinned = value),
                      ),
                      const SizedBox(width: 8),
                      Text(l10n.pinnedLabel),
                    ],
                  )
                : SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _isPinned,
                    onChanged: (value) => setState(() => _isPinned = value),
                    title: Text(l10n.pinnedLabel),
                  ),
          ],
        ),
      ),
    );

    void onSave() {
      final tags = _tagsController.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      Navigator.of(context).pop(
        ChronicleNoteDialogResult(
          title: _titleController.text.trim(),
          content: _contentController.text,
          tags: tags,
          isPinned: _isPinned,
        ),
      );
    }

    if (isMacOSNativeUI) {
      return MacosSheet(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: const TextStyle(fontSize: 18)),
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
                    onPressed: onSave,
                    child: Text(
                      widget.mode == ChronicleNoteDialogMode.create
                          ? l10n.createAction
                          : l10n.saveAction,
                    ),
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
      content: content,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: onSave,
          child: Text(
            widget.mode == ChronicleNoteDialogMode.create
                ? l10n.createAction
                : l10n.saveAction,
          ),
        ),
      ],
    );
  }
}

class ChronicleNoteDialogResult {
  const ChronicleNoteDialogResult({
    required this.title,
    required this.content,
    required this.tags,
    required this.isPinned,
  });

  final String title;
  final String content;
  final List<String> tags;
  final bool isPinned;
}

const Key _kNoteDialogMarkdownToolbarKey = Key('note_dialog_markdown_toolbar');
const Key _kMatterColorCustomButtonKey = Key('matter_color_custom_button');
const Key _kMatterColorPreviewFieldKey = Key('matter_color_preview_field');
const Key _kMatterColorDropdownKey = Key('matter_color_dropdown');
const Key _kMatterIconDropdownKey = Key('matter_icon_dropdown');
const Key _kCategoryColorDropdownKey = Key('category_color_dropdown');
const Key _kCategoryIconDropdownKey = Key('category_icon_dropdown');

const List<String> _kMatterPresetColors = <String>[
  '#EF4444',
  '#F97316',
  '#F59E0B',
  '#EAB308',
  '#84CC16',
  '#22C55E',
  '#10B981',
  '#14B8A6',
  '#06B6D4',
  '#3B82F6',
  '#6366F1',
  '#8B5CF6',
  '#A855F7',
  '#EC4899',
  '#64748B',
];

class _MatterIconOption {
  const _MatterIconOption({required this.key, required this.iconData});

  final String key;
  final IconData iconData;
}

const List<_MatterIconOption> _kMatterIconOptions = <_MatterIconOption>[
  _MatterIconOption(key: 'description', iconData: Icons.description_outlined),
  _MatterIconOption(key: 'folder', iconData: Icons.folder_open),
  _MatterIconOption(key: 'work', iconData: Icons.work_outline),
  _MatterIconOption(key: 'gavel', iconData: Icons.gavel),
  _MatterIconOption(key: 'school', iconData: Icons.school_outlined),
  _MatterIconOption(
    key: 'account_balance',
    iconData: Icons.account_balance_outlined,
  ),
  _MatterIconOption(key: 'home', iconData: Icons.home_outlined),
  _MatterIconOption(key: 'build', iconData: Icons.build_outlined),
  _MatterIconOption(key: 'bolt', iconData: Icons.bolt_outlined),
  _MatterIconOption(key: 'assignment', iconData: Icons.assignment_outlined),
  _MatterIconOption(key: 'event', iconData: Icons.event_outlined),
  _MatterIconOption(key: 'campaign', iconData: Icons.campaign_outlined),
  _MatterIconOption(
    key: 'local_hospital',
    iconData: Icons.local_hospital_outlined,
  ),
  _MatterIconOption(key: 'science', iconData: Icons.science_outlined),
  _MatterIconOption(key: 'terminal', iconData: Icons.terminal_outlined),
];

class _MacosLabeledField extends StatelessWidget {
  const _MacosLabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final labelStyle = MacosTheme.of(
      context,
    ).typography.body.copyWith(fontWeight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(label, style: labelStyle),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.hexColor});

  final String hexColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: _colorFromHex(hexColor),
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}

bool _isMacOSNativeUI(BuildContext context) {
  return MacosTheme.maybeOf(context) != null;
}

TextStyle _macosPlaceholderStyle(BuildContext context) {
  final color = MacosTheme.brightnessOf(
    context,
  ).resolve(const Color(0x8A000000), const Color(0xCCEBEBF5));
  return MacosTheme.of(
    context,
  ).typography.body.copyWith(fontWeight: FontWeight.w400, color: color);
}

List<String> _colorOptionsForSelection(String selectedColorHex) {
  final normalized = _normalizeHexColor(selectedColorHex);
  if (_kMatterPresetColors.contains(normalized)) {
    return _kMatterPresetColors;
  }
  return <String>[normalized, ..._kMatterPresetColors];
}

String _normalizeHexColor(String value, {String fallback = '#4C956C'}) {
  final normalizedFallback = fallback.trim().toUpperCase();
  final trimmed = value.trim().toUpperCase();
  if (RegExp(r'^#[0-9A-F]{6}$').hasMatch(trimmed)) {
    return trimmed;
  }
  if (RegExp(r'^[0-9A-F]{6}$').hasMatch(trimmed)) {
    return '#$trimmed';
  }
  return RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalizedFallback)
      ? normalizedFallback
      : '#4C956C';
}

Color _colorFromHex(String value, {String fallback = '#4C956C'}) {
  final normalized = _normalizeHexColor(value, fallback: fallback);
  final rgbValue = int.parse(normalized.substring(1), radix: 16);
  return Color(0xFF000000 | rgbValue);
}

String _colorToHex(Color color) {
  final rgb = color.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

_MatterIconOption _matterIconOptionForKey(String iconKey) {
  for (final option in _kMatterIconOptions) {
    if (option.key == iconKey.trim()) {
      return option;
    }
  }
  return _kMatterIconOptions.first;
}

String _normalizeMatterIconKey(String iconKey) {
  return _matterIconOptionForKey(iconKey).key;
}

String _matterIconLabel(AppLocalizations l10n, String iconKey) {
  return switch (_normalizeMatterIconKey(iconKey)) {
    'description' => l10n.matterIconDescriptionLabel,
    'folder' => l10n.matterIconFolderLabel,
    'work' => l10n.matterIconWorkLabel,
    'gavel' => l10n.matterIconGavelLabel,
    'school' => l10n.matterIconSchoolLabel,
    'account_balance' => l10n.matterIconAccountBalanceLabel,
    'home' => l10n.matterIconHomeLabel,
    'build' => l10n.matterIconBuildLabel,
    'bolt' => l10n.matterIconBoltLabel,
    'assignment' => l10n.matterIconAssignmentLabel,
    'event' => l10n.matterIconEventLabel,
    'campaign' => l10n.matterIconCampaignLabel,
    'local_hospital' => l10n.matterIconLocalHospitalLabel,
    'science' => l10n.matterIconScienceLabel,
    'terminal' => l10n.matterIconTerminalLabel,
    _ => l10n.matterIconDescriptionLabel,
  };
}

String _matterStatusLabel(AppLocalizations l10n, MatterStatus status) {
  return switch (status) {
    MatterStatus.active => l10n.matterStatusActive,
    MatterStatus.paused => l10n.matterStatusPaused,
    MatterStatus.completed => l10n.matterStatusCompleted,
    MatterStatus.archived => l10n.matterStatusArchived,
  };
}
