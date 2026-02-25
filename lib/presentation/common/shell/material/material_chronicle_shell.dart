import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../l10n/localization.dart';
import '../chronicle_shell_contract.dart';

const Key _kReturnSearchResultsButtonKey = Key(
  'material_return_search_results_button',
);

class MaterialChronicleShell extends StatelessWidget {
  const MaterialChronicleShell({super.key, required this.viewModel});

  final ChronicleShellViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final hasParkedSearchResults = viewModel.hasParkedSearchResults;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final searchWidth = viewportWidth < 760
        ? 180.0
        : viewportWidth < 980
        ? 240.0
        : viewModel.searchFieldWidth;
    final topControlsSlotWidth = ((viewportWidth - searchWidth - 320).clamp(
      180.0,
      420.0,
    )).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: Text(viewModel.title),
        actions: <Widget>[
          if (viewModel.topBarContextActions != null)
            SizedBox(
              width: topControlsSlotWidth,
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: viewModel.topBarContextActions!,
                  ),
                ),
              ),
            ),
          SizedBox(
            width: searchWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: TextField(
                controller: viewModel.searchController,
                onChanged: viewModel.onSearchChanged,
                onTap: viewModel.onSearchFieldTap,
                maxLines: 1,
                minLines: 1,
                textInputAction: TextInputAction.search,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.singleLineFormatter,
                ],
                decoration: InputDecoration(
                  hintText: l10n.searchNotesHint,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: hasParkedSearchResults
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: hasParkedSearchResults
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colorScheme.primary),
                  ),
                  filled: hasParkedSearchResults,
                  fillColor: hasParkedSearchResults
                      ? colorScheme.primaryContainer.withAlpha(95)
                      : null,
                  isDense: true,
                ),
              ),
            ),
          ),
          if (hasParkedSearchResults)
            IconButton(
              key: _kReturnSearchResultsButtonKey,
              tooltip: l10n.returnToSearchResultsAction,
              onPressed: viewModel.onReturnToSearchResults,
              icon: const Icon(Icons.undo),
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
