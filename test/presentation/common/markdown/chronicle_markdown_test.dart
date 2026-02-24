import 'package:chronicle/presentation/common/markdown/chronicle_markdown.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:webview_flutter/webview_flutter.dart';

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
