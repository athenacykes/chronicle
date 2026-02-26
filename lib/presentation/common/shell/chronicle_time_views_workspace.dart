import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../domain/entities/matter.dart';
import '../../../domain/entities/notebook_folder.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/localization.dart';
import '../../matters/matters_controller.dart';
import 'chronicle_time_views_controller.dart';

class ChronicleTimeViewsWorkspace extends StatelessWidget {
  const ChronicleTimeViewsWorkspace({
    super.key,
    required this.summary,
    required this.matterById,
    required this.notebookFolderById,
    required this.useMacOSNativeUI,
    required this.onOpenNote,
  });

  final ChronicleTimeViewSummary summary;
  final Map<String, Matter> matterById;
  final Map<String, NotebookFolder> notebookFolderById;
  final bool useMacOSNativeUI;
  final Future<void> Function(String noteId) onOpenNote;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (summary.totalNotes == 0) {
      return Center(child: Text(l10n.timeViewNoNotesMessage));
    }

    final sections = <Widget>[
      _TimeViewSummaryHeader(
        title: _timeViewLabel(l10n, summary.timeView),
        summaryText: l10n.timeViewSummaryCounts(
          summary.totalNotes,
          summary.matterGroups.length,
          summary.notebookNotes.length,
        ),
        useMacOSNativeUI: useMacOSNativeUI,
      ),
      const SizedBox(height: 12),
      if (summary.matterGroups.isNotEmpty)
        _TimeViewSectionTitle(
          title: l10n.timeViewMatterSectionLabel(summary.matterGroups.length),
          useMacOSNativeUI: useMacOSNativeUI,
        ),
      for (final group in summary.matterGroups)
        _TimeViewMatterGroupCard(
          matter: matterById[group.matterId],
          group: group,
          useMacOSNativeUI: useMacOSNativeUI,
          onOpenNote: onOpenNote,
        ),
      if (summary.notebookNotes.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        _TimeViewSectionTitle(
          title: l10n.timeViewNotebookSectionLabel(
            summary.notebookNotes.length,
          ),
          useMacOSNativeUI: useMacOSNativeUI,
        ),
        _TimeViewNotebookCard(
          entries: summary.notebookNotes,
          notebookFolderById: notebookFolderById,
          useMacOSNativeUI: useMacOSNativeUI,
          onOpenNote: onOpenNote,
        ),
      ],
    ];

    return ListView(
      key: Key('time_view_workspace_${summary.timeView.name}'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: sections,
    );
  }
}

class _TimeViewSummaryHeader extends StatelessWidget {
  const _TimeViewSummaryHeader({
    required this.title,
    required this.summaryText,
    required this.useMacOSNativeUI,
  });

  final String title;
  final String summaryText;
  final bool useMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: useMacOSNativeUI
                ? MacosTheme.of(context).typography.title3
                : Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            summaryText,
            style: useMacOSNativeUI
                ? MacosTheme.of(context).typography.caption1
                : Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
    return _TimeViewPanel(useMacOSNativeUI: useMacOSNativeUI, child: child);
  }
}

class _TimeViewSectionTitle extends StatelessWidget {
  const _TimeViewSectionTitle({
    required this.title,
    required this.useMacOSNativeUI,
  });

  final String title;
  final bool useMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
      child: Text(
        title,
        style: useMacOSNativeUI
            ? MacosTheme.of(context).typography.headline
            : Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _TimeViewMatterGroupCard extends StatelessWidget {
  const _TimeViewMatterGroupCard({
    required this.matter,
    required this.group,
    required this.useMacOSNativeUI,
    required this.onOpenNote,
  });

  final Matter? matter;
  final ChronicleTimeMatterGroup group;
  final bool useMacOSNativeUI;
  final Future<void> Function(String noteId) onOpenNote;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final matterTitle = matter == null
        ? l10n.untitledMatterLabel
        : _displayMatterTitle(matter!, l10n);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _TimeViewPanel(
        useMacOSNativeUI: useMacOSNativeUI,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                '$matterTitle (${group.notes.length})',
                style: useMacOSNativeUI
                    ? MacosTheme.of(
                        context,
                      ).typography.body.copyWith(fontWeight: FontWeight.w700)
                    : Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (
              var index = 0;
              index < group.notes.length;
              index++
            ) ...<Widget>[
              _TimeViewNoteRow(
                entry: group.notes[index],
                subtitle: _matterSubtitle(
                  l10n: l10n,
                  entry: group.notes[index],
                  matter: matter,
                ),
                useMacOSNativeUI: useMacOSNativeUI,
                onTap: () => onOpenNote(group.notes[index].note.id),
              ),
              if (index != group.notes.length - 1)
                _TimeViewDivider(useMacOSNativeUI: useMacOSNativeUI),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeViewNotebookCard extends StatelessWidget {
  const _TimeViewNotebookCard({
    required this.entries,
    required this.notebookFolderById,
    required this.useMacOSNativeUI,
    required this.onOpenNote,
  });

  final List<ChronicleTimeViewEntry> entries;
  final Map<String, NotebookFolder> notebookFolderById;
  final bool useMacOSNativeUI;
  final Future<void> Function(String noteId) onOpenNote;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _TimeViewPanel(
      useMacOSNativeUI: useMacOSNativeUI,
      child: Column(
        children: <Widget>[
          for (var index = 0; index < entries.length; index++) ...<Widget>[
            _TimeViewNoteRow(
              entry: entries[index],
              subtitle: _notebookSubtitle(
                l10n: l10n,
                entry: entries[index],
                notebookFolderById: notebookFolderById,
              ),
              useMacOSNativeUI: useMacOSNativeUI,
              onTap: () => onOpenNote(entries[index].note.id),
            ),
            if (index != entries.length - 1)
              _TimeViewDivider(useMacOSNativeUI: useMacOSNativeUI),
          ],
        ],
      ),
    );
  }
}

class _TimeViewNoteRow extends StatelessWidget {
  const _TimeViewNoteRow({
    required this.entry,
    required this.subtitle,
    required this.useMacOSNativeUI,
    required this.onTap,
  });

  final ChronicleTimeViewEntry entry;
  final String subtitle;
  final bool useMacOSNativeUI;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = entry.note.title.trim().isEmpty
        ? l10n.untitledLabel
        : entry.note.title.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await onTap();
        },
        child: Padding(
          key: ValueKey<String>('time_view_note_${entry.note.id}'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: useMacOSNativeUI
                          ? MacosTheme.of(context).typography.body
                          : Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: useMacOSNativeUI
                          ? MacosTheme.of(context).typography.caption1
                          : Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                useMacOSNativeUI
                    ? CupertinoIcons.arrow_up_right_square
                    : Icons.open_in_new,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeViewDivider extends StatelessWidget {
  const _TimeViewDivider({required this.useMacOSNativeUI});

  final bool useMacOSNativeUI;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: useMacOSNativeUI
          ? MacosTheme.of(context).dividerColor
          : Theme.of(context).dividerColor,
    );
  }
}

class _TimeViewPanel extends StatelessWidget {
  const _TimeViewPanel({required this.useMacOSNativeUI, required this.child});

  final bool useMacOSNativeUI;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (useMacOSNativeUI) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: MacosTheme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: child,
    );
  }
}

String _displayMatterTitle(Matter matter, AppLocalizations l10n) {
  final trimmed = matter.title.trim();
  if (trimmed.isEmpty) {
    return l10n.untitledMatterLabel;
  }
  return trimmed;
}

String _timeViewLabel(AppLocalizations l10n, ChronicleTimeView timeView) {
  return switch (timeView) {
    ChronicleTimeView.today => l10n.timeViewTodayLabel,
    ChronicleTimeView.yesterday => l10n.timeViewYesterdayLabel,
    ChronicleTimeView.thisWeek => l10n.timeViewThisWeekLabel,
    ChronicleTimeView.lastWeek => l10n.timeViewLastWeekLabel,
  };
}

String _matterSubtitle({
  required AppLocalizations l10n,
  required ChronicleTimeViewEntry entry,
  required Matter? matter,
}) {
  final activity = DateFormat(
    'yyyy-MM-dd HH:mm',
  ).format(entry.latestActivityAtLocal);
  final phaseId = entry.note.phaseId;
  if (phaseId == null || matter == null) {
    return l10n.timeViewActivityAtLabel(activity);
  }
  for (final phase in matter.phases) {
    if (phase.id == phaseId) {
      final phaseName = phase.name.trim();
      final phaseLabel = phaseName.isEmpty ? phase.id : phaseName;
      return '$phaseLabel • ${l10n.timeViewActivityAtLabel(activity)}';
    }
  }
  return '$phaseId • ${l10n.timeViewActivityAtLabel(activity)}';
}

String _notebookSubtitle({
  required AppLocalizations l10n,
  required ChronicleTimeViewEntry entry,
  required Map<String, NotebookFolder> notebookFolderById,
}) {
  final activity = DateFormat(
    'yyyy-MM-dd HH:mm',
  ).format(entry.latestActivityAtLocal);
  final folderId = entry.note.notebookFolderId;
  if (folderId == null) {
    return '${l10n.notebookRootLabel} • ${l10n.timeViewActivityAtLabel(activity)}';
  }
  final folder = notebookFolderById[folderId];
  final folderName = folder?.name.trim();
  if (folderName == null || folderName.isEmpty) {
    return '$folderId • ${l10n.timeViewActivityAtLabel(activity)}';
  }
  return '$folderName • ${l10n.timeViewActivityAtLabel(activity)}';
}
