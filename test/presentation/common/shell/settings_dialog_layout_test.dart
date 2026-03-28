import 'package:chronicle/app/app_providers.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/enums.dart';
import 'package:chronicle/domain/entities/note_search_hit.dart';
import 'package:chronicle/domain/entities/search_query.dart';
import 'package:chronicle/domain/entities/sync_bootstrap_assessment.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/entities/sync_proxy_config.dart';
import 'package:chronicle/domain/entities/sync_result.dart';
import 'package:chronicle/domain/entities/sync_run_options.dart';
import 'package:chronicle/domain/repositories/search_repository.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:chronicle/domain/repositories/sync_repository.dart';
import 'package:chronicle/l10n/generated/app_localizations.dart';
import 'package:chronicle/presentation/common/shell/chronicle_home_coordinator.dart';
import 'package:chronicle/presentation/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';

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
    expect(
      find.byKey(const Key('settings_export_backup_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('settings_import_backup_button')),
      findsOneWidget,
    );
    expect(find.text('Export backup'), findsOneWidget);
    expect(find.text('Import backup'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings_reset_all_button')), findsOneWidget);
    expect(find.text('Reset all'), findsOneWidget);

    final navSize = tester.getSize(navPane);
    final contentSize = tester.getSize(contentPane);
    final navTopLeft = tester.getTopLeft(navPane);
    final contentTopLeft = tester.getTopLeft(contentPane);
    final contentRight = tester.getTopRight(contentPane).dx;
    final dialogContentWidth = contentRight - navTopLeft.dx;

    expect(dialogContentWidth, greaterThanOrEqualTo(520));
    expect(dialogContentWidth, lessThanOrEqualTo(600));
    expect(navSize.width, greaterThanOrEqualTo(130));
    expect(navSize.width, lessThanOrEqualTo(170));
    expect(contentSize.width, greaterThan(navSize.width));
    expect(navTopLeft.dx, lessThan(contentTopLeft.dx));
    expect((navTopLeft.dy - contentTopLeft.dy).abs(), lessThan(12));

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
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

  testWidgets(
    'settings dialog requires double confirmation for replace remote with local',
    (tester) async {
      final syncRepository = _TrackingSyncRepository(
        assessment: SyncBootstrapAssessment.fromCounts(
          localItemCount: 2,
          remoteItemCount: 3,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            _FakeSettingsRepository(
              AppSettings(
                storageRootPath: '/tmp/chronicle-test',
                clientId: 'settings-layout-client',
                syncConfig: SyncConfig(
                  type: SyncTargetType.webdav,
                  url: 'https://old.example.com/dav/Chronicle',
                  username: 'chronicle-user',
                  intervalMinutes: 5,
                  failSafe: true,
                  proxy: SyncProxyConfig.initial(),
                ),
                lastSyncAt: null,
              ),
            ),
          ),
          syncRepositoryProvider.overrideWithValue(syncRepository),
          searchRepositoryProvider.overrideWithValue(_NoopSearchRepository()),
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

      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'WebDAV URL',
        ),
        'https://new.example.com/dav/Chronicle',
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Choose Source Of Truth'), findsOneWidget);
      expect(
        find.textContaining('Local items: 2. Remote items: 3.'),
        findsOneWidget,
      );
      expect(syncRepository.lastOptions, isNull);

      await tester.tap(find.text('Replace Remote With Local'));
      await tester.pumpAndSettle();

      expect(find.text('Local Wins Recovery'), findsOneWidget);
      await tester.tap(find.text('Continue').last);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Clear Remote And Replace It?'), findsOneWidget);
      expect(syncRepository.lastSavedConfig, isNull);
      expect(syncRepository.lastOptions, isNull);

      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(syncRepository.lastSavedConfig, isNull);
      expect(syncRepository.lastOptions, isNull);
    },
  );

  testWidgets(
    'native settings dialog shows explicit labels and ignores backdrop taps',
    (tester) async {
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
          child: MacosApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Center(
                child: PushButton(
                  controlSize: ControlSize.large,
                  onPressed: () {
                    showChronicleSettingsDialog(
                      context: context,
                      useMacOSNativeUI: true,
                    );
                  },
                  child: const Text('Open settings'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();

      final storageLabel = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Storage root path' &&
            widget.style?.fontWeight == FontWeight.w600,
      );
      expect(storageLabel, findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(storageLabel, findsOneWidget);
    },
  );
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

class _TrackingSyncRepository implements SyncRepository {
  _TrackingSyncRepository({required this.assessment});

  final SyncBootstrapAssessment assessment;
  SyncConfig? lastSavedConfig;
  SyncRunOptions? lastOptions;

  @override
  Future<SyncConfig> getConfig() async => SyncConfig.initial();

  @override
  Future<String?> getPassword() async => null;

  @override
  Future<SyncBootstrapAssessment> assessBootstrap({
    required SyncConfig config,
    required String storageRootPath,
    String? password,
  }) async {
    return assessment;
  }

  @override
  Future<void> saveConfig(SyncConfig config, {String? password}) async {
    lastSavedConfig = config;
  }

  @override
  Future<SyncResult> syncNow({
    SyncRunOptions options = const SyncRunOptions(),
    SyncProgressCallback? onProgress,
  }) async {
    lastOptions = options;
    return SyncResult.empty(DateTime.utc(2026, 3, 28, 12));
  }
}

class _NoopSearchRepository implements SearchRepository {
  @override
  Future<List<String>> listTags() async => const <String>[];

  @override
  Future<void> rebuildIndex() async {}

  @override
  Future<List<NoteSearchHit>> search(SearchQuery query) async {
    return const <NoteSearchHit>[];
  }
}
