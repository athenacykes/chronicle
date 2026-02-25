import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

class ChronicleMacosCompactIconButton extends StatelessWidget {
  const ChronicleMacosCompactIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return MacosTooltip(
      message: tooltip,
      child: MacosIconButton(
        semanticLabel: tooltip,
        icon: icon,
        backgroundColor: MacosColors.transparent,
        boxConstraints: const BoxConstraints(
          minHeight: 28,
          minWidth: 28,
          maxHeight: 28,
          maxWidth: 28,
        ),
        padding: const EdgeInsets.all(4),
        onPressed: onPressed,
      ),
    );
  }
}

class ChronicleMacosSelectableRow extends StatelessWidget {
  const ChronicleMacosSelectableRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    required this.onTap,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typography = MacosTheme.of(context).typography;
    final selectedColor = MacosTheme.of(context).primaryColor.withAlpha(26);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? selectedColor : null,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading!,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DefaultTextStyle(
                    style: typography.body.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    child: title,
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style: typography.caption1,
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
