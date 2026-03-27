import 'dart:convert';
import 'dart:io';

import '../../core/file_system_utils.dart';
import '../local_fs/chronicle_layout.dart';

class LocalConflictHistoryStore {
  LocalConflictHistoryStore({required FileSystemUtils fileSystemUtils})
    : _fileSystemUtils = fileSystemUtils;

  final FileSystemUtils _fileSystemUtils;

  Future<Set<String>> load({
    required ChronicleLayout layout,
    required String namespace,
  }) async {
    final file = _historyFile(layout);
    if (!await file.exists()) {
      return <String>{};
    }

    final decoded = await _readEnvelope(file);
    if (decoded.namespace != namespace) {
      await _fileSystemUtils.deleteIfExists(file);
      return <String>{};
    }
    return decoded.fingerprints.toSet();
  }

  Future<void> record({
    required ChronicleLayout layout,
    required String namespace,
    required String fingerprint,
  }) async {
    final next = await load(layout: layout, namespace: namespace);
    if (next.contains(fingerprint)) {
      return;
    }
    next.add(fingerprint);
    await _save(layout: layout, namespace: namespace, fingerprints: next);
  }

  Future<void> clear({
    required ChronicleLayout layout,
    String? namespace,
  }) async {
    final file = _historyFile(layout);
    if (!await file.exists()) {
      return;
    }
    if (namespace == null) {
      await _fileSystemUtils.deleteIfExists(file);
      return;
    }

    final decoded = await _readEnvelope(file);
    if (decoded.namespace == namespace) {
      await _fileSystemUtils.deleteIfExists(file);
    }
  }

  File _historyFile(ChronicleLayout layout) {
    return File('${layout.syncDirectory.path}/conflict_history.json');
  }

  Future<void> _save({
    required ChronicleLayout layout,
    required String namespace,
    required Set<String> fingerprints,
  }) {
    final jsonMap = <String, dynamic>{
      'namespace': namespace,
      'fingerprints': fingerprints.toList()..sort(),
    };
    return _fileSystemUtils.atomicWriteString(
      _historyFile(layout),
      const JsonEncoder.withIndent('  ').convert(jsonMap),
    );
  }

  Future<_ConflictHistoryEnvelope> _readEnvelope(File file) async {
    try {
      final raw = await file.readAsString();
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final namespace = (decoded['namespace'] as String?) ?? '';
      final fingerprints =
          (decoded['fingerprints'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => '$value')
              .where((value) => value.isNotEmpty)
              .toList();
      return _ConflictHistoryEnvelope(
        namespace: namespace,
        fingerprints: fingerprints,
      );
    } catch (_) {
      return const _ConflictHistoryEnvelope(
        namespace: '',
        fingerprints: <String>[],
      );
    }
  }
}

class _ConflictHistoryEnvelope {
  const _ConflictHistoryEnvelope({
    required this.namespace,
    required this.fingerprints,
  });

  final String namespace;
  final List<String> fingerprints;
}
