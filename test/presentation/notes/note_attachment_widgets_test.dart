import 'package:chronicle/presentation/notes/note_attachment_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects image attachment extensions', () {
    expect(isImageAttachmentPath('resources/a/photo.png'), isTrue);
    expect(isImageAttachmentPath('resources/a/photo.JPG'), isTrue);
    expect(isImageAttachmentPath('resources/a/doc.pdf'), isFalse);
  });

  test('formats attachment helpers consistently', () {
    expect(
      attachmentDisplayName('resources/a/report.final.pdf'),
      'report.final.pdf',
    );
    expect(formatAttachmentBytes(999), '999 B');
    expect(formatAttachmentBytes(2048), '2.0 KB');
    expect(formatAttachmentBytes(5 * 1024 * 1024), '5.0 MB');
  });
}
