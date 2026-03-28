import '../entities/chronicle_backup_result.dart';

abstract class ChronicleBackupRepository {
  Future<ChronicleBackupExportResult> exportToArchive({
    required String outputPath,
  });

  Future<ChronicleBackupImportResult> importFromArchive({
    required String archivePath,
    required ChronicleBackupImportMode mode,
  });

  Future<ChronicleBackupResetResult> resetStorageToBlank();
}
