enum SyncBlockerType {
  versionMismatchRemoteOlder,
  versionMismatchClientTooOld,
  failSafeDeletionBlocked,
}

class SyncBlocker {
  const SyncBlocker({
    required this.type,
    this.candidateDeletionCount,
    this.trackedCount,
    this.localFormatVersion,
    this.remoteFormatVersion,
    this.message,
  });

  final SyncBlockerType type;
  final int? candidateDeletionCount;
  final int? trackedCount;
  final int? localFormatVersion;
  final int? remoteFormatVersion;
  final String? message;
}
