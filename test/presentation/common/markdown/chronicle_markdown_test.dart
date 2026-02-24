import 'package:chronicle/presentation/common/markdown/chronicle_markdown.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:webview_flutter/webview_flutter.dart';

List<_SpanChunk> _collectChunks(InlineSpan span) {
  if (span is! TextSpan) {
    return const <_SpanChunk>[];
  }

  final chunks = <_SpanChunk>[];
  void visit(TextSpan node, TextStyle? inheritedStyle) {
    final effectiveStyle = inheritedStyle?.merge(node.style) ?? node.style;
    final value = node.text;
    if (value != null && value.isNotEmpty) {
      chunks.add(_SpanChunk(text: value, style: effectiveStyle));
    }
    for (final child in node.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) {
        visit(child, effectiveStyle);
      }
    }
  }

  visit(span, null);
  return chunks;
}

@immutable
class _SpanChunk {
  const _SpanChunk({required this.text, required this.style});

  final String text;
  final TextStyle? style;
}

void main() {
  Widget buildTestApp(String data) {
    return MaterialApp(
      home: Scaffold(body: ChronicleMarkdown(data: data)),
    );
  }

  testWidgets('renders gfm tables', (tester) async {
    await tester.pumpWidget(
      buildTestApp('| A | B |\n| --- | --- |\n| 1 | 2 |'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Table), findsOneWidget);
  });

  testWidgets('renders inline and block latex', (tester) async {
    await tester.pumpWidget(
      buildTestApp('Inline \$a^2 + b^2\$.\n\n\$\$c^2 = a^2 + b^2\$\$'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Math), findsNWidgets(2));
  });

  testWidgets('escaped dollar stays text and does not create math', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestApp(r'Price is \$5 only.'));
    await tester.pumpAndSettle();

    expect(find.byType(Math), findsNothing);
    expect(find.textContaining('Price is \$5 only.'), findsOneWidget);
  });

  test('code helper extracts language and source from fenced pre blocks', () {
    final code = md.Element.text('code', 'final value = 1;\n')
      ..attributes['class'] = 'language-dart';
    final pre = md.Element('pre', <md.Node>[code]);

    final block = extractCodeBlockFromPre(pre);
    expect(block, isNotNull);
    expect(block?.languageHint, 'dart');
    expect(block?.source, 'final value = 1;\n');
  });

  testWidgets('read mode highlights fenced code blocks', (tester) async {
    await tester.pumpWidget(
      buildTestApp('```dart\nfinal value = 1;\nprint(value);\n```'),
    );
    await tester.pumpAndSettle();

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final codeRichText = richTexts.firstWhere(
      (widget) => widget.text.toPlainText().contains('final value = 1;'),
    );
    final chunks = _collectChunks(codeRichText.text);
    final hasTokenColor = chunks.any(
      (chunk) =>
          chunk.style?.color != null &&
          chunk.style?.color != codeRichText.text.style?.color,
    );

    expect(hasTokenColor, isTrue);
  });

  testWidgets('read mode code blocks use monospace font', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(buildTestApp('```dart\nfinal value = 1;\n```'));
      await tester.pumpAndSettle();

      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      final codeRichText = richTexts.firstWhere(
        (widget) => widget.text.toPlainText().contains('final value = 1;'),
      );

      expect(codeRichText.text.style?.fontFamily, 'monospace');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('read mode unknown code language falls back safely', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestApp('```totally-unknown\nv = 42\n```'));
    await tester.pumpAndSettle();

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final hasCodeText = richTexts.any(
      (widget) => widget.text.toPlainText().contains('v = 42'),
    );

    expect(hasCodeText, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('mermaid helper detects language-mermaid fenced blocks', () {
    final code = md.Element.text('code', 'graph TD\nA-->B')
      ..attributes['class'] = 'language-mermaid';
    final pre = md.Element('pre', <md.Node>[code]);

    final fence = extractMermaidFenceFromPre(pre);
    expect(fence, isNotNull);
    expect(fence?.source, 'graph TD\nA-->B');
  });

  test('mermaid helper ignores non-mermaid fenced blocks', () {
    final code = md.Element.text('code', 'final x = 1;')
      ..attributes['class'] = 'language-dart';
    final pre = md.Element('pre', <md.Node>[code]);

    expect(extractMermaidFenceFromPre(pre), isNull);
  });

  testWidgets('mermaid fences fallback to source on non-macos platforms', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(buildTestApp('```mermaid\ngraph TD\nA-->B\n```'));
      await tester.pumpAndSettle();

      expect(find.byType(WebViewWidget), findsNothing);
      expect(find.textContaining('graph TD'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
