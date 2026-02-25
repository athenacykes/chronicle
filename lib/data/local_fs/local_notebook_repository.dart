import 'dart:convert';
import '../../core/app_exception.dart';
import '../../core/clock.dart';
import '../../core/file_system_utils.dart';
import '../../core/id_generator.dart';
import '../../domain/entities/notebook_folder.dart';
import '../../domain/repositories/notebook_repository.dart';
import 'chronicle_layout.dart';
import 'chronicle_storage_initializer.dart';
import 'note_file_codec.dart';
import 'storage_root_locator.dart';

class LocalNotebookRepository implements NotebookRepository {
  LocalNotebookRepository({
    required StorageRootLocator storageRootLocator,
    required ChronicleStorageInitializer storageInitializer,
    required FileSystemUtils fileSystemUtils,
    required Clock clock,
    required IdGenerator idGenerator,
    required NoteFileCodec noteCodec,
  }) : _storageRootLocator = storageRootLocator,
       _storageInitializer = storageInitializer,
       _fileSystemUtils = fileSystemUtils,
       _clock = clock,
       _idGenerator = idGenerator,
       _noteCodec = noteCodec;

  final StorageRootLocator _storageRootLocator;
  final ChronicleStorageInitializer _storageInitializer;
  final FileSystemUtils _fileSystemUtils;
  final Clock _clock;
  final IdGenerator _idGenerator;
  final NoteFileCodec _noteCodec;

  @override
  Future<List<NotebookFolder>> listFolders() async {
    final folders = await _loadFolders();
    folders.sort(_sortByTierAndName);
    return folders;
  }

  @override
  Future<NotebookFolder?> getFolderById(String folderId) async {
    final folders = await _loadFolders();
    for (final folder in folders) {
      if (folder.id == folderId) {
        return folder;
      }
    }
    return null;
  }

  @override
  Future<NotebookFolder> createFolder({
    required String name,
    String? parentId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw AppException('Folder name cannot be empty.');
    }

    final layout = await _layout();
    final folders = await _loadFolders();
    if (parentId != null && !folders.any((folder) => folder.id == parentId)) {
      throw AppException('Notebook parent folder does not exist: $parentId');
    }
    _ensureUniqueName(
      folders: folders,
      parentId: parentId,
      name: trimmed,
    );

    final now = _clock.nowUtc();
    final folder = NotebookFolder(
      id: _idGenerator.newId(),
      name: trimmed,
      parentId: parentId,
      createdAt: now,
      updatedAt: now,
    );
    folders.add(folder);
    await _saveFolders(folders);
    await _fileSystemUtils.ensureDirectory(
      layout.notebookFolderDirectory(folder.id),
    );
    return folder;
  }

  @override
  Future<NotebookFolder> renameFolder({
    required String folderId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw AppException('Folder name cannot be empty.');
    }

    final folders = await _loadFolders();
    final index = folders.indexWhere((folder) => folder.id == folderId);
    if (index < 0) {
      throw AppException('Notebook folder not found: $folderId');
    }

    final existing = folders[index];
    _ensureUniqueName(
      folders: folders,
      parentId: existing.parentId,
      name: trimmed,
      excludeFolderId: existing.id,
    );

    final renamed = existing.copyWith(name: trimmed, updatedAt: _clock.nowUtc());
    folders[index] = renamed;
    await _saveFolders(folders);
    return renamed;
  }

  @override
  Future<void> deleteFolder(String folderId) async {
    final layout = await _layout();
    final folders = await _loadFolders();
    final index = folders.indexWhere((folder) => folder.id == folderId);
    if (index < 0) {
      return;
    }

    final deleted = folders[index];
    final parentId = deleted.parentId;
    final now = _clock.nowUtc();

    for (var i = 0; i < folders.length; i++) {
      if (folders[i].parentId == folderId) {
        folders[i] = folders[i].copyWith(
          parentId: parentId,
          clearParentId: parentId == null,
          updatedAt: now,
        );
      }
    }

    await _reparentDirectFolderNotes(
      layout: layout,
      sourceFolderId: folderId,
      targetFolderId: parentId,
    );

    folders.removeAt(index);
    await _saveFolders(folders);
    final folderDir = layout.notebookFolderDirectory(folderId);
    if (await folderDir.exists()) {
      await folderDir.delete(recursive: true);
    }
  }

  Future<void> _reparentDirectFolderNotes({
    required ChronicleLayout layout,
    required String sourceFolderId,
    required String? targetFolderId,
  }) async {
    final sourceDir = layout.notebookFolderDirectory(sourceFolderId);
    if (!await sourceDir.exists()) {
      return;
    }

    final files = await _fileSystemUtils.listFilesRecursively(sourceDir);
    for (final file in files) {
      if (!file.path.endsWith('.md') || file.path.contains('.conflict.')) {
        continue;
      }
      final raw = await file.readAsString();
      final note = _noteCodec.decode(raw);
      final updated = note.copyWith(
        notebookFolderId: targetFolderId,
        clearNotebookFolderId: targetFolderId == null,
        clearMatterId: true,
        clearPhaseId: true,
        updatedAt: _clock.nowUtc(),
      );
      final target = targetFolderId == null
          ? layout.notebookRootNoteFile(note.id)
          : layout.notebookFolderNoteFile(folderId: targetFolderId, noteId: note.id);
      await _fileSystemUtils.ensureDirectory(target.parent);
      await _fileSystemUtils.atomicWriteString(target, _noteCodec.encode(updated));
      if (target.path != file.path) {
        await _fileSystemUtils.deleteIfExists(file);
      }
    }
  }

  void _ensureUniqueName({
    required List<NotebookFolder> folders,
    required String? parentId,
    required String name,
    String? excludeFolderId,
  }) {
    final normalized = name.toLowerCase();
    final duplicate = folders.any((folder) {
      if (excludeFolderId != null && folder.id == excludeFolderId) {
        return false;
      }
      return folder.parentId == parentId &&
          folder.name.trim().toLowerCase() == normalized;
    });
    if (duplicate) {
      throw AppException('A folder with this name already exists.');
    }
  }

  int _sortByTierAndName(NotebookFolder a, NotebookFolder b) {
    final parentA = a.parentId ?? '';
    final parentB = b.parentId ?? '';
    final parentCompare = parentA.compareTo(parentB);
    if (parentCompare != 0) {
      return parentCompare;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  Future<List<NotebookFolder>> _loadFolders() async {
    final layout = await _layout();
    final file = layout.notebookFoldersIndexFile;
    if (!await file.exists()) {
      return <NotebookFolder>[];
    }

    try {
      final raw = await file.readAsString();
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final items = decoded['folders'] as List<dynamic>? ?? <dynamic>[];
      final folders = <NotebookFolder>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        folders.add(NotebookFolder.fromJson(item));
      }
      return folders;
    } catch (_) {
      return <NotebookFolder>[];
    }
  }

  Future<void> _saveFolders(List<NotebookFolder> folders) async {
    final layout = await _layout();
    final payload = <String, dynamic>{
      'folders': folders.map((folder) => folder.toJson()).toList(),
    };
    await _fileSystemUtils.atomicWriteString(
      layout.notebookFoldersIndexFile,
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<ChronicleLayout> _layout() async {
    final root = await _storageRootLocator.requireRootDirectory();
    await _storageInitializer.ensureInitialized(root);
    return ChronicleLayout(root);
  }
}
