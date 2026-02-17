import '../../entities/note_link.dart';
import '../../repositories/link_repository.dart';

class ListNoteLinksForNote {
  const ListNoteLinksForNote(this._linkRepository);

  final LinkRepository _linkRepository;

  Future<List<NoteLink>> call(String noteId) {
    return _linkRepository.listLinksForNote(noteId);
  }
}
