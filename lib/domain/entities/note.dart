import '../../core/time_utils.dart';

class Note {
  const Note({
    required this.id,
    required this.matterId,
    required this.phaseId,
    required this.title,
    required this.content,
    required this.tags,
    required this.isPinned,
    required this.attachments,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? matterId;
  final String? phaseId;
  final String title;
  final String content;
  final List<String> tags;
  final bool isPinned;
  final List<String> attachments;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOrphan => matterId == null || phaseId == null;

  Note copyWith({
    String? id,
    String? matterId,
    bool clearMatterId = false,
    String? phaseId,
    bool clearPhaseId = false,
    String? title,
    String? content,
    List<String>? tags,
    bool? isPinned,
    List<String>? attachments,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      matterId: clearMatterId ? null : matterId ?? this.matterId,
      phaseId: clearPhaseId ? null : phaseId ?? this.phaseId,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      isPinned: isPinned ?? this.isPinned,
      attachments: attachments ?? this.attachments,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toFrontMatterMap() {
    return {
      'id': id,
      'matterId': matterId,
      'phaseId': phaseId,
      'title': title,
      'createdAt': formatIsoUtc(createdAt),
      'updatedAt': formatIsoUtc(updatedAt),
      'tags': tags,
      'isPinned': isPinned,
      'attachments': attachments,
    };
  }

  static Note fromFrontMatterMap(
    Map<String, dynamic> frontMatter,
    String body,
  ) {
    return Note(
      id: frontMatter['id'] as String,
      matterId: frontMatter['matterId'] as String?,
      phaseId: frontMatter['phaseId'] as String?,
      title: (frontMatter['title'] as String?) ?? '',
      content: body,
      createdAt: parseIsoUtc(frontMatter['createdAt'] as String),
      updatedAt: parseIsoUtc(frontMatter['updatedAt'] as String),
      tags: (frontMatter['tags'] as List<dynamic>? ?? <dynamic>[])
          .map((value) => '$value')
          .toList(),
      isPinned: (frontMatter['isPinned'] as bool?) ?? false,
      attachments: (frontMatter['attachments'] as List<dynamic>? ?? <dynamic>[])
          .map((value) => '$value')
          .toList(),
    );
  }
}
