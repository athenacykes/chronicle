import 'package:flutter/material.dart';

import '../../../../l10n/localization.dart';
import '../chronicle_shell_contract.dart';

class MaterialChronicleShell extends StatelessWidget {
  const MaterialChronicleShell({super.key, required this.viewModel});

  final ChronicleShellViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

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
                decoration: InputDecoration(
                  hintText: l10n.searchNotesHint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.conflictsLabel,
            onPressed: viewModel.onShowConflicts,
            icon: Badge(
              isLabelVisible: viewModel.conflictCount > 0,
              label: Text('${viewModel.conflictCount}'),
              child: const Icon(Icons.report_problem_outlined),
            ),
          ),
          IconButton(
            tooltip: l10n.settingsTitle,
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
    );
  }
}
