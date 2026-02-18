import 'dart:collection';
import 'dart:typed_data';
import 'dart:async';

import 'package:chronicle/data/sync_webdav/webdav_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ensureDirectory keeps base URL path prefix', () async {
    final adapter = _QueueHttpClientAdapter(
      responses: <_AdapterResponse>[_AdapterResponse(statusCode: 405)],
    );
    final dio = Dio(
      BaseOptions(baseUrl: 'https://example.com/webdav/chronicle/'),
    )..httpClientAdapter = adapter;

    final client = DioWebDavClient(
      baseUrl: 'https://unused.example',
      username: 'u',
      password: 'p',
      dio: dio,
    );

    await client.ensureDirectory('locks');

    expect(adapter.requestedUris, hasLength(1));
    expect(
      adapter.requestedUris.single.toString(),
      'https://example.com/webdav/chronicle/locks/',
    );
    expect(adapter.requestedMethods.single, 'MKCOL');
    expect(adapter.requestedDepths.single, isNull);
  });

  test(
    'listFilesRecursively follows 301 redirect and preserves method',
    () async {
      const xml = '''
<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/chronicle/</d:href>
  </d:response>
  <d:response>
    <d:href>/dav/chronicle/orphans/a.md</d:href>
    <d:propstat>
      <d:prop>
        <d:getlastmodified>Tue, 18 Feb 2026 02:01:00 GMT</d:getlastmodified>
        <d:getcontentlength>3</d:getcontentlength>
        <d:getetag>"etag-a"</d:getetag>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
''';

      final adapter = _QueueHttpClientAdapter(
        responses: <_AdapterResponse>[
          _AdapterResponse(
            statusCode: 301,
            headers: <String, List<String>>{
              'location': <String>['https://example.com/dav/chronicle/'],
            },
          ),
          _AdapterResponse(statusCode: 207, body: xml),
        ],
      );
      final dio = Dio(
        BaseOptions(baseUrl: 'https://example.com/webdav/chronicle/'),
      )..httpClientAdapter = adapter;

      final client = DioWebDavClient(
        baseUrl: 'https://unused.example',
        username: 'u',
        password: 'p',
        dio: dio,
      );

      final files = await client.listFilesRecursively('/');

      expect(adapter.requestedMethods, <String>['PROPFIND', 'PROPFIND']);
      expect(adapter.requestedUris, hasLength(2));
      expect(
        adapter.requestedUris.first.toString(),
        'https://example.com/webdav/chronicle/',
      );
      expect(adapter.requestedDepths, <String?>['infinity', 'infinity']);
      expect(files, hasLength(1));
      expect(files.single.path, endsWith('orphans/a.md'));
    },
  );

  test(
    'falls back to recursive Depth=1 when Depth=infinity is forbidden',
    () async {
      const rootXml = '''
<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Chronicle/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Chronicle/orphans/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Chronicle/root.md</d:href>
    <d:propstat><d:prop><d:getcontentlength>5</d:getcontentlength></d:prop></d:propstat>
  </d:response>
</d:multistatus>
''';
      const orphansXml = '''
<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Chronicle/orphans/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Chronicle/orphans/a.md</d:href>
    <d:propstat><d:prop><d:getcontentlength>3</d:getcontentlength></d:prop></d:propstat>
  </d:response>
</d:multistatus>
''';

      final adapter = _QueueHttpClientAdapter(
        responses: <_AdapterResponse>[
          _AdapterResponse(
            statusCode: 403,
            body:
                'PROPFIND requests with a Depth of "infinity" are not allowed.',
          ),
          _AdapterResponse(statusCode: 207, body: rootXml),
          _AdapterResponse(statusCode: 207, body: orphansXml),
        ],
      );
      final dio = Dio(
        BaseOptions(baseUrl: 'https://example.com/dav/Chronicle/'),
      )..httpClientAdapter = adapter;

      final client = DioWebDavClient(
        baseUrl: 'https://unused.example',
        username: 'u',
        password: 'p',
        dio: dio,
        maxRetries: 0,
      );

      final files = await client.listFilesRecursively('/');

      expect(adapter.requestedMethods, <String>[
        'PROPFIND',
        'PROPFIND',
        'PROPFIND',
      ]);
      expect(adapter.requestedDepths, <String?>['infinity', '1', '1']);
      expect(files.map((file) => file.path).toSet(), <String>{
        'root.md',
        'orphans/a.md',
      });
    },
  );

  test('logs full response body for 4xx errors', () async {
    final adapter = _QueueHttpClientAdapter(
      responses: <_AdapterResponse>[
        _AdapterResponse(statusCode: 403, body: 'forbidden: missing privilege'),
      ],
    );
    final dio = Dio(
      BaseOptions(baseUrl: 'https://example.com/webdav/chronicle/'),
    )..httpClientAdapter = adapter;

    final client = DioWebDavClient(
      baseUrl: 'https://unused.example',
      username: 'u',
      password: 'p',
      dio: dio,
      maxRetries: 0,
    );

    final logs = <String>[];
    await runZoned(
      () async {
        await expectLater(
          client.ensureDirectory('locks'),
          throwsA(isA<DioException>()),
        );
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, message) {
          logs.add(message);
        },
      ),
    );

    final joined = logs.join('\n');
    expect(joined, contains('[WebDAV][Error] HTTP 403 MKCOL'));
    expect(joined, contains('forbidden: missing privilege'));
  });
}

class _QueueHttpClientAdapter implements HttpClientAdapter {
  _QueueHttpClientAdapter({required List<_AdapterResponse> responses})
    : _responses = Queue<_AdapterResponse>.from(responses);

  final Queue<_AdapterResponse> _responses;
  final List<Uri> requestedUris = <Uri>[];
  final List<String> requestedMethods = <String>[];
  final List<String?> requestedDepths = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUris.add(options.uri);
    requestedMethods.add(options.method);
    requestedDepths.add(_readHeader(options.headers, 'depth'));

    if (_responses.isEmpty) {
      throw StateError('No queued response for ${options.uri}');
    }

    final response = _responses.removeFirst();
    return ResponseBody.fromString(
      response.body,
      response.statusCode,
      headers: response.headers,
    );
  }

  String? _readHeader(Map<String, dynamic> headers, String key) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == key) {
        return '${entry.value}';
      }
    }
    return null;
  }

  @override
  void close({bool force = false}) {}
}

class _AdapterResponse {
  const _AdapterResponse({
    required this.statusCode,
    this.body = '',
    this.headers = const <String, List<String>>{},
  });

  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;
}
