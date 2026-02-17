import 'dart:io';

import '../../core/app_exception.dart';
import '../../domain/repositories/settings_repository.dart';

class StorageRootLocator {
  const StorageRootLocator(this._settingsRepository);

  final SettingsRepository _settingsRepository;

  Future<Directory> requireRootDirectory() async {
    final settings = await _settingsRepository.loadSettings();
    final path = settings.storageRootPath;
    if (path == null || path.isEmpty) {
      throw AppException('Storage root is not configured');
    }
    return Directory(path);
  }
}
