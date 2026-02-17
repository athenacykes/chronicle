class SyncStatus {
  const SyncStatus({
    required this.isRunning,
    required this.lastMessage,
    required this.lastUpdatedAt,
  });

  final bool isRunning;
  final String lastMessage;
  final DateTime? lastUpdatedAt;

  SyncStatus copyWith({
    bool? isRunning,
    String? lastMessage,
    DateTime? lastUpdatedAt,
  }) {
    return SyncStatus(
      isRunning: isRunning ?? this.isRunning,
      lastMessage: lastMessage ?? this.lastMessage,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }

  static const idle = SyncStatus(
    isRunning: false,
    lastMessage: 'Idle',
    lastUpdatedAt: null,
  );
}
