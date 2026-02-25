import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../domain/entities/enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/localization.dart';
import '../../settings/settings_controller.dart';
import '../../sync/sync_controller.dart';

const Key _kSettingsDialogNavPaneKey = Key('settings_dialog_nav_pane');
const Key _kSettingsDialogContentPaneKey = Key('settings_dialog_content_pane');

class ChronicleSettingsDialog extends ConsumerStatefulWidget {
  const ChronicleSettingsDialog({super.key, required this.useMacOSNativeUI});

  final bool useMacOSNativeUI;

  @override
  ConsumerState<ChronicleSettingsDialog> createState() =>
      _ChronicleSettingsDialogState();
}

enum _SettingsSection { storage, language, sync }

class _ChronicleSettingsDialogState
    extends ConsumerState<ChronicleSettingsDialog> {
  late final TextEditingController _rootPathController;
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _intervalController;
  bool _failSafe = true;
  SyncTargetType _type = SyncTargetType.none;
  String _localeTag = 'en';
  _SettingsSection _selectedSection = _SettingsSection.storage;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsControllerProvider).asData?.value;
    _rootPathController = TextEditingController(
      text: settings?.storageRootPath ?? '',
    );
    _urlController = TextEditingController(
      text: settings?.syncConfig.url ?? '',
    );
    _usernameController = TextEditingController(
      text: settings?.syncConfig.username ?? '',
    );
    _passwordController = TextEditingController();
    _intervalController = TextEditingController(
      text: (settings?.syncConfig.intervalMinutes ?? 5).toString(),
    );
    _type = settings?.syncConfig.type ?? SyncTargetType.none;
    _failSafe = settings?.syncConfig.failSafe ?? true;
    _localeTag = appLocaleTag(resolveAppLocale(settings?.localeTag));
  }

  @override
  void dispose() {
    _rootPathController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final useMacOSNativeUI = widget.useMacOSNativeUI;
    final localeItems = AppLocalizations.supportedLocales
        .map((locale) => appLocaleTag(locale))
        .toList(growable: false);
    final viewportSize = MediaQuery.sizeOf(context);
    final sheetBodyWidth = useMacOSNativeUI
        ? math.min(1400.0, math.max(760.0, viewportSize.width - 80))
        : math.min(960.0, math.max(360.0, viewportSize.width - 64));

    String localeDisplayName(String localeTag) {
      final locale = resolveAppLocale(localeTag);
      final localized = lookupAppLocalizations(locale);
      return localized.languageSelfName;
    }

    String sectionLabel(_SettingsSection section) {
      return switch (section) {
        _SettingsSection.storage => l10n.settingsSectionStorage,
        _SettingsSection.language => l10n.settingsSectionLanguage,
        _SettingsSection.sync => l10n.settingsSectionSync,
      };
    }

    Widget sectionNavItem(_SettingsSection section) {
      final selected = _selectedSection == section;
      if (useMacOSNativeUI) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: PushButton(
            controlSize: ControlSize.large,
            secondary: !selected,
            onPressed: () => setState(() => _selectedSection = section),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(sectionLabel(section)),
            ),
          ),
        );
      }

      return ListTile(
        dense: true,
        selected: selected,
        title: Text(sectionLabel(section)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () => setState(() => _selectedSection = section),
      );
    }

    Widget buildStorageSection() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          useMacOSNativeUI
              ? MacosTextField(
                  controller: _rootPathController,
                  placeholder: l10n.storageRootPathLabel,
                )
              : TextField(
                  controller: _rootPathController,
                  decoration: InputDecoration(
                    labelText: l10n.storageRootPathLabel,
                  ),
                ),
        ],
      );
    }

    Widget buildLanguageSection() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          useMacOSNativeUI
              ? Row(
                  children: <Widget>[
                    Text(l10n.languageLabel),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MacosPopupButton<String>(
                        value: _localeTag,
                        onChanged: (value) {
                          if (value == null || value.isEmpty) {
                            return;
                          }
                          setState(() {
                            _localeTag = value;
                          });
                        },
                        items: localeItems
                            .map(
                              (localeTag) => MacosPopupMenuItem<String>(
                                value: localeTag,
                                child: Text(localeDisplayName(localeTag)),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                )
              : DropdownButtonFormField<String>(
                  initialValue: _localeTag,
                  items: localeItems
                      .map(
                        (localeTag) => DropdownMenuItem<String>(
                          value: localeTag,
                          child: Text(localeDisplayName(localeTag)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null || value.isEmpty) {
                      return;
                    }
                    setState(() {
                      _localeTag = value;
                    });
                  },
                  decoration: InputDecoration(labelText: l10n.languageLabel),
                ),
        ],
      );
    }

    Widget buildSyncSection() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          useMacOSNativeUI
              ? Row(
                  children: <Widget>[
                    Text(l10n.syncTargetTypeLabel),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MacosPopupButton<SyncTargetType>(
                        value: _type,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _type = value;
                          });
                        },
                        items: SyncTargetType.values
                            .map(
                              (value) => MacosPopupMenuItem<SyncTargetType>(
                                value: value,
                                child: Text(_syncTargetTypeLabel(value, l10n)),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                )
              : DropdownButtonFormField<SyncTargetType>(
                  initialValue: _type,
                  items: SyncTargetType.values
                      .map(
                        (value) => DropdownMenuItem<SyncTargetType>(
                          value: value,
                          child: Text(_syncTargetTypeLabel(value, l10n)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _type = value;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: l10n.syncTargetTypeLabel,
                  ),
                ),
          const SizedBox(height: 8),
          useMacOSNativeUI
              ? MacosTextField(
                  controller: _urlController,
                  placeholder: l10n.webDavUrlLabel,
                )
              : TextField(
                  controller: _urlController,
                  decoration: InputDecoration(labelText: l10n.webDavUrlLabel),
                ),
          const SizedBox(height: 8),
          useMacOSNativeUI
              ? MacosTextField(
                  controller: _usernameController,
                  placeholder: l10n.webDavUsernameLabel,
                )
              : TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: l10n.webDavUsernameLabel,
                  ),
                ),
          const SizedBox(height: 8),
          useMacOSNativeUI
              ? MacosTextField(
                  controller: _passwordController,
                  placeholder: l10n.webDavPasswordLabel,
                  obscureText: true,
                )
              : TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: l10n.webDavPasswordLabel,
                  ),
                  obscureText: true,
                ),
          const SizedBox(height: 8),
          useMacOSNativeUI
              ? MacosTextField(
                  controller: _intervalController,
                  placeholder: l10n.autoSyncIntervalMinutesLabel,
                  keyboardType: TextInputType.number,
                )
              : TextField(
                  controller: _intervalController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.autoSyncIntervalMinutesLabel,
                  ),
                ),
          const SizedBox(height: 8),
          useMacOSNativeUI
              ? Row(
                  children: <Widget>[
                    MacosSwitch(
                      value: _failSafe,
                      onChanged: (value) => setState(() => _failSafe = value),
                    ),
                    const SizedBox(width: 8),
                    Text(l10n.deletionFailSafeLabel),
                  ],
                )
              : SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _failSafe,
                  onChanged: (value) => setState(() => _failSafe = value),
                  title: Text(l10n.deletionFailSafeLabel),
                ),
        ],
      );
    }

    final sectionContent = switch (_selectedSection) {
      _SettingsSection.storage => buildStorageSection(),
      _SettingsSection.language => buildLanguageSection(),
      _SettingsSection.sync => buildSyncSection(),
    };

    final sectionNav = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        sectionNavItem(_SettingsSection.storage),
        sectionNavItem(_SettingsSection.language),
        sectionNavItem(_SettingsSection.sync),
      ],
    );

    final content = SizedBox(
      width: sheetBodyWidth,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            key: _kSettingsDialogNavPaneKey,
            width: 146,
            child: Align(alignment: Alignment.topLeft, child: sectionNav),
          ),
          const SizedBox(width: 14),
          Expanded(
            key: _kSettingsDialogContentPaneKey,
            child: Container(
              padding: const EdgeInsets.only(left: 14, top: 4),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Align(alignment: Alignment.topLeft, child: sectionContent),
            ),
          ),
        ],
      ),
    );

    final scrollableContent = SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: sheetBodyWidth),
        child: content,
      ),
    );

    Future<void> saveSettings() async {
      await ref
          .read(settingsControllerProvider.notifier)
          .setStorageRootPath(_rootPathController.text.trim());

      final syncConfig = ref
          .read(settingsControllerProvider)
          .asData
          ?.value
          .syncConfig
          .copyWith(
            type: _type,
            url: _urlController.text.trim(),
            username: _usernameController.text.trim(),
            intervalMinutes: int.tryParse(_intervalController.text.trim()) ?? 5,
            failSafe: _failSafe,
          );

      if (syncConfig != null) {
        await ref
            .read(settingsControllerProvider.notifier)
            .saveSyncConfig(
              syncConfig,
              password: _passwordController.text.trim().isEmpty
                  ? null
                  : _passwordController.text.trim(),
            );

        await ref
            .read(syncControllerProvider.notifier)
            .startAutoSync(syncConfig.intervalMinutes);
      }

      await ref
          .read(settingsControllerProvider.notifier)
          .setLocaleTag(_localeTag);

      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    if (useMacOSNativeUI) {
      return MacosSheet(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: sheetBodyWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      l10n.settingsTitle,
                      style: const TextStyle(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    scrollableContent,
                    const SizedBox(height: 14),
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
                          onPressed: saveSettings,
                          child: Text(l10n.saveAction),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(l10n.settingsTitle),
      content: scrollableContent,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(onPressed: saveSettings, child: Text(l10n.saveAction)),
      ],
    );
  }
}

String _syncTargetTypeLabel(SyncTargetType type, AppLocalizations l10n) {
  return switch (type) {
    SyncTargetType.none => l10n.syncTargetTypeNone,
    SyncTargetType.filesystem => l10n.syncTargetTypeFilesystem,
    SyncTargetType.webdav => l10n.syncTargetTypeWebdav,
  };
}
