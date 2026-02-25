import '../entities/note.dart';

abstract class NoteRepository {
  Future<List<Note>> listAllNotes();
  Future<Note?> getNoteById(String noteId);
  Future<Note> createNote({
    required String title,
    required String content,
    String? matterId,
    String? phaseId,
    String? notebookFolderId,
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
    required String? notebookFolderId,
  });
  Future<Note> addAttachments({
    required String noteId,
    required List<String> sourceFilePaths,
  });
  Future<Note> removeAttachment({
    required String noteId,
    required String attachmentPath,
  });
  Future<List<Note>> listOrphanNotes();
  Future<List<Note>> listNotebookNotes({String? folderId});
  Future<List<Note>> listNotesByMatterAndPhase({
    required String matterId,
    required String phaseId,
  });
  Future<List<Note>> listMatterTimeline(String matterId);
}
