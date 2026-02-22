import '../../core/time_utils.dart';

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String color;
  final String icon;
  final DateTime createdAt;
  final DateTime updatedAt;

  Category copyWith({
    String? id,
    String? name,
    String? color,
    String? icon,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'color': color,
      'icon': icon,
      'createdAt': formatIsoUtc(createdAt),
      'updatedAt': formatIsoUtc(updatedAt),
    };
  }

  static Category fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      color: (json['color'] as String?) ?? '#4C956C',
      icon: (json['icon'] as String?) ?? 'folder',
      createdAt: parseIsoUtc(json['createdAt'] as String),
      updatedAt: parseIsoUtc(json['updatedAt'] as String),
    );
  }
}
