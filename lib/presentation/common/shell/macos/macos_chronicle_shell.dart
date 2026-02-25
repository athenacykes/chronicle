import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../../l10n/localization.dart';
import '../chronicle_shell_contract.dart';

const Key _kReturnSearchResultsButtonKey = Key(
  'macos_return_search_results_button',
);

class MacosChronicleShell extends StatelessWidget {
  const MacosChronicleShell({super.key, required this.viewModel});

  final ChronicleShellViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MacosWindow(
      titleBar: TitleBar(title: Text(l10n.appTitle)),
      sidebar: Sidebar(
        minWidth: viewModel.sidebarWidth,
        maxWidth: viewModel.sidebarWidth + 80,
        startWidth: viewModel.sidebarWidth,
        dragClosed: true,
        dragClosedBuffer: 0,
        topOffset: 28,
        builder: (context, scrollController) => PrimaryScrollController(
          controller: scrollController,
          child: viewModel.sidebarBuilder(scrollController),
        ),
      ),
      child: MacosScaffold(
        children: <Widget>[
          ContentArea(
            builder: (context, scrollController) {
              return Column(
                children: <Widget>[
                  _MacosTopBar(viewModel: viewModel),
                  Expanded(
                    child: _withMaterialBridge(
                      context: context,
                      child: viewModel.content,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

Widget _withMaterialBridge({
  required BuildContext context,
  required Widget child,
}) {
  final brightness = MacosTheme.brightnessOf(context);
  final materialTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2D6A4F),
      brightness: brightness,
    ),
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
  );

  return Theme(
    data: materialTheme,
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class _MacosTopBar extends StatelessWidget {
  const _MacosTopBar({required this.viewModel});

  final ChronicleShellViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final typography = MacosTheme.of(context).typography;
    final primaryColor = MacosTheme.of(context).primaryColor;
    final titleStyle = typography.title3.copyWith(
      fontSize: 15,
      fontWeight: MacosFontWeight.w590,
    );
    final hasParkedSearchResults = viewModel.hasParkedSearchResults;
    final parkedSearchDecoration = BoxDecoration(
      color: primaryColor.withAlpha(26),
      borderRadius: const BorderRadius.all(Radius.circular(7)),
      border: Border.all(color: primaryColor.withAlpha(150)),
    );
    final parkedSearchFocusedDecoration = BoxDecoration(
      borderRadius: const BorderRadius.all(Radius.circular(7)),
      border: Border.all(color: primaryColor),
    );

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: MacosTheme.of(context).dividerColor),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final searchWidth = constraints.maxWidth < 760
              ? 180.0
              : constraints.maxWidth < 980
              ? 240.0
              : viewModel.searchFieldWidth;

          return Row(
            children: <Widget>[
              _ToolbarActionIcon(
                tooltip: l10n.toggleSidebarTooltip,
                icon: const MacosIcon(CupertinoIcons.sidebar_left),
                onPressed: MacosWindowScope.maybeOf(context)?.toggleSidebar,
              ),
              const SizedBox(width: 6),
              Text(viewModel.title, style: titleStyle),
              const Spacer(),
              SizedBox(
                width: searchWidth,
                child: MacosSearchField<void>(
                  controller: viewModel.searchController,
                  placeholder: l10n.searchNotesHint,
                  onChanged: viewModel.onSearchChanged,
                  onTap: viewModel.onSearchFieldTap,
                  maxLines: 1,
                  minLines: 1,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.singleLineFormatter,
                  ],
                  decoration: hasParkedSearchResults
                      ? parkedSearchDecoration
                      : kDefaultRoundedBorderDecoration,
                  focusedDecoration: hasParkedSearchResults
                      ? parkedSearchFocusedDecoration
                      : kDefaultFocusedBorderDecoration,
                ),
              ),
              if (hasParkedSearchResults) ...<Widget>[
                const SizedBox(width: 4),
                _ToolbarActionIcon(
                  buttonKey: _kReturnSearchResultsButtonKey,
                  tooltip: l10n.returnToSearchResultsAction,
                  icon: const MacosIcon(CupertinoIcons.arrow_uturn_left),
                  onPressed: viewModel.onReturnToSearchResults,
                ),
              ],
              const SizedBox(width: 8),
              _ToolbarActionIcon(
                tooltip: l10n.conflictsLabel,
                icon: _ConflictIconBadge(count: viewModel.conflictCount),
                onPressed: viewModel.onShowConflicts,
              ),
              _ToolbarActionIcon(
                tooltip: l10n.settingsTitle,
                icon: const MacosIcon(CupertinoIcons.gear_solid),
                onPressed: () {
                  unawaited(viewModel.onOpenSettings());
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ToolbarActionIcon extends StatelessWidget {
  const _ToolbarActionIcon({
    this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final Key? buttonKey;
  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return MacosTooltip(
      message: tooltip,
      child: MacosIconButton(
        key: buttonKey,
        semanticLabel: tooltip,
        icon: icon,
        backgroundColor: MacosColors.transparent,
        boxConstraints: const BoxConstraints(
          minHeight: 26,
          minWidth: 26,
          maxHeight: 26,
          maxWidth: 26,
        ),
        padding: const EdgeInsets.all(4),
        onPressed: onPressed,
      ),
    );
  }
}

class _ConflictIconBadge extends StatelessWidget {
  const _ConflictIconBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        const MacosIcon(CupertinoIcons.exclamationmark_triangle),
        if (count > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: const BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              alignment: Alignment.center,
              child: Text(
                count > 99 ? '99+' : '$count',
                style: MacosTheme.of(context).typography.caption2.copyWith(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
