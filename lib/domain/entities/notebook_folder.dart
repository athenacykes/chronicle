import '../../core/time_utils.dart';

class NotebookFolder {
  const NotebookFolder({
    required this.id,
    required this.name,
    required this.parentId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? parentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  NotebookFolder copyWith({
    String? id,
    String? name,
    String? parentId,
    bool clearParentId = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NotebookFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: clearParentId ? null : parentId ?? this.parentId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'parentId': parentId,
      'createdAt': formatIsoUtc(createdAt),
      'updatedAt': formatIsoUtc(updatedAt),
    };
  }

  factory NotebookFolder.fromJson(Map<String, dynamic> json) {
    return NotebookFolder(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      parentId: json['parentId'] as String?,
      createdAt: parseIsoUtc(json['createdAt'] as String),
      updatedAt: parseIsoUtc(json['updatedAt'] as String),
    );
  }
}
