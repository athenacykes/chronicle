import '../entities/note.dart';

abstract class NoteRepository {
  Future<List<Note>> listAllNotes();
  Future<Note?> getNoteById(String noteId);
  Future<Note> createNote({
    required String title,
    required String content,
    String? matterId,
    String? phaseId,
    List<String> tags,
    bool isPinned,
    List<String> attachments,
  });
  Future<void> updateNote(Note note);
  Future<void> deleteNote(String noteId);
  Future<void> moveNote({
    required String noteId,
    required String? matterId,
    required String? phaseId,
  });
  Future<List<Note>> listOrphanNotes();
  Future<List<Note>> listNotesByMatterAndPhase({
    required String matterId,
    required String phaseId,
  });
  Future<List<Note>> listMatterTimeline(String matterId);
}
