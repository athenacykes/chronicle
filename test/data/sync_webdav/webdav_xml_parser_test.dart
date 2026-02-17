import 'package:chronicle/data/sync_webdav/webdav_xml_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses namespaced propfind XML into file metadata', () {
    const xml = '''
<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/webdav/chronicle/</d:href>
  </d:response>
  <d:response>
    <d:href>/webdav/chronicle/orphans/a.md</d:href>
    <d:propstat>
      <d:status>HTTP/1.1 200 OK</d:status>
      <d:prop>
        <d:getlastmodified>Tue, 17 Feb 2026 12:00:00 GMT</d:getlastmodified>
        <d:getcontentlength>123</d:getcontentlength>
        <d:getetag>"etag-a"</d:getetag>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/webdav/chronicle/matters/m1/start/b.md</d:href>
    <d:propstat>
      <d:prop>
        <d:getlastmodified>Tue, 17 Feb 2026 13:00:00 GMT</d:getlastmodified>
        <d:getcontentlength>456</d:getcontentlength>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
''';

    final parser = const WebDavXmlParser();
    final files = parser.parsePropfindResponse(
      xmlPayload: xml,
      requestRootPath: '/webdav/chronicle',
    );

    expect(files.length, 2);
    expect(files[0].path, 'orphans/a.md');
    expect(files[0].size, 123);
    expect(files[0].etag, '"etag-a"');
    expect(files[1].path, 'matters/m1/start/b.md');
    expect(files[1].size, 456);
  });

  test('normalizes relative path when request root is /', () {
    const xml = '''
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/orphans/n1.md</d:href>
    <d:propstat><d:prop><d:getcontentlength>1</d:getcontentlength></d:prop></d:propstat>
  </d:response>
</d:multistatus>
''';

    final parser = const WebDavXmlParser();
    final files = parser.parsePropfindResponse(
      xmlPayload: xml,
      requestRootPath: '/',
    );

    expect(files.length, 1);
    expect(files.single.path, 'orphans/n1.md');
  });
}
