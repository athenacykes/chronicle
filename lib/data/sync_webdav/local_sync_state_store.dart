import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/app_directories.dart';
import '../../core/file_hash.dart';
import '../../core/file_system_utils.dart';
import 'webdav_types.dart';

class LocalSyncStateStore {
  LocalSyncStateStore({
    required AppDirectories appDirectories,
    required FileSystemUtils fileSystemUtils,
  }) : _appDirectories = appDirectories,
       _fileSystemUtils = fileSystemUtils;

  final AppDirectories _appDirectories;
  final FileSystemUtils _fileSystemUtils;

  Future<Map<String, SyncFileState>> load({required String namespace}) async {
    final file = await _stateFile();
    if (!await file.exists()) {
      return <String, SyncFileState>{};
    }

    final decoded = await _readEnvelope(file);
    if (decoded.namespace != namespace) {
      await _fileSystemUtils.deleteIfExists(file);
      return <String, SyncFileState>{};
    }

    final states = <String, SyncFileState>{};
    for (final entry in decoded.states.entries) {
      states[entry.key] = SyncFileState.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    return states;
  }

  Future<void> save({
    required String namespace,
    required Map<String, SyncFileState> states,
  }) async {
    final file = await _stateFile();
    final stateMap = <String, dynamic>{
      for (final entry in states.entries) entry.key: entry.value.toJson(),
    };

    final jsonMap = <String, dynamic>{
      'namespace': namespace,
      'states': stateMap,
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
    required String syncTargetUrl,
    required String username,
    required String storageRootPath,
    required int localFormatVersion,
  }) {
    final raw = '$syncTargetUrl|$username|$storageRootPath|$localFormatVersion';
    return sha256ForString(raw);
  }

  Future<File> _stateFile() async {
    final appSupport = await _appDirectories.appSupportDirectory();
    await _fileSystemUtils.ensureDirectory(appSupport);
    return File(p.join(appSupport.path, 'chronicle_sync_state.json'));
  }

  Future<_SyncStateEnvelope> _readEnvelope(File file) async {
    try {
      final raw = await file.readAsString();
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final namespace = (decoded['namespace'] as String?) ?? '';
      final states = decoded['states'];
      if (states is! Map<String, dynamic>) {
        return const _SyncStateEnvelope(
          namespace: '',
          states: <String, dynamic>{},
        );
      }
      return _SyncStateEnvelope(namespace: namespace, states: states);
    } catch (_) {
      return const _SyncStateEnvelope(
        namespace: '',
        states: <String, dynamic>{},
      );
    }
  }
}

class _SyncStateEnvelope {
  const _SyncStateEnvelope({required this.namespace, required this.states});

  final String namespace;
  final Map<String, dynamic> states;
}
