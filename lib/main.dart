import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_window_utils/macos_window_utils.dart';

import 'app/app.dart';
import 'presentation/common/platform/platform_info.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (PlatformInfo.useMacOSNativeUI) {
    await WindowManipulator.initialize();
    await WindowManipulator.enableFullSizeContentView();
    await WindowManipulator.setToolbarStyle(
      toolbarStyle: NSWindowToolbarStyle.unified,
    );
  }

  runApp(const ProviderScope(child: ChronicleApp()));
}
