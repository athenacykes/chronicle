import 'dart:convert';

import '../../domain/entities/matter.dart';

class MatterFileCodec {
  const MatterFileCodec();

  String encode(Matter matter) {
    return const JsonEncoder.withIndent('  ').convert(matter.toJson());
  }

  Matter decode(String raw) {
    final jsonMap = json.decode(raw) as Map<String, dynamic>;
    return Matter.fromJson(jsonMap);
  }
}
