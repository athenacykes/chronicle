import 'package:chronicle/app/app.dart';
import 'package:chronicle/app/app_providers.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows storage setup screen when root is not configured', (
    tester,
  ) async {
    final fakeRepo = _FakeSettingsRepository(
      AppSettings(
        storageRootPath: null,
        clientId: 'test-client',
        syncConfig: SyncConfig.initial(),
        lastSyncAt: null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: const ChronicleApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Set up Chronicle storage'), findsOneWidget);
  });
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
