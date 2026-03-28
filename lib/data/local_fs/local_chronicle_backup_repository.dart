import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../core/app_exception.dart';
import '../../core/clock.dart';
import '../../core/file_system_utils.dart';
import '../../core/id_generator.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/chronicle_backup_result.dart';
import '../../domain/entities/matter.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/note_link.dart';
import '../../domain/entities/notebook_folder.dart';
import '../../domain/entities/phase.dart';
import '../../domain/repositories/chronicle_backup_repository.dart';
import '../sync_webdav/sync_local_metadata_tracker.dart';
import 'chronicle_layout.dart';
import 'chronicle_storage_initializer.dart';
import 'link_file_codec.dart';
import 'matter_file_codec.dart';
import 'note_file_codec.dart';
import 'storage_root_locator.dart';

class LocalChronicleBackupRepository implements ChronicleBackupRepository {
  LocalChronicleBackupRepository({
    required StorageRootLocator storageRootLocator,
    required ChronicleStorageInitializer storageInitializer,
    required FileSystemUtils fileSystemUtils,
    required NoteFileCodec noteCodec,
    required MatterFileCodec matterCodec,
    required LinkFileCodec linkCodec,
    required IdGenerator idGenerator,
    required Clock clock,
    SyncLocalMetadataTracker? syncMetadataTracker,
  }) : _storageRootLocator = storageRootLocator,
       _storageInitializer = storageInitializer,
       _fileSystemUtils = fileSystemUtils,
       _noteCodec = noteCodec,
       _matterCodec = matterCodec,
       _linkCodec = linkCodec,
       _idGenerator = idGenerator,
       _clock = clock,
       _syncMetadataTracker = syncMetadataTracker;

  static const String _manifestPath = 'chronicle-backup.json';
  static const String _storagePrefix = 'storage/';
  static const int _backupFormatVersion = 1;

  final StorageRootLocator _storageRootLocator;
  final ChronicleStorageInitializer _storageInitializer;
  final FileSystemUtils _fileSystemUtils;
  final NoteFileCodec _noteCodec;
  final MatterFileCodec _matterCodec;
  final LinkFileCodec _linkCodec;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final SyncLocalMetadataTracker? _syncMetadataTracker;

  @override
  Future<ChronicleBackupExportResult> exportToArchive({
    required String outputPath,
  }) async {
    final normalizedOutputPath = outputPath.trim();
    if (normalizedOutputPath.isEmpty) {
      throw AppException('Backup output path cannot be empty.');
    }

    final layout = await _layout();
    final files = await _fileSystemUtils.listFilesRecursively(
      layout.rootDirectory,
    );
    files.sort((a, b) => a.path.compareTo(b.path));

    final archive = Archive();
    final warnings = <ChronicleBackupWarning>[];
    var exportedFileCount = 0;
    var exportedByteCount = 0;

    for (final file in files) {
      final relativePath = layout.relativePath(file);
      if (_shouldSkipExportPath(relativePath)) {
        continue;
      }
      final entryPath = '$_storagePrefix$relativePath';
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile.bytes(entryPath, bytes));
      exportedFileCount += 1;
      exportedByteCount += bytes.length;
    }

    final formatVersion = await _readStorageFormatVersion(layout);
    final manifest = <String, dynamic>{
      'app': 'chronicle',
      'backupFormatVersion': _backupFormatVersion,
      'createdAt': _clock.nowUtc().toIso8601String(),
      'storageFormatVersion': formatVersion,
      'scope': 'storage-root',
      'fileCount': exportedFileCount,
      'excludedPrefixes': <String>['locks/'],
    };
    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
    archive.addFile(ArchiveFile.bytes(_manifestPath, manifestBytes));

    final zipBytes = ZipEncoder().encodeBytes(archive);
    final outputFile = File(normalizedOutputPath);
    await _fileSystemUtils.atomicWriteBytes(outputFile, zipBytes);

    return ChronicleBackupExportResult(
      archivePath: normalizedOutputPath,
      exportedFileCount: exportedFileCount,
      exportedByteCount: exportedByteCount,
      warnings: warnings,
    );
  }

  @override
  Future<ChronicleBackupImportResult> importFromArchive({
    required String archivePath,
    required ChronicleBackupImportMode mode,
  }) async {
    final normalizedArchivePath = archivePath.trim();
    if (normalizedArchivePath.isEmpty) {
      throw AppException('Backup archive path cannot be empty.');
    }

    final archiveFile = File(normalizedArchivePath);
    if (!await archiveFile.exists()) {
      throw AppException(
        'Backup archive does not exist: $normalizedArchivePath',
      );
    }

    final warnings = <ChronicleBackupWarning>[];
    final extracted = await _extractArchive(
      archiveFile: archiveFile,
      warnings: warnings,
    );
    final extractedRoot = extracted.storageRootDirectory;
    final extractedLayout = ChronicleLayout(extractedRoot);
    final targetLayout = await _layout();
    final sourceState = await _readImportState(extractedLayout);

    try {
      late final _ImportCounts counts;
      if (mode == ChronicleBackupImportMode.blankRestore) {
        await _restoreBlankStorage(
          sourceLayout: extractedLayout,
          targetLayout: targetLayout,
        );
        counts = _ImportCounts(
          importedCategoryCount: sourceState.categoryCount,
          importedMatterCount: sourceState.matterCount,
          importedNotebookFolderCount: sourceState.folderCount,
          importedNoteCount: sourceState.noteCount,
          importedLinkCount: sourceState.linkCount,
          importedResourceCount: sourceState.resourceCount,
        );
      } else {
        counts = await _mergeIntoExistingStorage(
          sourceLayout: extractedLayout,
          sourceState: sourceState,
          targetLayout: targetLayout,
          warnings: warnings,
        );
      }

      await _syncMetadataTracker?.rebuildFromDisk();
      return ChronicleBackupImportResult(
        archivePath: normalizedArchivePath,
        mode: mode,
        importedCategoryCount: counts.importedCategoryCount,
        importedMatterCount: counts.importedMatterCount,
        importedNotebookFolderCount: counts.importedNotebookFolderCount,
        importedNoteCount: counts.importedNoteCount,
        importedLinkCount: counts.importedLinkCount,
        importedResourceCount: counts.importedResourceCount,
        warnings: warnings,
      );
    } finally {
      if (await extracted.tempDirectory.exists()) {
        await extracted.tempDirectory.delete(recursive: true);
      }
    }
  }

  @override
  Future<ChronicleBackupResetResult> resetStorageToBlank() async {
    final root = await _storageRootLocator.requireRootDirectory();
    await _wipeRoot(root);
    await _storageInitializer.ensureInitialized(root);
    await _syncMetadataTracker?.rebuildFromDisk();
    return ChronicleBackupResetResult(rootPath: root.path);
  }

  Future<_ExtractedBackup> _extractArchive({
    required File archiveFile,
    required List<ChronicleBackupWarning> warnings,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp(
      'chronicle-backup-import-',
    );
    final storageRoot = Directory(p.join(tempDir.path, 'storage_root'));
    await _fileSystemUtils.ensureDirectory(storageRoot);

    final archiveBytes = await archiveFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(archiveBytes, verify: true);
    Map<String, dynamic>? manifest;

    for (final entry in archive) {
      if (!entry.isFile) {
        continue;
      }

      final relativePath = _normalizeArchiveEntryPath(entry.name);
      if (relativePath == null) {
        warnings.add(
          ChronicleBackupWarning(
            archivePath: archiveFile.path,
            entryPath: entry.name,
            message: 'Skipped unsafe archive entry.',
          ),
        );
        continue;
      }

      if (relativePath == _manifestPath) {
        try {
          manifest =
              json.decode(utf8.decode(_archiveEntryBytes(entry)))
                  as Map<String, dynamic>;
        } catch (error) {
          throw AppException('Backup manifest is invalid.', cause: error);
        }
        continue;
      }

      if (!relativePath.startsWith(_storagePrefix)) {
        warnings.add(
          ChronicleBackupWarning(
            archivePath: archiveFile.path,
            entryPath: relativePath,
            message: 'Skipped unsupported archive entry.',
          ),
        );
        continue;
      }

      final storageRelativePath = relativePath.substring(_storagePrefix.length);
      if (storageRelativePath.isEmpty) {
        continue;
      }
      final target = File(p.join(storageRoot.path, storageRelativePath));
      await _fileSystemUtils.ensureDirectory(target.parent);
      await _fileSystemUtils.atomicWriteBytes(
        target,
        _archiveEntryBytes(entry),
      );
    }

    if (manifest == null) {
      throw AppException('Backup archive is missing its manifest.');
    }
    if ((manifest['app'] as String?) != 'chronicle') {
      throw AppException('Backup archive is not a Chronicle backup.');
    }

    return _ExtractedBackup(
      tempDirectory: tempDir,
      storageRootDirectory: storageRoot,
    );
  }

  Future<void> _restoreBlankStorage({
    required ChronicleLayout sourceLayout,
    required ChronicleLayout targetLayout,
  }) async {
    await _wipeRoot(targetLayout.rootDirectory);
    await _copyStorageTree(
      sourceRoot: sourceLayout.rootDirectory,
      targetRoot: targetLayout.rootDirectory,
    );
    await _storageInitializer.ensureInitialized(targetLayout.rootDirectory);
  }

  Future<_ImportCounts> _mergeIntoExistingStorage({
    required ChronicleLayout sourceLayout,
    required _ImportedStorageState sourceState,
    required ChronicleLayout targetLayout,
    required List<ChronicleBackupWarning> warnings,
  }) async {
    await _storageInitializer.ensureInitialized(targetLayout.rootDirectory);

    final targetState = await _readImportState(targetLayout);

    final categoryIdMap = <String, String>{};
    final matterIdMap = <String, String>{};
    final phaseIdMap = <String, String>{};
    final folderIdMap = <String, String?>{};
    final noteIdMap = <String, String>{};
    final attachmentPathMapByNoteId = <String, Map<String, String>>{};

    final mergedCategories = <Category>[...targetState.categories];
    final existingCategoryIds = mergedCategories.map((item) => item.id).toSet();
    for (final sourceCategory in sourceState.categories) {
      final targetId = existingCategoryIds.contains(sourceCategory.id)
          ? _idGenerator.newId()
          : sourceCategory.id;
      categoryIdMap[sourceCategory.id] = targetId;
      existingCategoryIds.add(targetId);
      mergedCategories.add(
        sourceCategory.copyWith(id: targetId, updatedAt: _clock.nowUtc()),
      );
    }

    final existingFolders = <NotebookFolder>[...targetState.folders];
    final existingFolderIds = existingFolders.map((item) => item.id).toSet();
    final usedFolderNames = <String>{};
    for (final folder in existingFolders) {
      usedFolderNames.add(_folderNameKey(folder.parentId, folder.name));
    }
    final sourceFoldersSorted = [...sourceState.folders]
      ..sort((a, b) {
        final depthCompare = _folderDepth(
          sourceState.folderById,
          a,
        ).compareTo(_folderDepth(sourceState.folderById, b));
        if (depthCompare != 0) {
          return depthCompare;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    for (final sourceFolder in sourceFoldersSorted) {
      final remappedParentId = sourceFolder.parentId == null
          ? null
          : folderIdMap[sourceFolder.parentId];
      if (sourceFolder.parentId != null && remappedParentId == null) {
        warnings.add(
          ChronicleBackupWarning(
            entryPath: sourceFolder.id,
            message: 'Skipped notebook folder with missing parent mapping.',
          ),
        );
        continue;
      }
      final targetId = existingFolderIds.contains(sourceFolder.id)
          ? _idGenerator.newId()
          : sourceFolder.id;
      final targetName = _uniqueFolderName(
        parentId: remappedParentId,
        originalName: sourceFolder.name,
        usedNames: usedFolderNames,
      );
      folderIdMap[sourceFolder.id] = targetId;
      existingFolderIds.add(targetId);
      existingFolders.add(
        sourceFolder.copyWith(
          id: targetId,
          name: targetName,
          parentId: remappedParentId,
          clearParentId: remappedParentId == null,
          updatedAt: _clock.nowUtc(),
        ),
      );
    }

    final mergedMatters = <Matter>[...targetState.matters];
    final existingMatterIds = mergedMatters.map((item) => item.id).toSet();
    for (final sourceMatter in sourceState.matters) {
      final targetMatterId = existingMatterIds.contains(sourceMatter.id)
          ? _idGenerator.newId()
          : sourceMatter.id;
      existingMatterIds.add(targetMatterId);
      matterIdMap[sourceMatter.id] = targetMatterId;

      final remappedPhases = <Phase>[];
      for (final phase in sourceMatter.phases) {
        final targetPhaseId = _idGenerator.newId();
        phaseIdMap[phase.id] = targetPhaseId;
        remappedPhases.add(
          phase.copyWith(id: targetPhaseId, matterId: targetMatterId),
        );
      }
      mergedMatters.add(
        sourceMatter.copyWith(
          id: targetMatterId,
          categoryId: sourceMatter.categoryId == null
              ? null
              : categoryIdMap[sourceMatter.categoryId!] ??
                    sourceMatter.categoryId,
          clearCategoryId: sourceMatter.categoryId == null,
          phases: remappedPhases,
          currentPhaseId: sourceMatter.currentPhaseId == null
              ? null
              : phaseIdMap[sourceMatter.currentPhaseId!],
          clearCurrentPhaseId: sourceMatter.currentPhaseId == null,
          updatedAt: _clock.nowUtc(),
        ),
      );
    }

    final targetExistingNotes = <Note>[...targetState.notes];
    final existingNoteIds = targetExistingNotes.map((item) => item.id).toSet();
    final mergedNotes = <Note>[...targetExistingNotes];
    var importedResourceCount = 0;
    var importedNoteCount = 0;

    for (final sourceNote in sourceState.notes) {
      final targetNoteId = existingNoteIds.contains(sourceNote.id)
          ? _idGenerator.newId()
          : sourceNote.id;
      existingNoteIds.add(targetNoteId);
      noteIdMap[sourceNote.id] = targetNoteId;

      final ownership = _remapNoteOwnership(
        sourceNote: sourceNote,
        matterIdMap: matterIdMap,
        phaseIdMap: phaseIdMap,
        folderIdMap: folderIdMap,
      );
      if (sourceNote.isInMatter &&
          (ownership.matterId == null || ownership.phaseId == null)) {
        warnings.add(
          ChronicleBackupWarning(
            entryPath: sourceNote.id,
            message:
                'Skipped matter note with unresolved matter or phase mapping.',
          ),
        );
        continue;
      }

      final attachmentPathMap = <String, String>{};
      final remappedAttachments = <String>[];
      for (final attachment in sourceNote.attachments) {
        final sourceResource = sourceLayout.fromRelativePath(attachment);
        if (!await sourceResource.exists()) {
          warnings.add(
            ChronicleBackupWarning(
              entryPath: attachment,
              message:
                  'Skipped missing attachment referenced by imported note.',
            ),
          );
          continue;
        }
        final targetRelativePath = await _nextAttachmentRelativePath(
          layout: targetLayout,
          noteId: targetNoteId,
          originalRelativePath: attachment,
        );
        final targetResource = targetLayout.fromRelativePath(
          targetRelativePath,
        );
        final bytes = await sourceResource.readAsBytes();
        await _fileSystemUtils.atomicWriteBytes(targetResource, bytes);
        attachmentPathMap[attachment] = targetRelativePath;
        remappedAttachments.add(targetRelativePath);
        importedResourceCount += 1;
      }
      attachmentPathMapByNoteId[sourceNote.id] = attachmentPathMap;

      var remappedContent = sourceNote.content;
      for (final entry in attachmentPathMap.entries) {
        remappedContent = remappedContent.replaceAll(entry.key, entry.value);
      }

      mergedNotes.add(
        sourceNote.copyWith(
          id: targetNoteId,
          matterId: ownership.matterId,
          clearMatterId: ownership.matterId == null,
          phaseId: ownership.phaseId,
          clearPhaseId: ownership.phaseId == null,
          notebookFolderId: ownership.notebookFolderId,
          clearNotebookFolderId: ownership.notebookFolderId == null,
          attachments: remappedAttachments,
          content: remappedContent,
          updatedAt: _clock.nowUtc(),
        ),
      );
      importedNoteCount += 1;
    }

    final mergedLinks = <NoteLink>[...targetState.links];
    final existingLinkIds = mergedLinks.map((item) => item.id).toSet();
    var importedLinkCount = 0;
    for (final sourceLink in sourceState.links) {
      final mappedSourceNoteId = noteIdMap[sourceLink.sourceNoteId];
      final mappedTargetNoteId = noteIdMap[sourceLink.targetNoteId];
      if (mappedSourceNoteId == null || mappedTargetNoteId == null) {
        warnings.add(
          ChronicleBackupWarning(
            entryPath: sourceLink.id,
            message: 'Skipped link whose notes were not imported.',
          ),
        );
        continue;
      }
      final targetLinkId = existingLinkIds.contains(sourceLink.id)
          ? _idGenerator.newId()
          : sourceLink.id;
      existingLinkIds.add(targetLinkId);
      mergedLinks.add(
        NoteLink(
          id: targetLinkId,
          sourceNoteId: mappedSourceNoteId,
          targetNoteId: mappedTargetNoteId,
          context: sourceLink.context,
          createdAt: sourceLink.createdAt,
        ),
      );
      importedLinkCount += 1;
    }

    await _writeCategories(targetLayout, mergedCategories);
    await _writeFolders(targetLayout, existingFolders);
    await _writeMatters(targetLayout, mergedMatters);
    await _writeNotes(targetLayout, mergedNotes);
    await _writeLinks(targetLayout, mergedLinks);

    return _ImportCounts(
      importedCategoryCount: sourceState.categoryCount,
      importedMatterCount: sourceState.matterCount,
      importedNotebookFolderCount: folderIdMap.length,
      importedNoteCount: importedNoteCount,
      importedLinkCount: importedLinkCount,
      importedResourceCount: importedResourceCount,
    );
  }

  _RemappedOwnership _remapNoteOwnership({
    required Note sourceNote,
    required Map<String, String> matterIdMap,
    required Map<String, String> phaseIdMap,
    required Map<String, String?> folderIdMap,
  }) {
    if (sourceNote.isInMatter) {
      final mappedMatterId = sourceNote.matterId == null
          ? null
          : matterIdMap[sourceNote.matterId!];
      final mappedPhaseId = sourceNote.phaseId == null
          ? null
          : phaseIdMap[sourceNote.phaseId!];
      if (mappedMatterId == null || mappedPhaseId == null) {
        return const _RemappedOwnership(
          matterId: null,
          phaseId: null,
          notebookFolderId: null,
        );
      }
      return _RemappedOwnership(
        matterId: mappedMatterId,
        phaseId: mappedPhaseId,
        notebookFolderId: null,
      );
    }
    return _RemappedOwnership(
      matterId: null,
      phaseId: null,
      notebookFolderId: sourceNote.notebookFolderId == null
          ? null
          : folderIdMap[sourceNote.notebookFolderId!],
    );
  }

  Future<String> _nextAttachmentRelativePath({
    required ChronicleLayout layout,
    required String noteId,
    required String originalRelativePath,
  }) async {
    final basename = p.basename(originalRelativePath);
    final resourceDir = p.posix.join('resources', noteId);
    var attempt = 0;
    while (true) {
      final candidateName = attempt == 0
          ? basename
          : '${p.basenameWithoutExtension(basename)}_$attempt${p.extension(basename)}';
      final candidate = p.posix.join(resourceDir, candidateName);
      if (!await layout.fromRelativePath(candidate).exists()) {
        return candidate;
      }
      attempt += 1;
    }
  }

  Future<void> _writeCategories(
    ChronicleLayout layout,
    List<Category> categories,
  ) async {
    await _fileSystemUtils.ensureDirectory(layout.categoriesDirectory);
    final existingFiles = await _fileSystemUtils.listFilesRecursively(
      layout.categoriesDirectory,
    );
    for (final file in existingFiles) {
      if (p.extension(file.path) == '.json') {
        await _fileSystemUtils.deleteIfExists(file);
      }
    }
    for (final category in categories) {
      final target = layout.categoryJsonFile(category.id);
      final encoded = const JsonEncoder.withIndent(
        '  ',
      ).convert(category.toJson());
      await _fileSystemUtils.atomicWriteString(target, encoded);
    }
  }

  Future<void> _writeFolders(
    ChronicleLayout layout,
    List<NotebookFolder> folders,
  ) async {
    await _fileSystemUtils.ensureDirectory(layout.notebookDirectory);
    await _fileSystemUtils.ensureDirectory(layout.notebookRootDirectory);
    if (await layout.notebookFoldersDirectory.exists()) {
      await layout.notebookFoldersDirectory.delete(recursive: true);
    }
    await _fileSystemUtils.ensureDirectory(layout.notebookFoldersDirectory);
    for (final folder in folders) {
      await _fileSystemUtils.ensureDirectory(
        layout.notebookFolderDirectory(folder.id),
      );
    }
    final payload = <String, dynamic>{
      'folders': folders.map((folder) => folder.toJson()).toList(),
    };
    await _fileSystemUtils.atomicWriteString(
      layout.notebookFoldersIndexFile,
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<void> _writeMatters(
    ChronicleLayout layout,
    List<Matter> matters,
  ) async {
    await _fileSystemUtils.ensureDirectory(layout.mattersDirectory);
    if (await layout.mattersDirectory.exists()) {
      await layout.mattersDirectory.delete(recursive: true);
      await _fileSystemUtils.ensureDirectory(layout.mattersDirectory);
    }
    for (final matter in matters) {
      final matterDir = layout.matterDirectory(matter.id);
      await _fileSystemUtils.ensureDirectory(matterDir);
      for (final phase in matter.phases) {
        await _fileSystemUtils.ensureDirectory(
          layout.phaseDirectory(matter.id, phase.id),
        );
      }
      await _fileSystemUtils.atomicWriteString(
        layout.matterJsonFile(matter.id),
        _matterCodec.encode(matter),
      );
    }
  }

  Future<void> _writeNotes(ChronicleLayout layout, List<Note> notes) async {
    if (await layout.notebookRootDirectory.exists()) {
      await layout.notebookRootDirectory.delete(recursive: true);
    }
    await _fileSystemUtils.ensureDirectory(layout.notebookRootDirectory);

    if (await layout.notebookFoldersDirectory.exists()) {
      final folders = await layout.notebookFoldersDirectory.list().toList();
      for (final folder in folders) {
        if (folder is Directory) {
          await folder.delete(recursive: true);
          await _fileSystemUtils.ensureDirectory(folder);
        }
      }
    }

    if (await layout.orphansDirectory.exists()) {
      await layout.orphansDirectory.delete(recursive: true);
    }
    await _fileSystemUtils.ensureDirectory(layout.orphansDirectory);

    for (final matter in await _listMatterDirectories(layout)) {
      final phasesDir = Directory(p.join(matter.path, 'phases'));
      if (!await phasesDir.exists()) {
        continue;
      }
      await for (final phaseDir in phasesDir.list(followLinks: false)) {
        if (phaseDir is Directory) {
          final files = await _fileSystemUtils.listFilesRecursively(phaseDir);
          for (final file in files) {
            if (file.path.endsWith('.md')) {
              await _fileSystemUtils.deleteIfExists(file);
            }
          }
        }
      }
    }

    for (final note in notes) {
      final target = await _targetFileFor(layout, note);
      await _fileSystemUtils.ensureDirectory(target.parent);
      await _fileSystemUtils.atomicWriteString(target, _noteCodec.encode(note));
    }
  }

  Future<void> _writeLinks(ChronicleLayout layout, List<NoteLink> links) async {
    if (await layout.linksDirectory.exists()) {
      await layout.linksDirectory.delete(recursive: true);
    }
    await _fileSystemUtils.ensureDirectory(layout.linksDirectory);
    for (final link in links) {
      await _fileSystemUtils.atomicWriteString(
        layout.linkFile(link.id),
        _linkCodec.encode(link),
      );
    }
  }

  Future<File> _targetFileFor(ChronicleLayout layout, Note note) async {
    if (note.isInMatter) {
      return layout.phaseNoteFile(
        matterId: note.matterId!,
        phaseId: note.phaseId!,
        noteId: note.id,
      );
    }
    if (note.notebookFolderId == null) {
      return layout.notebookRootNoteFile(note.id);
    }
    return layout.notebookFolderNoteFile(
      folderId: note.notebookFolderId!,
      noteId: note.id,
    );
  }

  Future<List<Directory>> _listMatterDirectories(ChronicleLayout layout) async {
    if (!await layout.mattersDirectory.exists()) {
      return <Directory>[];
    }
    final result = <Directory>[];
    await for (final entity in layout.mattersDirectory.list(
      followLinks: false,
    )) {
      if (entity is Directory) {
        result.add(entity);
      }
    }
    return result;
  }

  Future<void> _copyStorageTree({
    required Directory sourceRoot,
    required Directory targetRoot,
  }) async {
    final files = await _fileSystemUtils.listFilesRecursively(sourceRoot);
    for (final sourceFile in files) {
      final relativePath = p.relative(sourceFile.path, from: sourceRoot.path);
      final normalizedRelativePath = relativePath.replaceAll('\\', '/');
      if (_shouldSkipExportPath(normalizedRelativePath)) {
        continue;
      }
      final targetFile = File(p.join(targetRoot.path, relativePath));
      await _fileSystemUtils.ensureDirectory(targetFile.parent);
      await _fileSystemUtils.atomicWriteBytes(
        targetFile,
        await sourceFile.readAsBytes(),
      );
    }
  }

  Future<void> _wipeRoot(Directory rootDirectory) async {
    if (!await rootDirectory.exists()) {
      return;
    }
    await for (final entity in rootDirectory.list(followLinks: false)) {
      await entity.delete(recursive: true);
    }
  }

  String? _normalizeArchiveEntryPath(String rawPath) {
    final normalized = rawPath.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) {
      return null;
    }
    final posixPath = p.posix.normalize(normalized);
    if (posixPath == '.' ||
        posixPath == '..' ||
        posixPath.startsWith('../') ||
        posixPath.contains('/../') ||
        posixPath.startsWith('/')) {
      return null;
    }
    return posixPath;
  }

  Uint8List _archiveEntryBytes(ArchiveFile entry) {
    return Uint8List.fromList(entry.content as List<int>);
  }

  bool _shouldSkipExportPath(String relativePath) {
    return relativePath.startsWith('locks/');
  }

  Future<int> _readStorageFormatVersion(ChronicleLayout layout) async {
    if (!await layout.infoFile.exists()) {
      return 0;
    }
    try {
      final decoded =
          json.decode(await layout.infoFile.readAsString())
              as Map<String, dynamic>;
      return (decoded['formatVersion'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<_ImportedStorageState> _readImportState(ChronicleLayout layout) async {
    final categories = await _readCategories(layout);
    final matters = await _readMatters(layout);
    final folders = await _readFolders(layout);
    final notes = await _readNotes(layout);
    final links = await _readLinks(layout);
    final resourceFiles = await _readResources(layout);
    return _ImportedStorageState(
      categories: categories,
      matters: matters,
      folders: folders,
      notes: notes,
      links: links,
      resourceFiles: resourceFiles,
    );
  }

  Future<List<Category>> _readCategories(ChronicleLayout layout) async {
    if (!await layout.categoriesDirectory.exists()) {
      return <Category>[];
    }
    final categories = <Category>[];
    await for (final entity in layout.categoriesDirectory.list(
      followLinks: false,
    )) {
      if (entity is! File || p.extension(entity.path) != '.json') {
        continue;
      }
      try {
        final decoded =
            json.decode(await entity.readAsString()) as Map<String, dynamic>;
        categories.add(Category.fromJson(decoded));
      } catch (_) {
        continue;
      }
    }
    categories.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return categories;
  }

  Future<List<Matter>> _readMatters(ChronicleLayout layout) async {
    if (!await layout.mattersDirectory.exists()) {
      return <Matter>[];
    }
    final matters = <Matter>[];
    await for (final entity in layout.mattersDirectory.list(
      followLinks: false,
    )) {
      if (entity is! Directory) {
        continue;
      }
      final matterFile = File(p.join(entity.path, 'matter.json'));
      if (!await matterFile.exists()) {
        continue;
      }
      try {
        matters.add(_matterCodec.decode(await matterFile.readAsString()));
      } catch (_) {
        continue;
      }
    }
    matters.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matters;
  }

  Future<List<NotebookFolder>> _readFolders(ChronicleLayout layout) async {
    final folders = <NotebookFolder>[];
    if (await layout.notebookFoldersIndexFile.exists()) {
      try {
        final decoded =
            json.decode(await layout.notebookFoldersIndexFile.readAsString())
                as Map<String, dynamic>;
        final items = decoded['folders'] as List<dynamic>? ?? const <dynamic>[];
        for (final item in items) {
          if (item is Map<String, dynamic>) {
            folders.add(NotebookFolder.fromJson(item));
          }
        }
      } catch (_) {
        // Ignore malformed folder indexes in backups and recover from directories.
      }
    }

    final byId = <String, NotebookFolder>{
      for (final folder in folders) folder.id: folder,
    };
    if (await layout.notebookFoldersDirectory.exists()) {
      await for (final entity in layout.notebookFoldersDirectory.list(
        followLinks: false,
      )) {
        if (entity is! Directory) {
          continue;
        }
        final folderId = p.basename(entity.path);
        byId.putIfAbsent(
          folderId,
          () => NotebookFolder(
            id: folderId,
            name:
                'Recovered folder ${folderId.length <= 8 ? folderId : folderId.substring(0, 8)}',
            parentId: null,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        );
      }
    }
    return byId.values.toList(growable: false);
  }

  Future<List<Note>> _readNotes(ChronicleLayout layout) async {
    final files = <File>[];
    if (await layout.notebookRootDirectory.exists()) {
      files.addAll(
        (await _fileSystemUtils.listFilesRecursively(
          layout.notebookRootDirectory,
        )).where(_isNoteFile),
      );
    }
    if (await layout.notebookFoldersDirectory.exists()) {
      files.addAll(
        (await _fileSystemUtils.listFilesRecursively(
          layout.notebookFoldersDirectory,
        )).where(_isNoteFile),
      );
    }
    if (await layout.mattersDirectory.exists()) {
      files.addAll(
        (await _fileSystemUtils.listFilesRecursively(
          layout.mattersDirectory,
        )).where(_isNoteFile),
      );
    }
    if (await layout.orphansDirectory.exists()) {
      files.addAll(
        (await _fileSystemUtils.listFilesRecursively(
          layout.orphansDirectory,
        )).where(_isNoteFile),
      );
    }

    final notes = <Note>[];
    for (final file in files) {
      try {
        notes.add(_noteCodec.decode(await file.readAsString()));
      } catch (_) {
        continue;
      }
    }
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  bool _isNoteFile(File file) {
    return file.path.endsWith('.md') && !file.path.contains('.conflict.');
  }

  Future<List<NoteLink>> _readLinks(ChronicleLayout layout) async {
    if (!await layout.linksDirectory.exists()) {
      return <NoteLink>[];
    }
    final files = await _fileSystemUtils.listFilesRecursively(
      layout.linksDirectory,
    );
    final links = <NoteLink>[];
    for (final file in files.where((item) => item.path.endsWith('.json'))) {
      try {
        links.add(_linkCodec.decode(await file.readAsString()));
      } catch (_) {
        continue;
      }
    }
    return links;
  }

  Future<List<File>> _readResources(ChronicleLayout layout) async {
    if (!await layout.resourcesDirectory.exists()) {
      return <File>[];
    }
    return _fileSystemUtils.listFilesRecursively(layout.resourcesDirectory);
  }

  String _folderNameKey(String? parentId, String name) {
    return '${parentId ?? ''}|${name.trim().toLowerCase()}';
  }

  int _folderDepth(Map<String, NotebookFolder> byId, NotebookFolder folder) {
    var depth = 0;
    var currentParentId = folder.parentId;
    while (currentParentId != null) {
      currentParentId = byId[currentParentId]?.parentId;
      depth += 1;
    }
    return depth;
  }

  String _uniqueFolderName({
    required String? parentId,
    required String originalName,
    required Set<String> usedNames,
  }) {
    final trimmed = originalName.trim().isEmpty
        ? 'Imported folder'
        : originalName.trim();
    var candidate = trimmed;
    var index = 1;
    while (usedNames.contains(_folderNameKey(parentId, candidate))) {
      candidate = index == 1
          ? '$trimmed (Imported)'
          : '$trimmed (Imported $index)';
      index += 1;
    }
    usedNames.add(_folderNameKey(parentId, candidate));
    return candidate;
  }

  Future<ChronicleLayout> _layout() async {
    final root = await _storageRootLocator.requireRootDirectory();
    await _storageInitializer.ensureInitialized(root);
    return ChronicleLayout(root);
  }
}

class _ExtractedBackup {
  const _ExtractedBackup({
    required this.tempDirectory,
    required this.storageRootDirectory,
  });

  final Directory tempDirectory;
  final Directory storageRootDirectory;
}

class _ImportedStorageState {
  const _ImportedStorageState({
    required this.categories,
    required this.matters,
    required this.folders,
    required this.notes,
    required this.links,
    required this.resourceFiles,
  });

  final List<Category> categories;
  final List<Matter> matters;
  final List<NotebookFolder> folders;
  final List<Note> notes;
  final List<NoteLink> links;
  final List<File> resourceFiles;

  int get categoryCount => categories.length;
  int get matterCount => matters.length;
  int get folderCount => folders.length;
  int get noteCount => notes.length;
  int get linkCount => links.length;
  int get resourceCount => resourceFiles.length;

  Map<String, NotebookFolder> get folderById => <String, NotebookFolder>{
    for (final folder in folders) folder.id: folder,
  };
}

class _RemappedOwnership {
  const _RemappedOwnership({
    required this.matterId,
    required this.phaseId,
    required this.notebookFolderId,
  });

  final String? matterId;
  final String? phaseId;
  final String? notebookFolderId;
}

class _ImportCounts {
  const _ImportCounts({
    required this.importedCategoryCount,
    required this.importedMatterCount,
    required this.importedNotebookFolderCount,
    required this.importedNoteCount,
    required this.importedLinkCount,
    required this.importedResourceCount,
  });

  final int importedCategoryCount;
  final int importedMatterCount;
  final int importedNotebookFolderCount;
  final int importedNoteCount;
  final int importedLinkCount;
  final int importedResourceCount;
}
