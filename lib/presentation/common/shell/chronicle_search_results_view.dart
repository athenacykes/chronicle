import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../l10n/localization.dart';

class SearchListItem {
  const SearchListItem({
    required this.noteId,
    required this.title,
    required this.contextLine,
    required this.snippet,
    required this.searchQuery,
  });

  final String noteId;
  final String title;
  final String contextLine;
  final String snippet;
  final String searchQuery;
}

class ChronicleSearchResultsView extends StatelessWidget {
  const ChronicleSearchResultsView({
    super.key,
    required this.results,
    required this.useMacOSNativeUI,
    required this.onOpenResult,
  });

  final List<SearchListItem> results;
  final bool useMacOSNativeUI;
  final Future<void> Function(String noteId) onOpenResult;

  static const int _minSearchLength = 2;

  Widget _buildHighlightedText(
    BuildContext context,
    String text,
    String searchQuery,
    TextStyle? style,
  ) {
    if (searchQuery.trim().length < _minSearchLength) {
      return Text(
        text,
        style: style,
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = searchQuery.toLowerCase().trim();
    final matches = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        if (start < text.length) {
          matches.add(TextSpan(text: text.substring(start)));
        }
        break;
      }

      if (index > start) {
        matches.add(TextSpan(text: text.substring(start, index)));
      }

      matches.add(
        TextSpan(
          text: text.substring(index, index + lowerQuery.length),
          style: style?.copyWith(
            backgroundColor: Colors.yellow.withValues(alpha: 0.4),
            fontWeight: FontWeight.w600,
          ),
        ),
      );

      start = index + lowerQuery.length;
    }

    return Text.rich(
      maxLines: 5,
      overflow: TextOverflow.ellipsis,
      TextSpan(style: style, children: matches),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (results.isEmpty) {
      return Center(child: Text(l10n.noSearchResultsMessage));
    }

    // 3-column grid layout with cards
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];

        if (useMacOSNativeUI) {
          return _MacosSearchResultCard(
            item: result,
            onTap: () async => await onOpenResult(result.noteId),
            highlightBuilder: (text, style) =>
                _buildHighlightedText(context, text, result.searchQuery, style),
          );
        }

        return _MaterialSearchResultCard(
          item: result,
          onTap: () async => await onOpenResult(result.noteId),
          highlightBuilder: (text, style) =>
              _buildHighlightedText(context, text, result.searchQuery, style),
        );
      },
    );
  }
}

class _MacosSearchResultCard extends StatelessWidget {
  const _MacosSearchResultCard({
    required this.item,
    required this.onTap,
    required this.highlightBuilder,
  });

  final SearchListItem item;
  final VoidCallback onTap;
  final Widget Function(String text, TextStyle? style) highlightBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final l10n = context.l10n;
    final title = item.title.trim().isEmpty
        ? l10n.untitledLabel
        : item.title.trim();

    return Material(
      color: theme.canvasColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const MacosIcon(
                    CupertinoIcons.arrow_up_right_square,
                    size: 14,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.contextLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.caption1.copyWith(
                  color: MacosColors.systemGrayColor,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: highlightBuilder(
                  item.snippet,
                  theme.typography.caption1.copyWith(
                    color: theme.typography.caption1.color?.withValues(
                      alpha: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialSearchResultCard extends StatelessWidget {
  const _MaterialSearchResultCard({
    required this.item,
    required this.onTap,
    required this.highlightBuilder,
  });

  final SearchListItem item;
  final VoidCallback onTap;
  final Widget Function(String text, TextStyle? style) highlightBuilder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = item.title.trim().isEmpty
        ? l10n.untitledLabel
        : item.title.trim();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.open_in_new, size: 16),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.contextLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  highlightBuilder(
                    item.snippet,
                    Theme.of(context).textTheme.bodySmall,
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
