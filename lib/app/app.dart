import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

import '../l10n/generated/app_localizations.dart';
import '../l10n/localization.dart';
import '../presentation/common/shell/chronicle_home_coordinator.dart';
import '../presentation/common/platform/platform_info.dart';
import '../presentation/notes/notes_controller.dart';
import '../presentation/settings/settings_controller.dart';

class ChronicleApp extends ConsumerStatefulWidget {
  const ChronicleApp({super.key, this.forceMacOSNativeUI});

  final bool? forceMacOSNativeUI;

  @override
  ConsumerState<ChronicleApp> createState() => _ChronicleAppState();
}

class _ChronicleAppState extends ConsumerState<ChronicleApp> {
  static const MethodChannel _appChannel = MethodChannel('chronicle/app');
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _settingsDialogOpen = false;
  bool _importDialogOpen = false;

  void _logSettingsMenu(String message) {
    debugPrint('[Chronicle][SettingsMenu] $message');
  }

  @override
  void initState() {
    super.initState();
    _logSettingsMenu('registering MethodChannel handler');
    _appChannel.setMethodCallHandler(_handleAppChannelCall);
  }

  @override
  void dispose() {
    _logSettingsMenu('clearing MethodChannel handler');
    _appChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _handleAppChannelCall(MethodCall call) async {
    if (!mounted) {
      _logSettingsMenu('received method=${call.method} but widget not mounted');
      return;
    }
    _logSettingsMenu(
      'received method=${call.method}, arguments=${call.arguments}',
    );
    if (call.method == 'openSettings') {
      await _openSettingsDialogFromApp();
    } else {
      _logSettingsMenu('ignored unknown method=${call.method}');
    }
  }

  Future<void> _openSettingsDialogFromApp() async {
    if (!mounted) {
      _logSettingsMenu('open dialog skipped: widget not mounted');
      return;
    }
    if (_settingsDialogOpen) {
      _logSettingsMenu('open dialog skipped: already open');
      return;
    }

    final context = _navigatorKey.currentContext;
    if (context == null) {
      _logSettingsMenu('navigator context is null, retrying next frame');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openSettingsDialogFromApp();
      });
      return;
    }

    _settingsDialogOpen = true;
    _logSettingsMenu('opening settings dialog');
    try {
      await showChronicleSettingsDialog(
        context: context,
        useMacOSNativeUI:
            widget.forceMacOSNativeUI ?? PlatformInfo.useMacOSNativeUI,
      );
      _logSettingsMenu('settings dialog closed normally');
    } catch (error, stackTrace) {
      _logSettingsMenu('settings dialog open failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    } finally {
      _settingsDialogOpen = false;
    }
  }

  Future<void> _openImportDialogFromApp() async {
    if (!mounted) {
      return;
    }
    if (_importDialogOpen) {
      return;
    }

    final context = _navigatorKey.currentContext;
    if (context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openImportDialogFromApp();
      });
      return;
    }

    _importDialogOpen = true;
    try {
      final result = await ref
          .read(noteEditorControllerProvider.notifier)
          .importNotebookFilesFromPicker();
      if (!mounted || result == null || !context.mounted) {
        return;
      }

      final l10n = context.l10n;
      final summary = result.hasWarnings
          ? l10n.notebookImportPartialSummary(
              result.importedNoteCount,
              result.importedFolderCount,
              result.importedResourceCount,
              result.warningCount,
            )
          : l10n.notebookImportSuccessSummary(
              result.importedNoteCount,
              result.importedFolderCount,
              result.importedResourceCount,
            );
      final warningLines = result.warnings
          .take(12)
          .map((warning) {
            final source = warning.sourcePath?.trim() ?? '';
            if (source.isEmpty) {
              return '- ${warning.message}';
            }
            return '- ${p.basename(source)}: ${warning.message}';
          })
          .join('\n');
      final hasExtraWarnings = result.warningCount > 12;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final isMacOSNativeUI =
              widget.forceMacOSNativeUI ?? PlatformInfo.useMacOSNativeUI;
          if (isMacOSNativeUI) {
            return MacosSheet(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.notebookImportDialogTitle,
                      style: MacosTheme.of(dialogContext).typography.title3,
                    ),
                    const SizedBox(height: 8),
                    Text(summary),
                    if (result.hasWarnings) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        l10n.notebookImportWarningsTitle(result.warningCount),
                        style: MacosTheme.of(dialogContext).typography.headline,
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            hasExtraWarnings
                                ? '$warningLines\n...'
                                : warningLines,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        PushButton(
                          controlSize: ControlSize.regular,
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: Text(l10n.closeAction),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          return AlertDialog(
            title: Text(l10n.notebookImportDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(summary),
                if (result.hasWarnings) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(l10n.notebookImportWarningsTitle(result.warningCount)),
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
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.closeAction),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted || !context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.notebookImportDialogTitle),
          content: Text(context.l10n.notebookImportFailed(error.toString())),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.l10n.closeAction),
            ),
          ],
        ),
      );
    } finally {
      _importDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(settingsControllerProvider);
    final configuredLocaleTag = settingsState.asData?.value.localeTag ?? 'en';
    final locale = resolveAppLocale(configuredLocaleTag);

    final useMacOSNativeUI =
        widget.forceMacOSNativeUI ?? PlatformInfo.useMacOSNativeUI;
    if (useMacOSNativeUI) {
      final nativeMacOSHome = PlatformInfo.isMacOS
          ? _ChronicleMacOSMenuHost(
              onImportNotebook: _openImportDialogFromApp,
              onOpenSettings: _openSettingsDialogFromApp,
              child: const ChronicleHomeScreen(useMacOSNativeUI: true),
            )
          : const ChronicleHomeScreen(useMacOSNativeUI: true);
      return MacosApp(
        navigatorKey: _navigatorKey,
        onGenerateTitle: (context) => context.l10n.appTitle,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: MacosThemeData(
          brightness: Brightness.light,
          accentColor: AccentColor.green,
          visualDensity: VisualDensity.standard,
        ),
        darkTheme: MacosThemeData(
          brightness: Brightness.dark,
          accentColor: AccentColor.green,
          visualDensity: VisualDensity.standard,
        ),
        home: nativeMacOSHome,
      );
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      onGenerateTitle: (context) => context.l10n.appTitle,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D6A4F),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D6A4F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      ),
      home: const ChronicleHomeScreen(useMacOSNativeUI: false),
    );
  }
}

class _ChronicleMacOSMenuHost extends StatelessWidget {
  const _ChronicleMacOSMenuHost({
    required this.onImportNotebook,
    required this.onOpenSettings,
    required this.child,
  });

  final Future<void> Function() onImportNotebook;
  final Future<void> Function() onOpenSettings;
  final Widget child;

  static void _invokeFocusedIntent(Intent intent) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) {
      return;
    }
    Actions.maybeInvoke(focusContext, intent);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final materialL10n = MaterialLocalizations.of(context);

    return PlatformMenuBar(
      menus: <PlatformMenuItem>[
        PlatformMenu(
          label: 'APP_NAME',
          menus: <PlatformMenuItem>[
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.about,
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: '${l10n.settingsTitle}...',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.comma,
                    meta: true,
                  ),
                  onSelected: () => unawaited(onOpenSettings()),
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.servicesSubmenu,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.quit,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: l10n.fileMenuLabel,
          menus: <PlatformMenuItem>[
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: l10n.importNotebookActionEllipsis,
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyI,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: () => unawaited(onImportNotebook()),
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: l10n.editAction,
          menus: <PlatformMenuItem>[
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: 'Undo',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    meta: true,
                  ),
                  onSelected: () => _invokeFocusedIntent(
                    const UndoTextIntent(SelectionChangedCause.toolbar),
                  ),
                ),
                PlatformMenuItem(
                  label: 'Redo',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: () => _invokeFocusedIntent(
                    const RedoTextIntent(SelectionChangedCause.toolbar),
                  ),
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: materialL10n.cutButtonLabel,
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyX,
                    meta: true,
                  ),
                  onSelected: () => _invokeFocusedIntent(
                    const CopySelectionTextIntent.cut(
                      SelectionChangedCause.toolbar,
                    ),
                  ),
                ),
                PlatformMenuItem(
                  label: materialL10n.copyButtonLabel,
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyC,
                    meta: true,
                  ),
                  onSelected: () =>
                      _invokeFocusedIntent(CopySelectionTextIntent.copy),
                ),
                PlatformMenuItem(
                  label: materialL10n.pasteButtonLabel,
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyV,
                    meta: true,
                  ),
                  onSelected: () => _invokeFocusedIntent(
                    const PasteTextIntent(SelectionChangedCause.toolbar),
                  ),
                ),
                PlatformMenuItem(
                  label: materialL10n.selectAllButtonLabel,
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyA,
                    meta: true,
                  ),
                  onSelected: () => _invokeFocusedIntent(
                    const SelectAllTextIntent(SelectionChangedCause.toolbar),
                  ),
                ),
              ],
            ),
          ],
        ),
        const PlatformMenu(
          label: 'Window',
          menus: <PlatformMenuItem>[
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.minimizeWindow,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.zoomWindow,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.toggleFullScreen,
                ),
              ],
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
