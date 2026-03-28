import 'package:chronicle/app/app_providers.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/enums.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/entities/sync_proxy_config.dart';
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
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(settingsControllerProvider.future);
    await container
        .read(settingsControllerProvider.notifier)
        .setLocaleTag('zh');

    final state = container.read(settingsControllerProvider).asData?.value;
    expect(state?.localeTag, 'zh');
    expect((await repository.loadSettings()).localeTag, 'zh');
  });

  test('setSidebarSectionCollapsed persists collapsed section ids', () async {
    final repository = _InMemorySettingsRepository(
      AppSettings(
        storageRootPath: null,
        clientId: 'settings-test',
        syncConfig: SyncConfig.initial(),
        lastSyncAt: null,
      ),
    );

    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(settingsControllerProvider.future);
    await container
        .read(settingsControllerProvider.notifier)
        .setSidebarSectionCollapsed('views', true);
    await container
        .read(settingsControllerProvider.notifier)
        .setSidebarSectionCollapsed('notebooks', true);
    await container
        .read(settingsControllerProvider.notifier)
        .setSidebarSectionCollapsed('views', false);

    final state = container.read(settingsControllerProvider).asData?.value;
    expect(state?.collapsedSidebarSectionIds, <String>['notebooks']);
    expect(
      (await repository.loadSettings()).collapsedSidebarSectionIds,
      <String>['notebooks'],
    );
  });

  test('setNoteListPaneWidth methods persist both pane widths', () async {
    final repository = _InMemorySettingsRepository(
      AppSettings(
        storageRootPath: null,
        clientId: 'settings-test',
        syncConfig: SyncConfig.initial(),
        lastSyncAt: null,
      ),
    );

    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(settingsControllerProvider.future);
    await container
        .read(settingsControllerProvider.notifier)
        .setMatterNoteListPaneWidth(226);
    await container
        .read(settingsControllerProvider.notifier)
        .setNotebookNoteListPaneWidth(294);

    final state = container.read(settingsControllerProvider).asData?.value;
    expect(state?.matterNoteListPaneWidth, 226);
    expect(state?.notebookNoteListPaneWidth, 294);
    expect((await repository.loadSettings()).matterNoteListPaneWidth, 226);
    expect((await repository.loadSettings()).notebookNoteListPaneWidth, 294);
  });

  test('editor view toggles persist in settings repository', () async {
    final repository = _InMemorySettingsRepository(
      AppSettings(
        storageRootPath: null,
        clientId: 'settings-test',
        syncConfig: SyncConfig.initial(),
        lastSyncAt: null,
      ),
    );

    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(settingsControllerProvider.future);
    await container
        .read(settingsControllerProvider.notifier)
        .setEditorLineNumbersEnabled(false);
    await container
        .read(settingsControllerProvider.notifier)
        .setEditorWordWrapEnabled(true);

    final state = container.read(settingsControllerProvider).asData?.value;
    expect(state?.editorLineNumbersEnabled, isFalse);
    expect(state?.editorWordWrapEnabled, isTrue);
    expect((await repository.loadSettings()).editorLineNumbersEnabled, isFalse);
    expect((await repository.loadSettings()).editorWordWrapEnabled, isTrue);
  });

  test(
    'disableSyncAndClearCredentials resets sync state and clears passwords',
    () async {
      final repository = _InMemorySettingsRepository(
        AppSettings(
          storageRootPath: '/tmp/chronicle-test',
          clientId: 'settings-test',
          syncConfig: const SyncConfig(
            type: SyncTargetType.webdav,
            url: 'https://example.com/dav/Chronicle',
            username: 'chronicle-user',
            intervalMinutes: 15,
            failSafe: false,
            proxy: SyncProxyConfig(
              type: SyncProxyType.http,
              host: '127.0.0.1',
              port: 8899,
              username: 'proxy-user',
            ),
          ),
          lastSyncAt: DateTime.utc(2026, 3, 28, 12),
        ),
      );
      repository
        .._password = 'secret'
        .._proxyPassword = 'proxy-secret';

      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await container.read(settingsControllerProvider.future);
      final updated = await container
          .read(settingsControllerProvider.notifier)
          .disableSyncAndClearCredentials();

      expect(updated.syncConfig.type, SyncTargetType.none);
      expect(updated.syncConfig.url, isEmpty);
      expect(updated.syncConfig.username, isEmpty);
      expect(updated.syncConfig.proxy.type, SyncProxyType.none);
      expect(updated.lastSyncAt, isNull);
      expect(repository._password, isNull);
      expect(repository._proxyPassword, isNull);
    },
  );
}

class _InMemorySettingsRepository implements SettingsRepository {
  _InMemorySettingsRepository(this._settings);

  AppSettings _settings;
  String? _password;
  String? _proxyPassword;

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<String?> readSyncPassword() async => _password;

  @override
  Future<String?> readSyncProxyPassword() async => _proxyPassword;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> saveSyncPassword(String password) async {
    _password = password;
  }

  @override
  Future<void> clearSyncPassword() async {
    _password = null;
  }

  @override
  Future<void> saveSyncProxyPassword(String password) async {
    _proxyPassword = password;
  }

  @override
  Future<void> clearSyncProxyPassword() async {
    _proxyPassword = null;
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
