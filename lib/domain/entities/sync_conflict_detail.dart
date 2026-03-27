import 'sync_conflict.dart';

class SyncConflictDetail {
  const SyncConflictDetail({
    required this.conflict,
    required this.localContent,
    required this.mainFileContent,
    required this.localContentHash,
    required this.mainFileContentHash,
    required this.remoteContentHashAtCapture,
    required this.conflictFingerprint,
    required this.originalFileMissing,
    required this.mainFileChangedSinceCapture,
    required this.hasActualDiff,
  });

  final SyncConflict conflict;
  final String? localContent;
  final String? mainFileContent;
  final String? localContentHash;
  final String? mainFileContentHash;
  final String? remoteContentHashAtCapture;
  final String? conflictFingerprint;
  final bool originalFileMissing;
  final bool mainFileChangedSinceCapture;
  final bool hasActualDiff;

  bool get hasTextDiff =>
      localContent != null &&
      localContent!.trim().isNotEmpty &&
      mainFileContent != null &&
      mainFileContent!.trim().isNotEmpty;
}
