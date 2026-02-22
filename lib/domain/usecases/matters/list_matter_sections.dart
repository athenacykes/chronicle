import '../../entities/category.dart';
import '../../entities/matter.dart';
import '../../entities/matter_sections.dart';
import '../../repositories/category_repository.dart';
import '../../repositories/matter_repository.dart';

class ListMatterSections {
  const ListMatterSections(this._matterRepository, this._categoryRepository);

  final MatterRepository _matterRepository;
  final CategoryRepository _categoryRepository;

  Future<MatterSections> call() async {
    final matters = await _matterRepository.listMatters();
    final categories = await _categoryRepository.listCategories();
    categories.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    final pinned = <Matter>[];
    final unpinnedByCategoryId = <String, List<Matter>>{};
    final uncategorized = <Matter>[];

    final categoryById = <String, Category>{
      for (final category in categories) category.id: category,
    };

    for (final matter in matters) {
      if (matter.isPinned) {
        pinned.add(matter);
        continue;
      }

      final categoryId = matter.categoryId;
      if (categoryId == null || !categoryById.containsKey(categoryId)) {
        uncategorized.add(matter);
        continue;
      }
      unpinnedByCategoryId
          .putIfAbsent(categoryId, () => <Matter>[])
          .add(matter);
    }

    int byUpdatedDesc(Matter a, Matter b) {
      return b.updatedAt.compareTo(a.updatedAt);
    }

    pinned.sort(byUpdatedDesc);
    uncategorized.sort(byUpdatedDesc);
    final categorySections = categories
        .map((category) {
          final mattersInCategory =
              unpinnedByCategoryId[category.id] ?? <Matter>[];
          mattersInCategory.sort(byUpdatedDesc);
          return MatterCategorySection(
            category: category,
            matters: mattersInCategory,
          );
        })
        .toList(growable: false);

    return MatterSections(
      pinned: pinned,
      categorySections: categorySections,
      uncategorized: uncategorized,
    );
  }
}
