enum SyncRunMode {
  normal,
  forceApplyDeletionsOnce,
  forceBreakRemoteLockOnce,
  recoverLocalWins,
  recoverRemoteWins,
}

class SyncRunOptions {
  const SyncRunOptions({this.mode = SyncRunMode.normal});

  final SyncRunMode mode;
}
