import 'package:path/path.dart' as p;

enum SyncConflictType { note, link, unknown }

class SyncConflict {
  const SyncConflict({
    this.type = SyncConflictType.unknown,
    required this.conflictPath,
    required this.originalPath,
    required this.detectedAt,
    required this.localDevice,
    required this.remoteDevice,
    required this.title,
    required this.preview,
  });

  final SyncConflictType type;
  final String conflictPath;
  final String originalPath;
  final DateTime detectedAt;
  final String localDevice;
  final String remoteDevice;
  final String title;
  final String preview;

  bool get isNote => type == SyncConflictType.note;
  bool get isLink => type == SyncConflictType.link;

  String? get originalNoteId {
    if (!isNote || !originalPath.endsWith('.md')) {
      return null;
    }
    final value = p.basenameWithoutExtension(originalPath);
    return value.isEmpty ? null : value;
  }
}
