import '../entities/note_search_hit.dart';
import '../entities/search_query.dart';

abstract class SearchRepository {
  Future<void> rebuildIndex();
  Future<List<NoteSearchHit>> search(SearchQuery query);
  Future<List<String>> listTags();
}
