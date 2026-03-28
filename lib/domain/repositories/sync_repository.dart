import '../entities/sync_bootstrap_assessment.dart';
import '../entities/sync_config.dart';
import '../entities/sync_progress.dart';
import '../entities/sync_result.dart';
import '../entities/sync_run_options.dart';

typedef SyncProgressCallback = void Function(SyncProgress progress);

abstract class SyncRepository {
  Future<SyncConfig> getConfig();
  Future<void> saveConfig(SyncConfig config, {String? password});
  Future<String?> getPassword();
  Future<SyncBootstrapAssessment> assessBootstrap({
    required SyncConfig config,
    required String storageRootPath,
    String? password,
  });
  Future<SyncResult> syncNow({
    SyncRunOptions options = const SyncRunOptions(),
    SyncProgressCallback? onProgress,
  });
}
