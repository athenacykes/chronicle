import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/entities/sync_conflict.dart';

final showConflictsProvider = StateProvider<bool>((ref) => false);
final selectedConflictPathProvider = StateProvider<String?>((ref) => null);

final conflictsControllerProvider =
    AsyncNotifierProvider<ConflictsController, List<SyncConflict>>(
      ConflictsController.new,
    );

final conflictCountProvider = Provider<int>((ref) {
  final asyncConflicts = ref.watch(conflictsControllerProvider);
  return asyncConflicts.valueOrNull?.length ?? 0;
});

final selectedConflictProvider = Provider<SyncConflict?>((ref) {
  final selectedPath = ref.watch(selectedConflictPathProvider);
  final conflicts = ref.watch(conflictsControllerProvider).valueOrNull;
  if (selectedPath == null || conflicts == null) {
    return null;
  }

  for (final conflict in conflicts) {
    if (conflict.conflictPath == selectedPath) {
      return conflict;
    }
  }
  return null;
});

final selectedConflictContentProvider = FutureProvider<String?>((ref) {
  final selected = ref.watch(selectedConflictProvider);
  if (selected == null) {
    return Future<String?>.value(null);
  }

  return ref
      .read(conflictServiceProvider)
      .readConflictContent(selected.conflictPath);
});

class ConflictsController extends AsyncNotifier<List<SyncConflict>> {
  @override
  Future<List<SyncConflict>> build() async {
    return _load();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = AsyncData(await _load());

    final selected = ref.read(selectedConflictPathProvider);
    if (selected == null) {
      return;
    }

    final exists =
        state.valueOrNull?.any(
          (conflict) => conflict.conflictPath == selected,
        ) ??
        false;
    if (!exists) {
      ref.read(selectedConflictPathProvider.notifier).state = null;
    }
  }

  void selectConflict(String? conflictPath) {
    ref.read(selectedConflictPathProvider.notifier).state = conflictPath;
    ref.invalidate(selectedConflictContentProvider);
  }

  Future<void> resolveConflict(String conflictPath) async {
    await ref.read(conflictServiceProvider).resolveConflict(conflictPath);
    await reload();
  }

  Future<List<SyncConflict>> _load() {
    return ref.read(conflictServiceProvider).listConflicts();
  }
}
