class WebDavFileMetadata {
  const WebDavFileMetadata({
    required this.path,
    required this.updatedAt,
    required this.size,
    required this.etag,
  });

  final String path;
  final DateTime updatedAt;
  final int size;
  final String? etag;
}

class SyncFileState {
  const SyncFileState({
    required this.path,
    required this.localHash,
    required this.remoteHash,
    required this.updatedAt,
  });

  final String path;
  final String localHash;
  final String remoteHash;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'localHash': localHash,
      'remoteHash': remoteHash,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static SyncFileState fromJson(Map<String, dynamic> json) {
    return SyncFileState(
      path: json['path'] as String,
      localHash: (json['localHash'] as String?) ?? '',
      remoteHash: (json['remoteHash'] as String?) ?? '',
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
  }
}
