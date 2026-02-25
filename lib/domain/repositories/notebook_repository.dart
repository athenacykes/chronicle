import '../entities/notebook_folder.dart';

abstract class NotebookRepository {
  Future<List<NotebookFolder>> listFolders();
  Future<NotebookFolder?> getFolderById(String folderId);
  Future<NotebookFolder> createFolder({
    required String name,
    String? parentId,
  });
  Future<NotebookFolder> renameFolder({
    required String folderId,
    required String name,
  });
  Future<void> deleteFolder(String folderId);
}
