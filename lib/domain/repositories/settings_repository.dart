import '../entities/app_settings.dart';

abstract class SettingsRepository {
  Future<AppSettings> loadSettings();
  Future<void> saveSettings(AppSettings settings);
  Future<void> setStorageRootPath(String path);
  Future<void> setLastSyncAt(DateTime value);
  Future<void> saveSyncPassword(String password);
  Future<String?> readSyncPassword();
}
