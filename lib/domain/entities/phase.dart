import 'enums.dart';

class Phase {
  const Phase({
    required this.id,
    required this.matterId,
    required this.type,
    required this.name,
    required this.order,
  });

  final String id;
  final String matterId;
  final PhaseType type;
  final String name;
  final int order;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'matterId': matterId,
      'type': type.name,
      'name': name,
      'order': order,
    };
  }

  static Phase fromJson(Map<String, dynamic> json) {
    return Phase(
      id: json['id'] as String,
      matterId: json['matterId'] as String,
      type: PhaseType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => PhaseType.process,
      ),
      name: json['name'] as String,
      order: (json['order'] as num).toInt(),
    );
  }
}
