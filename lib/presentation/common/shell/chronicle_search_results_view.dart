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
  });

  final String noteId;
  final String title;
  final String contextLine;
  final String snippet;
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (results.isEmpty) {
      return Center(child: Text(l10n.noSearchResultsMessage));
    }

    if (useMacOSNativeUI) {
      return ListView.separated(
        padding: const EdgeInsets.all(10),
        itemBuilder: (_, index) {
          final result = results[index];
          return _MacosSearchResultRow(
            title: result.title,
            subtitle: '${result.contextLine}\n${result.snippet}',
            onTap: () async {
              await onOpenResult(result.noteId);
            },
          );
        },
        separatorBuilder: (_, index) => const SizedBox(height: 4),
        itemCount: results.length,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemBuilder: (_, index) {
        final result = results[index];
        return ListTile(
          title: Text(result.title),
          subtitle: Text(
            '${result.contextLine}\n${result.snippet}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          onTap: () async {
            await onOpenResult(result.noteId);
          },
        );
      },
      separatorBuilder: (_, index) => const Divider(height: 1),
      itemCount: results.length,
    );
  }
}

class _MacosSearchResultRow extends StatelessWidget {
  const _MacosSearchResultRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = MacosTheme.of(context).dividerColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          await onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: MacosTheme.of(context).typography.caption1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const MacosIcon(CupertinoIcons.arrow_up_right_square, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}
