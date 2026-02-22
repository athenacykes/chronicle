import '../entities/category.dart';

abstract class CategoryRepository {
  Future<List<Category>> listCategories();
  Future<Category?> getCategoryById(String categoryId);
  Future<Category> createCategory({
    required String name,
    String color,
    String icon,
  });
  Future<void> updateCategory(Category category);
  Future<void> deleteCategory(String categoryId);
}
