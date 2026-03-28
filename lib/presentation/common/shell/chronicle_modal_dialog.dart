import 'package:flutter/material.dart';

Future<T?> showChronicleModalDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useRootNavigator = true,
}) {
  final barrierBaseColor = Theme.of(context).colorScheme.scrim;
  final barrierColor = barrierBaseColor.withValues(alpha: 0.42);
  return showDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: false,
    barrierColor: barrierColor,
    builder: builder,
  );
}
