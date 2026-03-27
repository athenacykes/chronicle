enum SyncProgressPhase {
  preparing,
  acquiringLock,
  scanning,
  planning,
  uploading,
  downloading,
  deletingLocal,
  deletingRemote,
  resolvingConflicts,
  finalizing,
}

class SyncProgress {
  const SyncProgress({
    required this.phase,
    this.completed = 0,
    this.total,
    this.uploadedCount = 0,
    this.downloadedCount = 0,
    this.deletedCount = 0,
    this.conflictCount = 0,
    this.errorCount = 0,
  });

  final SyncProgressPhase phase;
  final int completed;
  final int? total;
  final int uploadedCount;
  final int downloadedCount;
  final int deletedCount;
  final int conflictCount;
  final int errorCount;

  SyncProgress copyWith({
    SyncProgressPhase? phase,
    int? completed,
    int? total,
    bool clearTotal = false,
    int? uploadedCount,
    int? downloadedCount,
    int? deletedCount,
    int? conflictCount,
    int? errorCount,
  }) {
    return SyncProgress(
      phase: phase ?? this.phase,
      completed: completed ?? this.completed,
      total: clearTotal ? null : total ?? this.total,
      uploadedCount: uploadedCount ?? this.uploadedCount,
      downloadedCount: downloadedCount ?? this.downloadedCount,
      deletedCount: deletedCount ?? this.deletedCount,
      conflictCount: conflictCount ?? this.conflictCount,
      errorCount: errorCount ?? this.errorCount,
    );
  }

  static const idle = SyncProgress(phase: SyncProgressPhase.preparing);
}
