import '../../core/file_hash.dart';
import 'webdav_client.dart';
import 'webdav_types.dart';

class InMemoryWebDavClient implements WebDavClient {
  InMemoryWebDavClient();

  final Map<String, _Entry> _files = <String, _Entry>{};
  final Set<String> _directories = <String>{'/'};

  @override
  Future<void> ensureDirectory(String path) async {
    var current = '';
    final normalized = _normalize(path);
    final segments = normalized.split('/').where((value) => value.isNotEmpty);
    for (final segment in segments) {
      current = '$current/$segment';
      _directories.add(current);
    }
  }

  @override
  Future<List<WebDavFileMetadata>> listFilesRecursively(String rootPath) async {
    final normalized = _normalize(rootPath);
    final out = <WebDavFileMetadata>[];

    for (final entry in _files.entries) {
      final path = entry.key;
      if (!path.startsWith(normalized)) {
        continue;
      }
      out.add(
        WebDavFileMetadata(
          path: path.startsWith('/') ? path.substring(1) : path,
          updatedAt: entry.value.updatedAt,
          size: entry.value.bytes.length,
          etag: entry.value.etag,
        ),
      );
    }

    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  @override
  Future<List<int>> downloadFile(String path) async {
    final normalized = _normalize(path);
    final entry = _files[normalized];
    if (entry == null) {
      throw Exception('File not found: $path');
    }
    return List<int>.from(entry.bytes);
  }

  @override
  Future<void> uploadFile(String path, List<int> bytes) async {
    final normalized = _normalize(path);
    final etag = await sha256ForBytes(bytes);
    _files[normalized] = _Entry(
      bytes: List<int>.from(bytes),
      updatedAt: DateTime.now().toUtc(),
      etag: etag,
    );
  }

  @override
  Future<void> deleteFile(String path) async {
    _files.remove(_normalize(path));
  }

  String _normalize(String path) {
    if (path.startsWith('/')) {
      return path;
    }
    return '/$path';
  }
}

class _Entry {
  const _Entry({
    required this.bytes,
    required this.updatedAt,
    required this.etag,
  });

  final List<int> bytes;
  final DateTime updatedAt;
  final String etag;
}
