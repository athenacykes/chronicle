import '../../core/time_utils.dart';
import 'enums.dart';
import 'phase.dart';

class Matter {
  const Matter({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.color,
    required this.icon,
    required this.isPinned,
    required this.createdAt,
    required this.updatedAt,
    required this.startedAt,
    required this.endedAt,
    required this.phases,
    required this.currentPhaseId,
  });

  final String id;
  final String title;
  final String description;
  final MatterStatus status;
  final String color;
  final String icon;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<Phase> phases;
  final String? currentPhaseId;

  Matter copyWith({
    String? id,
    String? title,
    String? description,
    MatterStatus? status,
    String? color,
    String? icon,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? startedAt,
    bool clearStartedAt = false,
    DateTime? endedAt,
    bool clearEndedAt = false,
    List<Phase>? phases,
    String? currentPhaseId,
    bool clearCurrentPhaseId = false,
  }) {
    return Matter(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
      endedAt: clearEndedAt ? null : endedAt ?? this.endedAt,
      phases: phases ?? this.phases,
      currentPhaseId: clearCurrentPhaseId
          ? null
          : currentPhaseId ?? this.currentPhaseId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status.name,
      'color': color,
      'icon': icon,
      'createdAt': formatIsoUtc(createdAt),
      'updatedAt': formatIsoUtc(updatedAt),
      'startedAt': startedAt == null ? null : formatIsoUtc(startedAt!),
      'endedAt': endedAt == null ? null : formatIsoUtc(endedAt!),
      'isPinned': isPinned,
      'phases': phases.map((value) => value.toJson()).toList(),
      'currentPhaseId': currentPhaseId,
    };
  }

  static Matter fromJson(Map<String, dynamic> json) {
    final phases = (json['phases'] as List<dynamic>? ?? <dynamic>[])
        .map((value) => Phase.fromJson(value as Map<String, dynamic>))
        .toList();
    return Matter(
      id: json['id'] as String,
      title: json['title'] as String,
      description: (json['description'] as String?) ?? '',
      status: MatterStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => MatterStatus.active,
      ),
      color: (json['color'] as String?) ?? '#4C956C',
      icon: (json['icon'] as String?) ?? 'description',
      isPinned: (json['isPinned'] as bool?) ?? false,
      createdAt: parseIsoUtc(json['createdAt'] as String),
      updatedAt: parseIsoUtc(json['updatedAt'] as String),
      startedAt: json['startedAt'] == null
          ? null
          : parseIsoUtc(json['startedAt'] as String),
      endedAt: json['endedAt'] == null
          ? null
          : parseIsoUtc(json['endedAt'] as String),
      phases: phases,
      currentPhaseId:
          (json['currentPhaseId'] as String?) ??
          (phases.isEmpty ? null : phases.first.id),
    );
  }
}
