import 'package:chronicle/app/app_providers.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:chronicle/presentation/settings/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('setLocaleTag persists locale to settings repository', () async {
    final repository = _InMemorySettingsRepository(
      AppSettings(
        storageRootPath: null,
        clientId: 'settings-test',
        syncConfig: SyncConfig.initial(),
        lastSyncAt: null,
      ),
    );

    final container = ProviderContainer(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(settingsControllerProvider.future);
    await container
        .read(settingsControllerProvider.notifier)
        .setLocaleTag('zh');

    final state = container.read(settingsControllerProvider).valueOrNull;
    expect(state?.localeTag, 'zh');
    expect((await repository.loadSettings()).localeTag, 'zh');
  });
}

class _InMemorySettingsRepository implements SettingsRepository {
  _InMemorySettingsRepository(this._settings);

  AppSettings _settings;
  String? _password;

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<String?> readSyncPassword() async => _password;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> saveSyncPassword(String password) async {
    _password = password;
  }

  @override
  Future<void> setLastSyncAt(DateTime value) async {
    _settings = _settings.copyWith(lastSyncAt: value);
  }

  @override
  Future<void> setStorageRootPath(String path) async {
    _settings = _settings.copyWith(storageRootPath: path);
  }
}
