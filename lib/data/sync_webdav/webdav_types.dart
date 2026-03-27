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

class WebDavPropfindEntry {
  const WebDavPropfindEntry({
    required this.path,
    required this.isDirectory,
    required this.updatedAt,
    required this.size,
    required this.etag,
  });

  final String path;
  final bool isDirectory;
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

class LocalSyncMetadataEntry {
  const LocalSyncMetadataEntry({
    required this.canonicalPath,
    required this.sourcePath,
    required this.contentHash,
    required this.size,
    required this.modifiedAt,
  });

  final String canonicalPath;
  final String sourcePath;
  final String contentHash;
  final int size;
  final DateTime modifiedAt;

  Map<String, dynamic> toJson() {
    return {
      'canonicalPath': canonicalPath,
      'sourcePath': sourcePath,
      'contentHash': contentHash,
      'size': size,
      'modifiedAt': modifiedAt.toIso8601String(),
    };
  }

  static LocalSyncMetadataEntry fromJson(Map<String, dynamic> json) {
    return LocalSyncMetadataEntry(
      canonicalPath: json['canonicalPath'] as String,
      sourcePath: json['sourcePath'] as String,
      contentHash: (json['contentHash'] as String?) ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String).toUtc(),
    );
  }
}

class LocalSyncMetadataSnapshot {
  const LocalSyncMetadataSnapshot({
    required this.entries,
    required this.dirty,
    required this.runsSinceAudit,
    this.lastAuditAt,
  });

  final Map<String, LocalSyncMetadataEntry> entries;
  final bool dirty;
  final int runsSinceAudit;
  final DateTime? lastAuditAt;

  LocalSyncMetadataSnapshot copyWith({
    Map<String, LocalSyncMetadataEntry>? entries,
    bool? dirty,
    int? runsSinceAudit,
    DateTime? lastAuditAt,
    bool clearLastAuditAt = false,
  }) {
    return LocalSyncMetadataSnapshot(
      entries: entries ?? this.entries,
      dirty: dirty ?? this.dirty,
      runsSinceAudit: runsSinceAudit ?? this.runsSinceAudit,
      lastAuditAt: clearLastAuditAt ? null : (lastAuditAt ?? this.lastAuditAt),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dirty': dirty,
      'runsSinceAudit': runsSinceAudit,
      'lastAuditAt': lastAuditAt?.toIso8601String(),
      'entries': {
        for (final entry in entries.entries) entry.key: entry.value.toJson(),
      },
    };
  }

  static LocalSyncMetadataSnapshot fromJson(Map<String, dynamic> json) {
    final decodedEntries = <String, LocalSyncMetadataEntry>{};
    final rawEntries = json['entries'];
    if (rawEntries is Map<String, dynamic>) {
      for (final entry in rawEntries.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) {
          continue;
        }
        decodedEntries[entry.key] = LocalSyncMetadataEntry.fromJson(value);
      }
    }

    final rawLastAuditAt = json['lastAuditAt'] as String?;
    return LocalSyncMetadataSnapshot(
      entries: decodedEntries,
      dirty: json['dirty'] as bool? ?? false,
      runsSinceAudit: (json['runsSinceAudit'] as num?)?.toInt() ?? 0,
      lastAuditAt: rawLastAuditAt == null || rawLastAuditAt.isEmpty
          ? null
          : DateTime.parse(rawLastAuditAt).toUtc(),
    );
  }

  static const empty = LocalSyncMetadataSnapshot(
    entries: <String, LocalSyncMetadataEntry>{},
    dirty: false,
    runsSinceAudit: 0,
  );
}

class SyncManifestEntry {
  const SyncManifestEntry({
    required this.canonicalPath,
    required this.sourcePath,
    required this.contentHash,
    required this.size,
    required this.updatedAt,
    required this.isLegacyOrphan,
  });

  final String canonicalPath;
  final String sourcePath;
  final String contentHash;
  final int size;
  final DateTime updatedAt;
  final bool isLegacyOrphan;

  Map<String, dynamic> toJson() {
    return {
      'canonicalPath': canonicalPath,
      'sourcePath': sourcePath,
      'contentHash': contentHash,
      'size': size,
      'updatedAt': updatedAt.toIso8601String(),
      'isLegacyOrphan': isLegacyOrphan,
    };
  }

  static SyncManifestEntry fromJson(Map<String, dynamic> json) {
    return SyncManifestEntry(
      canonicalPath: json['canonicalPath'] as String,
      sourcePath: json['sourcePath'] as String,
      contentHash: (json['contentHash'] as String?) ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      isLegacyOrphan: json['isLegacyOrphan'] as bool? ?? false,
    );
  }
}

class SyncManifest {
  const SyncManifest({
    required this.revision,
    required this.generatedAt,
    required this.entries,
  });

  final String revision;
  final DateTime generatedAt;
  final Map<String, SyncManifestEntry> entries;

  Map<String, dynamic> toJson() {
    return {
      'revision': revision,
      'generatedAt': generatedAt.toIso8601String(),
      'entries': {
        for (final entry in entries.entries) entry.key: entry.value.toJson(),
      },
    };
  }

  static SyncManifest fromJson(Map<String, dynamic> json) {
    final decodedEntries = <String, SyncManifestEntry>{};
    final rawEntries = json['entries'];
    if (rawEntries is Map<String, dynamic>) {
      for (final entry in rawEntries.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) {
          continue;
        }
        decodedEntries[entry.key] = SyncManifestEntry.fromJson(value);
      }
    }

    return SyncManifest(
      revision: (json['revision'] as String?) ?? '',
      generatedAt: DateTime.parse(json['generatedAt'] as String).toUtc(),
      entries: decodedEntries,
    );
  }
}
