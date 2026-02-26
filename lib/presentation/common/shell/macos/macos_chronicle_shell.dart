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
const Key _kMacosTopBarSearchSlotKey = Key('macos_top_bar_search_slot');
const Key _kMacosTopBarConflictsButtonKey = Key(
  'macos_top_bar_conflicts_button',
);
const Key _kMacosTopBarCompactMenuButtonKey = Key(
  'macos_top_bar_compact_menu_button',
);
const Key _kMacosTopBarCompactPanelKey = Key('macos_top_bar_compact_panel');

class MacosChronicleShell extends StatelessWidget {
  const MacosChronicleShell({super.key, required this.viewModel});

  final ChronicleShellViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return MacosWindow(
      titleBar: TitleBar(title: Text(viewModel.appWindowTitle)),
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

  Widget _buildSearchField({
    required BuildContext context,
    required bool hasParkedSearchResults,
    required BoxDecoration parkedSearchDecoration,
    required BoxDecoration parkedSearchFocusedDecoration,
    double? width,
  }) {
    return SizedBox(
      key: _kMacosTopBarSearchSlotKey,
      width: width,
      child: SizedBox(
        height: 34,
        child: Align(
          alignment: Alignment.center,
          child: MacosSearchField<void>(
            controller: viewModel.searchController,
            placeholder: context.l10n.searchNotesHint,
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
      ),
    );
  }

  Future<void> _showCompactPanel({
    required BuildContext context,
    required bool hasParkedSearchResults,
    required BoxDecoration parkedSearchDecoration,
    required BoxDecoration parkedSearchFocusedDecoration,
    required VoidCallback? onToggleSidebar,
  }) async {
    final l10n = context.l10n;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withAlpha(64),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, _) {
        final panelWidth = (MediaQuery.sizeOf(dialogContext).width * 0.82)
            .clamp(280.0, 420.0)
            .toDouble();
        final panelColor = MacosTheme.brightnessOf(
          dialogContext,
        ).resolve(const Color(0xFFF8F8F8), const Color(0xFF24272B));
        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, right: 8, bottom: 8),
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  key: _kMacosTopBarCompactPanelKey,
                  width: panelWidth,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(dialogContext).height - 24,
                  ),
                  decoration: BoxDecoration(
                    color: panelColor,
                    border: Border.all(
                      color: MacosTheme.of(dialogContext).dividerColor,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: <Widget>[
                            _ToolbarActionIcon(
                              tooltip: l10n.toggleSidebarTooltip,
                              icon: const MacosIcon(
                                CupertinoIcons.sidebar_left,
                              ),
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                onToggleSidebar?.call();
                              },
                            ),
                            if (hasParkedSearchResults)
                              _ToolbarActionIcon(
                                buttonKey: _kReturnSearchResultsButtonKey,
                                tooltip: l10n.returnToSearchResultsAction,
                                icon: const MacosIcon(
                                  CupertinoIcons.arrow_uturn_left,
                                ),
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  viewModel.onReturnToSearchResults();
                                },
                              ),
                            _ToolbarActionIcon(
                              buttonKey: _kMacosTopBarConflictsButtonKey,
                              tooltip: l10n.conflictsLabel,
                              icon: _ConflictIconBadge(
                                count: viewModel.conflictCount,
                              ),
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                viewModel.onShowConflicts();
                              },
                            ),
                            _ToolbarActionIcon(
                              tooltip: l10n.settingsTitle,
                              icon: const MacosIcon(CupertinoIcons.gear_solid),
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                unawaited(viewModel.onOpenSettings());
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildSearchField(
                          context: dialogContext,
                          hasParkedSearchResults: hasParkedSearchResults,
                          parkedSearchDecoration: parkedSearchDecoration,
                          parkedSearchFocusedDecoration:
                              parkedSearchFocusedDecoration,
                        ),
                        if (viewModel.topBarContextActions != null) ...<Widget>[
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: viewModel.topBarContextActions!,
                          ),
                        ],
                        if (viewModel.compactHamburgerContent !=
                            null) ...<Widget>[
                          const SizedBox(height: 8),
                          viewModel.compactHamburgerContent!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.08, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

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
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: MacosTheme.of(context).dividerColor),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < kMacosCompactContentWidth;
          final searchWidth = constraints.maxWidth < 760
              ? 180.0
              : constraints.maxWidth < 980
              ? 240.0
              : viewModel.searchFieldWidth;
          final onToggleSidebar = MacosWindowScope.maybeOf(
            context,
          )?.toggleSidebar;

          if (isCompact) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(
                    viewModel.title,
                    style: titleStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                _ToolbarActionIcon(
                  buttonKey: _kMacosTopBarCompactMenuButtonKey,
                  tooltip: l10n.noteMoreActionsTooltip,
                  icon: const MacosIcon(CupertinoIcons.line_horizontal_3),
                  onPressed: () {
                    unawaited(
                      _showCompactPanel(
                        context: context,
                        hasParkedSearchResults: hasParkedSearchResults,
                        parkedSearchDecoration: parkedSearchDecoration,
                        parkedSearchFocusedDecoration:
                            parkedSearchFocusedDecoration,
                        onToggleSidebar: onToggleSidebar,
                      ),
                    );
                  },
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.35,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _ToolbarActionIcon(
                      tooltip: l10n.toggleSidebarTooltip,
                      icon: const MacosIcon(CupertinoIcons.sidebar_left),
                      onPressed: onToggleSidebar,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        viewModel.title,
                        style: titleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: viewModel.topBarContextActions == null
                    ? const SizedBox.shrink()
                    : Center(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: viewModel.topBarContextActions!,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  _buildSearchField(
                    context: context,
                    hasParkedSearchResults: hasParkedSearchResults,
                    parkedSearchDecoration: parkedSearchDecoration,
                    parkedSearchFocusedDecoration:
                        parkedSearchFocusedDecoration,
                    width: searchWidth,
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
                    buttonKey: _kMacosTopBarConflictsButtonKey,
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
