class MatterGraphNode {
  const MatterGraphNode({
    required this.noteId,
    required this.title,
    required this.matterId,
    required this.phaseId,
    required this.isPinned,
    required this.isOrphan,
    required this.isInSelectedMatter,
    required this.updatedAt,
  });

  final String noteId;
  final String title;
  final String? matterId;
  final String? phaseId;
  final bool isPinned;
  final bool isOrphan;
  final bool isInSelectedMatter;
  final DateTime updatedAt;
}
