import 'dart:io';

import 'package:chronicle/core/clock.dart';
import 'package:chronicle/core/file_system_utils.dart';
import 'package:chronicle/core/id_generator.dart';
import 'package:chronicle/data/local_fs/chronicle_layout.dart';
import 'package:chronicle/data/local_fs/chronicle_storage_initializer.dart';
import 'package:chronicle/data/local_fs/link_file_codec.dart';
import 'package:chronicle/data/local_fs/local_category_repository.dart';
import 'package:chronicle/data/local_fs/local_chronicle_backup_repository.dart';
import 'package:chronicle/data/local_fs/local_link_repository.dart';
import 'package:chronicle/data/local_fs/local_matter_repository.dart';
import 'package:chronicle/data/local_fs/local_note_repository.dart';
import 'package:chronicle/data/local_fs/local_notebook_repository.dart';
import 'package:chronicle/data/local_fs/matter_file_codec.dart';
import 'package:chronicle/data/local_fs/note_file_codec.dart';
import 'package:chronicle/data/local_fs/storage_root_locator.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/chronicle_backup_result.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Directory sourceRoot;
  late Directory targetRoot;
  late FileSystemUtils fileSystemUtils;
  late ChronicleStorageInitializer storageInitializer;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'chronicle-backup-repository-test-',
    );
    sourceRoot = Directory('${tempDir.path}/source');
    targetRoot = Directory('${tempDir.path}/target');
    fileSystemUtils = const FileSystemUtils();
    storageInitializer = ChronicleStorageInitializer(fileSystemUtils);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('exports storage archive and restores blank storage', () async {
    final source = _Harness(
      root: sourceRoot,
      fileSystemUtils: fileSystemUtils,
      storageInitializer: storageInitializer,
      repositoryClock: DateTime.utc(2026, 3, 28, 10),
      categoryIdStart: 1,
      matterIdStart: 1,
      notebookIdStart: 1000,
      noteIdStart: 2000,
      linkIdStart: 3000,
      backupIdStart: 9000,
    );
    await source.initialize();

    final category = await source.categoryRepository.createCategory(
      name: 'Source Category',
    );
    final matter = await source.matterRepository.createMatter(
      title: 'Source Matter',
      categoryId: category.id,
    );
    final note = await source.noteRepository.createNote(
      title: 'Source Note',
      content: '# Restored',
      matterId: matter.id,
      phaseId: matter.phases.first.id,
    );
    final resourceFile = File('${tempDir.path}/restore.txt');
    await resourceFile.writeAsString('restore-me');
    await source.noteRepository.addAttachments(
      noteId: note.id,
      sourceFilePaths: <String>[resourceFile.path],
    );

    final archivePath = '${tempDir.path}/chronicle-restore.zip';
    final exportResult = await source.backupRepository.exportToArchive(
      outputPath: archivePath,
    );
    expect(exportResult.exportedFileCount, greaterThan(0));
    expect(await File(archivePath).exists(), isTrue);

    final target = _Harness(
      root: targetRoot,
      fileSystemUtils: fileSystemUtils,
      storageInitializer: storageInitializer,
      repositoryClock: DateTime.utc(2026, 3, 28, 11),
      categoryIdStart: 1,
      matterIdStart: 1,
      notebookIdStart: 1000,
      noteIdStart: 2000,
      linkIdStart: 3000,
      backupIdStart: 9500,
    );
    await target.initialize();

    final existingMatter = await target.matterRepository.createMatter(
      title: 'Existing Matter',
    );
    await target.noteRepository.createNote(
      title: 'Existing Note',
      content: '# Old',
      matterId: existingMatter.id,
      phaseId: existingMatter.phases.first.id,
    );
    await File('${targetRoot.path}/obsolete.txt').writeAsString('stale');

    final importResult = await target.backupRepository.importFromArchive(
      archivePath: archivePath,
      mode: ChronicleBackupImportMode.blankRestore,
    );

    expect(importResult.importedMatterCount, 1);
    expect(importResult.importedNoteCount, 1);
    expect(await File('${targetRoot.path}/obsolete.txt').exists(), isFalse);

    final restoredMatters = await target.matterRepository.listMatters();
    final restoredNotes = await target.noteRepository.listAllNotes();
    expect(restoredMatters, hasLength(1));
    expect(restoredMatters.single.title, 'Source Matter');
    expect(restoredNotes, hasLength(1));
    expect(restoredNotes.single.title, 'Source Note');
  });

  test(
    'merge import remaps colliding ids and rewrites attachment paths',
    () async {
      final source = _Harness(
        root: sourceRoot,
        fileSystemUtils: fileSystemUtils,
        storageInitializer: storageInitializer,
        repositoryClock: DateTime.utc(2026, 3, 28, 12),
        categoryIdStart: 1,
        matterIdStart: 1,
        notebookIdStart: 1000,
        noteIdStart: 2000,
        linkIdStart: 3000,
        backupIdStart: 8000,
      );
      await source.initialize();

      final sourceCategory = await source.categoryRepository.createCategory(
        name: 'Imported Category',
      );
      final sourceMatter = await source.matterRepository.createMatter(
        title: 'Imported Matter',
        categoryId: sourceCategory.id,
      );
      final sourceFolder = await source.notebookRepository.createFolder(
        name: 'Imported Folder',
      );
      final sourceMatterNote = await source.noteRepository.createNote(
        title: 'Imported Matter Note',
        content: '# Imported Matter Note',
        matterId: sourceMatter.id,
        phaseId: sourceMatter.phases.first.id,
      );
      final sourceAttachment = File('${tempDir.path}/source-attachment.txt');
      await sourceAttachment.writeAsString('attachment payload');
      final sourceMatterNoteWithAttachment = await source.noteRepository
          .addAttachments(
            noteId: sourceMatterNote.id,
            sourceFilePaths: <String>[sourceAttachment.path],
          );
      final sourceMatterAttachmentPath =
          sourceMatterNoteWithAttachment.attachments.single;
      await source.noteRepository.updateNote(
        sourceMatterNoteWithAttachment.copyWith(
          content:
              'See attachment at $sourceMatterAttachmentPath in imported content.',
        ),
      );
      final sourceNotebookNote = await source.noteRepository.createNote(
        title: 'Imported Notebook Note',
        content: '# Imported Notebook',
        notebookFolderId: sourceFolder.id,
      );
      await source.linkRepository.createLink(
        sourceNoteId: sourceMatterNote.id,
        targetNoteId: sourceNotebookNote.id,
        context: 'Imported context',
      );

      final archivePath = '${tempDir.path}/chronicle-merge.zip';
      await source.backupRepository.exportToArchive(outputPath: archivePath);

      final target = _Harness(
        root: targetRoot,
        fileSystemUtils: fileSystemUtils,
        storageInitializer: storageInitializer,
        repositoryClock: DateTime.utc(2026, 3, 28, 13),
        categoryIdStart: 1,
        matterIdStart: 1,
        notebookIdStart: 1000,
        noteIdStart: 2000,
        linkIdStart: 3000,
        backupIdStart: 9000,
      );
      await target.initialize();

      final targetCategory = await target.categoryRepository.createCategory(
        name: 'Existing Category',
      );
      final targetMatter = await target.matterRepository.createMatter(
        title: 'Existing Matter',
        categoryId: targetCategory.id,
      );
      final targetFolder = await target.notebookRepository.createFolder(
        name: 'Imported Folder',
      );
      final existingMatterNote = await target.noteRepository.createNote(
        title: 'Existing Matter Note',
        content: '# Existing Matter',
        matterId: targetMatter.id,
        phaseId: targetMatter.phases.first.id,
      );
      final existingNotebookNote = await target.noteRepository.createNote(
        title: 'Existing Notebook Note',
        content: '# Existing Notebook',
        notebookFolderId: targetFolder.id,
      );

      final importResult = await target.backupRepository.importFromArchive(
        archivePath: archivePath,
        mode: ChronicleBackupImportMode.mergeExisting,
      );

      expect(importResult.importedCategoryCount, 1);
      expect(importResult.importedMatterCount, 1);
      expect(importResult.importedNotebookFolderCount, 1);
      expect(importResult.importedNoteCount, 2);
      expect(importResult.importedLinkCount, 1);
      expect(importResult.importedResourceCount, 1);

      final categories = await target.categoryRepository.listCategories();
      expect(categories, hasLength(2));
      final importedCategory = categories.firstWhere(
        (category) => category.name == 'Imported Category',
      );
      expect(importedCategory.id, isNot(sourceCategory.id));

      final folders = await target.notebookRepository.listFolders();
      expect(folders, hasLength(2));
      final importedFolder = folders.firstWhere(
        (folder) => folder.id != targetFolder.id,
      );
      expect(importedFolder.name, isNot(sourceFolder.name));
      expect(importedFolder.name, contains('Imported'));

      final notes = await target.noteRepository.listAllNotes();
      expect(notes, hasLength(4));
      final importedMatterNote = notes.firstWhere(
        (note) => note.title == 'Imported Matter Note',
      );
      expect(importedMatterNote.id, isNot(sourceMatterNote.id));
      expect(importedMatterNote.id, isNot(existingMatterNote.id));
      expect(importedMatterNote.attachments, hasLength(1));
      final importedAttachmentPath = importedMatterNote.attachments.single;
      expect(
        importedAttachmentPath,
        startsWith('resources/${importedMatterNote.id}/'),
      );
      expect(importedMatterNote.content, contains(importedAttachmentPath));
      expect(
        importedMatterNote.content,
        isNot(contains(sourceMatterAttachmentPath)),
      );

      final importedNotebookNote = notes.firstWhere(
        (note) => note.title == 'Imported Notebook Note',
      );
      expect(importedNotebookNote.id, isNot(existingNotebookNote.id));
      expect(importedNotebookNote.notebookFolderId, importedFolder.id);

      final links = await target.linkRepository.listLinks();
      expect(links, hasLength(1));
      expect(links.single.sourceNoteId, importedMatterNote.id);
      expect(links.single.targetNoteId, importedNotebookNote.id);

      final importedAttachmentFile = ChronicleLayout(
        targetRoot,
      ).fromRelativePath(importedAttachmentPath);
      expect(await importedAttachmentFile.exists(), isTrue);
      expect(await importedAttachmentFile.readAsString(), 'attachment payload');
    },
  );

  test(
    'resetStorageToBlank wipes storage and initializes a fresh root',
    () async {
      final harness = _Harness(
        root: targetRoot,
        fileSystemUtils: fileSystemUtils,
        storageInitializer: storageInitializer,
        repositoryClock: DateTime.utc(2026, 3, 28, 14),
        categoryIdStart: 1,
        matterIdStart: 1,
        notebookIdStart: 1000,
        noteIdStart: 2000,
        linkIdStart: 3000,
        backupIdStart: 9000,
      );
      await harness.initialize();

      final matter = await harness.matterRepository.createMatter(
        title: 'Reset Matter',
      );
      await harness.noteRepository.createNote(
        title: 'Reset Note',
        content: '# Content',
        matterId: matter.id,
        phaseId: matter.phases.first.id,
      );
      await File('${targetRoot.path}/stale.txt').writeAsString('stale');

      final result = await harness.backupRepository.resetStorageToBlank();
      final layout = ChronicleLayout(targetRoot);

      expect(result.rootPath, targetRoot.path);
      expect(await targetRoot.exists(), isTrue);
      expect(await File('${targetRoot.path}/stale.txt').exists(), isFalse);
      expect(await layout.infoFile.exists(), isTrue);
      expect(await layout.notebookFoldersIndexFile.exists(), isTrue);
      expect(await layout.syncVersionFile.exists(), isTrue);
      expect(await harness.matterRepository.listMatters(), isEmpty);
      expect(await harness.noteRepository.listAllNotes(), isEmpty);
    },
  );
}

class _Harness {
  _Harness({
    required this.root,
    required FileSystemUtils fileSystemUtils,
    required ChronicleStorageInitializer storageInitializer,
    required DateTime repositoryClock,
    required int categoryIdStart,
    required int matterIdStart,
    required int notebookIdStart,
    required int noteIdStart,
    required int linkIdStart,
    required int backupIdStart,
  }) : _fileSystemUtils = fileSystemUtils,
       _storageInitializer = storageInitializer,
       _repositoryClock = repositoryClock,
       _categoryIdStart = categoryIdStart,
       _matterIdStart = matterIdStart,
       _notebookIdStart = notebookIdStart,
       _noteIdStart = noteIdStart,
       _linkIdStart = linkIdStart,
       _backupIdStart = backupIdStart;

  final Directory root;
  final FileSystemUtils _fileSystemUtils;
  final ChronicleStorageInitializer _storageInitializer;
  final DateTime _repositoryClock;
  final int _categoryIdStart;
  final int _matterIdStart;
  final int _notebookIdStart;
  final int _noteIdStart;
  final int _linkIdStart;
  final int _backupIdStart;

  late final _InMemorySettingsRepository settingsRepository;
  late final StorageRootLocator storageRootLocator;
  late final LocalCategoryRepository categoryRepository;
  late final LocalMatterRepository matterRepository;
  late final LocalNotebookRepository notebookRepository;
  late final LocalNoteRepository noteRepository;
  late final LocalLinkRepository linkRepository;
  late final LocalChronicleBackupRepository backupRepository;

  Future<void> initialize() async {
    settingsRepository = _InMemorySettingsRepository(
      AppSettings(
        storageRootPath: root.path,
        clientId:
            'client-${root.uri.pathSegments.where((part) => part.isNotEmpty).last}',
        syncConfig: SyncConfig.initial(),
        lastSyncAt: null,
      ),
    );
    storageRootLocator = StorageRootLocator(settingsRepository);
    await _storageInitializer.ensureInitialized(root);

    categoryRepository = LocalCategoryRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: _storageInitializer,
      fileSystemUtils: _fileSystemUtils,
      clock: _FixedClock(_repositoryClock),
      idGenerator: _IncrementalIdGenerator(start: _categoryIdStart),
    );
    matterRepository = LocalMatterRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: _storageInitializer,
      codec: const MatterFileCodec(),
      fileSystemUtils: _fileSystemUtils,
      clock: _FixedClock(_repositoryClock),
      idGenerator: _IncrementalIdGenerator(start: _matterIdStart),
    );
    notebookRepository = LocalNotebookRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: _storageInitializer,
      fileSystemUtils: _fileSystemUtils,
      clock: _FixedClock(_repositoryClock),
      idGenerator: _IncrementalIdGenerator(start: _notebookIdStart),
      noteCodec: const NoteFileCodec(),
    );
    noteRepository = LocalNoteRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: _storageInitializer,
      codec: const NoteFileCodec(),
      fileSystemUtils: _fileSystemUtils,
      clock: _FixedClock(_repositoryClock),
      idGenerator: _IncrementalIdGenerator(start: _noteIdStart),
      matterRepository: matterRepository,
      notebookRepository: notebookRepository,
    );
    linkRepository = LocalLinkRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: _storageInitializer,
      codec: const LinkFileCodec(),
      fileSystemUtils: _fileSystemUtils,
      clock: _FixedClock(_repositoryClock),
      idGenerator: _IncrementalIdGenerator(start: _linkIdStart),
    );
    backupRepository = LocalChronicleBackupRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: _storageInitializer,
      fileSystemUtils: _fileSystemUtils,
      noteCodec: const NoteFileCodec(),
      matterCodec: const MatterFileCodec(),
      linkCodec: const LinkFileCodec(),
      idGenerator: _IncrementalIdGenerator(start: _backupIdStart),
      clock: _FixedClock(_repositoryClock.add(const Duration(minutes: 5))),
    );
  }
}

class _InMemorySettingsRepository implements SettingsRepository {
  _InMemorySettingsRepository(this._settings);

  AppSettings _settings;

  @override
  Future<void> clearSyncPassword() async {}

  @override
  Future<void> clearSyncProxyPassword() async {}

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<String?> readSyncPassword() async => null;

  @override
  Future<String?> readSyncProxyPassword() async => null;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> saveSyncPassword(String password) async {}

  @override
  Future<void> saveSyncProxyPassword(String password) async {}

  @override
  Future<void> setLastSyncAt(DateTime value) async {
    _settings = _settings.copyWith(lastSyncAt: value);
  }

  @override
  Future<void> setStorageRootPath(String path) async {
    _settings = _settings.copyWith(storageRootPath: path);
  }
}

class _FixedClock implements Clock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime nowUtc() => value;
}

class _IncrementalIdGenerator implements IdGenerator {
  _IncrementalIdGenerator({required int start}) : _counter = start;

  int _counter;

  @override
  String newId() {
    final next = _counter;
    _counter += 1;
    return 'id-$next';
  }
}
