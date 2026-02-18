import 'package:chronicle/app/app.dart';
import 'package:chronicle/app/app_providers.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:chronicle/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';

void main() {
  testWidgets('shows storage setup screen when root is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp(useMacOSNativeUI: false));

    await tester.pumpAndSettle();

    expect(find.text('Set up Chronicle storage'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('shows Chinese storage setup when locale is zh', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(useMacOSNativeUI: false, localeTag: 'zh'),
    );

    await tester.pumpAndSettle();

    expect(find.text('设置 Chronicle 存储'), findsOneWidget);
  });

  testWidgets('falls back to English for unsupported locale tags', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(useMacOSNativeUI: false, localeTag: 'xx'),
    );

    await tester.pumpAndSettle();

    expect(find.text('Set up Chronicle storage'), findsOneWidget);
  });

  testWidgets('renders macOS app shell when macOS native UI is forced', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp(useMacOSNativeUI: true));

    await tester.pumpAndSettle();

    expect(find.byType(MacosApp), findsOneWidget);
    expect(find.byType(MacosWindow), findsOneWidget);
    expect(find.byType(MacosTextField), findsWidgets);
  });

  testWidgets('renders Material app shell when macOS native UI is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp(useMacOSNativeUI: false));

    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
  });

  test('falls back to English string when zh key is missing', () {
    final zh = appLocalizationsForTag('zh');
    expect(zh.fallbackProbeMessage, 'English fallback probe');
  });
}

Widget _buildTestApp({
  required bool useMacOSNativeUI,
  String localeTag = 'en',
}) {
  final fakeRepo = _FakeSettingsRepository(
    AppSettings(
      storageRootPath: null,
      clientId: 'test-client',
      syncConfig: SyncConfig.initial(),
      lastSyncAt: null,
      localeTag: localeTag,
    ),
  );

  return ProviderScope(
    overrides: <Override>[
      settingsRepositoryProvider.overrideWithValue(fakeRepo),
    ],
    child: ChronicleApp(forceMacOSNativeUI: useMacOSNativeUI),
  );
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this._settings);

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
