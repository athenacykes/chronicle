import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

typedef NowLocal = DateTime Function();

class MarkdownEditFormatter {
  MarkdownEditFormatter({NowLocal? nowLocal})
    : _nowLocal = nowLocal ?? DateTime.now;

  final NowLocal _nowLocal;

  TextEditingValue applyBold(TextEditingValue value) {
    return _wrapSelection(value, marker: '**');
  }

  TextEditingValue applyItalic(TextEditingValue value) {
    return _wrapSelection(value, marker: '*');
  }

  TextEditingValue applyHeading(TextEditingValue value, {required int level}) {
    final clampedLevel = level.clamp(1, 6);
    return _applyLinePrefixes(
      value,
      prefixBuilder: (_) => '${'#' * clampedLevel} ',
    );
  }

  TextEditingValue applyUnorderedList(TextEditingValue value) {
    return _applyLinePrefixes(value, prefixBuilder: (_) => '- ');
  }

  TextEditingValue applyOrderedList(TextEditingValue value) {
    return _applyLinePrefixes(
      value,
      prefixBuilder: (index) => '${index + 1}. ',
    );
  }

  TextEditingValue applyCodeBlock(TextEditingValue value, {String? language}) {
    final selection = _normalizedSelection(value);
    final range = _selectionRange(selection);
    final languagePart = (language ?? '').trim();
    final opening = languagePart.isEmpty ? '```\n' : '```$languagePart\n';

    if (range.isCollapsed) {
      return _replaceRange(
        value: value,
        range: range,
        replacement: '$opening```',
        selectionBaseOffsetInReplacement: opening.length,
        selectionExtentOffsetInReplacement: opening.length,
      );
    }

    final selectedText = value.text.substring(range.start, range.end);
    final selectedWithTrailingBreak = selectedText.endsWith('\n')
        ? selectedText
        : '$selectedText\n';
    return _replaceRange(
      value: value,
      range: range,
      replacement: '$opening$selectedWithTrailingBreak```',
      selectionBaseOffsetInReplacement: opening.length,
      selectionExtentOffsetInReplacement: opening.length + selectedText.length,
    );
  }

  TextEditingValue applyTable(
    TextEditingValue value, {
    required int rows,
    required int columns,
  }) {
    if (rows < 1 || columns < 1) {
      return value;
    }
    return _replaceSelection(
      value,
      _tableSnippet(rows: rows, columns: columns),
    );
  }

  TextEditingValue applyLink(
    TextEditingValue value, {
    String? text,
    required String url,
    String? title,
  }) {
    final urlValue = url.trim();
    if (urlValue.isEmpty) {
      return value;
    }

    final selectedText = _selectedText(value).trim();
    final label = (text ?? '').trim().isNotEmpty
        ? text!.trim()
        : (selectedText.isNotEmpty ? selectedText : urlValue);
    final titlePart = _optionalTitlePart(title);
    return _replaceSelection(value, '[$label]($urlValue$titlePart)');
  }

  TextEditingValue applyImage(
    TextEditingValue value, {
    String? alt,
    required String src,
    String? title,
  }) {
    final srcValue = src.trim();
    if (srcValue.isEmpty) {
      return value;
    }

    final selectedText = _selectedText(value).trim();
    final altValue = (alt ?? '').trim().isNotEmpty ? alt!.trim() : selectedText;
    final titlePart = _optionalTitlePart(title);
    return _replaceSelection(value, '![$altValue]($srcValue$titlePart)');
  }

  TextEditingValue applyCurrentDate(TextEditingValue value) {
    final formatted = DateFormat('yyyy-MM-dd').format(_nowLocal());
    return _replaceSelection(value, formatted);
  }

  TextEditingValue _wrapSelection(
    TextEditingValue value, {
    required String marker,
  }) {
    final selection = _normalizedSelection(value);
    final range = _selectionRange(selection);
    final selectedText = value.text.substring(range.start, range.end);
    final wrapped = '$marker$selectedText$marker';
    final offsetStart = marker.length;
    final offsetEnd = marker.length + selectedText.length;

    return _replaceRange(
      value: value,
      range: range,
      replacement: wrapped,
      selectionBaseOffsetInReplacement: selection.isCollapsed
          ? offsetStart
          : offsetStart,
      selectionExtentOffsetInReplacement: selection.isCollapsed
          ? offsetStart
          : offsetEnd,
    );
  }

  TextEditingValue _applyLinePrefixes(
    TextEditingValue value, {
    required String Function(int transformedLineIndex) prefixBuilder,
  }) {
    final text = value.text;
    final selection = _normalizedSelection(value);
    final range = _selectionRange(selection);
    final lines = _splitLines(text);
    final selectedIndexes = _selectedLineIndexes(lines, range: range);
    if (selectedIndexes.isEmpty) {
      return value;
    }

    final linePrefixes = <int, String>{};
    var transformedLineIndex = 0;
    for (final lineIndex in selectedIndexes) {
      final line = lines[lineIndex];
      if (line.content.trim().isEmpty) {
        continue;
      }
      linePrefixes[lineIndex] = prefixBuilder(transformedLineIndex);
      transformedLineIndex += 1;
    }

    if (linePrefixes.isEmpty) {
      return value;
    }

    final output = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final prefix = linePrefixes[i];
      if (prefix != null) {
        output.write(prefix);
      }
      output.write(line.content);
      if (line.hasTrailingNewline) {
        output.write('\n');
      }
    }

    int shiftOffset(int oldOffset) {
      var shifted = oldOffset;
      for (final entry in linePrefixes.entries) {
        final line = lines[entry.key];
        if (oldOffset >= line.start) {
          shifted += entry.value.length;
        }
      }
      return shifted;
    }

    final newText = output.toString();
    final base = shiftOffset(selection.baseOffset).clamp(0, newText.length);
    final extent = shiftOffset(selection.extentOffset).clamp(0, newText.length);

    return value.copyWith(
      text: newText,
      selection: TextSelection(baseOffset: base, extentOffset: extent),
      composing: TextRange.empty,
    );
  }

  TextEditingValue _replaceSelection(
    TextEditingValue value,
    String replacement,
  ) {
    final selection = _normalizedSelection(value);
    final range = _selectionRange(selection);
    return _replaceRange(
      value: value,
      range: range,
      replacement: replacement,
      selectionBaseOffsetInReplacement: replacement.length,
      selectionExtentOffsetInReplacement: replacement.length,
    );
  }

  TextEditingValue _replaceRange({
    required TextEditingValue value,
    required _SelectionRange range,
    required String replacement,
    required int selectionBaseOffsetInReplacement,
    required int selectionExtentOffsetInReplacement,
  }) {
    final newText = value.text.replaceRange(
      range.start,
      range.end,
      replacement,
    );
    final base = (range.start + selectionBaseOffsetInReplacement).clamp(
      0,
      newText.length,
    );
    final extent = (range.start + selectionExtentOffsetInReplacement).clamp(
      0,
      newText.length,
    );

    return value.copyWith(
      text: newText,
      selection: TextSelection(baseOffset: base, extentOffset: extent),
      composing: TextRange.empty,
    );
  }

  List<_LineInfo> _splitLines(String text) {
    final lines = <_LineInfo>[];
    var start = 0;
    while (true) {
      final newlineIndex = text.indexOf('\n', start);
      if (newlineIndex == -1) {
        lines.add(
          _LineInfo(
            start: start,
            end: text.length,
            hasTrailingNewline: false,
            content: text.substring(start),
          ),
        );
        return lines;
      }

      lines.add(
        _LineInfo(
          start: start,
          end: newlineIndex,
          hasTrailingNewline: true,
          content: text.substring(start, newlineIndex),
        ),
      );
      start = newlineIndex + 1;
    }
  }

  List<int> _selectedLineIndexes(
    List<_LineInfo> lines, {
    required _SelectionRange range,
  }) {
    if (lines.isEmpty) {
      return const <int>[];
    }

    if (range.isCollapsed) {
      final cursor = range.start;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final containsCursor =
            (cursor >= line.start && cursor < line.endWithBreak) ||
            (i == lines.length - 1 && cursor == line.endWithBreak);
        if (containsCursor) {
          return <int>[i];
        }
      }
      return <int>[lines.length - 1];
    }

    final indexes = <int>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final intersects =
          line.start < range.end && line.endWithBreak > range.start;
      if (intersects) {
        indexes.add(i);
      }
    }
    return indexes;
  }

  TextSelection _normalizedSelection(TextEditingValue value) {
    final selection = value.selection;
    final textLength = value.text.length;
    if (!selection.isValid) {
      return TextSelection.collapsed(offset: textLength);
    }
    final base = selection.baseOffset.clamp(0, textLength);
    final extent = selection.extentOffset.clamp(0, textLength);
    return TextSelection(baseOffset: base, extentOffset: extent);
  }

  _SelectionRange _selectionRange(TextSelection selection) {
    return _SelectionRange(
      start: selection.start,
      end: selection.end,
      isCollapsed: selection.isCollapsed,
    );
  }

  String _selectedText(TextEditingValue value) {
    final range = _selectionRange(_normalizedSelection(value));
    return value.text.substring(range.start, range.end);
  }

  String _optionalTitlePart(String? title) {
    final value = (title ?? '').trim();
    if (value.isEmpty) {
      return '';
    }
    final escaped = value.replaceAll('"', r'\"');
    return ' "$escaped"';
  }

  String _tableSnippet({required int rows, required int columns}) {
    String row(List<String> cells) => '| ${cells.join(' | ')} |';
    final header = row(
      List<String>.generate(columns, (index) => 'Column ${index + 1}'),
    );
    final separator = row(List<String>.filled(columns, '---'));
    final bodyRows = List<String>.generate(
      rows,
      (_) => row(List<String>.filled(columns, '')),
    );
    return <String>[header, separator, ...bodyRows].join('\n');
  }
}

class _LineInfo {
  const _LineInfo({
    required this.start,
    required this.end,
    required this.hasTrailingNewline,
    required this.content,
  });

  final int start;
  final int end;
  final bool hasTrailingNewline;
  final String content;

  int get endWithBreak => hasTrailingNewline ? end + 1 : end;
}

class _SelectionRange {
  const _SelectionRange({
    required this.start,
    required this.end,
    required this.isCollapsed,
  });

  final int start;
  final int end;
  final bool isCollapsed;
}
