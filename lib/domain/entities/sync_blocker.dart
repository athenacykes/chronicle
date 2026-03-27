enum SyncBlockerType {
  versionMismatchRemoteOlder,
  versionMismatchClientTooOld,
  failSafeDeletionBlocked,
  activeRemoteLock,
}

class SyncBlocker {
  const SyncBlocker({
    required this.type,
    this.candidateDeletionCount,
    this.trackedCount,
    this.localFormatVersion,
    this.remoteFormatVersion,
    this.lockPath,
    this.lockClientId,
    this.lockClientType,
    this.lockUpdatedAt,
    this.competingLockCount,
    this.message,
  });

  final SyncBlockerType type;
  final int? candidateDeletionCount;
  final int? trackedCount;
  final int? localFormatVersion;
  final int? remoteFormatVersion;
  final String? lockPath;
  final String? lockClientId;
  final String? lockClientType;
  final DateTime? lockUpdatedAt;
  final int? competingLockCount;
  final String? message;
}
