import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
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
       _retryBaseDelay = retryBaseDelay;

  final Dio _dio;
  final WebDavXmlParser _xmlParser;
  final Duration _operationTimeout;
  final int _maxRetries;
  final Duration _retryBaseDelay;
  final Random _random = Random();

  @override
  Future<void> ensureDirectory(String path) async {
    final normalized = _normalize(path);
    final segments = normalized.split('/').where((value) => value.isNotEmpty);
    var current = '';

    for (final segment in segments) {
      current = '$current/$segment';
      await _withRetry<void>(
        action: () async {
          await _dio.request<void>(
            current,
            options: Options(
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
            ),
          );
        },
      );
    }
  }

  @override
  Future<List<WebDavFileMetadata>> listFilesRecursively(String rootPath) async {
    final normalized = _normalize(rootPath);

    final response = await _withRetry<Response<String>>(
      action: () {
        return _dio.request<String>(
          normalized,
          options: Options(
            method: 'PROPFIND',
            headers: <String, Object>{
              'Depth': 'infinity',
              'Content-Type': 'application/xml',
            },
            responseType: ResponseType.plain,
            validateStatus: (code) {
              if (code == null) {
                return false;
              }
              return code == 200 || code == 207;
            },
          ),
          data:
              '<?xml version="1.0"?>'
              '<d:propfind xmlns:d="DAV:"><d:prop>'
              '<d:getlastmodified/><d:getcontentlength/><d:getetag/>'
              '</d:prop></d:propfind>',
        );
      },
    );

    final payload = response.data ?? '';
    if (payload.trim().isEmpty) {
      return <WebDavFileMetadata>[];
    }

    try {
      return _xmlParser.parsePropfindResponse(
        xmlPayload: payload,
        requestRootPath: normalized,
      );
    } catch (error) {
      throw FormatException('Failed to parse PROPFIND XML: $error');
    }
  }

  @override
  Future<List<int>> downloadFile(String path) async {
    final normalized = _normalize(path);
    final response = await _withRetry<Response<List<int>>>(
      action: () {
        return _dio.get<List<int>>(
          normalized,
          options: Options(
            responseType: ResponseType.bytes,
            validateStatus: (code) {
              if (code == null) {
                return false;
              }
              return code >= 200 && code < 300;
            },
          ),
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
        await _dio.put<void>(
          normalized,
          data: Stream.value(bytes),
          options: Options(
            headers: <String, Object>{
              'Content-Type': 'application/octet-stream',
            },
            validateStatus: (code) {
              if (code == null) {
                return false;
              }
              return code >= 200 && code < 300;
            },
          ),
        );
      },
    );
  }

  @override
  Future<void> deleteFile(String path) async {
    final normalized = _normalize(path);
    await _withRetry<void>(
      action: () async {
        await _dio.delete<void>(
          normalized,
          options: Options(
            validateStatus: (code) {
              if (code == null) {
                return false;
              }
              return (code >= 200 && code < 300) || code == 404;
            },
          ),
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

  String _normalize(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '/';
    }
    if (trimmed.startsWith('/')) {
      return trimmed;
    }
    return '/$trimmed';
  }
}
