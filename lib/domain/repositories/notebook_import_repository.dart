import '../entities/notebook_import_result.dart';

abstract class NotebookImportRepository {
  Future<NotebookImportBatchResult> importFiles({
    required List<String> sourcePaths,
  });
}
