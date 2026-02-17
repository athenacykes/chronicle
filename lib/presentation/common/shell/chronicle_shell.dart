import 'package:flutter/widgets.dart';

import 'chronicle_shell_contract.dart';
import 'macos/macos_chronicle_shell.dart';
import 'material/material_chronicle_shell.dart';

class ChronicleShell extends StatelessWidget {
  const ChronicleShell({
    super.key,
    required this.useMacOSNativeUI,
    required this.viewModel,
  });

  final bool useMacOSNativeUI;
  final ChronicleShellViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (useMacOSNativeUI) {
      return MacosChronicleShell(viewModel: viewModel);
    }
    return MaterialChronicleShell(viewModel: viewModel);
  }
}
