import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/notebook_folder.dart';
import '../../domain/entities/notebook_import_result.dart';
import '../../domain/usecases/notes/create_note.dart';
import '../../l10n/localization.dart';
import '../common/state/value_notifier_provider.dart';
import '../common/shell/chronicle_time_views_controller.dart';
import '../links/links_controller.dart';
import '../matters/matters_controller.dart';
import '../settings/settings_controller.dart';
import '../sync/conflicts_controller.dart';

final selectedNoteIdProvider =
    NotifierProvider<ValueNotifierController<String?>, String?>(
      () => ValueNotifierController<String?>(null),
    );
final selectedNotebookFolderIdProvider =
    NotifierProvider<ValueNotifierController<String?>, String?>(
      () => ValueNotifierController<String?>(null),
    );

enum NoteEditorViewMode { edit, read }

final noteEditorViewModeProvider =
    NotifierProvider<
      ValueNotifierController<NoteEditorViewMode>,
      NoteEditorViewMode
    >(
      () =>
          ValueNotifierController<NoteEditorViewMode>(NoteEditorViewMode.edit),
    );

final noteListProvider = FutureProvider<List<Note>>((ref) async {
  final repository = ref.watch(noteRepositoryProvider);
  final matterId = ref.watch(selectedMatterIdProvider);
  final viewMode = ref.watch(matterViewModeProvider);
  final phaseId = ref.watch(selectedPhaseIdProvider);

  if (matterId == null || matterId.isEmpty) {
    return <Note>[];
  }

  if (viewMode == MatterViewMode.phase) {
    if (phaseId == null || phaseId.isEmpty) {
      return repository.listMatterTimeline(matterId);
    }
    return repository.listNotesByMatterAndPhase(
      matterId: matterId,
      phaseId: phaseId,
    );
  }

  return repository.listMatterTimeline(matterId);
});

final orphanNotesProvider = FutureProvider<List<Note>>((ref) {
  return ref.watch(noteRepositoryProvider).listOrphanNotes();
});

final notebookFoldersProvider = FutureProvider<List<NotebookFolder>>((ref) {
  return ref.watch(notebookRepositoryProvider).listFolders();
});

final notebookFolderTreeProvider = Provider<List<NotebookFolderTreeNode>>((
  ref,
) {
  final folders =
      ref.watch(notebookFoldersProvider).asData?.value ?? <NotebookFolder>[];
  return buildNotebookFolderTree(folders);
});

final notebookNoteListProvider = FutureProvider<List<Note>>((ref) {
  final folderId = ref.watch(selectedNotebookFolderIdProvider);
  return ref
      .watch(noteRepositoryProvider)
      .listNotebookNotes(folderId: folderId);
});

class NotebookFolderTreeNode {
  const NotebookFolderTreeNode({required this.folder, required this.children});

  final NotebookFolder folder;
  final List<NotebookFolderTreeNode> children;
}

List<NotebookFolderTreeNode> buildNotebookFolderTree(
  List<NotebookFolder> folders,
) {
  final byParent = <String?, List<NotebookFolder>>{};
  for (final folder in folders) {
    byParent.putIfAbsent(folder.parentId, () => <NotebookFolder>[]).add(folder);
  }
  for (final items in byParent.values) {
    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<NotebookFolderTreeNode> build(String? parentId) {
    final items = byParent[parentId] ?? const <NotebookFolder>[];
    return items
        .map(
          (folder) => NotebookFolderTreeNode(
            folder: folder,
            children: build(folder.id),
          ),
        )
        .toList(growable: false);
  }

  return build(null);
}

final noteEditorControllerProvider =
    AsyncNotifierProvider<NoteEditorController, Note?>(
      NoteEditorController.new,
    );

class NoteEditorController extends AsyncNotifier<Note?> {
  @override
  Future<Note?> build() async {
    final noteId = ref.watch(selectedNoteIdProvider);
    if (noteId == null || noteId.isEmpty) {
      return null;
    }
    return ref.read(noteRepositoryProvider).getNoteById(noteId);
  }

  Future<void> selectNote(String? noteId) async {
    if (noteId == null) {
      state = const AsyncData(null);
      ref.read(selectedNoteIdProvider.notifier).set(null);
      return;
    }

    final note = await ref.read(noteRepositoryProvider).getNoteById(noteId);
    state = AsyncData(note);
    ref.read(selectedNoteIdProvider.notifier).set(noteId);
  }

  Future<Note?> createNoteForSelectedMatter() async {
    final matterId = ref.read(selectedMatterIdProvider);
    if (matterId == null) {
      return null;
    }

    final l10n = appLocalizationsForTag(
      ref.read(settingsControllerProvider).asData?.value.localeTag,
    );

    var phaseId = ref.read(selectedPhaseIdProvider);
    if (phaseId == null || phaseId.isEmpty) {
      final matter = await ref
          .read(matterRepositoryProvider)
          .getMatterById(matterId);
      phaseId =
          matter?.currentPhaseId ??
          (matter?.phases.isEmpty ?? true ? null : matter!.phases.first.id);
    }
    final created = await CreateNote(ref.read(noteRepositoryProvider)).call(
      title: l10n.defaultUntitledNoteTitle,
      content: '# ${l10n.defaultUntitledNoteTitle}\n',
      matterId: matterId,
      phaseId: phaseId,
    );

    await _refreshCollections();
    await selectNote(created.id);
    return created;
  }

  Future<Note> createCustomNote({
    required String title,
    required String content,
    required List<String> tags,
    required bool isPinned,
    required String? matterId,
    required String? phaseId,
    String? notebookFolderId,
  }) async {
    final created = await CreateNote(ref.read(noteRepositoryProvider)).call(
      title: title,
      content: content,
      tags: tags,
      isPinned: isPinned,
      matterId: matterId,
      phaseId: phaseId,
      notebookFolderId: notebookFolderId,
    );

    await _refreshCollections();
    await selectNote(created.id);
    return created;
  }

  Future<Note> createOrphan() async {
    final l10n = appLocalizationsForTag(
      ref.read(settingsControllerProvider).asData?.value.localeTag,
    );

    final created = await CreateNote(ref.read(noteRepositoryProvider)).call(
      title: l10n.defaultQuickCaptureTitle,
      content: '# ${l10n.defaultQuickCaptureTitle}\n',
      matterId: null,
      phaseId: null,
      notebookFolderId: null,
    );

    await _refreshCollections();
    await selectNote(created.id);
    return created;
  }

  Future<Note> createUntitledOrphanNote() async {
    final l10n = appLocalizationsForTag(
      ref.read(settingsControllerProvider).asData?.value.localeTag,
    );

    final created = await CreateNote(ref.read(noteRepositoryProvider)).call(
      title: l10n.defaultUntitledNoteTitle,
      content: '# ${l10n.defaultUntitledNoteTitle}\n',
      matterId: null,
      phaseId: null,
      notebookFolderId: ref.read(selectedNotebookFolderIdProvider),
    );

    await _refreshCollections();
    await selectNote(created.id);
    return created;
  }

  Future<Note> createUntitledNotebookNote() async {
    return createUntitledOrphanNote();
  }

  Future<NotebookImportBatchResult?> importNotebookFilesFromPicker() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      type: FileType.custom,
      allowedExtensions: const <String>['enex', 'jex'],
    );
    if (picked == null || picked.files.isEmpty) {
      return null;
    }

    final sourcePaths = picked.files
        .map((file) => file.path)
        .whereType<String>()
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (sourcePaths.isEmpty) {
      return null;
    }

    final result = await ref
        .read(notebookImportRepositoryProvider)
        .importFiles(sourcePaths: sourcePaths);
    await _refreshCollections();
    return result;
  }

  Future<void> selectNotebookFolder(String? folderId) async {
    ref.read(selectedTimeViewProvider.notifier).set(null);
    ref.read(showNotebookProvider.notifier).set(true);
    ref.read(showConflictsProvider.notifier).set(false);
    ref.read(selectedMatterIdProvider.notifier).set(null);
    ref.read(selectedPhaseIdProvider.notifier).set(null);
    ref.read(selectedNotebookFolderIdProvider.notifier).set(folderId);
    ref.invalidate(notebookNoteListProvider);
  }

  Future<void> createNotebookFolder({
    required String name,
    String? parentId,
  }) async {
    await ref
        .read(notebookRepositoryProvider)
        .createFolder(name: name, parentId: parentId);
    await _refreshCollections();
  }

  Future<void> renameNotebookFolder({
    required String folderId,
    required String name,
  }) async {
    await ref
        .read(notebookRepositoryProvider)
        .renameFolder(folderId: folderId, name: name);
    await _refreshCollections();
  }

  Future<void> deleteNotebookFolder(String folderId) async {
    final selectedFolderId = ref.read(selectedNotebookFolderIdProvider);
    final folder = await ref
        .read(notebookRepositoryProvider)
        .getFolderById(folderId);
    await ref.read(notebookRepositoryProvider).deleteFolder(folderId);
    if (selectedFolderId == folderId) {
      ref.read(selectedNotebookFolderIdProvider.notifier).set(folder?.parentId);
    }
    await _refreshCollections();
  }

  Future<void> updateCurrent({
    String? title,
    String? content,
    List<String>? tags,
    bool? isPinned,
  }) async {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }

    final updated = current.copyWith(
      title: title ?? current.title,
      content: content ?? current.content,
      tags: tags ?? current.tags,
      isPinned: isPinned ?? current.isPinned,
      updatedAt: DateTime.now().toUtc(),
    );

    await ref.read(noteRepositoryProvider).updateNote(updated);
    await _refreshCollections();
    state = AsyncData(updated);
  }

  Future<void> updateNoteById({
    required String noteId,
    String? title,
    String? content,
    List<String>? tags,
    bool? isPinned,
    String? matterId,
    String? phaseId,
    String? notebookFolderId,
    bool clearMatter = false,
    bool clearPhase = false,
    bool clearNotebookFolder = false,
  }) async {
    final existing = await ref.read(noteRepositoryProvider).getNoteById(noteId);
    if (existing == null) {
      return;
    }

    final updated = existing.copyWith(
      title: title ?? existing.title,
      content: content ?? existing.content,
      tags: tags ?? existing.tags,
      isPinned: isPinned ?? existing.isPinned,
      matterId: clearMatter ? null : matterId ?? existing.matterId,
      phaseId: clearPhase ? null : phaseId ?? existing.phaseId,
      notebookFolderId: clearNotebookFolder
          ? null
          : notebookFolderId ?? existing.notebookFolderId,
      clearMatterId: clearMatter,
      clearPhaseId: clearPhase,
      clearNotebookFolderId: clearNotebookFolder,
      updatedAt: DateTime.now().toUtc(),
    );

    await ref.read(noteRepositoryProvider).updateNote(updated);
    await _refreshCollections();
    if (ref.read(selectedNoteIdProvider) == noteId) {
      state = AsyncData(updated);
    }
  }

  Future<void> moveCurrent({
    required String? matterId,
    required String? phaseId,
    required String? notebookFolderId,
  }) async {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }

    await moveNoteById(
      noteId: current.id,
      matterId: matterId,
      phaseId: phaseId,
      notebookFolderId: notebookFolderId,
    );
  }

  Future<void> moveNoteById({
    required String noteId,
    required String? matterId,
    required String? phaseId,
    required String? notebookFolderId,
  }) async {
    await ref
        .read(noteRepositoryProvider)
        .moveNote(
          noteId: noteId,
          matterId: matterId,
          phaseId: phaseId,
          notebookFolderId: notebookFolderId,
        );

    await _refreshCollections();
    if (ref.read(selectedNoteIdProvider) == noteId) {
      await selectNote(noteId);
    }
  }

  Future<void> deleteCurrent() async {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }

    await ref.read(noteRepositoryProvider).deleteNote(current.id);
    ref.read(selectedNoteIdProvider.notifier).set(null);

    await _refreshCollections();
    state = const AsyncData(null);
  }

  Future<void> deleteNote(String noteId) async {
    await ref.read(noteRepositoryProvider).deleteNote(noteId);
    if (ref.read(selectedNoteIdProvider) == noteId) {
      ref.read(selectedNoteIdProvider.notifier).set(null);
      state = const AsyncData(null);
    }
    await _refreshCollections();
  }

  Future<Note?> attachFilesToCurrent() async {
    final current = state.asData?.value;
    if (current == null) {
      return null;
    }

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      type: FileType.any,
    );
    if (picked == null || picked.files.isEmpty) {
      return current;
    }

    final paths = picked.files
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .toList();
    if (paths.isEmpty) {
      return current;
    }

    final updated = await ref
        .read(noteRepositoryProvider)
        .addAttachments(noteId: current.id, sourceFilePaths: paths);
    await _refreshCollections();
    state = AsyncData(updated);
    return updated;
  }

  Future<Note?> removeAttachmentFromCurrent(String attachmentPath) async {
    final current = state.asData?.value;
    if (current == null) {
      return null;
    }

    final updated = await ref
        .read(noteRepositoryProvider)
        .removeAttachment(noteId: current.id, attachmentPath: attachmentPath);
    await _refreshCollections();
    state = AsyncData(updated);
    return updated;
  }

  Future<void> openNoteInWorkspace(
    String noteId, {
    bool openInReadMode = false,
  }) async {
    final note = await ref.read(noteRepositoryProvider).getNoteById(noteId);
    if (note == null) {
      return;
    }

    ref.read(selectedTimeViewProvider.notifier).set(null);
    ref.read(showConflictsProvider.notifier).set(false);

    if (note.isInNotebook) {
      ref.read(showNotebookProvider.notifier).set(true);
      ref.read(selectedMatterIdProvider.notifier).set(null);
      ref.read(selectedPhaseIdProvider.notifier).set(null);
      ref
          .read(selectedNotebookFolderIdProvider.notifier)
          .set(note.notebookFolderId);
    } else {
      ref.read(showNotebookProvider.notifier).set(false);
      ref.read(selectedMatterIdProvider.notifier).set(note.matterId);
      ref.read(selectedPhaseIdProvider.notifier).set(note.phaseId);
      ref.read(selectedNotebookFolderIdProvider.notifier).set(null);
      ref.read(matterViewModeProvider.notifier).set(MatterViewMode.phase);
      if (note.matterId != null && note.phaseId != null) {
        final matter = ref
            .read(mattersControllerProvider.notifier)
            .findMatter(note.matterId!);
        if (matter != null) {
          await ref
              .read(mattersControllerProvider.notifier)
              .setMatterCurrentPhase(matter: matter, phaseId: note.phaseId!);
        }
      }
    }

    ref.invalidate(noteListProvider);
    await selectNote(noteId);
    if (openInReadMode) {
      ref
          .read(noteEditorViewModeProvider.notifier)
          .set(NoteEditorViewMode.read);
    }
  }

  Future<void> _refreshCollections() async {
    ref.invalidate(noteListProvider);
    ref.invalidate(notebookNoteListProvider);
    ref.invalidate(notebookFoldersProvider);
    ref.invalidate(notebookFolderTreeProvider);
    ref.invalidate(orphanNotesProvider);
    ref.invalidate(timeViewSummaryProvider);
    await ref.read(searchRepositoryProvider).rebuildIndex();
    ref.read(linksControllerProvider).invalidateAll();
  }
}
