import '../../entities/sync_result.dart';
import '../../entities/sync_run_options.dart';
import '../../repositories/sync_repository.dart';

class RunSyncNow {
  const RunSyncNow(this._syncRepository);

  final SyncRepository _syncRepository;

  Future<SyncResult> call({SyncRunOptions options = const SyncRunOptions()}) {
    return _syncRepository.syncNow(options: options);
  }
}
