import 'package:chronicle/app/app.dart';
import 'package:chronicle/app/app_providers.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const appkitUiElementColors = MethodChannel('appkit_ui_element_colors');

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appkitUiElementColors, (call) async {
          switch (call.method) {
            case 'getColorComponents':
              return <String, double>{
                'redComponent': 0.0,
                'greenComponent': 0.47843137254901963,
                'blueComponent': 1.0,
                'hueComponent': 0.5866013071895425,
              };
            case 'getColor':
              return 0xFF007AFF;
          }
          return null;
        });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appkitUiElementColors, null);
  });

  testWidgets('material setup shell golden', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildTestApp(useMacOSNativeUI: false));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/material_setup_shell.png'),
    );
  });

  testWidgets('macos setup shell golden', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildTestApp(useMacOSNativeUI: true));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ChronicleApp),
      matchesGoldenFile('goldens/macos_setup_shell.png'),
    );
  });
}

Widget _buildTestApp({required bool useMacOSNativeUI}) {
  final fakeRepo = _FakeSettingsRepository(
    AppSettings(
      storageRootPath: null,
      clientId: 'golden-client',
      syncConfig: SyncConfig.initial(),
      lastSyncAt: null,
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
