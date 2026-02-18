import 'dart:convert';
import 'dart:io';

import '../../core/file_system_utils.dart';
import '../../core/json_utils.dart';
import 'chronicle_layout.dart';

class ChronicleStorageInitializer {
  ChronicleStorageInitializer(this._fileSystemUtils);

  static const int _formatVersion = 2;

  final FileSystemUtils _fileSystemUtils;
  Future<void> _initializationChain = Future<void>.value();

  Future<void> ensureInitialized(Directory rootDirectory) {
    final next = _initializationChain.then<void>(
      (_) => _ensureInitializedInternal(rootDirectory),
    );
    _initializationChain = next.catchError((_) {});
    return next;
  }

  Future<void> _ensureInitializedInternal(Directory rootDirectory) async {
    if (await _needsReset(rootDirectory)) {
      await _wipeRoot(rootDirectory);
    }

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

    final existingCreatedAt = await _existingCreatedAt(layout.infoFile);
    final payload = <String, dynamic>{
      'app': 'chronicle',
      'formatVersion': _formatVersion,
      'createdAt':
          existingCreatedAt ?? DateTime.now().toUtc().toIso8601String(),
    };
    await _fileSystemUtils.atomicWriteString(
      layout.infoFile,
      prettyJson(payload),
    );
  }

  Future<bool> _needsReset(Directory rootDirectory) async {
    if (!await rootDirectory.exists()) {
      return false;
    }

    final infoFile = ChronicleLayout(rootDirectory).infoFile;
    if (!await infoFile.exists()) {
      return false;
    }

    try {
      final raw = await infoFile.readAsString();
      final map = json.decode(raw) as Map<String, dynamic>;
      final version = (map['formatVersion'] as num?)?.toInt();
      return version != _formatVersion;
    } catch (_) {
      return true;
    }
  }

  Future<void> _wipeRoot(Directory rootDirectory) async {
    if (!await rootDirectory.exists()) {
      return;
    }
    await for (final entity in rootDirectory.list(followLinks: false)) {
      await entity.delete(recursive: true);
    }
  }

  Future<String?> _existingCreatedAt(File infoFile) async {
    if (!await infoFile.exists()) {
      return null;
    }
    try {
      final raw = await infoFile.readAsString();
      final map = json.decode(raw) as Map<String, dynamic>;
      final createdAt = map['createdAt'];
      if (createdAt is String && createdAt.trim().isNotEmpty) {
        return createdAt;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
