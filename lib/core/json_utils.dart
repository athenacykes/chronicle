import 'dart:convert';

String prettyJson(Map<String, dynamic> value) {
  return const JsonEncoder.withIndent('  ').convert(value);
}
