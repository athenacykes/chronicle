import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../l10n/localization.dart';

class ChronicleLoadingShell extends StatelessWidget {
  const ChronicleLoadingShell({super.key, required this.useMacOSNativeUI});

  final bool useMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!useMacOSNativeUI) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return MacosWindow(
      titleBar: TitleBar(title: Text(l10n.appTitle)),
      child: MacosScaffold(
        children: <Widget>[
          ContentArea(
            builder: (context, scrollController) =>
                const Center(child: ProgressCircle()),
          ),
        ],
      ),
    );
  }
}

class ChronicleErrorShell extends StatelessWidget {
  const ChronicleErrorShell({
    super.key,
    required this.useMacOSNativeUI,
    required this.message,
  });

  final bool useMacOSNativeUI;
  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!useMacOSNativeUI) {
      return Scaffold(body: Center(child: Text(message)));
    }

    return MacosWindow(
      titleBar: TitleBar(title: Text(l10n.appTitle)),
      child: MacosScaffold(
        children: <Widget>[
          ContentArea(
            builder: (context, scrollController) =>
                Center(child: Text(message)),
          ),
        ],
      ),
    );
  }
}

class ChronicleStorageRootSetupScreen extends StatefulWidget {
  const ChronicleStorageRootSetupScreen({
    super.key,
    required this.useMacOSNativeUI,
    required this.loadSuggestedDefaultPath,
    required this.pickStorageRootPath,
    required this.onConfirm,
  });

  final bool useMacOSNativeUI;
  final Future<String> Function() loadSuggestedDefaultPath;
  final Future<String?> Function() pickStorageRootPath;
  final Future<void> Function(String path) onConfirm;

  @override
  State<ChronicleStorageRootSetupScreen> createState() =>
      _ChronicleStorageRootSetupScreenState();
}

class _ChronicleStorageRootSetupScreenState
    extends State<ChronicleStorageRootSetupScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _loadingDefault = true;

  @override
  void initState() {
    super.initState();
    _initDefault();
  }

  Future<void> _initDefault() async {
    final value = await widget.loadSuggestedDefaultPath();
    if (!mounted) {
      return;
    }
    _controller.text = value;
    setState(() {
      _loadingDefault = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loadingDefault) {
      if (widget.useMacOSNativeUI) {
        return const ChronicleLoadingShell(useMacOSNativeUI: true);
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final body = Center(
      child: SizedBox(
        width: 520,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.storageSetupTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(l10n.storageSetupDescription),
                const SizedBox(height: 12),
                widget.useMacOSNativeUI
                    ? MacosTextField(
                        controller: _controller,
                        placeholder: l10n.storageRootPathLabel,
                      )
                    : TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          labelText: l10n.storageRootPathLabel,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    widget.useMacOSNativeUI
                        ? PushButton(
                            controlSize: ControlSize.large,
                            onPressed: () async {
                              final path = await widget.pickStorageRootPath();
                              if (!mounted || path == null || path.isEmpty) {
                                return;
                              }
                              _controller.text = path;
                            },
                            child: Text(l10n.pickFolderAction),
                          )
                        : FilledButton(
                            onPressed: () async {
                              final path = await widget.pickStorageRootPath();
                              if (!mounted || path == null || path.isEmpty) {
                                return;
                              }
                              _controller.text = path;
                            },
                            child: Text(l10n.pickFolderAction),
                          ),
                    const SizedBox(width: 8),
                    widget.useMacOSNativeUI
                        ? PushButton(
                            controlSize: ControlSize.large,
                            onPressed: () async {
                              await widget.onConfirm(_controller.text.trim());
                            },
                            child: Text(l10n.continueAction),
                          )
                        : FilledButton.tonal(
                            onPressed: () async {
                              await widget.onConfirm(_controller.text.trim());
                            },
                            child: Text(l10n.continueAction),
                          ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!widget.useMacOSNativeUI) {
      return Scaffold(body: body);
    }

    return MacosWindow(
      titleBar: TitleBar(title: Text(l10n.chronicleSetupTitle)),
      child: MacosScaffold(
        children: <Widget>[
          ContentArea(builder: (context, scrollController) => body),
        ],
      ),
    );
  }
}
