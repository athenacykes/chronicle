import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/localization.dart';
import '../presentation/common/shell/chronicle_home_coordinator.dart';
import '../presentation/common/platform/platform_info.dart';
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

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(settingsControllerProvider);
    final configuredLocaleTag = settingsState.asData?.value.localeTag ?? 'en';
    final locale = resolveAppLocale(configuredLocaleTag);

    final useMacOSNativeUI =
        widget.forceMacOSNativeUI ?? PlatformInfo.useMacOSNativeUI;
    if (useMacOSNativeUI) {
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
        home: const ChronicleHomeScreen(useMacOSNativeUI: true),
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
