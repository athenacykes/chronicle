class MatterGraphEdge {
  const MatterGraphEdge({
    required this.linkId,
    required this.sourceNoteId,
    required this.targetNoteId,
    required this.context,
    required this.createdAt,
  });

  final String linkId;
  final String sourceNoteId;
  final String targetNoteId;
  final String context;
  final DateTime createdAt;
}
