import '../../core/clock.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/sync_config.dart';
import '../../domain/entities/sync_result.dart';
import '../../domain/entities/sync_run_options.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/sync_repository.dart';
import 'webdav_client.dart';
import 'webdav_sync_engine.dart';

class WebDavSyncRepository implements SyncRepository {
  WebDavSyncRepository({
    required SettingsRepository settingsRepository,
    required WebDavSyncEngine syncEngine,
    required Clock clock,
  }) : _settingsRepository = settingsRepository,
       _syncEngine = syncEngine,
       _clock = clock;

  final SettingsRepository _settingsRepository;
  final WebDavSyncEngine _syncEngine;
  final Clock _clock;

  @override
  Future<SyncConfig> getConfig() async {
    final settings = await _settingsRepository.loadSettings();
    return settings.syncConfig;
  }

  @override
  Future<void> saveConfig(SyncConfig config, {String? password}) async {
    final settings = await _settingsRepository.loadSettings();
    await _settingsRepository.saveSettings(
      settings.copyWith(syncConfig: config),
    );

    if (password != null) {
      await _settingsRepository.saveSyncPassword(password);
    }
  }

  @override
  Future<String?> getPassword() {
    return _settingsRepository.readSyncPassword();
  }

  @override
  Future<SyncResult> syncNow({
    SyncRunOptions options = const SyncRunOptions(),
  }) async {
    final settings = await _settingsRepository.loadSettings();
    final config = settings.syncConfig;
    if (config.type != SyncTargetType.webdav || config.url.isEmpty) {
      final now = _clock.nowUtc();
      return SyncResult.empty(now);
    }

    final password = await _settingsRepository.readSyncPassword();
    if (password == null || password.isEmpty) {
      final now = _clock.nowUtc();
      return SyncResult(
        uploadedCount: 0,
        downloadedCount: 0,
        conflictCount: 0,
        deletedCount: 0,
        startedAt: now,
        endedAt: now,
        errors: const <String>['Sync password is missing'],
        blocker: null,
      );
    }

    final client = DioWebDavClient(
      baseUrl: config.url,
      username: config.username,
      password: password,
    );

    final result = await _syncEngine.run(
      client: client,
      clientId: settings.clientId,
      failSafe: config.failSafe,
      options: options,
      syncTargetUrl: config.url.trim(),
      syncUsername: config.username.trim(),
    );

    await _settingsRepository.setLastSyncAt(result.endedAt);
    return result;
  }
}
