import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/app_directories.dart';
import '../../core/file_hash.dart';
import '../../core/file_system_utils.dart';
import 'webdav_types.dart';

class LocalSyncMetadataStore {
  LocalSyncMetadataStore({
    required AppDirectories appDirectories,
    required FileSystemUtils fileSystemUtils,
  }) : _appDirectories = appDirectories,
       _fileSystemUtils = fileSystemUtils;

  final AppDirectories _appDirectories;
  final FileSystemUtils _fileSystemUtils;

  Future<LocalSyncMetadataSnapshot> load({required String namespace}) async {
    final file = await _stateFile();
    if (!await file.exists()) {
      return LocalSyncMetadataSnapshot.empty;
    }

    final decoded = await _readEnvelope(file);
    if (decoded.namespace != namespace) {
      await _fileSystemUtils.deleteIfExists(file);
      return LocalSyncMetadataSnapshot.empty;
    }

    return LocalSyncMetadataSnapshot.fromJson(decoded.snapshot);
  }

  Future<void> save({
    required String namespace,
    required LocalSyncMetadataSnapshot snapshot,
  }) async {
    final file = await _stateFile();
    final jsonMap = <String, dynamic>{
      'namespace': namespace,
      'snapshot': snapshot.toJson(),
    };

    await _fileSystemUtils.atomicWriteString(
      file,
      const JsonEncoder.withIndent('  ').convert(jsonMap),
    );
  }

  Future<void> clear({String? namespace}) async {
    final file = await _stateFile();
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

  String buildNamespace({
    required String storageRootPath,
    required int localFormatVersion,
  }) {
    return sha256ForString('$storageRootPath|$localFormatVersion');
  }

  Future<File> _stateFile() async {
    final appSupport = await _appDirectories.appSupportDirectory();
    await _fileSystemUtils.ensureDirectory(appSupport);
    return File(p.join(appSupport.path, 'chronicle_local_sync_metadata.json'));
  }

  Future<_MetadataEnvelope> _readEnvelope(File file) async {
    try {
      final raw = await file.readAsString();
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final namespace = (decoded['namespace'] as String?) ?? '';
      final snapshot = decoded['snapshot'];
      if (snapshot is! Map<String, dynamic>) {
        return const _MetadataEnvelope(
          namespace: '',
          snapshot: <String, dynamic>{},
        );
      }
      return _MetadataEnvelope(namespace: namespace, snapshot: snapshot);
    } catch (_) {
      return const _MetadataEnvelope(
        namespace: '',
        snapshot: <String, dynamic>{},
      );
    }
  }
}

class _MetadataEnvelope {
  const _MetadataEnvelope({required this.namespace, required this.snapshot});

  final String namespace;
  final Map<String, dynamic> snapshot;
}
