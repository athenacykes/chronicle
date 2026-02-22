import '../../repositories/category_repository.dart';

class DeleteCategory {
  const DeleteCategory(this._categoryRepository);

  final CategoryRepository _categoryRepository;

  Future<void> call(String categoryId) {
    return _categoryRepository.deleteCategory(categoryId);
  }
}
