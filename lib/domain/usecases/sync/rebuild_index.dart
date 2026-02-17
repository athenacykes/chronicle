import '../../repositories/search_repository.dart';

class RebuildIndex {
  const RebuildIndex(this._searchRepository);

  final SearchRepository _searchRepository;

  Future<void> call() {
    return _searchRepository.rebuildIndex();
  }
}
