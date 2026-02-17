import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<String> sha256ForBytes(List<int> bytes) async {
  return sha256.convert(bytes).toString();
}

Future<String> sha256ForFile(File file) async {
  final bytes = await file.readAsBytes();
  return sha256.convert(bytes).toString();
}

String sha256ForString(String value) {
  return sha256.convert(utf8.encode(value)).toString();
}
