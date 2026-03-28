class ChronicleBackupWarning {
  const ChronicleBackupWarning({
    required this.message,
    this.archivePath,
    this.entryPath,
  });

  final String message;
  final String? archivePath;
  final String? entryPath;
}

enum ChronicleBackupImportMode { blankRestore, mergeExisting }

class ChronicleBackupExportResult {
  const ChronicleBackupExportResult({
    required this.archivePath,
    required this.exportedFileCount,
    required this.exportedByteCount,
    required this.warnings,
  });

  final String archivePath;
  final int exportedFileCount;
  final int exportedByteCount;
  final List<ChronicleBackupWarning> warnings;

  int get warningCount => warnings.length;
  bool get hasWarnings => warnings.isNotEmpty;
}

class ChronicleBackupImportResult {
  const ChronicleBackupImportResult({
    required this.archivePath,
    required this.mode,
    required this.importedCategoryCount,
    required this.importedMatterCount,
    required this.importedNotebookFolderCount,
    required this.importedNoteCount,
    required this.importedLinkCount,
    required this.importedResourceCount,
    required this.warnings,
  });

  final String archivePath;
  final ChronicleBackupImportMode mode;
  final int importedCategoryCount;
  final int importedMatterCount;
  final int importedNotebookFolderCount;
  final int importedNoteCount;
  final int importedLinkCount;
  final int importedResourceCount;
  final List<ChronicleBackupWarning> warnings;

  int get warningCount => warnings.length;
  bool get hasWarnings => warnings.isNotEmpty;
}

class ChronicleBackupResetResult {
  const ChronicleBackupResetResult({required this.rootPath});

  final String rootPath;
}
