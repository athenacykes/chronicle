import '../entities/note_link.dart';

abstract class LinkRepository {
  Future<List<NoteLink>> listLinks();
  Future<List<NoteLink>> listLinksForNote(String noteId);
  Future<NoteLink> createLink({
    required String sourceNoteId,
    required String targetNoteId,
    required String context,
  });
  Future<void> deleteLink(String linkId);
}
