import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../domain/entities/note.dart';
import '../../matters/matters_controller.dart';

class ChronicleTimeWindow {
  const ChronicleTimeWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class ChronicleTimeViewEntry {
  const ChronicleTimeViewEntry({
    required this.note,
    required this.latestActivityAtLocal,
  });

  final Note note;
  final DateTime latestActivityAtLocal;
}

class ChronicleTimeMatterGroup {
  const ChronicleTimeMatterGroup({
    required this.matterId,
    required this.notes,
    required this.latestActivityAtLocal,
  });

  final String matterId;
  final List<ChronicleTimeViewEntry> notes;
  final DateTime latestActivityAtLocal;
}

class ChronicleTimeViewSummary {
  const ChronicleTimeViewSummary({
    required this.timeView,
    required this.window,
    required this.matterGroups,
    required this.notebookNotes,
  });

  final ChronicleTimeView timeView;
  final ChronicleTimeWindow window;
  final List<ChronicleTimeMatterGroup> matterGroups;
  final List<ChronicleTimeViewEntry> notebookNotes;

  int get totalNotes =>
      notebookNotes.length +
      matterGroups.fold<int>(0, (sum, group) => sum + group.notes.length);
}

final timeViewSummaryProvider = FutureProvider<ChronicleTimeViewSummary?>((
  ref,
) async {
  final timeView = ref.watch(selectedTimeViewProvider);
  if (timeView == null) {
    return null;
  }
  final notes = await ref.watch(noteRepositoryProvider).listAllNotes();
  final nowLocal = ref.read(clockProvider).nowUtc().toLocal();
  return buildChronicleTimeViewSummary(
    timeView: timeView,
    notes: notes,
    nowLocal: nowLocal,
  );
});

ChronicleTimeViewSummary buildChronicleTimeViewSummary({
  required ChronicleTimeView timeView,
  required List<Note> notes,
  required DateTime nowLocal,
}) {
  final window = resolveChronicleTimeWindow(
    timeView: timeView,
    nowLocal: nowLocal,
  );
  final entriesById = <String, ChronicleTimeViewEntry>{};

  for (final note in notes) {
    final latestInWindow = _latestInWindow(
      note: note,
      windowStart: window.start,
      windowEnd: window.end,
    );
    if (latestInWindow == null) {
      continue;
    }
    entriesById[note.id] = ChronicleTimeViewEntry(
      note: note,
      latestActivityAtLocal: latestInWindow,
    );
  }

  final matterEntries = <String, List<ChronicleTimeViewEntry>>{};
  final notebookEntries = <ChronicleTimeViewEntry>[];
  for (final entry in entriesById.values) {
    final note = entry.note;
    if (note.isInNotebook || note.matterId == null) {
      notebookEntries.add(entry);
      continue;
    }
    matterEntries
        .putIfAbsent(note.matterId!, () => <ChronicleTimeViewEntry>[])
        .add(entry);
  }

  final matterGroups =
      matterEntries.entries.map((entry) {
        final items = entry.value.toList()..sort(_compareEntries);
        return ChronicleTimeMatterGroup(
          matterId: entry.key,
          notes: List<ChronicleTimeViewEntry>.unmodifiable(items),
          latestActivityAtLocal: items.first.latestActivityAtLocal,
        );
      }).toList()..sort((a, b) {
        final latestCompare = b.latestActivityAtLocal.compareTo(
          a.latestActivityAtLocal,
        );
        if (latestCompare != 0) {
          return latestCompare;
        }
        return a.matterId.compareTo(b.matterId);
      });

  notebookEntries.sort(_compareEntries);
  return ChronicleTimeViewSummary(
    timeView: timeView,
    window: window,
    matterGroups: List<ChronicleTimeMatterGroup>.unmodifiable(matterGroups),
    notebookNotes: List<ChronicleTimeViewEntry>.unmodifiable(notebookEntries),
  );
}

ChronicleTimeWindow resolveChronicleTimeWindow({
  required ChronicleTimeView timeView,
  required DateTime nowLocal,
}) {
  final todayStart = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  return switch (timeView) {
    ChronicleTimeView.today => ChronicleTimeWindow(
      start: todayStart,
      end: todayStart.add(const Duration(days: 1)),
    ),
    ChronicleTimeView.yesterday => ChronicleTimeWindow(
      start: todayStart.subtract(const Duration(days: 1)),
      end: todayStart,
    ),
    ChronicleTimeView.thisWeek => _resolveWeekWindow(
      referenceDayLocal: todayStart,
      weekOffset: 0,
    ),
    ChronicleTimeView.lastWeek => _resolveWeekWindow(
      referenceDayLocal: todayStart,
      weekOffset: -1,
    ),
  };
}

ChronicleTimeWindow _resolveWeekWindow({
  required DateTime referenceDayLocal,
  required int weekOffset,
}) {
  final mondayOffset = referenceDayLocal.weekday - DateTime.monday;
  final weekStart = referenceDayLocal
      .subtract(Duration(days: mondayOffset))
      .add(Duration(days: weekOffset * 7));
  return ChronicleTimeWindow(
    start: weekStart,
    end: weekStart.add(const Duration(days: 7)),
  );
}

DateTime? _latestInWindow({
  required Note note,
  required DateTime windowStart,
  required DateTime windowEnd,
}) {
  DateTime? latest;
  final createdLocal = note.createdAt.toLocal();
  if (_isInWindow(createdLocal, windowStart, windowEnd)) {
    latest = createdLocal;
  }

  final updatedLocal = note.updatedAt.toLocal();
  if (_isInWindow(updatedLocal, windowStart, windowEnd) &&
      (latest == null || updatedLocal.isAfter(latest))) {
    latest = updatedLocal;
  }
  return latest;
}

bool _isInWindow(DateTime value, DateTime start, DateTime end) {
  return !value.isBefore(start) && value.isBefore(end);
}

int _compareEntries(ChronicleTimeViewEntry a, ChronicleTimeViewEntry b) {
  final byActivity = b.latestActivityAtLocal.compareTo(a.latestActivityAtLocal);
  if (byActivity != 0) {
    return byActivity;
  }
  final byUpdated = b.note.updatedAt.compareTo(a.note.updatedAt);
  if (byUpdated != 0) {
    return byUpdated;
  }
  return a.note.id.compareTo(b.note.id);
}
