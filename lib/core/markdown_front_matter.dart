import 'package:yaml/yaml.dart';

class ParsedFrontMatter {
  const ParsedFrontMatter({required this.frontMatter, required this.body});

  final Map<String, dynamic> frontMatter;
  final String body;
}

ParsedFrontMatter parseMarkdownWithFrontMatter(String input) {
  final normalized = input.replaceAll('\r\n', '\n');
  if (!normalized.startsWith('---\n')) {
    return ParsedFrontMatter(frontMatter: <String, dynamic>{}, body: input);
  }

  final endIndex = normalized.indexOf('\n---\n', 4);
  if (endIndex == -1) {
    return ParsedFrontMatter(frontMatter: <String, dynamic>{}, body: input);
  }

  final yamlSource = normalized.substring(4, endIndex);
  final body = normalized.substring(endIndex + 5);

  final parsed = loadYaml(yamlSource);
  if (parsed is! YamlMap) {
    return ParsedFrontMatter(frontMatter: <String, dynamic>{}, body: body);
  }

  final map = <String, dynamic>{};
  for (final entry in parsed.entries) {
    map['${entry.key}'] = _convertYaml(entry.value);
  }

  return ParsedFrontMatter(frontMatter: map, body: body);
}

String formatMarkdownWithFrontMatter({
  required Map<String, dynamic> frontMatter,
  required String body,
}) {
  final buffer = StringBuffer();
  buffer.writeln('---');
  for (final entry in frontMatter.entries) {
    buffer.writeln('${entry.key}: ${_formatYamlValue(entry.value)}');
  }
  buffer.writeln('---');
  if (body.isNotEmpty) {
    buffer.writeln();
    buffer.write(body);
  }
  return buffer.toString();
}

dynamic _convertYaml(dynamic value) {
  if (value is YamlList) {
    return value.map(_convertYaml).toList();
  }
  if (value is YamlMap) {
    return value.map<dynamic, dynamic>((dynamic key, dynamic innerValue) {
      return MapEntry(key, _convertYaml(innerValue));
    });
  }
  return value;
}

String _formatYamlValue(dynamic value) {
  if (value == null) {
    return 'null';
  }
  if (value is bool || value is num) {
    return '$value';
  }
  if (value is List) {
    return '[${value.map(_formatYamlValue).join(', ')}]';
  }
  final escaped = '$value'.replaceAll('"', '\\"');
  return '"$escaped"';
}
