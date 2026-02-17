import 'package:flutter/material.dart';

import '../chronicle_shell_contract.dart';

class MaterialChronicleShell extends StatelessWidget {
  const MaterialChronicleShell({super.key, required this.viewModel});

  final ChronicleShellViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(viewModel.title),
        actions: <Widget>[
          SizedBox(
            width: viewModel.searchFieldWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: TextField(
                controller: viewModel.searchController,
                onChanged: viewModel.onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Search notes...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Conflicts',
            onPressed: viewModel.onShowConflicts,
            icon: Badge(
              isLabelVisible: viewModel.conflictCount > 0,
              label: Text('${viewModel.conflictCount}'),
              child: const Icon(Icons.report_problem_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Sync now',
            onPressed: () async {
              await viewModel.onSyncNow();
            },
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () async {
              await viewModel.onOpenSettings();
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Row(
        children: <Widget>[
          SizedBox(
            width: viewModel.sidebarWidth,
            child: viewModel.sidebarBuilder(null),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: viewModel.content),
        ],
      ),
      bottomNavigationBar: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: viewModel.status,
      ),
    );
  }
}
