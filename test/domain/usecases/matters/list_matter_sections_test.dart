import 'package:chronicle/domain/entities/category.dart';
import 'package:chronicle/domain/entities/enums.dart';
import 'package:chronicle/domain/entities/matter.dart';
import 'package:chronicle/domain/entities/phase.dart';
import 'package:chronicle/domain/repositories/category_repository.dart';
import 'package:chronicle/domain/repositories/matter_repository.dart';
import 'package:chronicle/domain/usecases/matters/list_matter_sections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groups into pinned, categories, and uncategorized', () async {
    final now = DateTime.utc(2026, 2, 22, 12);
    final categories = <Category>[
      Category(
        id: 'category-b',
        name: 'Beta',
        color: '#4C956C',
        icon: 'folder',
        createdAt: now,
        updatedAt: now,
      ),
      Category(
        id: 'category-a',
        name: 'Alpha',
        color: '#4C956C',
        icon: 'folder',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final matters = <Matter>[
      _matter(
        id: 'pinned-in-a',
        categoryId: 'category-a',
        isPinned: true,
        updatedAt: now,
      ),
      _matter(
        id: 'in-a-newer',
        categoryId: 'category-a',
        updatedAt: now.subtract(const Duration(minutes: 1)),
      ),
      _matter(
        id: 'in-a-older',
        categoryId: 'category-a',
        updatedAt: now.subtract(const Duration(minutes: 5)),
      ),
      _matter(
        id: 'in-b',
        categoryId: 'category-b',
        updatedAt: now.subtract(const Duration(minutes: 2)),
      ),
      _matter(
        id: 'uncategorized',
        categoryId: null,
        updatedAt: now.subtract(const Duration(minutes: 3)),
      ),
      _matter(
        id: 'unknown-category',
        categoryId: 'category-x',
        updatedAt: now.subtract(const Duration(minutes: 4)),
      ),
    ];

    final sections = await ListMatterSections(
      _MemoryMatterRepository(matters),
      _MemoryCategoryRepository(categories),
    ).call();

    expect(sections.pinned.map((matter) => matter.id), <String>['pinned-in-a']);
    expect(
      sections.categorySections.map((section) => section.category.id),
      <String>['category-a', 'category-b'],
    );
    expect(
      sections.categorySections.first.matters.map((matter) => matter.id),
      <String>['in-a-newer', 'in-a-older'],
    );
    expect(
      sections.categorySections.last.matters.map((matter) => matter.id),
      <String>['in-b'],
    );
    expect(sections.uncategorized.map((matter) => matter.id), <String>[
      'uncategorized',
      'unknown-category',
    ]);
  });
}

Matter _matter({
  required String id,
  required String? categoryId,
  required DateTime updatedAt,
  bool isPinned = false,
}) {
  final createdAt = updatedAt.subtract(const Duration(minutes: 10));
  return Matter(
    id: id,
    categoryId: categoryId,
    title: id,
    description: '',
    status: MatterStatus.active,
    color: '#4C956C',
    icon: 'description',
    isPinned: isPinned,
    createdAt: createdAt,
    updatedAt: updatedAt,
    startedAt: createdAt,
    endedAt: null,
    phases: <Phase>[
      Phase(id: '$id-phase', matterId: id, name: 'Start', order: 0),
    ],
    currentPhaseId: '$id-phase',
  );
}

class _MemoryMatterRepository implements MatterRepository {
  _MemoryMatterRepository(this._matters);

  final List<Matter> _matters;

  @override
  Future<List<Matter>> listMatters() async => List<Matter>.of(_matters);

  @override
  Future<Matter> createMatter({
    required String title,
    String description = '',
    String? categoryId,
    String color = '#4C956C',
    String icon = 'description',
    bool isPinned = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteMatter(String matterId) {
    throw UnimplementedError();
  }

  @override
  Future<Matter?> getMatterById(String matterId) {
    throw UnimplementedError();
  }

  @override
  Future<void> setMatterCategory(String matterId, String? categoryId) {
    throw UnimplementedError();
  }

  @override
  Future<void> setMatterPinned(String matterId, bool isPinned) {
    throw UnimplementedError();
  }

  @override
  Future<void> setMatterStatus(String matterId, MatterStatus status) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateMatter(Matter matter) {
    throw UnimplementedError();
  }
}

class _MemoryCategoryRepository implements CategoryRepository {
  _MemoryCategoryRepository(this._categories);

  final List<Category> _categories;

  @override
  Future<List<Category>> listCategories() async =>
      List<Category>.of(_categories);

  @override
  Future<Category> createCategory({
    required String name,
    String color = '#4C956C',
    String icon = 'folder',
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteCategory(String categoryId) {
    throw UnimplementedError();
  }

  @override
  Future<Category?> getCategoryById(String categoryId) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateCategory(Category category) {
    throw UnimplementedError();
  }
}
