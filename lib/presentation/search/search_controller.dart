import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/entities/note_search_hit.dart';
import '../../domain/entities/search_query.dart';
import '../../domain/usecases/search/search_notes.dart';

final searchQueryProvider = StateProvider<SearchQuery>((ref) {
  return const SearchQuery(text: '');
});

final availableTagsProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(searchRepositoryProvider).listTags();
});

final searchControllerProvider =
    AsyncNotifierProvider<SearchController, List<NoteSearchHit>>(
      SearchController.new,
    );

class SearchController extends AsyncNotifier<List<NoteSearchHit>> {
  @override
  Future<List<NoteSearchHit>> build() async {
    final query = ref.watch(searchQueryProvider);
    if (_isEmpty(query)) {
      return <NoteSearchHit>[];
    }
    return SearchNotes(ref.read(searchRepositoryProvider))(query);
  }

  Future<void> setText(String text) async {
    final previous = ref.read(searchQueryProvider);
    ref.read(searchQueryProvider.notifier).state = SearchQuery(
      text: text,
      tags: previous.tags,
      matterId: previous.matterId,
      from: previous.from,
      to: previous.to,
    );
    ref.invalidateSelf();
  }

  Future<void> setMatterId(String? matterId) async {
    final previous = ref.read(searchQueryProvider);
    ref.read(searchQueryProvider.notifier).state = SearchQuery(
      text: previous.text,
      tags: previous.tags,
      matterId: matterId,
      from: previous.from,
      to: previous.to,
    );
    ref.invalidateSelf();
  }

  Future<void> setTags(List<String> tags) async {
    final previous = ref.read(searchQueryProvider);
    ref.read(searchQueryProvider.notifier).state = SearchQuery(
      text: previous.text,
      tags: tags,
      matterId: previous.matterId,
      from: previous.from,
      to: previous.to,
    );
    ref.invalidateSelf();
  }

  Future<void> setDateRange(DateTime? from, DateTime? to) async {
    final previous = ref.read(searchQueryProvider);
    ref.read(searchQueryProvider.notifier).state = SearchQuery(
      text: previous.text,
      tags: previous.tags,
      matterId: previous.matterId,
      from: from,
      to: to,
    );
    ref.invalidateSelf();
  }

  bool _isEmpty(SearchQuery query) {
    return query.text.trim().isEmpty &&
        query.tags.isEmpty &&
        (query.matterId == null || query.matterId!.isEmpty) &&
        query.from == null &&
        query.to == null;
  }
}
