import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'webdav_types.dart';
import 'webdav_xml_parser.dart';

abstract class WebDavClient {
  Future<void> ensureDirectory(String path);
  Future<List<WebDavFileMetadata>> listFilesRecursively(String rootPath);
  Future<List<int>> downloadFile(String path);
  Future<void> uploadFile(String path, List<int> bytes);
  Future<void> deleteFile(String path);
}

class DioWebDavClient implements WebDavClient {
  DioWebDavClient({
    required String baseUrl,
    required String username,
    required String password,
    Dio? dio,
    WebDavXmlParser? xmlParser,
    Duration operationTimeout = const Duration(seconds: 30),
    int maxRetries = 3,
    Duration retryBaseDelay = const Duration(milliseconds: 500),
    int maxRedirects = 5,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: _normalizeBaseUrl(baseUrl),
               connectTimeout: const Duration(seconds: 10),
               sendTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(seconds: 30),
               headers: <String, Object>{
                 'Authorization':
                     'Basic ${base64Encode(utf8.encode('$username:$password'))}',
               },
             ),
           ),
       _xmlParser = xmlParser ?? const WebDavXmlParser(),
       _operationTimeout = operationTimeout,
       _maxRetries = maxRetries,
       _retryBaseDelay = retryBaseDelay,
       _maxRedirects = maxRedirects;

  final Dio _dio;
  final WebDavXmlParser _xmlParser;
  final Duration _operationTimeout;
  final int _maxRetries;
  final Duration _retryBaseDelay;
  final int _maxRedirects;
  final Random _random = Random();
  static const String _propfindRequestBody =
      '<?xml version="1.0"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:getlastmodified/><d:getcontentlength/><d:getetag/>'
      '<d:resourcetype/>'
      '</d:prop></d:propfind>';

  @override
  Future<void> ensureDirectory(String path) async {
    final normalized = _normalize(path);
    final segments = normalized.split('/').where((value) => value.isNotEmpty);
    var current = '';

    for (final segment in segments) {
      current = current.isEmpty ? segment : '$current/$segment';
      await _withRetry<void>(
        action: () async {
          await _requestWithRedirect<void>(
            path: '$current/',
            method: 'MKCOL',
            validateStatus: (code) {
              if (code == null) {
                return false;
              }
              return code == 200 ||
                  code == 201 ||
                  code == 204 ||
                  code == 207 ||
                  code == 405;
            },
          );
        },
      );
    }
  }

  @override
  Future<List<WebDavFileMetadata>> listFilesRecursively(String rootPath) async {
    final normalized = _normalize(rootPath, isDirectory: true);
    try {
      final response = await _propfind(path: normalized, depth: 'infinity');
      return _parseFilesFromPropfindResponse(response);
    } on DioException catch (error) {
      if (!_isDepthInfinityForbidden(error)) {
        rethrow;
      }

      // ignore: avoid_print
      print(
        '[WebDAV] Server rejected Depth=infinity PROPFIND; '
        'falling back to recursive Depth=1 traversal.',
      );
      return _listFilesRecursivelyWithDepthOne(normalized);
    }
  }

  @override
  Future<List<int>> downloadFile(String path) async {
    final normalized = _normalize(path);
    final response = await _withRetry<Response<List<int>>>(
      action: () {
        return _requestWithRedirect<List<int>>(
          path: normalized,
          method: 'GET',
          responseType: ResponseType.bytes,
          validateStatus: (code) {
            if (code == null) {
              return false;
            }
            return code >= 200 && code < 300;
          },
        );
      },
    );
    return response.data ?? <int>[];
  }

  @override
  Future<void> uploadFile(String path, List<int> bytes) async {
    final normalized = _normalize(path);
    final parent = normalized.split('/')..removeLast();
    if (parent.isNotEmpty) {
      await ensureDirectory(parent.join('/'));
    }

    await _withRetry<void>(
      action: () async {
        await _requestWithRedirect<void>(
          path: normalized,
          method: 'PUT',
          data: bytes,
          headers: <String, Object>{'Content-Type': 'application/octet-stream'},
          validateStatus: (code) {
            if (code == null) {
              return false;
            }
            return code >= 200 && code < 300;
          },
        );
      },
    );
  }

  @override
  Future<void> deleteFile(String path) async {
    final normalized = _normalize(path);
    await _withRetry<void>(
      action: () async {
        await _requestWithRedirect<void>(
          path: normalized,
          method: 'DELETE',
          validateStatus: (code) {
            if (code == null) {
              return false;
            }
            return (code >= 200 && code < 300) || code == 404;
          },
        );
      },
    );
  }

  Future<T> _withRetry<T>({required Future<T> Function() action}) async {
    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        return await action().timeout(_operationTimeout);
      } catch (error) {
        _logHttpErrorBody(error);
        final shouldRetry = _isRetryable(error);
        if (!shouldRetry || attempt > _maxRetries) {
          rethrow;
        }

        final backoffMs =
            _retryBaseDelay.inMilliseconds * pow(2, attempt - 1).toInt();
        final jitterMs = _random.nextInt(200);
        final wait = Duration(milliseconds: backoffMs + jitterMs);
        await Future<void>.delayed(wait);
      }
    }
  }

  bool _isRetryable(Object error) {
    if (error is TimeoutException || error is SocketException) {
      return true;
    }

    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return true;
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode;
          if (code == null) {
            return true;
          }
          return code == 429 || (code >= 500 && code < 600);
        case DioExceptionType.cancel:
        case DioExceptionType.badCertificate:
        case DioExceptionType.unknown:
          return false;
      }
    }

    return false;
  }

  void _logHttpErrorBody(Object error) {
    if (error is! DioException) {
      return;
    }

    final response = error.response;
    final statusCode = response?.statusCode;
    if (response == null ||
        statusCode == null ||
        statusCode < 400 ||
        statusCode >= 600) {
      return;
    }

    final method = response.requestOptions.method;
    final uri = response.requestOptions.uri;
    final body = _responseBodyAsString(response.data);
    final isRecoverable = _isDepthInfinityForbidden(error);
    final level = isRecoverable ? '[WebDAV][Recoverable]' : '[WebDAV][Error]';
    final hint = isRecoverable
        ? '\n[WebDAV] This will be retried with Depth=1 traversal.'
        : '';

    // ignore: avoid_print
    print(
      '$level HTTP $statusCode $method $uri\n'
      '[WebDAV] Full response body:\n$body$hint',
    );
  }

  String _responseBodyAsString(Object? data) {
    if (data == null) {
      return '<empty>';
    }

    if (data is String) {
      return data;
    }

    if (data is Uint8List) {
      return utf8.decode(data, allowMalformed: true);
    }

    if (data is List<int>) {
      return utf8.decode(data, allowMalformed: true);
    }

    if (data is Map || data is List) {
      try {
        return const JsonEncoder.withIndent('  ').convert(data);
      } catch (_) {
        return data.toString();
      }
    }

    return data.toString();
  }

  Future<List<WebDavFileMetadata>> _listFilesRecursivelyWithDepthOne(
    String normalizedRootPath,
  ) async {
    // ignore: avoid_print
    print('[WebDAV] Starting recursive Depth=1 traversal.');
    final rootResponse = await _propfind(path: normalizedRootPath, depth: '1');
    final rootRequestPath = rootResponse.realUri.path.isEmpty
        ? '/'
        : rootResponse.realUri.path;

    final filesByPath = <String, WebDavFileMetadata>{};
    final visitedDirectories = <String>{};
    final directories = Queue<String>();

    final rootEntries = _parseEntriesFromPropfindResponse(
      rootResponse,
      requestRootPath: rootRequestPath,
    );
    _accumulatePropfindEntries(
      entries: rootEntries,
      currentDirectory: '',
      filesByPath: filesByPath,
      directories: directories,
      visitedDirectories: visitedDirectories,
    );

    while (directories.isNotEmpty) {
      final nextDir = directories.removeFirst();
      final response = await _propfind(path: nextDir, depth: '1');
      final entries = _parseEntriesFromPropfindResponse(
        response,
        requestRootPath: rootRequestPath,
      );
      _accumulatePropfindEntries(
        entries: entries,
        currentDirectory: nextDir,
        filesByPath: filesByPath,
        directories: directories,
        visitedDirectories: visitedDirectories,
      );
    }

    // ignore: avoid_print
    print(
      '[WebDAV] Depth=1 traversal completed. '
      'Discovered ${filesByPath.length} remote files.',
    );
    return filesByPath.values.toList();
  }

  void _accumulatePropfindEntries({
    required List<WebDavPropfindEntry> entries,
    required String currentDirectory,
    required Map<String, WebDavFileMetadata> filesByPath,
    required Queue<String> directories,
    required Set<String> visitedDirectories,
  }) {
    final currentDirectoryNormalized = _normalize(
      currentDirectory,
      isDirectory: true,
    );
    for (final entry in entries) {
      if (entry.path.isEmpty) {
        continue;
      }

      if (entry.isDirectory) {
        final directoryPath = _normalize(entry.path, isDirectory: true);
        if (directoryPath.isEmpty ||
            directoryPath == currentDirectoryNormalized) {
          continue;
        }
        if (visitedDirectories.add(directoryPath)) {
          directories.add(directoryPath);
        }
        continue;
      }

      filesByPath[entry.path] = WebDavFileMetadata(
        path: entry.path,
        updatedAt: entry.updatedAt,
        size: entry.size,
        etag: entry.etag,
      );
    }
  }

  Future<Response<String>> _propfind({
    required String path,
    required String depth,
  }) {
    return _withRetry<Response<String>>(
      action: () {
        return _requestWithRedirect<String>(
          path: path,
          method: 'PROPFIND',
          headers: <String, Object>{
            'Depth': depth,
            'Content-Type': 'application/xml',
          },
          responseType: ResponseType.plain,
          validateStatus: (code) {
            if (code == null) {
              return false;
            }
            return code == 200 || code == 207;
          },
          data: _propfindRequestBody,
        );
      },
    );
  }

  List<WebDavFileMetadata> _parseFilesFromPropfindResponse(
    Response<String> response,
  ) {
    final payload = response.data ?? '';
    if (payload.trim().isEmpty) {
      return <WebDavFileMetadata>[];
    }

    try {
      final requestRootPath = response.realUri.path.isEmpty
          ? '/'
          : response.realUri.path;
      return _xmlParser.parsePropfindResponse(
        xmlPayload: payload,
        requestRootPath: requestRootPath,
      );
    } catch (error) {
      throw FormatException('Failed to parse PROPFIND XML: $error');
    }
  }

  List<WebDavPropfindEntry> _parseEntriesFromPropfindResponse(
    Response<String> response, {
    required String requestRootPath,
  }) {
    final payload = response.data ?? '';
    if (payload.trim().isEmpty) {
      return <WebDavPropfindEntry>[];
    }

    try {
      return _xmlParser.parsePropfindEntries(
        xmlPayload: payload,
        requestRootPath: requestRootPath,
      );
    } catch (error) {
      throw FormatException('Failed to parse PROPFIND XML: $error');
    }
  }

  bool _isDepthInfinityForbidden(DioException error) {
    final response = error.response;
    final status = response?.statusCode;
    if (status == null || status < 400 || status >= 500) {
      return false;
    }

    final body = _responseBodyAsString(response?.data).toLowerCase();
    return body.contains('depth') && body.contains('infinity');
  }

  Future<Response<T>> _requestWithRedirect<T>({
    required String path,
    required String method,
    required bool Function(int?) validateStatus,
    Map<String, Object>? headers,
    ResponseType? responseType,
    Object? data,
  }) async {
    var currentPath = path;
    for (var redirect = 0; redirect <= _maxRedirects; redirect++) {
      final response = await _dio.request<T>(
        currentPath,
        options: Options(
          method: method,
          headers: headers,
          responseType: responseType,
          followRedirects: false,
          validateStatus: (code) {
            if (_isRedirectStatus(code)) {
              return true;
            }
            return validateStatus(code);
          },
        ),
        data: data,
      );

      if (!_isRedirectStatus(response.statusCode)) {
        return response;
      }

      if (redirect >= _maxRedirects) {
        throw DioException.badResponse(
          statusCode: response.statusCode ?? 0,
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.trim().isEmpty) {
        throw DioException.badResponse(
          statusCode: response.statusCode ?? 0,
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      currentPath = _resolveRedirectPath(currentPath, location);
    }

    throw StateError('Redirect loop did not complete');
  }

  String _resolveRedirectPath(String currentPath, String location) {
    final rawLocation = location.trim();
    final inferredAbsolute =
        !_isAbsoluteUrl(rawLocation) &&
        !rawLocation.startsWith('/') &&
        currentPath.isEmpty &&
        !rawLocation.startsWith('?') &&
        !rawLocation.startsWith('./') &&
        !rawLocation.startsWith('../');
    final effectiveLocation = inferredAbsolute ? '/$rawLocation' : rawLocation;

    final currentUri = _resolveRequestUri(currentPath);
    final resolved = currentUri.resolve(effectiveLocation);
    final baseUri = Uri.parse(_dio.options.baseUrl);

    if (_sameOrigin(baseUri, resolved)) {
      final basePath = _normalizedAbsolutePath(baseUri.path, isDirectory: true);
      final targetPath = _normalizedAbsolutePath(resolved.path);

      if (basePath != '/' && targetPath.startsWith(basePath)) {
        final relative = targetPath.substring(basePath.length);
        return _withQuery(relative, resolved.query);
      }
      return _withQuery(targetPath, resolved.query);
    }

    return resolved.toString();
  }

  Uri _resolveRequestUri(String path) {
    if (_isAbsoluteUrl(path)) {
      return Uri.parse(path);
    }
    return Uri.parse(_dio.options.baseUrl).resolve(path);
  }

  bool _sameOrigin(Uri a, Uri b) {
    return a.scheme == b.scheme &&
        a.host == b.host &&
        _effectivePort(a) == _effectivePort(b);
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort) {
      return uri.port;
    }
    return uri.scheme == 'https' ? 443 : 80;
  }

  bool _isRedirectStatus(int? code) {
    if (code == null) {
      return false;
    }
    return code == 301 || code == 302 || code == 307 || code == 308;
  }

  String _withQuery(String path, String query) {
    if (query.isEmpty) {
      return path;
    }
    if (path.isEmpty) {
      return '?$query';
    }
    return '$path?$query';
  }

  String _normalize(String value, {bool isDirectory = false}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return '';
    }
    if (_isAbsoluteUrl(trimmed)) {
      return trimmed;
    }
    return _normalizePath(trimmed, isDirectory: isDirectory);
  }

  String _normalizePath(String value, {bool isDirectory = false}) {
    var normalized = value.replaceAll('\\', '/').trim();
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    while (normalized.contains('//')) {
      normalized = normalized.replaceAll('//', '/');
    }
    if (isDirectory && normalized.isNotEmpty && !normalized.endsWith('/')) {
      normalized = '$normalized/';
    }
    return normalized;
  }

  String _normalizedAbsolutePath(String value, {bool isDirectory = false}) {
    var normalized = value.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) {
      return '/';
    }
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    while (normalized.contains('//')) {
      normalized = normalized.replaceAll('//', '/');
    }
    if (isDirectory && !normalized.endsWith('/')) {
      normalized = '$normalized/';
    }
    return normalized;
  }

  static String _normalizeBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    final uri = Uri.parse(trimmed);
    var path = uri.path;
    if (!path.endsWith('/')) {
      path = '$path/';
    }
    return uri.replace(path: path).toString();
  }

  bool _isAbsoluteUrl(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }
}
