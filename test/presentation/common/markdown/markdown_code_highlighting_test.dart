import 'package:chronicle/presentation/common/markdown/markdown_code_highlighting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeCodeLanguage resolves common aliases', () {
    expect(normalizeCodeLanguage('js'), 'javascript');
    expect(normalizeCodeLanguage('TS'), 'typescript');
    expect(normalizeCodeLanguage('language-yml'), 'yaml');
    expect(normalizeCodeLanguage('c++'), 'cpp');
  });

  test('resolveHighlightLanguage returns null for unknown hints', () {
    expect(resolveHighlightLanguage('not-a-real-language'), isNull);
  });

  test('highlightCodeWithFallback uses explicit language when supported', () {
    final result = highlightCodeWithFallback(
      'const value: number = 1;',
      languageHint: 'ts',
    );

    expect(result.usedAutoDetection, isFalse);
    expect(result.language, 'typescript');
    expect(result.result.nodes, isNotEmpty);
  });

  test('highlightCodeWithFallback auto-detects unknown hints', () {
    final result = highlightCodeWithFallback(
      'def fn(x):\n  return x + 1',
      languageHint: 'unknown-language',
    );

    expect(result.usedAutoDetection, isTrue);
    expect(result.result.nodes, isNotEmpty);
  });

  test('buildHighlightedCodeTextSpan keeps full source text', () {
    const source = 'final x = 1;\nprint(x);';
    final span = buildHighlightedCodeTextSpan(
      source: source,
      styles: const <String, TextStyle>{},
      baseStyle: const TextStyle(fontSize: 13),
      languageHint: 'dart',
    );

    expect(span.toPlainText(), source);
  });
}
