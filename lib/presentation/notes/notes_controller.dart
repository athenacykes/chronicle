import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/note.dart';
import '../../domain/usecases/notes/create_note.dart';
import '../links/links_controller.dart';
import '../matters/matters_controller.dart';
import '../sync/conflicts_controller.dart';

final selectedNoteIdProvider = StateProvider<String?>((ref) => null);
final previewModeProvider = StateProvider<bool>((ref) => false);

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
      return <Note>[];
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
    ref.read(selectedNoteIdProvider.notifier).state = noteId;
    if (noteId == null) {
      state = const AsyncData(null);
      return;
    }

    state = const AsyncLoading();
    final note = await ref.read(noteRepositoryProvider).getNoteById(noteId);
    state = AsyncData(note);
  }

  Future<Note?> createNoteForSelectedMatter() async {
    final matterId = ref.read(selectedMatterIdProvider);
    if (matterId == null) {
      return null;
    }

    final phaseId = ref.read(selectedPhaseIdProvider);
    final created = await CreateNote(ref.read(noteRepositoryProvider)).call(
      title: 'Untitled Note',
      content: '# Untitled Note\n',
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
  }) async {
    final created = await CreateNote(ref.read(noteRepositoryProvider)).call(
      title: title,
      content: content,
      tags: tags,
      isPinned: isPinned,
      matterId: matterId,
      phaseId: phaseId,
    );

    await _refreshCollections();
    await selectNote(created.id);
    return created;
  }

  Future<Note> createOrphan() async {
    final created = await CreateNote(ref.read(noteRepositoryProvider)).call(
      title: 'Quick Capture',
      content: '# Quick Capture\n',
      matterId: null,
      phaseId: null,
    );

    await _refreshCollections();
    await selectNote(created.id);
    return created;
  }

  Future<void> updateCurrent({
    String? title,
    String? content,
    List<String>? tags,
    bool? isPinned,
  }) async {
    final current = state.valueOrNull;
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
    bool clearMatter = false,
    bool clearPhase = false,
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
      clearMatterId: clearMatter,
      clearPhaseId: clearPhase,
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
  }) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    await ref
        .read(noteRepositoryProvider)
        .moveNote(noteId: current.id, matterId: matterId, phaseId: phaseId);

    await _refreshCollections();
    await selectNote(current.id);
  }

  Future<void> deleteCurrent() async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    await ref.read(noteRepositoryProvider).deleteNote(current.id);
    ref.read(selectedNoteIdProvider.notifier).state = null;

    await _refreshCollections();
    state = const AsyncData(null);
  }

  Future<void> deleteNote(String noteId) async {
    await ref.read(noteRepositoryProvider).deleteNote(noteId);
    if (ref.read(selectedNoteIdProvider) == noteId) {
      ref.read(selectedNoteIdProvider.notifier).state = null;
      state = const AsyncData(null);
    }
    await _refreshCollections();
  }

  Future<void> openNoteInWorkspace(String noteId) async {
    final note = await ref.read(noteRepositoryProvider).getNoteById(noteId);
    if (note == null) {
      return;
    }

    ref.read(showConflictsProvider.notifier).state = false;

    if (note.isOrphan) {
      ref.read(showOrphansProvider.notifier).state = true;
      ref.read(selectedMatterIdProvider.notifier).state = null;
      ref.read(selectedPhaseIdProvider.notifier).state = null;
    } else {
      ref.read(showOrphansProvider.notifier).state = false;
      ref.read(selectedMatterIdProvider.notifier).state = note.matterId;
      ref.read(selectedPhaseIdProvider.notifier).state = note.phaseId;
    }

    ref.invalidate(noteListProvider);
    await selectNote(noteId);
  }

  Future<void> _refreshCollections() async {
    ref.invalidate(noteListProvider);
    ref.invalidate(orphanNotesProvider);
    await ref.read(searchRepositoryProvider).rebuildIndex();
    ref.read(linksControllerProvider).invalidateAll();
  }
}
