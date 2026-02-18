class Phase {
  const Phase({
    required this.id,
    required this.matterId,
    required this.name,
    required this.order,
  });

  final String id;
  final String matterId;
  final String name;
  final int order;

  Phase copyWith({String? id, String? matterId, String? name, int? order}) {
    return Phase(
      id: id ?? this.id,
      matterId: matterId ?? this.matterId,
      name: name ?? this.name,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'matterId': matterId, 'name': name, 'order': order};
  }

  static Phase fromJson(Map<String, dynamic> json) {
    return Phase(
      id: json['id'] as String,
      matterId: json['matterId'] as String,
      name: json['name'] as String,
      order: (json['order'] as num).toInt(),
    );
  }
}
