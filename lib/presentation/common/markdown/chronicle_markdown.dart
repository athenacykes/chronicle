import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:webview_flutter/webview_flutter.dart';

const String _kMermaidAssetPath = 'assets/vendor/mermaid/mermaid.min.js';

class ChronicleMarkdown extends StatelessWidget {
  const ChronicleMarkdown({
    super.key,
    required this.data,
    this.padding = EdgeInsets.zero,
  });

  final String data;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Markdown(
      data: data,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      blockSyntaxes: const <md.BlockSyntax>[
        _MermaidBlockSyntax(),
        _MathBlockSyntax(),
      ],
      inlineSyntaxes: <md.InlineSyntax>[_MathInlineSyntax()],
      builders: <String, MarkdownElementBuilder>{
        'math-inline': _MathInlineBuilder(),
        'math-block': _MathBlockBuilder(),
        'mermaid-block': _MermaidBlockBuilder(),
      },
      padding: padding,
    );
  }
}

class _MathInlineSyntax extends md.InlineSyntax {
  _MathInlineSyntax()
    : super(
        r'(?<![\\$])\$(?!\$)(?:\\.|[^$\\\n])+(?<!\\)\$(?!\$)',
        startCharacter: 36,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final matched = match[0];
    if (matched == null || matched.length < 2) {
      return false;
    }
    final expression = matched.substring(1, matched.length - 1).trim();
    if (expression.isEmpty) {
      return false;
    }
    parser.addNode(md.Element.text('math-inline', expression));
    return true;
  }
}

class _MathBlockSyntax extends md.BlockSyntax {
  const _MathBlockSyntax();

  static final RegExp _startsMath = RegExp(r'^\s*\$\$');
  static final RegExp _blockFence = RegExp(r'^\s*\$\$\s*$');
  static final RegExp _singleLineMath = RegExp(
    r'^\s*\$\$(?!\$)(.*?)(?<!\\)\$\$\s*$',
  );

  @override
  RegExp get pattern => _startsMath;

  @override
  md.Node? parse(md.BlockParser parser) {
    final current = parser.current.content;
    final singleLineMatch = _singleLineMath.firstMatch(current);
    if (singleLineMatch != null && !_blockFence.hasMatch(current)) {
      final expression = (singleLineMatch.group(1) ?? '').trim();
      if (expression.isEmpty) {
        return null;
      }
      parser.advance();
      final element = md.Element.withTag('math-block');
      element.attributes['tex'] = expression;
      return element;
    }

    if (!_blockFence.hasMatch(current)) {
      return null;
    }

    var consumed = 1;
    parser.advance();
    final lines = <String>[];

    while (!parser.isDone) {
      final line = parser.current.content;
      if (_blockFence.hasMatch(line)) {
        consumed += 1;
        parser.advance();
        final expression = lines.join('\n').trim();
        if (expression.isEmpty) {
          return null;
        }
        final element = md.Element.withTag('math-block');
        element.attributes['tex'] = expression;
        return element;
      }
      lines.add(line);
      consumed += 1;
      parser.advance();
    }

    parser.retreatBy(consumed);
    return null;
  }
}

class _MathInlineBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final expression = element.textContent.trim();
    if (expression.isEmpty) {
      return null;
    }
    return Math.tex(
      expression,
      mathStyle: MathStyle.text,
      textStyle: preferredStyle ?? parentStyle,
      onErrorFallback: (_) => Text(expression, style: preferredStyle),
    );
  }
}

class _MathBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final expression = (element.attributes['tex'] ?? '').trim();
    if (expression.isEmpty) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Math.tex(
        expression,
        mathStyle: MathStyle.display,
        textStyle: preferredStyle ?? parentStyle,
        onErrorFallback: (_) =>
            SelectableText(expression, style: preferredStyle ?? parentStyle),
      ),
    );
  }
}

class _MermaidBlockSyntax extends md.BlockSyntax {
  const _MermaidBlockSyntax();

  static final RegExp _openFence = RegExp(r'^\s*(```+|~~~+)\s*mermaid\s*$');

  @override
  RegExp get pattern => _openFence;

  @override
  md.Node? parse(md.BlockParser parser) {
    final openMatch = _openFence.firstMatch(parser.current.content);
    if (openMatch == null) {
      return null;
    }
    final marker = openMatch.group(1)!;
    final markerChar = marker[0];
    final markerLength = marker.length;
    final closeFence = RegExp(
      '^\\s*${RegExp.escape(markerChar)}{$markerLength,}\\s*\$',
    );

    var consumed = 1;
    parser.advance();
    final lines = <String>[];
    while (!parser.isDone) {
      final line = parser.current.content;
      if (closeFence.hasMatch(line)) {
        parser.advance();
        consumed += 1;
        final source = lines.join('\n').trim();
        if (source.isEmpty) {
          return null;
        }
        final element = md.Element.withTag('mermaid-block');
        element.attributes['source'] = source;
        return element;
      }
      lines.add(line);
      parser.advance();
      consumed += 1;
    }

    parser.retreatBy(consumed);
    return null;
  }
}

@immutable
class MermaidFence {
  const MermaidFence({required this.source});

  final String source;
}

@visibleForTesting
MermaidFence? extractMermaidFenceFromPre(md.Element element) {
  if (element.tag != 'pre' || element.children == null) {
    return null;
  }
  if (element.children!.length != 1) {
    return null;
  }
  final codeNode = element.children!.single;
  if (codeNode is! md.Element || codeNode.tag != 'code') {
    return null;
  }
  final classes = (codeNode.attributes['class'] ?? '')
      .split(RegExp(r'\s+'))
      .where((value) => value.trim().isNotEmpty)
      .toSet();
  if (!classes.contains('language-mermaid') && !classes.contains('mermaid')) {
    return null;
  }
  final source = codeNode.textContent.trim();
  if (source.isEmpty) {
    return null;
  }
  return MermaidFence(source: source);
}

class _MermaidBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final source = (element.attributes['source'] ?? '').trim();
    if (source.isEmpty) {
      return null;
    }
    if (!_isMermaidSupportedOnPlatform) {
      return _MermaidSourceFallback(source: source);
    }
    return _MermaidWebViewBlock(source: source);
  }
}

class _MermaidWebViewBlock extends StatefulWidget {
  const _MermaidWebViewBlock({required this.source});

  final String source;

  @override
  State<_MermaidWebViewBlock> createState() => _MermaidWebViewBlockState();
}

class _MermaidWebViewBlockState extends State<_MermaidWebViewBlock> {
  static Future<String>? _mermaidScriptFuture;

  WebViewController? _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _buildController();
  }

  Future<void> _buildController() async {
    if (!_isMermaidSupportedOnPlatform) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
      return;
    }

    try {
      final theme = _effectiveBrightness(context) == Brightness.dark
          ? 'dark'
          : 'default';
      final script = await (_mermaidScriptFuture ??= rootBundle.loadString(
        _kMermaidAssetPath,
      ));
      final html = _buildMermaidHtml(
        source: widget.source,
        script: script,
        theme: theme,
      );

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..setNavigationDelegate(
          NavigationDelegate(
            onWebResourceError: (_) {
              if (!mounted) {
                return;
              }
              setState(() {
                _failed = true;
                _loading = false;
              });
            },
          ),
        );
      await controller.loadHtmlString(html);
      if (!mounted) {
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _MermaidSourceFallback(source: widget.source);
    }

    final height = _estimatedHeightForMermaid(widget.source);
    if (_loading || _controller == null) {
      return SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: WebViewWidget(controller: _controller!),
      ),
    );
  }
}

class _MermaidSourceFallback extends StatelessWidget {
  const _MermaidSourceFallback({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withAlpha(128),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectableText(source, style: style),
    );
  }
}

double _estimatedHeightForMermaid(String source) {
  final lines = source.split('\n').length;
  final estimated = 140 + (lines * 18);
  return estimated.clamp(180, 560).toDouble();
}

Brightness _effectiveBrightness(BuildContext context) {
  if (MacosTheme.maybeOf(context) != null) {
    return MacosTheme.brightnessOf(context);
  }
  return Theme.of(context).brightness;
}

String _buildMermaidHtml({
  required String source,
  required String script,
  required String theme,
}) {
  final sourceJson = jsonEncode(source);
  final escapedScript = script.replaceAll('</script', '<\\/script');
  return '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1.0" />
    <style>
      html, body {
        margin: 0;
        padding: 0;
        background: transparent;
      }
      #chart {
        padding: 8px;
      }
      #fallback {
        display: none;
        margin: 0;
        padding: 8px;
        white-space: pre-wrap;
        font-family: Menlo, monospace;
        font-size: 13px;
      }
    </style>
  </head>
  <body>
    <div id="chart"></div>
    <pre id="fallback"></pre>
    <script>$escapedScript</script>
    <script>
      (function () {
        const src = $sourceJson;
        const chart = document.getElementById('chart');
        const fallback = document.getElementById('fallback');
        const showSource = () => {
          chart.style.display = 'none';
          fallback.style.display = 'block';
          fallback.textContent = src;
        };
        try {
          mermaid.initialize({
            startOnLoad: false,
            securityLevel: 'strict',
            theme: '$theme'
          });
          const rendered = mermaid.render('chronicle-mermaid', src);
          if (rendered && typeof rendered.then === 'function') {
            rendered
              .then((result) => {
                chart.innerHTML = result && result.svg ? result.svg : String(result ?? '');
              })
              .catch(showSource);
            return;
          }
          if (rendered && rendered.svg) {
            chart.innerHTML = rendered.svg;
            return;
          }
          if (typeof rendered === 'string') {
            chart.innerHTML = rendered;
            return;
          }
          showSource();
        } catch (_) {
          showSource();
        }
      })();
    </script>
  </body>
</html>
''';
}

bool get _isMermaidSupportedOnPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
