import 'dart:io';

import 'package:xml/xml.dart';

import 'webdav_types.dart';

class WebDavXmlParser {
  const WebDavXmlParser();

  List<WebDavPropfindEntry> parsePropfindEntries({
    required String xmlPayload,
    required String requestRootPath,
  }) {
    final document = XmlDocument.parse(xmlPayload);
    final responses = _allElements(
      document,
    ).where((element) => _localName(element) == 'response');

    final entries = <WebDavPropfindEntry>[];
    for (final response in responses) {
      final href = _readText(response, 'href');
      if (href == null) {
        continue;
      }

      final decodedHref = Uri.decodeFull(href).trim();
      if (decodedHref.isEmpty) {
        continue;
      }

      final relativePath = _toRelativePath(decodedHref, requestRootPath);
      final isDirectory =
          decodedHref.endsWith('/') || _hasElement(response, 'collection');

      final lastModified = _readText(response, 'getlastmodified');
      final contentLength = _readText(response, 'getcontentlength');
      final etag = _readText(response, 'getetag');

      entries.add(
        WebDavPropfindEntry(
          path: relativePath,
          isDirectory: isDirectory,
          updatedAt: _parseHttpDate(lastModified),
          size: int.tryParse((contentLength ?? '').trim()) ?? 0,
          etag: etag?.trim().isEmpty == true ? null : etag?.trim(),
        ),
      );
    }

    return entries;
  }

  List<WebDavFileMetadata> parsePropfindResponse({
    required String xmlPayload,
    required String requestRootPath,
  }) {
    final entries = parsePropfindEntries(
      xmlPayload: xmlPayload,
      requestRootPath: requestRootPath,
    );
    final files = <WebDavFileMetadata>[];
    for (final entry in entries) {
      if (entry.isDirectory || entry.path.isEmpty) {
        continue;
      }
      files.add(
        WebDavFileMetadata(
          path: entry.path,
          updatedAt: entry.updatedAt,
          size: entry.size,
          etag: entry.etag,
        ),
      );
    }

    return files;
  }

  String _localName(XmlElement element) {
    final qualified = element.name.qualified;
    final split = qualified.split(':');
    return split.length > 1 ? split.last : qualified;
  }

  String? _readText(XmlElement root, String localName) {
    for (final element in _allElements(root)) {
      if (_localName(element) == localName) {
        return element.innerText;
      }
    }
    return null;
  }

  bool _hasElement(XmlElement root, String localName) {
    for (final element in _allElements(root)) {
      if (_localName(element) == localName) {
        return true;
      }
    }
    return false;
  }

  DateTime _parseHttpDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    try {
      return HttpDate.parse(value).toUtc();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
  }

  String _toRelativePath(String href, String requestRootPath) {
    final root = _normalizeForComparison(requestRootPath);
    final path = _normalizeForComparison(href);

    if (root == '/') {
      final trimmed = path.startsWith('/') ? path.substring(1) : path;
      return _sanitizeRelative(trimmed);
    }

    if (path.startsWith(root)) {
      final suffix = path.substring(root.length);
      final trimmed = suffix.startsWith('/') ? suffix.substring(1) : suffix;
      return _sanitizeRelative(trimmed);
    }

    final trimmed = path.startsWith('/') ? path.substring(1) : path;
    return _sanitizeRelative(trimmed);
  }

  String _normalizeForComparison(String input) {
    var path = input.trim();
    if (path.isEmpty) {
      return '/';
    }

    try {
      final uri = Uri.parse(path);
      if (uri.hasScheme || uri.hasAuthority) {
        path = uri.path;
      }
    } catch (_) {
      // Keep original if uri parsing fails.
    }

    if (!path.startsWith('/')) {
      path = '/$path';
    }

    while (path.contains('//')) {
      path = path.replaceAll('//', '/');
    }

    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    return path;
  }

  String _sanitizeRelative(String value) {
    var output = value.replaceAll('\\', '/').trim();
    while (output.startsWith('/')) {
      output = output.substring(1);
    }
    return output;
  }

  Iterable<XmlElement> _allElements(XmlNode node) sync* {
    for (final descendant in node.descendants) {
      if (descendant is XmlElement) {
        yield descendant;
      }
    }
  }
}
