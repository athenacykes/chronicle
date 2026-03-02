import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

const Duration _kMenuDuration = Duration(milliseconds: 300);
const double _kMenuItemHeight = 20.0;
const EdgeInsets _kMenuItemPadding = EdgeInsets.symmetric(horizontal: 6.0);
const BorderRadius _kBorderRadius = BorderRadius.all(Radius.circular(5.0));
const double _kMenuLeftOffset = 8.0;

class ChronicleMacosContextMenuItem<T> extends MacosPulldownMenuItem {
  const ChronicleMacosContextMenuItem({
    super.key,
    required this.value,
    required super.title,
    super.enabled = true,
    super.alignment = AlignmentDirectional.centerStart,
  });

  final T value;
}

Future<T?> showChronicleMacosContextMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<MacosPulldownMenuEntry> items,
  PulldownMenuAlignment menuAlignment = PulldownMenuAlignment.left,
}) {
  if (items.isEmpty) {
    return Future<T?>.value(null);
  }

  final navigator = Navigator.of(context);
  final textDirection = Directionality.maybeOf(context);
  const menuMargin = EdgeInsets.symmetric(horizontal: 4.0);
  final menuAnchorBox = navigator.context.findRenderObject()! as RenderBox;
  final localPosition = menuAnchorBox.globalToLocal(globalPosition);
  final anchorRect = Rect.fromLTWH(localPosition.dx, localPosition.dy, 1, 1);

  final route = _ChronicleMacosContextMenuRoute<T>(
    items: items,
    padding: _kMenuItemPadding.resolve(textDirection),
    buttonRect: menuMargin.resolve(textDirection).inflateRect(anchorRect),
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    menuAlignment: menuAlignment,
  );

  return navigator.push<T>(route);
}

class _ChronicleMacosContextMenuItemButton<T> extends StatefulWidget {
  const _ChronicleMacosContextMenuItemButton({
    required this.route,
    required this.itemIndex,
  });

  final _ChronicleMacosContextMenuRoute<T> route;
  final int itemIndex;

  @override
  State<_ChronicleMacosContextMenuItemButton<T>> createState() =>
      _ChronicleMacosContextMenuItemButtonState<T>();
}

class _ChronicleMacosContextMenuItemButtonState<T>
    extends State<_ChronicleMacosContextMenuItemButton<T>> {
  bool _isHovered = false;

  void _handleOnTap() {
    final menuEntry = widget.route.items[widget.itemIndex];
    if (menuEntry is! MacosPulldownMenuItem || !menuEntry.enabled) {
      return;
    }
    Navigator.of(context).pop(
      menuEntry is ChronicleMacosContextMenuItem<T> ? menuEntry.value : null,
    );
    menuEntry.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final brightness = MacosTheme.brightnessOf(context);
    final menuEntry = widget.route.items[widget.itemIndex];

    if (menuEntry is MacosPulldownMenuItem) {
      Widget child = Container(
        padding: widget.route.padding,
        height: menuEntry.itemHeight,
        child: menuEntry,
      );

      if (menuEntry.enabled) {
        child = MouseRegion(
          cursor: SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleOnTap,
            child: Container(
              decoration: BoxDecoration(
                color: _isHovered
                    ? MacosPulldownButtonTheme.of(context).highlightColor
                    : Colors.transparent,
                borderRadius: _kBorderRadius,
              ),
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 13.0,
                  color: _isHovered
                      ? MacosColors.white
                      : brightness.resolve(
                          MacosColors.black,
                          MacosColors.white,
                        ),
                ),
                child: child,
              ),
            ),
          ),
        );
      } else {
        final disabledColor = brightness.resolve(
          MacosColors.disabledControlTextColor,
          MacosColors.disabledControlTextColor.darkColor,
        );
        child = DefaultTextStyle(
          style: theme.typography.body.copyWith(color: disabledColor),
          child: child,
        );
      }
      return child;
    }

    return menuEntry;
  }
}

class _ChronicleMacosContextMenu<T> extends StatefulWidget {
  const _ChronicleMacosContextMenu({
    required this.route,
    required this.constraints,
  });

  final _ChronicleMacosContextMenuRoute<T> route;
  final BoxConstraints constraints;

  @override
  State<_ChronicleMacosContextMenu<T>> createState() =>
      _ChronicleMacosContextMenuState<T>();
}

class _ChronicleMacosContextMenuState<T>
    extends State<_ChronicleMacosContextMenu<T>> {
  late CurvedAnimation _fadeOpacity;

  @override
  void initState() {
    super.initState();
    _fadeOpacity = CurvedAnimation(
      parent: widget.route.animation!,
      curve: const Interval(0.0, 0.25),
      reverseCurve: const Interval(0.75, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeOpacity,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        child: IntrinsicWidth(
          child: MacosOverlayFilter(
            color: MacosPulldownButtonTheme.of(
              context,
            ).pulldownColor?.withValues(alpha: 0.25),
            borderRadius: _kBorderRadius,
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (
                    int itemIndex = 0;
                    itemIndex < widget.route.items.length;
                    itemIndex++
                  )
                    _ChronicleMacosContextMenuItemButton<T>(
                      route: widget.route,
                      itemIndex: itemIndex,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChronicleMacosContextMenuRouteLayout<T>
    extends SingleChildLayoutDelegate {
  _ChronicleMacosContextMenuRouteLayout({
    required this.route,
    required this.buttonRect,
    required this.textDirection,
  });

  final _ChronicleMacosContextMenuRoute<T> route;
  final Rect buttonRect;
  final TextDirection? textDirection;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      minWidth: kMinInteractiveDimension,
      maxWidth: constraints.maxWidth,
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final menuLimits = route.getMenuLimits(buttonRect, size.height);

    double left;
    switch (route.menuAlignment) {
      case PulldownMenuAlignment.left:
        switch (textDirection!) {
          case TextDirection.rtl:
            left = buttonRect.right.clamp(0.0, size.width) - childSize.width;
            break;
          case TextDirection.ltr:
            left = buttonRect.left + _kMenuLeftOffset;
            break;
        }
        break;
      case PulldownMenuAlignment.right:
        switch (textDirection!) {
          case TextDirection.rtl:
            left = buttonRect.left + _kMenuLeftOffset;
            break;
          case TextDirection.ltr:
            left = buttonRect.left - childSize.width + buttonRect.width;
            break;
        }
        break;
    }

    if (left + childSize.width >= size.width) {
      left = left.clamp(0.0, size.width - childSize.width) - _kMenuLeftOffset;
    }

    return Offset(left, menuLimits.top);
  }

  @override
  bool shouldRelayout(_ChronicleMacosContextMenuRouteLayout<T> oldDelegate) {
    return buttonRect != oldDelegate.buttonRect ||
        textDirection != oldDelegate.textDirection ||
        route != oldDelegate.route;
  }
}

class _MenuLimits {
  const _MenuLimits(this.top, this.bottom, this.height);

  final double top;
  final double bottom;
  final double height;
}

class _ChronicleMacosContextMenuRoute<T> extends PopupRoute<T> {
  _ChronicleMacosContextMenuRoute({
    required this.items,
    required this.padding,
    required this.buttonRect,
    required this.capturedThemes,
    required this.menuAlignment,
    required this.barrierLabel,
  }) : itemHeights = items
           .map((item) => item.itemHeight)
           .toList(growable: false);

  final List<MacosPulldownMenuEntry> items;
  final EdgeInsets padding;
  final Rect buttonRect;
  final CapturedThemes capturedThemes;
  final PulldownMenuAlignment menuAlignment;
  final List<double> itemHeights;

  @override
  final String? barrierLabel;

  @override
  Duration get transitionDuration => _kMenuDuration;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  _MenuLimits getMenuLimits(Rect buttonRect, double availableHeight) {
    final computedMaxHeight = availableHeight - 2.0 * _kMenuItemHeight;
    final buttonTop = buttonRect.top;
    final buttonBottom = math.min(buttonRect.bottom, availableHeight);
    final bottomLimit = math.max(
      availableHeight - _kMenuItemHeight,
      buttonBottom,
    );

    var menuTop = buttonTop + buttonRect.height;
    var preferredMenuHeight = 8.0;
    if (items.isNotEmpty) {
      preferredMenuHeight += itemHeights.reduce((a, b) => a + b);
    }

    final menuHeight = math.min(computedMaxHeight, preferredMenuHeight);
    var menuBottom = menuTop + menuHeight;

    if (menuBottom > bottomLimit) {
      menuBottom = buttonTop - 5.0;
      menuTop = buttonTop - menuHeight - 5.0;
    } else {
      menuBottom += 1.0;
      menuTop += 1.0;
    }
    return _MenuLimits(menuTop, menuBottom, menuHeight);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final textDirection = Directionality.maybeOf(context);
    final menu = _ChronicleMacosContextMenu<T>(
      route: this,
      constraints: BoxConstraints.loose(MediaQuery.sizeOf(context)),
    );

    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: Builder(
        builder: (context) {
          return CustomSingleChildLayout(
            delegate: _ChronicleMacosContextMenuRouteLayout<T>(
              route: this,
              buttonRect: buttonRect,
              textDirection: textDirection,
            ),
            child: capturedThemes.wrap(menu),
          );
        },
      ),
    );
  }
}
