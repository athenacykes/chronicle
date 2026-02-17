import '../../entities/note.dart';
import '../../repositories/note_repository.dart';

class UpdateNoteContent {
  const UpdateNoteContent(this._noteRepository);

  final NoteRepository _noteRepository;

  Future<void> call(Note note, String content) {
    return _noteRepository.updateNote(
      note.copyWith(content: content, updatedAt: DateTime.now().toUtc()),
    );
  }
}
