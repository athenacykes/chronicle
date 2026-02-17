import '../../core/time_utils.dart';

class NoteLink {
  const NoteLink({
    required this.id,
    required this.sourceNoteId,
    required this.targetNoteId,
    required this.context,
    required this.createdAt,
  });

  final String id;
  final String sourceNoteId;
  final String targetNoteId;
  final String context;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceNoteId': sourceNoteId,
      'targetNoteId': targetNoteId,
      'context': context,
      'createdAt': formatIsoUtc(createdAt),
    };
  }

  static NoteLink fromJson(Map<String, dynamic> json) {
    return NoteLink(
      id: json['id'] as String,
      sourceNoteId: json['sourceNoteId'] as String,
      targetNoteId: json['targetNoteId'] as String,
      context: (json['context'] as String?) ?? '',
      createdAt: parseIsoUtc(json['createdAt'] as String),
    );
  }
}
