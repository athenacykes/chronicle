import '../../core/markdown_front_matter.dart';
import '../../domain/entities/note.dart';

class NoteFileCodec {
  const NoteFileCodec();

  String encode(Note note) {
    return formatMarkdownWithFrontMatter(
      frontMatter: note.toFrontMatterMap(),
      body: note.content,
    );
  }

  Note decode(String raw) {
    final parsed = parseMarkdownWithFrontMatter(raw);
    return Note.fromFrontMatterMap(parsed.frontMatter, parsed.body);
  }
}
