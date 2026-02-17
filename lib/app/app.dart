import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../presentation/common/chronicle_home_screen.dart';
import '../presentation/common/platform/platform_info.dart';

class ChronicleApp extends StatelessWidget {
  const ChronicleApp({super.key, this.forceMacOSNativeUI});

  final bool? forceMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    final useMacOSNativeUI =
        forceMacOSNativeUI ?? PlatformInfo.useMacOSNativeUI;
    if (useMacOSNativeUI) {
      return MacosApp(
        title: 'Chronicle',
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
      title: 'Chronicle',
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
