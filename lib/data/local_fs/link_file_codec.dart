import 'dart:convert';

import '../../domain/entities/note_link.dart';

class LinkFileCodec {
  const LinkFileCodec();

  String encode(NoteLink link) {
    return const JsonEncoder.withIndent('  ').convert(link.toJson());
  }

  NoteLink decode(String raw) {
    final jsonMap = json.decode(raw) as Map<String, dynamic>;
    return NoteLink.fromJson(jsonMap);
  }
}
