import 'package:chronicle/app/app_providers.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/enums.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/entities/sync_proxy_config.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:chronicle/l10n/generated/app_localizations.dart';
import 'package:chronicle/presentation/common/shell/chronicle_home_coordinator.dart';
import 'package:chronicle/presentation/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings dialog uses narrow left nav and wider right pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            _FakeSettingsRepository(
              AppSettings(
                storageRootPath: '/tmp/chronicle-test',
                clientId: 'settings-layout-client',
                syncConfig: SyncConfig.initial(),
                lastSyncAt: null,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showChronicleSettingsDialog(
                      context: context,
                      useMacOSNativeUI: false,
                    );
                  },
                  child: const Text('Open settings'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    final navPane = find.byKey(const Key('settings_dialog_nav_pane'));
    final contentPane = find.byKey(const Key('settings_dialog_content_pane'));
    expect(navPane, findsOneWidget);
    expect(contentPane, findsOneWidget);

    final navSize = tester.getSize(navPane);
    final contentSize = tester.getSize(contentPane);
    final navTopLeft = tester.getTopLeft(navPane);
    final contentTopLeft = tester.getTopLeft(contentPane);

    expect(navSize.width, greaterThanOrEqualTo(130));
    expect(navSize.width, lessThanOrEqualTo(170));
    expect(contentSize.width, greaterThan(navSize.width));
    expect(navTopLeft.dx, lessThan(contentTopLeft.dx));
    expect((navTopLeft.dy - contentTopLeft.dy).abs(), lessThan(12));
  });

  testWidgets('sync settings show proxy controls for webdav sync', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          _FakeSettingsRepository(
            AppSettings(
              storageRootPath: '/tmp/chronicle-test',
              clientId: 'settings-layout-client',
              syncConfig: const SyncConfig(
                type: SyncTargetType.webdav,
                url: 'https://uno.teracloud.jp/dav/Chronicle',
                username: 'chronicle-user',
                intervalMinutes: 5,
                failSafe: true,
                proxy: SyncProxyConfig(
                  type: SyncProxyType.http,
                  host: '127.0.0.1',
                  port: 8899,
                  username: 'proxy-user',
                ),
              ),
              lastSyncAt: null,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showChronicleSettingsDialog(
                      context: context,
                      useMacOSNativeUI: false,
                    );
                  },
                  child: const Text('Open settings'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();

    expect(find.text('Proxy'), findsOneWidget);
    expect(find.text('Proxy type'), findsOneWidget);
    expect(find.text('Proxy host'), findsOneWidget);
    expect(find.text('Proxy port'), findsOneWidget);
    expect(find.text('Proxy username'), findsOneWidget);
    expect(find.text('Proxy password'), findsOneWidget);
  });
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this._settings);

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
