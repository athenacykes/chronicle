import 'package:flutter/material.dart';

typedef ChronicleSidebarBuilder =
    Widget Function(ScrollController? scrollController);

class ChronicleShellViewModel {
  const ChronicleShellViewModel({
    required this.title,
    required this.searchController,
    required this.onSearchChanged,
    required this.onShowConflicts,
    required this.onSyncNow,
    required this.onOpenSettings,
    required this.conflictCount,
    required this.sidebarBuilder,
    required this.content,
    required this.status,
    this.searchFieldWidth = 340,
    this.sidebarWidth = 320,
  });

  final String title;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onShowConflicts;
  final Future<void> Function() onSyncNow;
  final Future<void> Function() onOpenSettings;
  final int conflictCount;
  final ChronicleSidebarBuilder sidebarBuilder;
  final Widget content;
  final Widget status;
  final double searchFieldWidth;
  final double sidebarWidth;
}
