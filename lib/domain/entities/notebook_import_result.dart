class NotebookImportWarning {
  const NotebookImportWarning({
    required this.message,
    this.sourcePath,
    this.itemId,
  });

  final String message;
  final String? sourcePath;
  final String? itemId;
}

class NotebookImportFileResult {
  const NotebookImportFileResult({
    required this.sourcePath,
    required this.importedNoteCount,
    required this.importedFolderCount,
    required this.importedResourceCount,
    required this.warnings,
  });

  final String sourcePath;
  final int importedNoteCount;
  final int importedFolderCount;
  final int importedResourceCount;
  final List<NotebookImportWarning> warnings;

  int get warningCount => warnings.length;
}

class NotebookImportBatchResult {
  const NotebookImportBatchResult({required this.files});

  final List<NotebookImportFileResult> files;

  int get importedNoteCount {
    var total = 0;
    for (final file in files) {
      total += file.importedNoteCount;
    }
    return total;
  }

  int get importedFolderCount {
    var total = 0;
    for (final file in files) {
      total += file.importedFolderCount;
    }
    return total;
  }

  int get importedResourceCount {
    var total = 0;
    for (final file in files) {
      total += file.importedResourceCount;
    }
    return total;
  }

  List<NotebookImportWarning> get warnings {
    final all = <NotebookImportWarning>[];
    for (final file in files) {
      all.addAll(file.warnings);
    }
    return all;
  }

  int get warningCount => warnings.length;
  bool get hasWarnings => warningCount > 0;
}
