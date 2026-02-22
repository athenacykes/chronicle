import '../../entities/category.dart';
import '../../repositories/category_repository.dart';

class CreateCategory {
  const CreateCategory(this._categoryRepository);

  final CategoryRepository _categoryRepository;

  Future<Category> call({
    required String name,
    String color = '#4C956C',
    String icon = 'folder',
  }) {
    return _categoryRepository.createCategory(
      name: name,
      color: color,
      icon: icon,
    );
  }
}
