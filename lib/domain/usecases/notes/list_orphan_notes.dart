import '../../entities/note.dart';
import '../../repositories/note_repository.dart';

class ListOrphanNotes {
  const ListOrphanNotes(this._noteRepository);

  final NoteRepository _noteRepository;

  Future<List<Note>> call() {
    return _noteRepository.listOrphanNotes();
  }
}
