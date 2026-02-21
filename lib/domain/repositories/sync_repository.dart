import '../entities/sync_config.dart';
import '../entities/sync_result.dart';
import '../entities/sync_run_options.dart';

abstract class SyncRepository {
  Future<SyncConfig> getConfig();
  Future<void> saveConfig(SyncConfig config, {String? password});
  Future<String?> getPassword();
  Future<SyncResult> syncNow({SyncRunOptions options = const SyncRunOptions()});
}
