import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/entities/note_search_hit.dart';
import '../../domain/entities/search_query.dart';
import '../../domain/usecases/search/search_notes.dart';
import '../common/state/value_notifier_provider.dart';

final searchQueryProvider =
    NotifierProvider<ValueNotifierController<SearchQuery>, SearchQuery>(
      () => ValueNotifierController<SearchQuery>(const SearchQuery(text: '')),
    );

final searchResultsVisibleProvider =
    NotifierProvider<ValueNotifierController<bool>, bool>(
      () => ValueNotifierController<bool>(false),
    );

final availableTagsProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(searchRepositoryProvider).listTags();
});

final searchControllerProvider =
    AsyncNotifierProvider<SearchController, List<NoteSearchHit>>(
      SearchController.new,
    );

class SearchController extends AsyncNotifier<List<NoteSearchHit>> {
  static const int _minSearchTextLength = 2;

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
    ref
        .read(searchQueryProvider.notifier)
        .set(
          SearchQuery(
            text: text,
            tags: previous.tags,
            matterId: previous.matterId,
            from: previous.from,
            to: previous.to,
          ),
        );
    // Note: We do NOT call ref.invalidateSelf() here because the provider
    // already watches searchQueryProvider, so it will automatically rebuild
    // when the query changes. Calling invalidateSelf() causes unnecessary
    // rebuilds that can cause the search text field to lose focus.
  }

  Future<void> setMatterId(String? matterId) async {
    final previous = ref.read(searchQueryProvider);
    ref
        .read(searchQueryProvider.notifier)
        .set(
          SearchQuery(
            text: previous.text,
            tags: previous.tags,
            matterId: matterId,
            from: previous.from,
            to: previous.to,
          ),
        );
    // Note: No ref.invalidateSelf() needed - provider watches searchQueryProvider
  }

  Future<void> setTags(List<String> tags) async {
    final previous = ref.read(searchQueryProvider);
    ref
        .read(searchQueryProvider.notifier)
        .set(
          SearchQuery(
            text: previous.text,
            tags: tags,
            matterId: previous.matterId,
            from: previous.from,
            to: previous.to,
          ),
        );
    // Note: No ref.invalidateSelf() needed - provider watches searchQueryProvider
  }

  Future<void> setDateRange(DateTime? from, DateTime? to) async {
    final previous = ref.read(searchQueryProvider);
    ref
        .read(searchQueryProvider.notifier)
        .set(
          SearchQuery(
            text: previous.text,
            tags: previous.tags,
            matterId: previous.matterId,
            from: from,
            to: to,
          ),
        );
    // Note: No ref.invalidateSelf() needed - provider watches searchQueryProvider
  }

  bool _isEmpty(SearchQuery query) {
    final nonWhitespaceTextLength = query.text
        .replaceAll(RegExp(r'\s+'), '')
        .length;
    final hasSearchText = nonWhitespaceTextLength >= _minSearchTextLength;
    return !hasSearchText &&
        query.tags.isEmpty &&
        (query.matterId == null || query.matterId!.isEmpty) &&
        query.from == null &&
        query.to == null;
  }
}
