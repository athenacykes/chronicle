import 'package:chronicle/domain/entities/note.dart';
import 'package:chronicle/presentation/common/shell/chronicle_time_views_controller.dart';
import 'package:chronicle/presentation/matters/matters_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildChronicleTimeViewSummary', () {
    final nowLocal = DateTime(2026, 2, 18, 12);

    test('includes notes created in window', () {
      final summary = buildChronicleTimeViewSummary(
        timeView: ChronicleTimeView.today,
        notes: <Note>[
          _matterNote(
            id: 'created-in-window',
            createdLocal: DateTime(2026, 2, 18, 9),
            updatedLocal: DateTime(2026, 2, 18, 9),
          ),
        ],
        nowLocal: nowLocal,
      );

      expect(summary.totalNotes, 1);
      expect(summary.matterGroups, hasLength(1));
      expect(
        summary.matterGroups.first.notes.single.note.id,
        'created-in-window',
      );
    });

    test('includes notes updated in window when created outside', () {
      final summary = buildChronicleTimeViewSummary(
        timeView: ChronicleTimeView.today,
        notes: <Note>[
          _matterNote(
            id: 'updated-in-window',
            createdLocal: DateTime(2026, 2, 10, 8),
            updatedLocal: DateTime(2026, 2, 18, 7),
          ),
        ],
        nowLocal: nowLocal,
      );

      expect(summary.totalNotes, 1);
      expect(
        summary.matterGroups.single.notes.single.note.id,
        'updated-in-window',
      );
    });

    test(
      'deduplicates a note that was created and updated in the same window',
      () {
        final summary = buildChronicleTimeViewSummary(
          timeView: ChronicleTimeView.today,
          notes: <Note>[
            _matterNote(
              id: 'single-row',
              createdLocal: DateTime(2026, 2, 18, 2),
              updatedLocal: DateTime(2026, 2, 18, 11),
            ),
          ],
          nowLocal: nowLocal,
        );

        expect(summary.totalNotes, 1);
        expect(summary.matterGroups.single.notes, hasLength(1));
      },
    );

    test('excludes notes outside the requested window', () {
      final summary = buildChronicleTimeViewSummary(
        timeView: ChronicleTimeView.today,
        notes: <Note>[
          _matterNote(
            id: 'old-note',
            createdLocal: DateTime(2026, 2, 10, 8),
            updatedLocal: DateTime(2026, 2, 11, 8),
          ),
        ],
        nowLocal: nowLocal,
      );

      expect(summary.totalNotes, 0);
      expect(summary.matterGroups, isEmpty);
      expect(summary.notebookNotes, isEmpty);
    });

    test('uses Monday-start windows for this week and last week', () {
      final thisWeekSummary = buildChronicleTimeViewSummary(
        timeView: ChronicleTimeView.thisWeek,
        notes: <Note>[
          _matterNote(
            id: 'monday-this-week',
            createdLocal: DateTime(2026, 2, 16, 1),
            updatedLocal: DateTime(2026, 2, 16, 1),
          ),
          _matterNote(
            id: 'sunday-last-week',
            createdLocal: DateTime(2026, 2, 15, 22),
            updatedLocal: DateTime(2026, 2, 15, 22),
          ),
        ],
        nowLocal: nowLocal,
      );
      final lastWeekSummary = buildChronicleTimeViewSummary(
        timeView: ChronicleTimeView.lastWeek,
        notes: <Note>[
          _matterNote(
            id: 'monday-this-week',
            createdLocal: DateTime(2026, 2, 16, 1),
            updatedLocal: DateTime(2026, 2, 16, 1),
          ),
          _matterNote(
            id: 'sunday-last-week',
            createdLocal: DateTime(2026, 2, 15, 22),
            updatedLocal: DateTime(2026, 2, 15, 22),
          ),
        ],
        nowLocal: nowLocal,
      );

      expect(
        thisWeekSummary.matterGroups.single.notes.single.note.id,
        'monday-this-week',
      );
      expect(
        lastWeekSummary.matterGroups.single.notes.single.note.id,
        'sunday-last-week',
      );
    });

    test('keeps notebook notes in a single section below matter groups', () {
      final summary = buildChronicleTimeViewSummary(
        timeView: ChronicleTimeView.today,
        notes: <Note>[
          _matterNote(
            id: 'matter-note',
            createdLocal: DateTime(2026, 2, 18, 8),
            updatedLocal: DateTime(2026, 2, 18, 8),
          ),
          _notebookNote(
            id: 'notebook-note',
            createdLocal: DateTime(2026, 2, 18, 9),
            updatedLocal: DateTime(2026, 2, 18, 9),
          ),
        ],
        nowLocal: nowLocal,
      );

      expect(summary.matterGroups, hasLength(1));
      expect(summary.notebookNotes, hasLength(1));
      expect(summary.notebookNotes.single.note.id, 'notebook-note');
    });
  });
}

Note _matterNote({
  required String id,
  required DateTime createdLocal,
  required DateTime updatedLocal,
  String matterId = 'matter-1',
  String phaseId = 'phase-1',
}) {
  return Note(
    id: id,
    matterId: matterId,
    phaseId: phaseId,
    notebookFolderId: null,
    title: id,
    content: id,
    tags: const <String>[],
    isPinned: false,
    attachments: const <String>[],
    createdAt: createdLocal.toUtc(),
    updatedAt: updatedLocal.toUtc(),
  );
}

Note _notebookNote({
  required String id,
  required DateTime createdLocal,
  required DateTime updatedLocal,
  String? folderId,
}) {
  return Note(
    id: id,
    matterId: null,
    phaseId: null,
    notebookFolderId: folderId,
    title: id,
    content: id,
    tags: const <String>[],
    isPinned: false,
    attachments: const <String>[],
    createdAt: createdLocal.toUtc(),
    updatedAt: updatedLocal.toUtc(),
  );
}
