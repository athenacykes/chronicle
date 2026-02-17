import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../chronicle_shell_contract.dart';

class MacosChronicleShell extends StatelessWidget {
  const MacosChronicleShell({super.key, required this.viewModel});

  final ChronicleShellViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return MacosWindow(
      titleBar: const TitleBar(title: Text('Chronicle')),
      sidebar: Sidebar(
        minWidth: viewModel.sidebarWidth,
        maxWidth: viewModel.sidebarWidth + 80,
        startWidth: viewModel.sidebarWidth,
        topOffset: 28,
        builder: (context, scrollController) => PrimaryScrollController(
          controller: scrollController,
          child: viewModel.sidebarBuilder(scrollController),
        ),
      ),
      child: MacosScaffold(
        toolBar: ToolBar(
          title: Text(viewModel.title),
          centerTitle: false,
          actions: <ToolbarItem>[
            CustomToolbarItem(
              tooltipMessage: 'Search notes',
              inToolbarBuilder: (context) => SizedBox(
                width: viewModel.searchFieldWidth,
                child: MacosSearchField<void>(
                  controller: viewModel.searchController,
                  placeholder: 'Search notes...',
                  onChanged: viewModel.onSearchChanged,
                ),
              ),
              inOverflowedBuilder: (context) => const ToolbarOverflowMenuItem(
                label: 'Search',
                onPressed: null,
              ),
            ),
            const ToolBarSpacer(),
            ToolBarIconButton(
              label: 'Conflicts',
              icon: _ConflictIconBadge(count: viewModel.conflictCount),
              tooltipMessage: 'Conflicts',
              showLabel: false,
              onPressed: viewModel.onShowConflicts,
            ),
            ToolBarIconButton(
              label: 'Sync now',
              icon: const MacosIcon(CupertinoIcons.arrow_2_circlepath),
              tooltipMessage: 'Sync now',
              showLabel: false,
              onPressed: () {
                unawaited(viewModel.onSyncNow());
              },
            ),
            ToolBarIconButton(
              label: 'Settings',
              icon: const MacosIcon(CupertinoIcons.gear_solid),
              tooltipMessage: 'Settings',
              showLabel: false,
              onPressed: () {
                unawaited(viewModel.onOpenSettings());
              },
            ),
          ],
        ),
        children: <Widget>[
          ContentArea(
            builder: (context, scrollController) {
              return Column(
                children: <Widget>[
                  Expanded(
                    child: _withMaterialBridge(
                      context: context,
                      child: viewModel.content,
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: MacosTheme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: DefaultTextStyle(
                      style: MacosTheme.of(context).typography.caption1,
                      child: _withMaterialBridge(
                        context: context,
                        child: viewModel.status,
                      ),
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
