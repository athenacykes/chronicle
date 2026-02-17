import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/note_link.dart';
import '../../domain/usecases/links/create_note_link.dart';
import '../../domain/usecases/links/delete_note_link.dart';
import '../../domain/usecases/links/list_note_links_for_note.dart';
import 'graph_controller.dart';

final allNotesForLinkPickerProvider = FutureProvider<List<Note>>((ref) async {
  final notes = await ref.watch(noteRepositoryProvider).listAllNotes();
  notes.sort((a, b) {
    final updated = b.updatedAt.compareTo(a.updatedAt);
    if (updated != 0) {
      return updated;
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return notes;
});

final linkedNotesByNoteProvider =
    FutureProvider.family<List<LinkedNoteItem>, String>((ref, noteId) async {
      final links = await ListNoteLinksForNote(
        ref.watch(linkRepositoryProvider),
      ).call(noteId);

      final noteRepository = ref.watch(noteRepositoryProvider);
      final result = <LinkedNoteItem>[];
      for (final link in links) {
        final relatedNoteId = link.sourceNoteId == noteId
            ? link.targetNoteId
            : link.sourceNoteId;
        final related = await noteRepository.getNoteById(relatedNoteId);
        if (related == null) {
          continue;
        }

        result.add(
          LinkedNoteItem(
            link: link,
            relatedNote: related,
            isOutgoing: link.sourceNoteId == noteId,
          ),
        );
      }

      result.sort((a, b) {
        final pinned = b.relatedNote.isPinned ? 1 : 0;
        final currentPinned = a.relatedNote.isPinned ? 1 : 0;
        final pinCompare = pinned.compareTo(currentPinned);
        if (pinCompare != 0) {
          return pinCompare;
        }

        final updated = b.relatedNote.updatedAt.compareTo(
          a.relatedNote.updatedAt,
        );
        if (updated != 0) {
          return updated;
        }
        return a.relatedNote.id.compareTo(b.relatedNote.id);
      });
      return result;
    });

final linksControllerProvider = Provider<LinksController>((ref) {
  return LinksController(ref);
});

class LinksController {
  const LinksController(this._ref);

  final Ref _ref;

  Future<NoteLink> createLink({
    required String sourceNoteId,
    required String targetNoteId,
    String context = '',
  }) async {
    final created =
        await CreateNoteLink(
          _ref.read(linkRepositoryProvider),
          _ref.read(noteRepositoryProvider),
        ).call(
          sourceNoteId: sourceNoteId,
          targetNoteId: targetNoteId,
          context: context,
        );

    _ref.invalidate(linkedNotesByNoteProvider(sourceNoteId));
    _ref.invalidate(linkedNotesByNoteProvider(targetNoteId));
    _ref.invalidate(graphControllerProvider);
    return created;
  }

  Future<void> deleteLink({
    required String currentNoteId,
    required NoteLink link,
  }) async {
    await DeleteNoteLink(_ref.read(linkRepositoryProvider)).call(link.id);
    _ref.invalidate(linkedNotesByNoteProvider(currentNoteId));
    _ref.invalidate(linkedNotesByNoteProvider(link.sourceNoteId));
    _ref.invalidate(linkedNotesByNoteProvider(link.targetNoteId));
    _ref.invalidate(graphControllerProvider);
  }

  void invalidateAll() {
    _ref.invalidate(allNotesForLinkPickerProvider);
    _ref.invalidate(linkedNotesByNoteProvider);
    _ref.invalidate(graphControllerProvider);
  }
}

class LinkedNoteItem {
  const LinkedNoteItem({
    required this.link,
    required this.relatedNote,
    required this.isOutgoing,
  });

  final NoteLink link;
  final Note relatedNote;
  final bool isOutgoing;
}
