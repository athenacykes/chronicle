class SyncResult {
  const SyncResult({
    required this.uploadedCount,
    required this.downloadedCount,
    required this.conflictCount,
    required this.deletedCount,
    required this.startedAt,
    required this.endedAt,
    required this.errors,
  });

  final int uploadedCount;
  final int downloadedCount;
  final int conflictCount;
  final int deletedCount;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<String> errors;

  Duration get duration => endedAt.difference(startedAt);

  static SyncResult empty(DateTime now) {
    return SyncResult(
      uploadedCount: 0,
      downloadedCount: 0,
      conflictCount: 0,
      deletedCount: 0,
      startedAt: now,
      endedAt: now,
      errors: const <String>[],
    );
  }
}
