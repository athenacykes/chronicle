import 'package:flutter/foundation.dart';

class PlatformInfo {
  const PlatformInfo._();

  static const bool macOSNativeUiFlag = bool.fromEnvironment(
    'CHRONICLE_MACOS_NATIVE_UI',
    defaultValue: false,
  );

  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get useMacOSNativeUI => isMacOS && macOSNativeUiFlag;
}
