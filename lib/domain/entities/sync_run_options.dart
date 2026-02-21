enum SyncRunMode {
  normal,
  forceApplyDeletionsOnce,
  recoverLocalWins,
  recoverRemoteWins,
}

class SyncRunOptions {
  const SyncRunOptions({this.mode = SyncRunMode.normal});

  final SyncRunMode mode;
}
