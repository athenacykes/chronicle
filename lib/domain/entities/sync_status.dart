import 'sync_blocker.dart';

class SyncStatus {
  const SyncStatus({
    required this.isRunning,
    required this.lastMessage,
    required this.lastUpdatedAt,
    this.blocker,
    this.forceDeletionArmed = false,
  });

  final bool isRunning;
  final String lastMessage;
  final DateTime? lastUpdatedAt;
  final SyncBlocker? blocker;
  final bool forceDeletionArmed;

  SyncStatus copyWith({
    bool? isRunning,
    String? lastMessage,
    DateTime? lastUpdatedAt,
    SyncBlocker? blocker,
    bool clearBlocker = false,
    bool? forceDeletionArmed,
  }) {
    return SyncStatus(
      isRunning: isRunning ?? this.isRunning,
      lastMessage: lastMessage ?? this.lastMessage,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      blocker: clearBlocker ? null : blocker ?? this.blocker,
      forceDeletionArmed: forceDeletionArmed ?? this.forceDeletionArmed,
    );
  }

  static const idle = SyncStatus(
    isRunning: false,
    lastMessage: 'Idle',
    lastUpdatedAt: null,
    blocker: null,
    forceDeletionArmed: false,
  );
}
