import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

const _kDialogBorderRadius = BorderRadius.all(Radius.circular(12.0));

/// A fixed-size dialog container for macOS native UI that mimics the appearance
/// of [MacosSheet] but does not expand to fill the window.
///
/// Use this for form dialogs (Create/Edit Matter, Category, Settings) where you
/// want a fixed width and natural content height, rather than a full-window sheet.
class ChronicleMacosFixedDialog extends StatelessWidget {
  const ChronicleMacosFixedDialog({
    super.key,
    required this.child,
    this.backgroundColor,
  });

  final Widget child;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final brightness = MacosTheme.brightnessOf(context);

    final outerBorderColor = brightness.resolve(
      Colors.black.withValues(alpha: 0.23),
      Colors.black.withValues(alpha: 0.76),
    );

    final innerBorderColor = brightness.resolve(
      Colors.white.withValues(alpha: 0.45),
      Colors.white.withValues(alpha: 0.15),
    );

    return Center(
      child: IntrinsicWidth(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color:
                backgroundColor ??
                brightness.resolve(
                  CupertinoColors.systemGrey6.color,
                  MacosColors.controlBackgroundColor.darkColor,
                ),
            borderRadius: _kDialogBorderRadius,
          ),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(width: 2, color: innerBorderColor),
              borderRadius: _kDialogBorderRadius,
            ),
            foregroundDecoration: BoxDecoration(
              border: Border.all(width: 1, color: outerBorderColor),
              borderRadius: _kDialogBorderRadius,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
