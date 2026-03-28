import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

import '../../../app/app_providers.dart';
import '../../../domain/entities/app_settings.dart';
import '../../../domain/entities/chronicle_backup_result.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/sync_bootstrap_assessment.dart';
import '../../../domain/entities/sync_config.dart';
import '../../../domain/entities/sync_proxy_config.dart';
import '../../../data/local_fs/chronicle_layout.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/localization.dart';
import '../../links/links_controller.dart';
import '../../matters/matters_controller.dart';
import '../../notes/notes_controller.dart';
import '../../search/search_controller.dart';
import '../../settings/settings_controller.dart';
import '../../sync/conflicts_controller.dart';
import '../../sync/sync_controller.dart';
import 'chronicle_time_views_controller.dart';
import 'chronicle_macos_fixed_dialog.dart';
import 'chronicle_modal_dialog.dart';

const Key _kSettingsDialogNavPaneKey = Key('settings_dialog_nav_pane');
const Key _kSettingsDialogContentPaneKey = Key('settings_dialog_content_pane');
const Key _kExportBackupButtonKey = Key('settings_export_backup_button');
const Key _kImportBackupButtonKey = Key('settings_import_backup_button');

class ChronicleSettingsDialog extends ConsumerStatefulWidget {
  const ChronicleSettingsDialog({super.key, required this.useMacOSNativeUI});

  final bool useMacOSNativeUI;

  @override
  ConsumerState<ChronicleSettingsDialog> createState() =>
      _ChronicleSettingsDialogState();
}

enum _SettingsSection { storage, language, sync }

enum _BootstrapSyncAction { none, normal, recoverLocalWins, recoverRemoteWins }

class _ChronicleSettingsDialogState
    extends ConsumerState<ChronicleSettingsDialog> {
  late final TextEditingController _rootPathController;
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _proxyHostController;
  late final TextEditingController _proxyPortController;
  late final TextEditingController _proxyUsernameController;
  late final TextEditingController _proxyPasswordController;
  late final TextEditingController _intervalController;
  bool _failSafe = true;
  SyncTargetType _type = SyncTargetType.none;
  SyncProxyType _proxyType = SyncProxyType.none;
  String _localeTag = 'en';
  _SettingsSection _selectedSection = _SettingsSection.storage;
  String? _proxyHostError;
  String? _proxyPortError;
  bool _storageTaskInProgress = false;

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
    _proxyHostController = TextEditingController(
      text: settings?.syncConfig.proxy.host ?? '',
    );
    _proxyPortController = TextEditingController(
      text: settings?.syncConfig.proxy.port?.toString() ?? '',
    );
    _proxyUsernameController = TextEditingController(
      text: settings?.syncConfig.proxy.username ?? '',
    );
    _proxyPasswordController = TextEditingController();
    _intervalController = TextEditingController(
      text: (settings?.syncConfig.intervalMinutes ?? 5).toString(),
    );
    _type = settings?.syncConfig.type ?? SyncTargetType.none;
    _failSafe = settings?.syncConfig.failSafe ?? true;
    _proxyType = settings?.syncConfig.proxy.type ?? SyncProxyType.none;
    _localeTag = appLocaleTag(resolveAppLocale(settings?.localeTag));
  }

  @override
  void dispose() {
    _rootPathController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _proxyHostController.dispose();
    _proxyPortController.dispose();
    _proxyUsernameController.dispose();
    _proxyPasswordController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    String? continueLabel,
  }) async {
    final l10n = context.l10n;
    final confirmed = await showChronicleModalDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(continueLabel ?? l10n.continueAction),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  bool _shouldAssessBootstrap({
    required AppSettings currentSettings,
    required SyncConfig nextConfig,
    required String nextStorageRootPath,
  }) {
    if (nextConfig.type != SyncTargetType.webdav ||
        nextConfig.url.trim().isEmpty ||
        nextConfig.username.trim().isEmpty ||
        nextStorageRootPath.isEmpty) {
      return false;
    }

    final currentConfig = currentSettings.syncConfig;
    final currentRoot = currentSettings.storageRootPath?.trim() ?? '';
    final currentUrl = currentConfig.url.trim();
    final currentUsername = currentConfig.username.trim();
    final nextUrl = nextConfig.url.trim();
    final nextUsername = nextConfig.username.trim();

    return currentConfig.type != SyncTargetType.webdav ||
        currentRoot != nextStorageRootPath ||
        currentUrl != nextUrl ||
        currentUsername != nextUsername;
  }

  Future<_BootstrapSyncAction?> _resolveBootstrapAction({
    required SyncBootstrapAssessment assessment,
  }) async {
    final l10n = context.l10n;
    final countsSummary = l10n.syncBootstrapCountsSummary(
      assessment.localItemCount,
      assessment.remoteItemCount,
    );

    switch (assessment.scenario) {
      case SyncBootstrapScenario.neither:
        return _BootstrapSyncAction.none;
      case SyncBootstrapScenario.localOnly:
        final confirmed = await _confirmDialog(
          title: l10n.syncBootstrapLocalOnlyTitle,
          message: '${l10n.syncBootstrapLocalOnlyWarning}\n\n$countsSummary',
        );
        return confirmed ? _BootstrapSyncAction.normal : null;
      case SyncBootstrapScenario.remoteOnly:
        final confirmed = await _confirmDialog(
          title: l10n.syncBootstrapRemoteOnlyTitle,
          message: '${l10n.syncBootstrapRemoteOnlyWarning}\n\n$countsSummary',
        );
        return confirmed ? _BootstrapSyncAction.normal : null;
      case SyncBootstrapScenario.both:
        final selection = await showChronicleModalDialog<_BootstrapSyncAction>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.syncBootstrapConflictTitle),
            content: Text(
              '${l10n.syncBootstrapConflictWarning}\n\n$countsSummary',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancelAction),
              ),
              TextButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(_BootstrapSyncAction.recoverRemoteWins),
                child: Text(l10n.syncBootstrapUseRemoteAction),
              ),
              FilledButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(_BootstrapSyncAction.recoverLocalWins),
                child: Text(l10n.syncBootstrapUseLocalAction),
              ),
            ],
          ),
        );
        if (selection == _BootstrapSyncAction.recoverLocalWins) {
          final firstConfirmed = await _confirmDialog(
            title: l10n.syncRecoverLocalWinsTitle,
            message: '${l10n.syncRecoverLocalWinsWarning}\n\n$countsSummary',
          );
          if (!firstConfirmed) {
            return null;
          }
          final secondConfirmed = await _confirmDialog(
            title: l10n.syncRecoverLocalWinsSecondTitle,
            message: l10n.syncRecoverLocalWinsSecondWarning,
          );
          return secondConfirmed ? _BootstrapSyncAction.recoverLocalWins : null;
        }
        if (selection == _BootstrapSyncAction.recoverRemoteWins) {
          final firstConfirmed = await _confirmDialog(
            title: l10n.syncRecoverRemoteWinsTitle,
            message: '${l10n.syncRecoverRemoteWinsWarning}\n\n$countsSummary',
          );
          if (!firstConfirmed) {
            return null;
          }
          final secondConfirmed = await _confirmDialog(
            title: l10n.syncRecoverRemoteWinsSecondTitle,
            message: l10n.syncRecoverRemoteWinsSecondWarning,
          );
          return secondConfirmed
              ? _BootstrapSyncAction.recoverRemoteWins
              : null;
        }
        return null;
    }
  }

  Future<void> _reloadStorageBoundState() async {
    await ref.read(mattersControllerProvider.notifier).reload();
    await ref.read(conflictsControllerProvider.notifier).reload();
    ref.invalidate(notebookFoldersProvider);
    ref.invalidate(notebookFolderTreeProvider);
  }

  Future<void> _runBootstrapSync(_BootstrapSyncAction action) async {
    switch (action) {
      case _BootstrapSyncAction.none:
        return;
      case _BootstrapSyncAction.normal:
        await ref.read(syncControllerProvider.notifier).runSyncNow();
        return;
      case _BootstrapSyncAction.recoverLocalWins:
        await ref.read(syncControllerProvider.notifier).runRecoverLocalWins();
        return;
      case _BootstrapSyncAction.recoverRemoteWins:
        await ref.read(syncControllerProvider.notifier).runRecoverRemoteWins();
        return;
    }
  }

  Future<void> _showStorageMessageDialog({
    required String title,
    required String message,
  }) {
    return showChronicleModalDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.closeAction),
          ),
        ],
      ),
    );
  }

  Future<ChronicleBackupImportMode?> _showBackupImportModeDialog() {
    final l10n = context.l10n;
    return showChronicleModalDialog<ChronicleBackupImportMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.backupImportModeTitle),
        content: Text(l10n.backupImportModeMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancelAction),
          ),
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(ChronicleBackupImportMode.mergeExisting),
            child: Text(l10n.backupImportMergeAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(ChronicleBackupImportMode.blankRestore),
            child: Text(l10n.backupImportBlankRestoreAction),
          ),
        ],
      ),
    );
  }

  Future<void> _showBackupResultDialog({
    required String title,
    required String summary,
    required List<ChronicleBackupWarning> warnings,
  }) async {
    final l10n = context.l10n;
    final warningLines = warnings
        .take(12)
        .map((warning) {
          final entry = warning.entryPath?.trim() ?? '';
          if (entry.isEmpty) {
            return '- ${warning.message}';
          }
          return '- ${p.basename(entry)}: ${warning.message}';
        })
        .join('\n');
    final hasExtraWarnings = warnings.length > 12;

    await showChronicleModalDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(summary),
              if (warnings.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(l10n.backupWarningsTitle(warnings.length)),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      hasExtraWarnings ? '$warningLines\n...' : warningLines,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.closeAction),
          ),
        ],
      ),
    );
  }

  String _defaultBackupFileName() {
    final now = DateTime.now().toUtc();
    final date =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'chronicle-backup-$date-$time.zip';
  }

  Future<bool> _ensureSyncIsIdleForStorageTask() async {
    final syncStatus = ref.read(syncControllerProvider).asData?.value;
    if (syncStatus?.isRunning == true) {
      await _showStorageMessageDialog(
        title: context.l10n.backupOperationBlockedTitle,
        message: context.l10n.backupOperationBlockedSyncRunningMessage,
      );
      return false;
    }
    return true;
  }

  Future<void> _prepareForStorageMutation() async {
    await ref.read(noteEditorFlushBridgeProvider).flush();
    await ref
        .read(noteEditorControllerProvider.notifier)
        .flushAndClearNotebookDraftSession();
    ref.read(syncControllerProvider.notifier).stopAutoSync();
  }

  Future<void> _clearSyncBookkeepingAfterImport() async {
    await ref.read(localSyncStateStoreProvider).clear();
    await ref.read(localSyncMetadataStoreProvider).clear();

    try {
      final root = await ref
          .read(storageRootLocatorProvider)
          .requireRootDirectory();
      await ref
          .read(conflictHistoryStoreProvider)
          .clear(layout: ChronicleLayout(root));
    } catch (_) {
      // Ignore missing storage root while resetting import bookkeeping.
    }
  }

  Future<void> _reloadStateAfterImport() async {
    ref.read(selectedNoteIdProvider.notifier).set(null);
    ref.read(selectedConflictPathProvider.notifier).set(null);
    ref.read(selectedMatterIdProvider.notifier).set(null);
    ref.read(selectedPhaseIdProvider.notifier).set(null);
    ref.read(selectedNotebookFolderIdProvider.notifier).set(null);
    ref.read(selectedTimeViewProvider.notifier).set(null);
    ref.read(showNotebookProvider.notifier).set(false);
    ref.read(showConflictsProvider.notifier).set(false);
    ref.read(searchResultsVisibleProvider.notifier).set(false);

    await ref.read(mattersControllerProvider.notifier).reload();
    await ref.read(conflictsControllerProvider.notifier).reload();
    ref.invalidate(noteListProvider);
    ref.invalidate(notebookNoteListProvider);
    ref.invalidate(notebookFoldersProvider);
    ref.invalidate(notebookFolderTreeProvider);
    ref.invalidate(orphanNotesProvider);
    ref.invalidate(timeViewSummaryProvider);
    await ref.read(searchRepositoryProvider).rebuildIndex();
    ref.invalidate(searchControllerProvider);
    ref.read(linksControllerProvider).invalidateAll();
  }

  Future<void> _exportBackup() async {
    if (_storageTaskInProgress) {
      return;
    }
    if (!await _ensureSyncIsIdleForStorageTask()) {
      return;
    }

    final outputPath = await ref
        .read(settingsControllerProvider.notifier)
        .chooseBackupExportPath(suggestedFileName: _defaultBackupFileName());
    if (!mounted || outputPath == null || outputPath.trim().isEmpty) {
      return;
    }

    setState(() {
      _storageTaskInProgress = true;
    });
    try {
      await ref.read(noteEditorFlushBridgeProvider).flush();
      final result = await ref
          .read(chronicleBackupRepositoryProvider)
          .exportToArchive(outputPath: outputPath);
      if (!mounted) {
        return;
      }
      final l10n = context.l10n;
      await _showBackupResultDialog(
        title: l10n.backupExportDialogTitle,
        summary: result.hasWarnings
            ? l10n.backupExportPartialSummary(
                result.exportedFileCount,
                result.warningCount,
              )
            : l10n.backupExportSuccessSummary(result.exportedFileCount),
        warnings: result.warnings,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showStorageMessageDialog(
        title: context.l10n.backupExportDialogTitle,
        message: context.l10n.backupExportFailed(error.toString()),
      );
    } finally {
      if (mounted) {
        setState(() {
          _storageTaskInProgress = false;
        });
      }
    }
  }

  Future<void> _importBackup() async {
    if (_storageTaskInProgress) {
      return;
    }
    if (!await _ensureSyncIsIdleForStorageTask()) {
      return;
    }

    final archivePath = await ref
        .read(settingsControllerProvider.notifier)
        .pickBackupArchivePath();
    if (!mounted || archivePath == null || archivePath.trim().isEmpty) {
      return;
    }

    final mode = await _showBackupImportModeDialog();
    if (!mounted || mode == null) {
      return;
    }

    if (mode == ChronicleBackupImportMode.blankRestore) {
      final confirmed = await _confirmDialog(
        title: context.l10n.backupImportBlankRestoreConfirmTitle,
        message: context.l10n.backupImportBlankRestoreConfirmMessage,
        continueLabel: context.l10n.backupImportBlankRestoreAction,
      );
      if (!confirmed || !mounted) {
        return;
      }
    }

    setState(() {
      _storageTaskInProgress = true;
    });
    final currentSettings = ref.read(settingsControllerProvider).asData?.value;
    try {
      await _prepareForStorageMutation();
      final result = await ref
          .read(chronicleBackupRepositoryProvider)
          .importFromArchive(archivePath: archivePath, mode: mode);
      await _clearSyncBookkeepingAfterImport();
      await _reloadStateAfterImport();
      if (currentSettings != null) {
        await ref
            .read(syncControllerProvider.notifier)
            .startAutoSync(currentSettings.syncConfig.intervalMinutes);
      }

      if (!mounted) {
        return;
      }
      final l10n = context.l10n;
      await _showBackupResultDialog(
        title: l10n.backupImportDialogTitle,
        summary: result.hasWarnings
            ? l10n.backupImportPartialSummary(
                result.importedCategoryCount,
                result.importedMatterCount,
                result.importedNotebookFolderCount,
                result.importedNoteCount,
                result.importedLinkCount,
                result.importedResourceCount,
                result.warningCount,
              )
            : l10n.backupImportSuccessSummary(
                result.importedCategoryCount,
                result.importedMatterCount,
                result.importedNotebookFolderCount,
                result.importedNoteCount,
                result.importedLinkCount,
                result.importedResourceCount,
              ),
        warnings: result.warnings,
      );
    } catch (error) {
      if (currentSettings != null) {
        await ref
            .read(syncControllerProvider.notifier)
            .startAutoSync(currentSettings.syncConfig.intervalMinutes);
      }
      if (!mounted) {
        return;
      }
      await _showStorageMessageDialog(
        title: context.l10n.backupImportDialogTitle,
        message: context.l10n.backupImportFailed(error.toString()),
      );
    } finally {
      if (mounted) {
        setState(() {
          _storageTaskInProgress = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final useMacOSNativeUI = widget.useMacOSNativeUI;
    final localeItems = AppLocalizations.supportedLocales
        .map((locale) => appLocaleTag(locale))
        .toList(growable: false);
    const dialogWidth = 580.0;
    final macosPlaceholderStyle = _macosPlaceholderStyle(context);

    Widget buildMacosLabeledField({
      required String label,
      required Widget child,
    }) {
      return _MacosLabeledField(label: label, child: child);
    }

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
              ? buildMacosLabeledField(
                  label: l10n.storageRootPathLabel,
                  child: MacosTextField(
                    controller: _rootPathController,
                    placeholder: l10n.storageRootPathLabel,
                    placeholderStyle: macosPlaceholderStyle,
                  ),
                )
              : TextField(
                  controller: _rootPathController,
                  decoration: InputDecoration(
                    labelText: l10n.storageRootPathLabel,
                  ),
                ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              useMacOSNativeUI
                  ? PushButton(
                      key: _kExportBackupButtonKey,
                      controlSize: ControlSize.large,
                      onPressed: _storageTaskInProgress ? null : _exportBackup,
                      child: Text(l10n.backupExportAction),
                    )
                  : FilledButton.tonal(
                      key: _kExportBackupButtonKey,
                      onPressed: _storageTaskInProgress ? null : _exportBackup,
                      child: Text(l10n.backupExportAction),
                    ),
              useMacOSNativeUI
                  ? PushButton(
                      key: _kImportBackupButtonKey,
                      controlSize: ControlSize.large,
                      secondary: true,
                      onPressed: _storageTaskInProgress ? null : _importBackup,
                      child: Text(l10n.backupImportAction),
                    )
                  : OutlinedButton(
                      key: _kImportBackupButtonKey,
                      onPressed: _storageTaskInProgress ? null : _importBackup,
                      child: Text(l10n.backupImportAction),
                    ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.backupStorageScopeDescription,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    Widget buildLanguageSection() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          useMacOSNativeUI
              ? buildMacosLabeledField(
                  label: l10n.languageLabel,
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
      final showProxySection = _type == SyncTargetType.webdav;
      final proxyFieldsVisible =
          showProxySection && _proxyType != SyncProxyType.none;

      Widget buildMacosErrorText(String? error) {
        if (error == null || error.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            error,
            style: TextStyle(
              color: MacosTheme.of(
                context,
              ).typography.caption1.color?.withAlpha(220),
              fontSize: 11,
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          useMacOSNativeUI
              ? buildMacosLabeledField(
                  label: l10n.syncTargetTypeLabel,
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
              ? buildMacosLabeledField(
                  label: l10n.webDavUrlLabel,
                  child: MacosTextField(
                    controller: _urlController,
                    placeholder: l10n.webDavUrlLabel,
                    placeholderStyle: macosPlaceholderStyle,
                  ),
                )
              : TextField(
                  controller: _urlController,
                  decoration: InputDecoration(labelText: l10n.webDavUrlLabel),
                ),
          const SizedBox(height: 8),
          useMacOSNativeUI
              ? buildMacosLabeledField(
                  label: l10n.webDavUsernameLabel,
                  child: MacosTextField(
                    controller: _usernameController,
                    placeholder: l10n.webDavUsernameLabel,
                    placeholderStyle: macosPlaceholderStyle,
                  ),
                )
              : TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: l10n.webDavUsernameLabel,
                  ),
                ),
          const SizedBox(height: 8),
          useMacOSNativeUI
              ? buildMacosLabeledField(
                  label: l10n.webDavPasswordLabel,
                  child: MacosTextField(
                    controller: _passwordController,
                    placeholder: l10n.webDavPasswordLabel,
                    placeholderStyle: macosPlaceholderStyle,
                    obscureText: true,
                  ),
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
              ? buildMacosLabeledField(
                  label: l10n.autoSyncIntervalMinutesLabel,
                  child: MacosTextField(
                    controller: _intervalController,
                    placeholder: l10n.autoSyncIntervalMinutesLabel,
                    placeholderStyle: macosPlaceholderStyle,
                    keyboardType: TextInputType.number,
                  ),
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
          if (showProxySection) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              l10n.syncProxySectionTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            useMacOSNativeUI
                ? buildMacosLabeledField(
                    label: l10n.syncProxyTypeLabel,
                    child: MacosPopupButton<SyncProxyType>(
                      value: _proxyType,
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _proxyType = value;
                          if (_proxyType == SyncProxyType.none) {
                            _proxyHostError = null;
                            _proxyPortError = null;
                          }
                        });
                      },
                      items: SyncProxyType.values
                          .map(
                            (value) => MacosPopupMenuItem<SyncProxyType>(
                              value: value,
                              child: Text(_syncProxyTypeLabel(value, l10n)),
                            ),
                          )
                          .toList(),
                    ),
                  )
                : DropdownButtonFormField<SyncProxyType>(
                    initialValue: _proxyType,
                    items: SyncProxyType.values
                        .map(
                          (value) => DropdownMenuItem<SyncProxyType>(
                            value: value,
                            child: Text(_syncProxyTypeLabel(value, l10n)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _proxyType = value;
                        if (_proxyType == SyncProxyType.none) {
                          _proxyHostError = null;
                          _proxyPortError = null;
                        }
                      });
                    },
                    decoration: InputDecoration(
                      labelText: l10n.syncProxyTypeLabel,
                    ),
                  ),
            if (proxyFieldsVisible) ...<Widget>[
              const SizedBox(height: 8),
              useMacOSNativeUI
                  ? buildMacosLabeledField(
                      label: l10n.syncProxyHostLabel,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          MacosTextField(
                            controller: _proxyHostController,
                            placeholder: l10n.syncProxyHostLabel,
                            placeholderStyle: macosPlaceholderStyle,
                          ),
                          buildMacosErrorText(_proxyHostError),
                        ],
                      ),
                    )
                  : TextField(
                      controller: _proxyHostController,
                      decoration: InputDecoration(
                        labelText: l10n.syncProxyHostLabel,
                        errorText: _proxyHostError,
                      ),
                    ),
              const SizedBox(height: 8),
              useMacOSNativeUI
                  ? buildMacosLabeledField(
                      label: l10n.syncProxyPortLabel,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          MacosTextField(
                            controller: _proxyPortController,
                            placeholder: l10n.syncProxyPortLabel,
                            placeholderStyle: macosPlaceholderStyle,
                            keyboardType: TextInputType.number,
                          ),
                          buildMacosErrorText(_proxyPortError),
                        ],
                      ),
                    )
                  : TextField(
                      controller: _proxyPortController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.syncProxyPortLabel,
                        errorText: _proxyPortError,
                      ),
                    ),
              const SizedBox(height: 8),
              useMacOSNativeUI
                  ? buildMacosLabeledField(
                      label: l10n.syncProxyUsernameLabel,
                      child: MacosTextField(
                        controller: _proxyUsernameController,
                        placeholder: l10n.syncProxyUsernameLabel,
                        placeholderStyle: macosPlaceholderStyle,
                      ),
                    )
                  : TextField(
                      controller: _proxyUsernameController,
                      decoration: InputDecoration(
                        labelText: l10n.syncProxyUsernameLabel,
                      ),
                    ),
              const SizedBox(height: 8),
              useMacOSNativeUI
                  ? buildMacosLabeledField(
                      label: l10n.syncProxyPasswordLabel,
                      child: MacosTextField(
                        controller: _proxyPasswordController,
                        placeholder: l10n.syncProxyPasswordLabel,
                        placeholderStyle: macosPlaceholderStyle,
                        obscureText: true,
                      ),
                    )
                  : TextField(
                      controller: _proxyPasswordController,
                      decoration: InputDecoration(
                        labelText: l10n.syncProxyPasswordLabel,
                      ),
                      obscureText: true,
                    ),
            ],
          ],
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
      width: dialogWidth,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            key: _kSettingsDialogNavPaneKey,
            width: 136,
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

    final scrollableContent = SingleChildScrollView(child: content);

    Future<void> saveSettings() async {
      if (_storageTaskInProgress) {
        return;
      }
      final currentSettings = ref
          .read(settingsControllerProvider)
          .asData
          ?.value;
      if (currentSettings == null) {
        return;
      }
      final proxyHost = _proxyHostController.text.trim();
      final proxyPortRaw = _proxyPortController.text.trim();
      final proxyPort = int.tryParse(proxyPortRaw);
      final storageRootPath = _rootPathController.text.trim();
      final proxyEnabled =
          _type == SyncTargetType.webdav && _proxyType != SyncProxyType.none;
      final password = _passwordController.text.trim();
      String? proxyHostError;
      String? proxyPortError;

      if (proxyEnabled) {
        if (proxyHost.isEmpty) {
          proxyHostError = l10n.syncProxyHostRequiredError;
        }
        if (proxyPort == null || proxyPort < 1 || proxyPort > 65535) {
          proxyPortError = l10n.syncProxyPortInvalidError;
        }
      }

      if (mounted) {
        setState(() {
          _proxyHostError = proxyHostError;
          _proxyPortError = proxyPortError;
        });
      }
      if (proxyHostError != null || proxyPortError != null) {
        return;
      }

      final syncConfig = currentSettings.syncConfig.copyWith(
        type: _type,
        url: _urlController.text.trim(),
        username: _usernameController.text.trim(),
        intervalMinutes: int.tryParse(_intervalController.text.trim()) ?? 5,
        failSafe: _failSafe,
        proxy: proxyEnabled
            ? SyncProxyConfig(
                type: _proxyType,
                host: proxyHost,
                port: proxyPort,
                username: _proxyUsernameController.text.trim(),
              )
            : SyncProxyConfig.initial(),
      );

      var bootstrapAction = _BootstrapSyncAction.none;
      if (_shouldAssessBootstrap(
        currentSettings: currentSettings,
        nextConfig: syncConfig,
        nextStorageRootPath: storageRootPath,
      )) {
        final assessment = await ref
            .read(syncRepositoryProvider)
            .assessBootstrap(
              config: syncConfig,
              storageRootPath: storageRootPath,
              password: password.isEmpty ? null : password,
            );
        final resolvedAction = await _resolveBootstrapAction(
          assessment: assessment,
        );
        if (!mounted || resolvedAction == null) {
          return;
        }
        bootstrapAction = resolvedAction;
      }

      await ref
          .read(settingsControllerProvider.notifier)
          .setStorageRootPath(storageRootPath);

      await ref
          .read(settingsControllerProvider.notifier)
          .saveSyncConfig(
            syncConfig,
            password: password.isEmpty ? null : password,
            proxyPassword:
                proxyEnabled && _proxyPasswordController.text.trim().isNotEmpty
                ? _proxyPasswordController.text.trim()
                : null,
            clearProxyPassword: !proxyEnabled,
          );

      await ref
          .read(syncControllerProvider.notifier)
          .startAutoSync(syncConfig.intervalMinutes);

      await ref
          .read(settingsControllerProvider.notifier)
          .setLocaleTag(_localeTag);

      if (storageRootPath != (currentSettings.storageRootPath?.trim() ?? '') ||
          bootstrapAction != _BootstrapSyncAction.none) {
        await _reloadStorageBoundState();
      }

      if (syncConfig.type == SyncTargetType.webdav &&
          bootstrapAction != _BootstrapSyncAction.none) {
        await _runBootstrapSync(bootstrapAction);
        await _reloadStorageBoundState();
      }

      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    if (useMacOSNativeUI) {
      return ChronicleMacosFixedDialog(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
                      onPressed: _storageTaskInProgress
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(l10n.cancelAction),
                    ),
                    const SizedBox(width: 8),
                    PushButton(
                      controlSize: ControlSize.large,
                      onPressed: _storageTaskInProgress ? null : saveSettings,
                      child: Text(l10n.saveAction),
                    ),
                  ],
                ),
              ],
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
          onPressed: _storageTaskInProgress
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: _storageTaskInProgress ? null : saveSettings,
          child: Text(l10n.saveAction),
        ),
      ],
    );
  }
}

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

TextStyle _macosPlaceholderStyle(BuildContext context) {
  final color = MacosTheme.brightnessOf(
    context,
  ).resolve(const Color(0x8A000000), const Color(0xCCEBEBF5));
  return MacosTheme.of(
    context,
  ).typography.body.copyWith(fontWeight: FontWeight.w400, color: color);
}

String _syncTargetTypeLabel(SyncTargetType type, AppLocalizations l10n) {
  return switch (type) {
    SyncTargetType.none => l10n.syncTargetTypeNone,
    SyncTargetType.filesystem => l10n.syncTargetTypeFilesystem,
    SyncTargetType.webdav => l10n.syncTargetTypeWebdav,
  };
}

String _syncProxyTypeLabel(SyncProxyType type, AppLocalizations l10n) {
  return switch (type) {
    SyncProxyType.none => l10n.syncProxyTypeNone,
    SyncProxyType.http => l10n.syncProxyTypeHttp,
    SyncProxyType.socks5 => l10n.syncProxyTypeSocks5,
  };
}
