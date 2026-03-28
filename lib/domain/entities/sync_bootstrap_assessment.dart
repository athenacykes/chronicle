enum SyncBootstrapScenario { neither, localOnly, remoteOnly, both }

class SyncBootstrapAssessment {
  const SyncBootstrapAssessment({
    required this.scenario,
    required this.localItemCount,
    required this.remoteItemCount,
  });

  final SyncBootstrapScenario scenario;
  final int localItemCount;
  final int remoteItemCount;

  bool get hasLocalContent => localItemCount > 0;
  bool get hasRemoteContent => remoteItemCount > 0;

  factory SyncBootstrapAssessment.fromCounts({
    required int localItemCount,
    required int remoteItemCount,
  }) {
    if (localItemCount > 0 && remoteItemCount > 0) {
      return SyncBootstrapAssessment(
        scenario: SyncBootstrapScenario.both,
        localItemCount: localItemCount,
        remoteItemCount: remoteItemCount,
      );
    }
    if (localItemCount > 0) {
      return SyncBootstrapAssessment(
        scenario: SyncBootstrapScenario.localOnly,
        localItemCount: localItemCount,
        remoteItemCount: remoteItemCount,
      );
    }
    if (remoteItemCount > 0) {
      return SyncBootstrapAssessment(
        scenario: SyncBootstrapScenario.remoteOnly,
        localItemCount: localItemCount,
        remoteItemCount: remoteItemCount,
      );
    }
    return SyncBootstrapAssessment(
      scenario: SyncBootstrapScenario.neither,
      localItemCount: localItemCount,
      remoteItemCount: remoteItemCount,
    );
  }
}
