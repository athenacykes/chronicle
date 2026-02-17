import '../../entities/note.dart';
import '../../repositories/note_repository.dart';

class ListMatterTimeline {
  const ListMatterTimeline(this._noteRepository);

  final NoteRepository _noteRepository;

  Future<List<Note>> call(String matterId) {
    return _noteRepository.listMatterTimeline(matterId);
  }
}
