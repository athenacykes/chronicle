import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/app_directories.dart';
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

  Future<Map<String, SyncFileState>> load() async {
    final file = await _stateFile();
    if (!await file.exists()) {
      return <String, SyncFileState>{};
    }

    final raw = await file.readAsString();
    final decoded = json.decode(raw) as Map<String, dynamic>;
    final states = <String, SyncFileState>{};
    for (final entry in decoded.entries) {
      states[entry.key] = SyncFileState.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    return states;
  }

  Future<void> save(Map<String, SyncFileState> states) async {
    final file = await _stateFile();
    final jsonMap = <String, dynamic>{
      for (final entry in states.entries) entry.key: entry.value.toJson(),
    };

    await _fileSystemUtils.atomicWriteString(
      file,
      const JsonEncoder.withIndent('  ').convert(jsonMap),
    );
  }

  Future<File> _stateFile() async {
    final appSupport = await _appDirectories.appSupportDirectory();
    await _fileSystemUtils.ensureDirectory(appSupport);
    return File(p.join(appSupport.path, 'chronicle_sync_state.json'));
  }
}
