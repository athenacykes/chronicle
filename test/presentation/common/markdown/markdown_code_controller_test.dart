import 'package:chronicle/presentation/common/markdown/markdown_code_controller.dart';
import 'package:chronicle/presentation/common/markdown/markdown_code_highlighting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';

@immutable
class _SpanChunk {
  const _SpanChunk({required this.text, required this.style});

  final String text;
  final TextStyle? style;
}

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

void main() {
  test('splitMarkdownWithFencedCode supports backtick and tilde fences', () {
    const markdown =
        '# Title\n```dart\nfinal x = 1;\n```\ntext\n~~~python\nprint(x)\n~~~\n';

    final segments = splitMarkdownWithFencedCode(markdown);
    final codeSegments = segments
        .where((segment) => segment.type == MarkdownTextSegmentType.code)
        .toList(growable: false);

    expect(codeSegments.length, 2);
    expect(codeSegments[0].languageHint, 'dart');
    expect(codeSegments[0].text, 'final x = 1;\n');
    expect(codeSegments[1].languageHint, 'python');
    expect(codeSegments[1].text, 'print(x)\n');
  });

  test('splitMarkdownWithFencedCode requires matching close fence length', () {
    const markdown = '````dart\nfinal x = 1;\n```\nrest';

    final segments = splitMarkdownWithFencedCode(markdown);

    expect(segments.length, 2);
    expect(segments.first.type, MarkdownTextSegmentType.markdown);
    expect(segments.first.text, '````dart\n');
    expect(segments.last.type, MarkdownTextSegmentType.code);
    expect(segments.last.text, 'final x = 1;\n```\nrest');
  });

  testWidgets('MarkdownCodeController highlights markdown and fenced code', (
    tester,
  ) async {
    final controller = MarkdownCodeController(
      text: '# Title\n```dart\nfinal value = 1;\n```\n',
    );
    final theme = markdownCodeThemeDataForBrightness(Brightness.light);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeTheme(
            data: theme,
            child: CodeField(
              controller: controller,
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final span = controller.lastTextSpan;
    expect(span, isNotNull);

    final chunks = _collectChunks(span!);
    final titleChunk = chunks.firstWhere(
      (chunk) => chunk.text.contains('# Title'),
    );
    final keywordChunk = chunks.firstWhere(
      (chunk) => chunk.text.contains('final'),
    );

    expect(titleChunk.style?.color, theme.styles['section']?.color);
    expect(keywordChunk.style?.color, theme.styles['keyword']?.color);
    expect(keywordChunk.style?.color, isNot(titleChunk.style?.color));
  });

  testWidgets('CodeField with markdown controller fits constrained height', (
    tester,
  ) async {
    final longText = List<String>.generate(
      120,
      (index) => 'line $index',
    ).join('\n');
    final controller = MarkdownCodeController(text: longText);
    final theme = markdownCodeThemeDataForBrightness(Brightness.light);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 260,
            child: CodeTheme(
              data: theme,
              child: CodeField(
                controller: controller,
                expands: true,
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
