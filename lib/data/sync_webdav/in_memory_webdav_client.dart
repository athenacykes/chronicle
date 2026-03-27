import 'dart:convert';

import '../../core/file_hash.dart';
import '../../core/json_utils.dart';
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
    final updatedAt =
        _lockUpdatedAt(normalized, bytes) ?? DateTime.now().toUtc();
    _files[normalized] = _Entry(
      bytes: List<int>.from(bytes),
      updatedAt: updatedAt,
      etag: etag,
    );
    await _maybeUpdateProtocolMetadata(changedPath: normalized);
  }

  @override
  Future<void> deleteFile(String path) async {
    final normalized = _normalize(path);
    _files.remove(normalized);
    await _maybeUpdateProtocolMetadata(changedPath: normalized);
  }

  String _normalize(String path) {
    if (path.startsWith('/')) {
      return path;
    }
    return '/$path';
  }

  DateTime? _lockUpdatedAt(String path, List<int> bytes) {
    if (!path.startsWith('/locks/sync_')) {
      return null;
    }
    try {
      final decoded = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
      final updatedTime = (decoded['updatedTime'] as num?)?.toInt();
      if (updatedTime == null) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(updatedTime, isUtc: true);
    } catch (_) {
      return null;
    }
  }

  Future<void> _maybeUpdateProtocolMetadata({
    required String changedPath,
  }) async {
    if (_isIgnoredProtocolPath(changedPath) || changedPath == '/info.json') {
      return;
    }

    final infoEntry = _files['/info.json'];
    if (infoEntry == null) {
      return;
    }

    Map<String, dynamic> infoJson;
    try {
      infoJson =
          json.decode(utf8.decode(infoEntry.bytes)) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if ((infoJson['syncProtocolVersion'] as num?)?.toInt() != 1) {
      return;
    }

    final revision = '${DateTime.now().toUtc().millisecondsSinceEpoch}';
    final entries = <String, SyncManifestEntry>{};
    for (final fileEntry in _files.entries) {
      final path = fileEntry.key.substring(1);
      if (_isIgnoredProtocolPath(fileEntry.key)) {
        continue;
      }
      final canonicalPath = _canonicalSyncPath(path);
      final nextEntry = SyncManifestEntry(
        canonicalPath: canonicalPath,
        sourcePath: path,
        contentHash: fileEntry.value.etag,
        size: fileEntry.value.bytes.length,
        updatedAt: fileEntry.value.updatedAt,
        isLegacyOrphan: path.startsWith('orphans/'),
      );
      final existing = entries[canonicalPath];
      if (existing == null ||
          (existing.isLegacyOrphan && !nextEntry.isLegacyOrphan)) {
        entries[canonicalPath] = nextEntry;
      }
    }

    final manifest = SyncManifest(
      revision: revision,
      generatedAt: DateTime.now().toUtc(),
      entries: entries,
    );
    final manifestBytes = utf8.encode(prettyJson(manifest.toJson()));
    _files['/.sync/manifest.json'] = _Entry(
      bytes: manifestBytes,
      updatedAt: DateTime.now().toUtc(),
      etag: await sha256ForBytes(manifestBytes),
    );

    infoJson['syncManifestRevision'] = revision;
    final nextInfoBytes = utf8.encode(prettyJson(infoJson));
    _files['/info.json'] = _Entry(
      bytes: nextInfoBytes,
      updatedAt: DateTime.now().toUtc(),
      etag: await sha256ForBytes(nextInfoBytes),
    );
  }

  bool _isIgnoredProtocolPath(String path) {
    return path.startsWith('/.sync/') || path.startsWith('/locks/');
  }

  String _canonicalSyncPath(String path) {
    if (path.startsWith('orphans/')) {
      return 'notebook/root/${path.substring('orphans/'.length)}';
    }
    return path;
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
