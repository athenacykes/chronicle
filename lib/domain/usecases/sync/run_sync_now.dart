import '../../entities/sync_result.dart';
import '../../repositories/sync_repository.dart';

class RunSyncNow {
  const RunSyncNow(this._syncRepository);

  final SyncRepository _syncRepository;

  Future<SyncResult> call({bool allowMassDeletion = false}) {
    return _syncRepository.syncNow(allowMassDeletion: allowMassDeletion);
  }
}
