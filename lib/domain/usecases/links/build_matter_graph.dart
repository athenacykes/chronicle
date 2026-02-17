import '../../entities/matter_graph_data.dart';
import '../../entities/matter_graph_edge.dart';
import '../../entities/matter_graph_node.dart';
import '../../repositories/link_repository.dart';
import '../../repositories/note_repository.dart';

class BuildMatterGraph {
  BuildMatterGraph(this._noteRepository, this._linkRepository, {NowUtc? nowUtc})
    : _nowUtc = nowUtc ?? _defaultNowUtc;

  final NoteRepository _noteRepository;
  final LinkRepository _linkRepository;
  final NowUtc _nowUtc;

  Future<MatterGraphData> call({required String matterId}) async {
    final allNotes = await _noteRepository.listAllNotes();
    final allLinks = await _linkRepository.listLinks();
    final notesById = <String, _NoteSnapshot>{};
    for (final note in allNotes) {
      notesById[note.id] = _NoteSnapshot(
        noteId: note.id,
        title: note.title,
        matterId: note.matterId,
        phaseId: note.phaseId,
        isPinned: note.isPinned,
        isOrphan: note.isOrphan,
        updatedAt: note.updatedAt,
      );
    }

    final selectedIds = <String>{};
    for (final note in notesById.values) {
      if (note.matterId == matterId) {
        selectedIds.add(note.noteId);
      }
    }

    final includedIds = <String>{...selectedIds};
    for (final link in allLinks) {
      final source = link.sourceNoteId;
      final target = link.targetNoteId;
      if (!notesById.containsKey(source) || !notesById.containsKey(target)) {
        continue;
      }

      final touchesSelected =
          selectedIds.contains(source) || selectedIds.contains(target);
      if (touchesSelected) {
        includedIds.add(source);
        includedIds.add(target);
      }
    }

    final nodes = <MatterGraphNode>[];
    for (final noteId in includedIds) {
      final note = notesById[noteId];
      if (note == null) {
        continue;
      }

      nodes.add(
        MatterGraphNode(
          noteId: note.noteId,
          title: note.title,
          matterId: note.matterId,
          phaseId: note.phaseId,
          isPinned: note.isPinned,
          isOrphan: note.isOrphan,
          isInSelectedMatter: selectedIds.contains(note.noteId),
          updatedAt: note.updatedAt,
        ),
      );
    }

    nodes.sort((a, b) {
      final updated = b.updatedAt.compareTo(a.updatedAt);
      if (updated != 0) {
        return updated;
      }
      return a.noteId.compareTo(b.noteId);
    });

    final edges = <MatterGraphEdge>[];
    for (final link in allLinks) {
      final source = link.sourceNoteId;
      final target = link.targetNoteId;
      if (!includedIds.contains(source) || !includedIds.contains(target)) {
        continue;
      }

      edges.add(
        MatterGraphEdge(
          linkId: link.id,
          sourceNoteId: source,
          targetNoteId: target,
          context: link.context,
          createdAt: link.createdAt,
        ),
      );
    }

    edges.sort((a, b) {
      final created = b.createdAt.compareTo(a.createdAt);
      if (created != 0) {
        return created;
      }
      return a.linkId.compareTo(b.linkId);
    });

    return MatterGraphData(nodes: nodes, edges: edges, generatedAt: _nowUtc());
  }
}

typedef NowUtc = DateTime Function();

DateTime _defaultNowUtc() => DateTime.now().toUtc();

class _NoteSnapshot {
  const _NoteSnapshot({
    required this.noteId,
    required this.title,
    required this.matterId,
    required this.phaseId,
    required this.isPinned,
    required this.isOrphan,
    required this.updatedAt,
  });

  final String noteId;
  final String title;
  final String? matterId;
  final String? phaseId;
  final bool isPinned;
  final bool isOrphan;
  final DateTime updatedAt;
}
