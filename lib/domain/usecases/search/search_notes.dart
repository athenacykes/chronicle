import '../../entities/note_search_hit.dart';
import '../../entities/search_query.dart';
import '../../repositories/search_repository.dart';

class SearchNotes {
  const SearchNotes(this._searchRepository);

  final SearchRepository _searchRepository;

  Future<List<NoteSearchHit>> call(SearchQuery query) {
    return _searchRepository.search(query);
  }
}
