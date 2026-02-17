import 'dart:async';

import '../../repositories/sync_repository.dart';

class StartAutoSync {
  const StartAutoSync(this._syncRepository);

  final SyncRepository _syncRepository;

  Timer start({
    required Duration interval,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    return Timer.periodic(interval, (timer) async {
      try {
        await _syncRepository.syncNow();
      } catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
    });
  }
}
