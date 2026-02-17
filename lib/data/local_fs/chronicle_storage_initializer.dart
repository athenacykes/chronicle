import 'dart:convert';
import 'dart:io';

import '../../core/file_system_utils.dart';
import '../../core/json_utils.dart';
import 'chronicle_layout.dart';

class ChronicleStorageInitializer {
  ChronicleStorageInitializer(this._fileSystemUtils);

  final FileSystemUtils _fileSystemUtils;

  Future<void> ensureInitialized(Directory rootDirectory) async {
    final layout = ChronicleLayout(rootDirectory);

    await _fileSystemUtils.ensureDirectory(rootDirectory);
    await _fileSystemUtils.ensureDirectory(layout.syncDirectory);
    await _fileSystemUtils.ensureDirectory(layout.locksDirectory);
    await _fileSystemUtils.ensureDirectory(layout.orphansDirectory);
    await _fileSystemUtils.ensureDirectory(layout.mattersDirectory);
    await _fileSystemUtils.ensureDirectory(layout.linksDirectory);
    await _fileSystemUtils.ensureDirectory(layout.resourcesDirectory);

    if (!await layout.syncVersionFile.exists()) {
      await _fileSystemUtils.atomicWriteString(layout.syncVersionFile, '1\n');
    }

    if (!await layout.infoFile.exists()) {
      final payload = <String, dynamic>{
        'app': 'chronicle',
        'formatVersion': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
      await _fileSystemUtils.atomicWriteString(
        layout.infoFile,
        prettyJson(payload),
      );
    } else {
      final raw = await layout.infoFile.readAsString();
      json.decode(raw) as Map<String, dynamic>;
    }
  }
}
