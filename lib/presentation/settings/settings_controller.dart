import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/app_providers.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/sync_config.dart';

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
      SettingsController.new,
    );

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final settingsRepository = ref.read(settingsRepositoryProvider);
    return settingsRepository.loadSettings();
  }

  Future<void> persistSettings(AppSettings settings) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.saveSettings(settings);
    state = AsyncData(settings);
  }

  Future<void> chooseAndSetStorageRoot() async {
    final selected = await FilePicker.platform.getDirectoryPath();
    if (selected == null || selected.isEmpty) {
      return;
    }
    await setStorageRootPath(selected);
  }

  Future<String> suggestedDefaultRootPath() async {
    final appDirs = ref.read(appDirectoriesProvider);
    final home = await appDirs.homeDirectory();
    return p.join(home.path, 'Chronicle');
  }

  Future<void> setStorageRootPath(String path) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setStorageRootPath(path);

    await ref
        .read(storageInitializerProvider)
        .ensureInitialized(Directory(path));

    final updated = await repository.loadSettings();
    state = AsyncData(updated);
  }

  Future<void> saveSyncConfig(SyncConfig config, {String? password}) async {
    final syncRepository = ref.read(syncRepositoryProvider);
    await syncRepository.saveConfig(config, password: password);

    final settings = await ref.read(settingsRepositoryProvider).loadSettings();
    state = AsyncData(settings);
  }

  Future<void> setLocaleTag(String localeTag) async {
    final repository = ref.read(settingsRepositoryProvider);
    final settings = await repository.loadSettings();
    final updated = settings.copyWith(localeTag: localeTag);
    await repository.saveSettings(updated);
    state = AsyncData(updated);
  }

  Future<void> setCollapsedCategoryIds(List<String> categoryIds) async {
    final repository = ref.read(settingsRepositoryProvider);
    final settings = await repository.loadSettings();
    final updated = settings.copyWith(
      collapsedCategoryIds: categoryIds.toSet().toList(growable: false),
    );
    await repository.saveSettings(updated);
    state = AsyncData(updated);
  }

  Future<void> setCategoryCollapsed(String categoryId, bool collapsed) async {
    final repository = ref.read(settingsRepositoryProvider);
    final settings = await repository.loadSettings();
    final collapsedSet = settings.collapsedCategoryIds.toSet();
    if (collapsed) {
      collapsedSet.add(categoryId);
    } else {
      collapsedSet.remove(categoryId);
    }
    final updated = settings.copyWith(
      collapsedCategoryIds: collapsedSet.toList(growable: false),
    );
    await repository.saveSettings(updated);
    state = AsyncData(updated);
  }

  Future<void> refresh() async {
    final settings = await ref.read(settingsRepositoryProvider).loadSettings();
    state = AsyncData(settings);
  }
}
