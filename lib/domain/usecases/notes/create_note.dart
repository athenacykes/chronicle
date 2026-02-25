import '../../entities/note.dart';
import '../../repositories/note_repository.dart';

class CreateNote {
  const CreateNote(this._noteRepository);

  final NoteRepository _noteRepository;

  Future<Note> call({
    required String title,
    required String content,
    String? matterId,
    String? phaseId,
    String? notebookFolderId,
    List<String> tags = const <String>[],
    bool isPinned = false,
    List<String> attachments = const <String>[],
  }) {
    return _noteRepository.createNote(
      title: title,
      content: content,
      matterId: matterId,
      phaseId: phaseId,
      notebookFolderId: notebookFolderId,
      tags: tags,
      isPinned: isPinned,
      attachments: attachments,
    );
  }
}
