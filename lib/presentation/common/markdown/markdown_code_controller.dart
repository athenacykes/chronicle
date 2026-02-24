import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_code_editor/src/code_field/search_result_highlighted_builder.dart';
import 'package:highlight/languages/markdown.dart' as highlight_markdown;

import 'markdown_code_highlighting.dart';

enum MarkdownTextSegmentType { markdown, code }

@immutable
class MarkdownTextSegment {
  const MarkdownTextSegment.markdown(this.text)
    : type = MarkdownTextSegmentType.markdown,
      languageHint = null;

  const MarkdownTextSegment.code(this.text, {required this.languageHint})
    : type = MarkdownTextSegmentType.code;

  final MarkdownTextSegmentType type;
  final String text;
  final String? languageHint;
}

class MarkdownCodeController extends CodeController {
  MarkdownCodeController({
    super.text,
    super.analyzer,
    super.namedSectionParser,
    super.readOnlySectionNames,
    super.visibleSectionNames,
    super.analysisResult,
    super.patternMap,
    super.readOnly,
    super.params,
    super.modifiers,
  }) : super(language: highlight_markdown.markdown);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    bool? withComposing,
  }) {
    final codeTheme = CodeTheme.of(context) ?? CodeThemeData();
    final segments = splitMarkdownWithFencedCode(text);

    final spans = <TextSpan>[];
    for (final segment in segments) {
      final languageHint = segment.type == MarkdownTextSegmentType.code
          ? segment.languageHint
          : 'markdown';
      spans.add(
        buildHighlightedCodeTextSpan(
          source: segment.text,
          styles: codeTheme.styles,
          baseStyle: style,
          languageHint: languageHint,
        ),
      );
    }

    final spanBeforeSearch = TextSpan(style: style, children: spans);
    final searchHighlightedSpan = SearchResultHighlightedBuilder(
      searchResult: fullSearchResult,
      rootStyle: style,
      textSpan: spanBeforeSearch,
      searchNavigationState: searchController.navigationController.value,
    ).build();

    lastTextSpan = searchHighlightedSpan;
    return searchHighlightedSpan;
  }
}

class _FenceInfo {
  const _FenceInfo({
    required this.markerChar,
    required this.markerLength,
    required this.languageHint,
  });

  final String markerChar;
  final int markerLength;
  final String? languageHint;
}

final RegExp _fenceOpenPattern = RegExp(r'^[ \t]{0,3}(`{3,}|~{3,})([^\n]*)$');

@visibleForTesting
List<MarkdownTextSegment> splitMarkdownWithFencedCode(String markdown) {
  if (markdown.isEmpty) {
    return const <MarkdownTextSegment>[];
  }

  final segments = <MarkdownTextSegment>[];
  var markdownStart = 0;
  _FenceInfo? activeFence;
  var codeStart = -1;

  var index = 0;
  while (index < markdown.length) {
    final newLine = markdown.indexOf('\n', index);
    final lineEnd = newLine == -1 ? markdown.length : newLine;
    final nextLineStart = newLine == -1 ? markdown.length : newLine + 1;

    final line = markdown.substring(index, lineEnd);
    final lineWithBreak = markdown.substring(index, nextLineStart);

    if (activeFence == null) {
      final fence = _parseFenceOpen(line);
      if (fence != null) {
        if (markdownStart < index) {
          segments.add(
            MarkdownTextSegment.markdown(
              markdown.substring(markdownStart, index),
            ),
          );
        }
        segments.add(MarkdownTextSegment.markdown(lineWithBreak));
        activeFence = fence;
        codeStart = nextLineStart;
        markdownStart = nextLineStart;
      }
      index = nextLineStart;
      continue;
    }

    if (_isFenceClose(
      line,
      markerChar: activeFence.markerChar,
      markerLength: activeFence.markerLength,
    )) {
      if (codeStart >= 0 && codeStart < index) {
        segments.add(
          MarkdownTextSegment.code(
            markdown.substring(codeStart, index),
            languageHint: activeFence.languageHint,
          ),
        );
      }

      segments.add(MarkdownTextSegment.markdown(lineWithBreak));
      activeFence = null;
      codeStart = -1;
      markdownStart = nextLineStart;
      index = nextLineStart;
      continue;
    }

    index = nextLineStart;
  }

  if (activeFence != null && codeStart >= 0 && codeStart < markdown.length) {
    segments.add(
      MarkdownTextSegment.code(
        markdown.substring(codeStart),
        languageHint: activeFence.languageHint,
      ),
    );
    markdownStart = markdown.length;
  }

  if (markdownStart < markdown.length) {
    segments.add(
      MarkdownTextSegment.markdown(markdown.substring(markdownStart)),
    );
  }

  return _coalesceMarkdownSegments(segments);
}

List<MarkdownTextSegment> _coalesceMarkdownSegments(
  List<MarkdownTextSegment> segments,
) {
  if (segments.isEmpty) {
    return segments;
  }

  final merged = <MarkdownTextSegment>[];
  for (final segment in segments) {
    if (segment.text.isEmpty) {
      continue;
    }

    if (segment.type == MarkdownTextSegmentType.markdown &&
        merged.isNotEmpty &&
        merged.last.type == MarkdownTextSegmentType.markdown) {
      final previous = merged.removeLast();
      merged.add(MarkdownTextSegment.markdown(previous.text + segment.text));
      continue;
    }

    merged.add(segment);
  }

  return merged;
}

_FenceInfo? _parseFenceOpen(String line) {
  final match = _fenceOpenPattern.firstMatch(line);
  if (match == null) {
    return null;
  }

  final marker = match.group(1)!;
  final info = match.group(2) ?? '';

  if (marker.startsWith('`') && info.contains('`')) {
    return null;
  }

  return _FenceInfo(
    markerChar: marker[0],
    markerLength: marker.length,
    languageHint: _languageHintFromFenceInfo(info),
  );
}

bool _isFenceClose(
  String line, {
  required String markerChar,
  required int markerLength,
}) {
  final pattern = RegExp(
    '^[ \\t]{0,3}${RegExp.escape(markerChar)}{$markerLength,}[ \\t]*\$',
  );
  return pattern.hasMatch(line);
}

String? _languageHintFromFenceInfo(String info) {
  final trimmed = info.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed.split(RegExp(r'\s+')).first;
}
