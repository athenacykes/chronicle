import '../../entities/category.dart';
import '../../repositories/category_repository.dart';

class UpdateCategory {
  const UpdateCategory(this._categoryRepository);

  final CategoryRepository _categoryRepository;

  Future<void> call(Category category) {
    return _categoryRepository.updateCategory(category);
  }
}
