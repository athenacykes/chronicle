import 'package:chronicle/presentation/common/markdown/markdown_edit_formatter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarkdownEditFormatter', () {
    test('applyBold wraps selected text and keeps selection on content', () {
      final formatter = MarkdownEditFormatter();
      final input = const TextEditingValue(
        text: 'hello',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      );

      final output = formatter.applyBold(input);

      expect(output.text, '**hello**');
      expect(output.selection.baseOffset, 2);
      expect(output.selection.extentOffset, 7);
    });

    test('applyItalic inserts markers at collapsed selection', () {
      final formatter = MarkdownEditFormatter();
      final input = const TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 1),
      );

      final output = formatter.applyItalic(input);

      expect(output.text, 'a**bc');
      expect(output.selection.baseOffset, 2);
      expect(output.selection.extentOffset, 2);
    });

    test('applyHeading prefixes selected non-empty lines', () {
      final formatter = MarkdownEditFormatter();
      final input = const TextEditingValue(
        text: 'one\ntwo\n\nthree',
        selection: TextSelection(baseOffset: 0, extentOffset: 7),
      );

      final output = formatter.applyHeading(input, level: 2);

      expect(output.text, '## one\n## two\n\nthree');
    });

    test(
      'applyUnorderedList prefixes current line when selection collapsed',
      () {
        final formatter = MarkdownEditFormatter();
        final input = const TextEditingValue(
          text: 'one\ntwo',
          selection: TextSelection.collapsed(offset: 4),
        );

        final output = formatter.applyUnorderedList(input);

        expect(output.text, 'one\n- two');
      },
    );

    test('applyOrderedList numbers selected non-empty lines', () {
      final formatter = MarkdownEditFormatter();
      final input = const TextEditingValue(
        text: 'a\n\nb\nc',
        selection: TextSelection(baseOffset: 0, extentOffset: 6),
      );

      final output = formatter.applyOrderedList(input);

      expect(output.text, '1. a\n\n2. b\n3. c');
    });

    test('applyCodeBlock wraps selected text in fenced block', () {
      final formatter = MarkdownEditFormatter();
      final input = const TextEditingValue(
        text: 'print(1);',
        selection: TextSelection(baseOffset: 0, extentOffset: 9),
      );

      final output = formatter.applyCodeBlock(input, language: 'dart');

      expect(output.text, '```dart\nprint(1);\n```');
      expect(output.selection.baseOffset, 8);
      expect(output.selection.extentOffset, 17);
    });

    test('applyTable inserts gfm table template', () {
      final formatter = MarkdownEditFormatter();
      final input = const TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
      );

      final output = formatter.applyTable(input, rows: 2, columns: 3);

      expect(
        output.text,
        '| Column 1 | Column 2 | Column 3 |\n'
        '| --- | --- | --- |\n'
        '|  |  |  |\n'
        '|  |  |  |',
      );
    });

    test('applyLink uses selected text when text is empty', () {
      final formatter = MarkdownEditFormatter();
      final input = const TextEditingValue(
        text: 'Docs',
        selection: TextSelection(baseOffset: 0, extentOffset: 4),
      );

      final output = formatter.applyLink(
        input,
        text: '',
        url: 'https://example.com',
      );

      expect(output.text, '[Docs](https://example.com)');
    });

    test('applyImage formats alt, source, and title', () {
      final formatter = MarkdownEditFormatter();
      final input = const TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
      );

      final output = formatter.applyImage(
        input,
        alt: 'Logo',
        src: '/resources/logo.png',
        title: 'Hero',
      );

      expect(output.text, '![Logo](/resources/logo.png "Hero")');
    });

    test('applyCurrentDate uses injected local clock', () {
      final formatter = MarkdownEditFormatter(
        nowLocal: () => DateTime(2026, 2, 25, 11, 32),
      );
      final input = const TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
      );

      final output = formatter.applyCurrentDate(input);

      expect(output.text, '2026-02-25');
    });
  });
}
