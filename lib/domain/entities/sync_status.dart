import 'sync_blocker.dart';
import 'sync_progress.dart';

class SyncStatus {
  const SyncStatus({
    required this.isRunning,
    required this.lastMessage,
    required this.lastUpdatedAt,
    this.blocker,
    this.forceDeletionArmed = false,
    this.progress,
  });

  final bool isRunning;
  final String lastMessage;
  final DateTime? lastUpdatedAt;
  final SyncBlocker? blocker;
  final bool forceDeletionArmed;
  final SyncProgress? progress;

  SyncStatus copyWith({
    bool? isRunning,
    String? lastMessage,
    DateTime? lastUpdatedAt,
    SyncBlocker? blocker,
    bool clearBlocker = false,
    bool? forceDeletionArmed,
    SyncProgress? progress,
    bool clearProgress = false,
  }) {
    return SyncStatus(
      isRunning: isRunning ?? this.isRunning,
      lastMessage: lastMessage ?? this.lastMessage,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      blocker: clearBlocker ? null : blocker ?? this.blocker,
      forceDeletionArmed: forceDeletionArmed ?? this.forceDeletionArmed,
      progress: clearProgress ? null : progress ?? this.progress,
    );
  }

  static const idle = SyncStatus(
    isRunning: false,
    lastMessage: 'Idle',
    lastUpdatedAt: null,
    blocker: null,
    forceDeletionArmed: false,
    progress: null,
  );
}
