import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../domain/entities/sync_conflict.dart';
import '../../../domain/entities/sync_conflict_detail.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/localization.dart';

class ChronicleConflictReviewPane extends StatelessWidget {
  const ChronicleConflictReviewPane({
    super.key,
    required this.conflict,
    required this.detail,
    required this.useMacOSNativeUI,
    required this.onAcceptLeft,
    required this.onAcceptRight,
    this.onOpenMainNote,
  });

  final SyncConflict conflict;
  final AsyncValue<SyncConflictDetail?> detail;
  final bool useMacOSNativeUI;
  final VoidCallback? onOpenMainNote;
  final VoidCallback onAcceptLeft;
  final VoidCallback onAcceptRight;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return detail.when(
      loading: () => Center(
        child: useMacOSNativeUI
            ? const ProgressCircle()
            : const CircularProgressIndicator(),
      ),
      error: (error, stackTrace) =>
          Text(l10n.failedToLoadConflict(error.toString())),
      data: (value) {
        if (value == null) {
          return Text(l10n.conflictContentEmpty);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              conflict.title,
              style: useMacOSNativeUI
                  ? MacosTheme.of(context).typography.title3
                  : Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _MetadataSummary(
              conflict: conflict,
              useMacOSNativeUI: useMacOSNativeUI,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                useMacOSNativeUI
                    ? PushButton(
                        controlSize: ControlSize.regular,
                        secondary: true,
                        onPressed: onOpenMainNote,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const MacosIcon(
                              CupertinoIcons.arrow_up_right_square,
                              size: 13,
                            ),
                            const SizedBox(width: 6),
                            Text(l10n.openMainNoteAction),
                          ],
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: onOpenMainNote,
                        icon: const Icon(Icons.open_in_new),
                        label: Text(l10n.openMainNoteAction),
                      ),
                useMacOSNativeUI
                    ? PushButton(
                        controlSize: ControlSize.regular,
                        onPressed: onAcceptLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const MacosIcon(
                              CupertinoIcons.arrow_left,
                              size: 13,
                            ),
                            const SizedBox(width: 6),
                            Text(l10n.acceptLeftAction),
                          ],
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: onAcceptLeft,
                        icon: const Icon(Icons.keyboard_arrow_left),
                        label: Text(l10n.acceptLeftAction),
                      ),
                useMacOSNativeUI
                    ? PushButton(
                        controlSize: ControlSize.regular,
                        onPressed: onAcceptRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const MacosIcon(
                              CupertinoIcons.arrow_right,
                              size: 13,
                            ),
                            const SizedBox(width: 6),
                            Text(l10n.acceptRightAction),
                          ],
                        ),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: onAcceptRight,
                        icon: const Icon(Icons.keyboard_arrow_right),
                        label: Text(l10n.acceptRightAction),
                      ),
              ],
            ),
            const SizedBox(height: 8),
            if (value.originalFileMissing)
              _NoticeBanner(
                key: const Key('conflict_notice_missing_original'),
                message: l10n.conflictOriginalFileMissingMessage,
                useMacOSNativeUI: useMacOSNativeUI,
              ),
            if (value.mainFileChangedSinceCapture)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _NoticeBanner(
                  key: const Key('conflict_notice_stale_main_file'),
                  message: l10n.conflictMainFileChangedSinceCaptureMessage,
                  useMacOSNativeUI: useMacOSNativeUI,
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _ConflictDiffSurface(
                detail: value,
                useMacOSNativeUI: useMacOSNativeUI,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetadataSummary extends StatelessWidget {
  const _MetadataSummary({
    required this.conflict,
    required this.useMacOSNativeUI,
  });

  final SyncConflict conflict;
  final bool useMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final children = <Widget>[
      Text(l10n.conflictTypeRow(_conflictTypeLabel(conflict.type, l10n))),
      Text(l10n.conflictFileRow(conflict.conflictPath)),
      Text(l10n.conflictOriginalRow(conflict.originalPath)),
      Text(l10n.conflictLocalRow(conflict.localDevice)),
      Text(l10n.conflictRemoteRow(conflict.remoteDevice)),
    ];
    return Container(
      decoration: _panelDecoration(context, useMacOSNativeUI: useMacOSNativeUI),
      padding: const EdgeInsets.all(10),
      child: DefaultTextStyle(
        style: useMacOSNativeUI
            ? MacosTheme.of(context).typography.body
            : theme.textTheme.bodyMedium ?? const TextStyle(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _ConflictDiffSurface extends StatelessWidget {
  const _ConflictDiffSurface({
    required this.detail,
    required this.useMacOSNativeUI,
  });

  final SyncConflictDetail detail;
  final bool useMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (detail.conflict.type == SyncConflictType.unknown) {
      return Text(l10n.binaryConflictNotPreviewable);
    }

    final localContent = detail.localContent;
    final mainFileContent = detail.mainFileContent;
    if (localContent == null || localContent.trim().isEmpty) {
      return Text(l10n.conflictReviewTextDiffUnavailableMessage);
    }
    if (mainFileContent == null || mainFileContent.trim().isEmpty) {
      return _SingleDocumentPanel(
        title: l10n.conflictReviewLocalCopyTitle,
        content: localContent,
        useMacOSNativeUI: useMacOSNativeUI,
      );
    }

    final rows = _buildDiffRows(localContent, mainFileContent);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        if (wide) {
          return _SideBySideDiffView(
            rows: rows,
            useMacOSNativeUI: useMacOSNativeUI,
          );
        }
        return _UnifiedDiffView(rows: rows, useMacOSNativeUI: useMacOSNativeUI);
      },
    );
  }
}

class _SingleDocumentPanel extends StatelessWidget {
  const _SingleDocumentPanel({
    required this.title,
    required this.content,
    required this.useMacOSNativeUI,
  });

  final String title;
  final String content;
  final bool useMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _panelDecoration(context, useMacOSNativeUI: useMacOSNativeUI),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _PaneHeader(title: title, useMacOSNativeUI: useMacOSNativeUI),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: <Widget>[
                _DiffLineCell(
                  text: content,
                  color: null,
                  useMacOSNativeUI: useMacOSNativeUI,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideBySideDiffView extends StatelessWidget {
  const _SideBySideDiffView({
    required this.rows,
    required this.useMacOSNativeUI,
  });

  final List<_DiffRow> rows;
  final bool useMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      key: const Key('conflict_diff_side_by_side'),
      decoration: _panelDecoration(context, useMacOSNativeUI: useMacOSNativeUI),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _PaneHeader(
                  title: l10n.conflictReviewLocalCopyTitle,
                  useMacOSNativeUI: useMacOSNativeUI,
                ),
              ),
              Container(width: 1, color: Theme.of(context).dividerColor),
              Expanded(
                child: _PaneHeader(
                  title: l10n.conflictReviewMainFileTitle,
                  useMacOSNativeUI: useMacOSNativeUI,
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: _DiffLineCell(
                          lineNumber: row.leftLineNumber,
                          text: row.leftText,
                          color: row.leftColor(context),
                          useMacOSNativeUI: useMacOSNativeUI,
                        ),
                      ),
                      Container(
                        width: 1,
                        color: Theme.of(context).dividerColor,
                      ),
                      Expanded(
                        child: _DiffLineCell(
                          lineNumber: row.rightLineNumber,
                          text: row.rightText,
                          color: row.rightColor(context),
                          useMacOSNativeUI: useMacOSNativeUI,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UnifiedDiffView extends StatelessWidget {
  const _UnifiedDiffView({required this.rows, required this.useMacOSNativeUI});

  final List<_DiffRow> rows;
  final bool useMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('conflict_diff_unified'),
      decoration: _panelDecoration(context, useMacOSNativeUI: useMacOSNativeUI),
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          final leading = switch (row.kind) {
            _DiffRowKind.unchanged => ' ',
            _DiffRowKind.removed => '-',
            _DiffRowKind.added => '+',
          };
          final text = switch (row.kind) {
            _DiffRowKind.unchanged => row.leftText ?? row.rightText ?? '',
            _DiffRowKind.removed => row.leftText ?? '',
            _DiffRowKind.added => row.rightText ?? '',
          };
          return _UnifiedDiffLine(
            prefix: leading,
            text: text,
            lineNumber: row.kind == _DiffRowKind.added
                ? row.rightLineNumber
                : row.leftLineNumber,
            color: switch (row.kind) {
              _DiffRowKind.unchanged => null,
              _DiffRowKind.removed => _removedTint(context),
              _DiffRowKind.added => _addedTint(context),
            },
            useMacOSNativeUI: useMacOSNativeUI,
          );
        },
      ),
    );
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.title, required this.useMacOSNativeUI});

  final String title;
  final bool useMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    final style = useMacOSNativeUI
        ? MacosTheme.of(
            context,
          ).typography.body.copyWith(fontWeight: MacosFontWeight.w600)
        : Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Text(title, style: style),
    );
  }
}

class _DiffLineCell extends StatelessWidget {
  const _DiffLineCell({
    required this.text,
    required this.color,
    required this.useMacOSNativeUI,
    this.lineNumber,
  });

  final int? lineNumber;
  final String? text;
  final Color? color;
  final bool useMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monoStyle =
        (useMacOSNativeUI
            ? MacosTheme.of(context).typography.body
            : theme.textTheme.bodyMedium) ??
        const TextStyle();
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 36,
            child: Text(
              lineNumber?.toString() ?? '',
              style: monoStyle.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                color: theme.hintColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              text ?? '',
              style: monoStyle.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnifiedDiffLine extends StatelessWidget {
  const _UnifiedDiffLine({
    required this.prefix,
    required this.text,
    required this.lineNumber,
    required this.color,
    required this.useMacOSNativeUI,
  });

  final String prefix;
  final String text;
  final int? lineNumber;
  final Color? color;
  final bool useMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monoStyle =
        (useMacOSNativeUI
            ? MacosTheme.of(context).typography.body
            : theme.textTheme.bodyMedium) ??
        const TextStyle();
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 16,
            child: Text(
              prefix,
              style: monoStyle.copyWith(fontFamily: 'monospace'),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              lineNumber?.toString() ?? '',
              style: monoStyle.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                color: theme.hintColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              text,
              style: monoStyle.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({
    super.key,
    required this.message,
    required this.useMacOSNativeUI,
  });

  final String message;
  final bool useMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.secondaryContainer.withValues(
      alpha: 0.65,
    );
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.35),
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

List<_DiffRow> _buildDiffRows(String left, String right) {
  final leftLines = _splitLines(left);
  final rightLines = _splitLines(right);
  if (leftLines.isEmpty && rightLines.isEmpty) {
    return const <_DiffRow>[];
  }

  final matrix = List<List<int>>.generate(
    leftLines.length + 1,
    (_) => List<int>.filled(rightLines.length + 1, 0),
  );

  for (var i = leftLines.length - 1; i >= 0; i--) {
    for (var j = rightLines.length - 1; j >= 0; j--) {
      if (leftLines[i] == rightLines[j]) {
        matrix[i][j] = matrix[i + 1][j + 1] + 1;
      } else {
        matrix[i][j] = math.max(matrix[i + 1][j], matrix[i][j + 1]);
      }
    }
  }

  final rows = <_DiffRow>[];
  var i = 0;
  var j = 0;
  var leftLineNumber = 1;
  var rightLineNumber = 1;
  while (i < leftLines.length || j < rightLines.length) {
    if (i < leftLines.length &&
        j < rightLines.length &&
        leftLines[i] == rightLines[j]) {
      rows.add(
        _DiffRow(
          kind: _DiffRowKind.unchanged,
          leftText: leftLines[i],
          rightText: rightLines[j],
          leftLineNumber: leftLineNumber,
          rightLineNumber: rightLineNumber,
        ),
      );
      i++;
      j++;
      leftLineNumber++;
      rightLineNumber++;
      continue;
    }

    final removeLeft =
        j == rightLines.length ||
        (i < leftLines.length && matrix[i + 1][j] >= matrix[i][j + 1]);
    if (removeLeft) {
      rows.add(
        _DiffRow(
          kind: _DiffRowKind.removed,
          leftText: leftLines[i],
          rightText: null,
          leftLineNumber: leftLineNumber,
          rightLineNumber: null,
        ),
      );
      i++;
      leftLineNumber++;
      continue;
    }

    rows.add(
      _DiffRow(
        kind: _DiffRowKind.added,
        leftText: null,
        rightText: rightLines[j],
        leftLineNumber: null,
        rightLineNumber: rightLineNumber,
      ),
    );
    j++;
    rightLineNumber++;
  }

  return rows;
}

List<String> _splitLines(String value) {
  final normalized = value.replaceAll('\r\n', '\n');
  if (normalized.isEmpty) {
    return const <String>[];
  }
  return normalized.split('\n');
}

BoxDecoration _panelDecoration(
  BuildContext context, {
  required bool useMacOSNativeUI,
}) {
  final theme = Theme.of(context);
  if (useMacOSNativeUI) {
    return BoxDecoration(
      color: MacosTheme.of(context).canvasColor,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: MacosTheme.of(context).dividerColor.withValues(alpha: 0.45),
      ),
    );
  }
  return BoxDecoration(
    border: Border.all(color: theme.dividerColor),
    borderRadius: BorderRadius.circular(8),
    color: theme.colorScheme.surface,
  );
}

Color _addedTint(BuildContext context) {
  return Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45);
}

Color _removedTint(BuildContext context) {
  return Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.45);
}

String _conflictTypeLabel(SyncConflictType type, AppLocalizations l10n) {
  return switch (type) {
    SyncConflictType.note => l10n.conflictTypeNote,
    SyncConflictType.link => l10n.conflictTypeLink,
    SyncConflictType.unknown => l10n.conflictTypeUnknown,
  };
}

enum _DiffRowKind { unchanged, removed, added }

class _DiffRow {
  const _DiffRow({
    required this.kind,
    required this.leftText,
    required this.rightText,
    required this.leftLineNumber,
    required this.rightLineNumber,
  });

  final _DiffRowKind kind;
  final String? leftText;
  final String? rightText;
  final int? leftLineNumber;
  final int? rightLineNumber;

  Color? leftColor(BuildContext context) {
    return switch (kind) {
      _DiffRowKind.unchanged => null,
      _DiffRowKind.removed => _removedTint(context),
      _DiffRowKind.added => null,
    };
  }

  Color? rightColor(BuildContext context) {
    return switch (kind) {
      _DiffRowKind.unchanged => null,
      _DiffRowKind.removed => null,
      _DiffRowKind.added => _addedTint(context),
    };
  }
}
