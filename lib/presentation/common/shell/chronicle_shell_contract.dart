import 'package:flutter/material.dart';

typedef ChronicleSidebarBuilder =
    Widget Function(ScrollController? scrollController);

const double kMacosCompactContentWidth = 720.0;

class ChronicleShellViewModel {
  const ChronicleShellViewModel({
    required this.appWindowTitle,
    required this.title,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSearchFieldTap,
    required this.onReturnToSearchResults,
    required this.hasParkedSearchResults,
    required this.onShowConflicts,
    required this.onOpenSettings,
    required this.conflictCount,
    required this.sidebarBuilder,
    required this.content,
    this.topBarContextActions,
    this.compactHamburgerContent,
    this.searchFieldWidth = 340,
    this.sidebarWidth = 320,
  });

  final String appWindowTitle;
  final String title;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchFieldTap;
  final VoidCallback onReturnToSearchResults;
  final bool hasParkedSearchResults;
  final VoidCallback onShowConflicts;
  final Future<void> Function() onOpenSettings;
  final int conflictCount;
  final ChronicleSidebarBuilder sidebarBuilder;
  final Widget content;
  final Widget? topBarContextActions;
  final Widget? compactHamburgerContent;
  final double searchFieldWidth;
  final double sidebarWidth;
}
