import '../../entities/category.dart';
import '../../repositories/category_repository.dart';

class ListCategories {
  const ListCategories(this._categoryRepository);

  final CategoryRepository _categoryRepository;

  Future<List<Category>> call() {
    return _categoryRepository.listCategories();
  }
}
