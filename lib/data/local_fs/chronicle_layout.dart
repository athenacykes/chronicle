import 'dart:io';

import 'package:path/path.dart' as p;

class ChronicleLayout {
  const ChronicleLayout(this.rootDirectory);

  final Directory rootDirectory;

  Directory get syncDirectory => Directory(p.join(rootDirectory.path, '.sync'));
  Directory get locksDirectory =>
      Directory(p.join(rootDirectory.path, 'locks'));
  Directory get orphansDirectory =>
      Directory(p.join(rootDirectory.path, 'orphans'));
  Directory get mattersDirectory =>
      Directory(p.join(rootDirectory.path, 'matters'));
  Directory get linksDirectory =>
      Directory(p.join(rootDirectory.path, 'links'));
  Directory get resourcesDirectory =>
      Directory(p.join(rootDirectory.path, 'resources'));

  File get infoFile => File(p.join(rootDirectory.path, 'info.json'));
  File get syncVersionFile => File(p.join(syncDirectory.path, 'version.txt'));

  Directory matterDirectory(String matterId) {
    return Directory(p.join(mattersDirectory.path, matterId));
  }

  File matterJsonFile(String matterId) {
    return File(p.join(matterDirectory(matterId).path, 'matter.json'));
  }

  Directory phasesDirectory(String matterId) {
    return Directory(p.join(matterDirectory(matterId).path, 'phases'));
  }

  Directory phaseDirectory(String matterId, String phaseId) {
    return Directory(p.join(phasesDirectory(matterId).path, phaseId));
  }

  File orphanNoteFile(String noteId) {
    return File(p.join(orphansDirectory.path, '$noteId.md'));
  }

  File phaseNoteFile({
    required String matterId,
    required String phaseId,
    required String noteId,
  }) {
    return File(p.join(phaseDirectory(matterId, phaseId).path, '$noteId.md'));
  }

  File linkFile(String linkId) {
    return File(p.join(linksDirectory.path, '$linkId.json'));
  }

  String relativePath(File file) {
    final relative = p.relative(file.path, from: rootDirectory.path);
    return relative.replaceAll('\\', '/');
  }

  File fromRelativePath(String relativePath) {
    return File(p.join(rootDirectory.path, relativePath));
  }

  bool isIgnoredSyncPath(String relativePath) {
    return relativePath.startsWith('.sync/') ||
        relativePath.startsWith('locks/');
  }
}
