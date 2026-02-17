import 'package:chronicle/core/markdown_front_matter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('front matter parse and format roundtrip', () {
    final source = formatMarkdownWithFrontMatter(
      frontMatter: <String, dynamic>{
        'id': 'note-1',
        'title': 'Hello',
        'matterId': null,
        'tags': <String>['one', 'two'],
        'isPinned': false,
      },
      body: '# Hello\nBody',
    );

    final parsed = parseMarkdownWithFrontMatter(source);

    expect(parsed.frontMatter['id'], 'note-1');
    expect(parsed.frontMatter['title'], 'Hello');
    expect(parsed.frontMatter['matterId'], isNull);
    expect(parsed.frontMatter['tags'], <dynamic>['one', 'two']);
    expect(parsed.frontMatter['isPinned'], false);
    expect(parsed.body.trim(), '# Hello\nBody');
  });
}
