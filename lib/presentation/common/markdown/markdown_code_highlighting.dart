import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/highlight.dart' as hl;
import 'package:highlight/languages/all.dart';
import 'package:macos_ui/macos_ui.dart';

const Map<String, String> _languageAliases = <String, String>{
  'c++': 'cpp',
  'cs': 'csharp',
  'golang': 'go',
  'hs': 'haskell',
  'html': 'xml',
  'js': 'javascript',
  'kt': 'kotlin',
  'md': 'markdown',
  'objc': 'objectivec',
  'py': 'python',
  'rb': 'ruby',
  'rs': 'rust',
  'shell': 'bash',
  'sh': 'bash',
  'ts': 'typescript',
  'tsx': 'typescript',
  'yml': 'yaml',
};

const List<String> _autoDetectCandidateLanguages = <String>[
  'bash',
  'c',
  'cpp',
  'csharp',
  'css',
  'dart',
  'dockerfile',
  'go',
  'html',
  'java',
  'javascript',
  'json',
  'kotlin',
  'markdown',
  'objectivec',
  'php',
  'python',
  'ruby',
  'rust',
  'scala',
  'sql',
  'swift',
  'typescript',
  'xml',
  'yaml',
];

@immutable
class HighlightedCodeResult {
  const HighlightedCodeResult({
    required this.result,
    required this.language,
    required this.usedAutoDetection,
  });

  final hl.Result result;
  final String? language;
  final bool usedAutoDetection;
}

CodeThemeData markdownCodeThemeDataForBrightness(Brightness brightness) {
  final styles = brightness == Brightness.dark
      ? monokaiSublimeTheme
      : githubTheme;
  return CodeThemeData(styles: styles);
}

Brightness markdownEffectiveBrightness(BuildContext context) {
  if (MacosTheme.maybeOf(context) != null) {
    return MacosTheme.brightnessOf(context);
  }
  return Theme.of(context).brightness;
}

String markdownMonospaceFontFamily({TargetPlatform? platform}) {
  final effectivePlatform = platform ?? defaultTargetPlatform;
  return effectivePlatform == TargetPlatform.macOS ? 'Menlo' : 'monospace';
}

String? normalizeCodeLanguage(String? language) {
  final value = language?.trim().toLowerCase();
  if (value == null || value.isEmpty) {
    return null;
  }

  final unprefixed = value.startsWith('language-')
      ? value.substring('language-'.length)
      : value;
  final canonical = _languageAliases[unprefixed] ?? unprefixed;
  return canonical.isEmpty ? null : canonical;
}

@visibleForTesting
String? resolveHighlightLanguage(String? languageHint) {
  final normalized = normalizeCodeLanguage(languageHint);
  if (normalized == null) {
    return null;
  }
  if (allLanguages.containsKey(normalized)) {
    return normalized;
  }
  return null;
}

HighlightedCodeResult highlightCodeWithFallback(
  String source, {
  String? languageHint,
}) {
  final resolvedLanguage = resolveHighlightLanguage(languageHint);

  try {
    if (resolvedLanguage != null) {
      return HighlightedCodeResult(
        result: hl.highlight.parse(source, language: resolvedLanguage),
        language: resolvedLanguage,
        usedAutoDetection: false,
      );
    }
    return _safeAutoDetectHighlight(source);
  } catch (_) {
    return HighlightedCodeResult(
      result: hl.Result(relevance: 0, nodes: <hl.Node>[hl.Node(value: source)]),
      language: resolvedLanguage,
      usedAutoDetection: false,
    );
  }
}

HighlightedCodeResult _safeAutoDetectHighlight(String source) {
  hl.Result? bestResult;
  String? bestLanguage;

  for (final language in _autoDetectCandidateLanguages) {
    if (!allLanguages.containsKey(language)) {
      continue;
    }
    try {
      final parsed = hl.highlight.parse(source, language: language);
      if (bestResult == null ||
          (parsed.relevance ?? 0) > (bestResult.relevance ?? 0)) {
        bestResult = parsed;
        bestLanguage = language;
      }
    } catch (_) {
      continue;
    }
  }

  if (bestResult == null) {
    return HighlightedCodeResult(
      result: hl.Result(relevance: 0, nodes: <hl.Node>[hl.Node(value: source)]),
      language: null,
      usedAutoDetection: true,
    );
  }

  return HighlightedCodeResult(
    result: bestResult,
    language: bestLanguage,
    usedAutoDetection: true,
  );
}

TextSpan buildHighlightedCodeTextSpan({
  required String source,
  required Map<String, TextStyle> styles,
  TextStyle? baseStyle,
  String? languageHint,
}) {
  final highlighted = highlightCodeWithFallback(
    source,
    languageHint: languageHint,
  );
  final children = _buildNodeSpans(highlighted.result.nodes, styles, baseStyle);

  return TextSpan(style: baseStyle, children: children);
}

List<TextSpan> _buildNodeSpans(
  List<hl.Node>? nodes,
  Map<String, TextStyle> styles,
  TextStyle? inheritedStyle,
) {
  if (nodes == null || nodes.isEmpty) {
    return const <TextSpan>[];
  }

  return nodes
      .map((node) => _buildNodeSpan(node, styles, inheritedStyle))
      .toList(growable: false);
}

TextSpan _buildNodeSpan(
  hl.Node node,
  Map<String, TextStyle> styles,
  TextStyle? inheritedStyle,
) {
  final tokenStyle = node.className == null ? null : styles[node.className!];
  final effectiveStyle = tokenStyle == null
      ? inheritedStyle
      : inheritedStyle?.merge(tokenStyle) ?? tokenStyle;

  if (node.children != null && node.children!.isNotEmpty) {
    return TextSpan(
      style: effectiveStyle,
      children: _buildNodeSpans(node.children, styles, effectiveStyle),
    );
  }

  return TextSpan(text: node.value ?? '', style: effectiveStyle);
}
