import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/clock.dart';
import '../../core/file_system_utils.dart';
import '../../core/id_generator.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';
import 'chronicle_layout.dart';
import 'chronicle_storage_initializer.dart';
import 'storage_root_locator.dart';

class LocalCategoryRepository implements CategoryRepository {
  LocalCategoryRepository({
    required StorageRootLocator storageRootLocator,
    required ChronicleStorageInitializer storageInitializer,
    required FileSystemUtils fileSystemUtils,
    required Clock clock,
    required IdGenerator idGenerator,
  }) : _storageRootLocator = storageRootLocator,
       _storageInitializer = storageInitializer,
       _fileSystemUtils = fileSystemUtils,
       _clock = clock,
       _idGenerator = idGenerator;

  final StorageRootLocator _storageRootLocator;
  final ChronicleStorageInitializer _storageInitializer;
  final FileSystemUtils _fileSystemUtils;
  final Clock _clock;
  final IdGenerator _idGenerator;

  @override
  Future<List<Category>> listCategories() async {
    final layout = await _layout();
    if (!await layout.categoriesDirectory.exists()) {
      return <Category>[];
    }

    final categories = <Category>[];
    await for (final entity in layout.categoriesDirectory.list()) {
      if (entity is! File || p.extension(entity.path) != '.json') {
        continue;
      }
      try {
        final raw = await entity.readAsString();
        final decoded = json.decode(raw) as Map<String, dynamic>;
        categories.add(Category.fromJson(decoded));
      } catch (_) {
        continue;
      }
    }

    categories.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return categories;
  }

  @override
  Future<Category?> getCategoryById(String categoryId) async {
    final layout = await _layout();
    final file = layout.categoryJsonFile(categoryId);
    if (!await file.exists()) {
      return null;
    }
    final raw = await file.readAsString();
    final decoded = json.decode(raw) as Map<String, dynamic>;
    return Category.fromJson(decoded);
  }

  @override
  Future<Category> createCategory({
    required String name,
    String color = '#4C956C',
    String icon = 'folder',
  }) async {
    final now = _clock.nowUtc();
    final category = Category(
      id: _idGenerator.newId(),
      name: name.trim(),
      color: color,
      icon: icon,
      createdAt: now,
      updatedAt: now,
    );
    await _writeCategory(category);
    return category;
  }

  @override
  Future<void> updateCategory(Category category) async {
    await _writeCategory(category.copyWith(updatedAt: _clock.nowUtc()));
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    final layout = await _layout();
    await _fileSystemUtils.deleteIfExists(layout.categoryJsonFile(categoryId));
  }

  Future<void> _writeCategory(Category category) async {
    final layout = await _layout();
    final file = layout.categoryJsonFile(category.id);
    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert(category.toJson());
    await _fileSystemUtils.atomicWriteString(file, encoded);
  }

  Future<ChronicleLayout> _layout() async {
    final root = await _storageRootLocator.requireRootDirectory();
    await _storageInitializer.ensureInitialized(root);
    return ChronicleLayout(root);
  }
}
