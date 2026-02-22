import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/matter.dart';
import '../../domain/entities/matter_sections.dart';
import '../../domain/entities/phase.dart';
import '../../domain/usecases/categories/create_category.dart';
import '../../domain/usecases/categories/delete_category.dart';
import '../../domain/usecases/categories/update_category.dart';
import '../../domain/usecases/matters/create_matter.dart';
import '../../domain/usecases/matters/list_matter_sections.dart';
import '../../domain/usecases/matters/update_matter.dart';

final selectedMatterIdProvider = StateProvider<String?>((ref) => null);
final selectedPhaseIdProvider = StateProvider<String?>((ref) => null);
final matterViewModeProvider = StateProvider<MatterViewMode>(
  (ref) => MatterViewMode.phase,
);
final showOrphansProvider = StateProvider<bool>((ref) => false);

final mattersControllerProvider =
    AsyncNotifierProvider<MattersController, MatterSections>(
      MattersController.new,
    );

class MattersController extends AsyncNotifier<MatterSections> {
  @override
  Future<MatterSections> build() async {
    return _loadSections();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = AsyncData(await _loadSections());
  }

  Future<void> createMatter({
    required String title,
    String description = '',
    String? categoryId,
    MatterStatus status = MatterStatus.active,
    String color = '#4C956C',
    String icon = 'description',
    bool isPinned = false,
  }) async {
    final created = await CreateMatter(ref.read(matterRepositoryProvider))(
      title: title,
      description: description,
      categoryId: categoryId,
      color: color,
      icon: icon,
      isPinned: isPinned,
    );

    if (status != MatterStatus.active) {
      await ref
          .read(matterRepositoryProvider)
          .setMatterStatus(created.id, status);
    }

    final sections = await _loadSections();
    state = AsyncData(sections);

    ref.read(showOrphansProvider.notifier).state = false;
    ref.read(selectedMatterIdProvider.notifier).state = created.id;
    ref.read(selectedPhaseIdProvider.notifier).state =
        created.currentPhaseId ??
        (created.phases.isEmpty ? null : created.phases.first.id);
  }

  Future<void> setMatterStatus(String matterId, MatterStatus status) async {
    await ref.read(matterRepositoryProvider).setMatterStatus(matterId, status);
    state = AsyncData(await _loadSections());
  }

  Future<void> setMatterCategory(String matterId, String? categoryId) async {
    await ref
        .read(matterRepositoryProvider)
        .setMatterCategory(matterId, categoryId);
    state = AsyncData(await _loadSections());
  }

  Future<void> setMatterPinned(String matterId, bool value) async {
    await ref.read(matterRepositoryProvider).setMatterPinned(matterId, value);
    state = AsyncData(await _loadSections());
  }

  Future<void> updateMatter({
    required Matter matter,
    required String title,
    required String description,
    required String? categoryId,
    required MatterStatus status,
    required String color,
    required String icon,
    required bool isPinned,
  }) async {
    final updated = matter.copyWith(
      title: title,
      description: description,
      categoryId: categoryId,
      clearCategoryId: categoryId == null,
      status: status,
      color: color,
      icon: icon,
      isPinned: isPinned,
      updatedAt: DateTime.now().toUtc(),
    );

    await UpdateMatter(ref.read(matterRepositoryProvider)).call(updated);
    if (matter.categoryId != categoryId) {
      await ref
          .read(matterRepositoryProvider)
          .setMatterCategory(matter.id, categoryId);
    }
    if (matter.status != status) {
      await ref
          .read(matterRepositoryProvider)
          .setMatterStatus(matter.id, status);
    }

    state = AsyncData(await _loadSections());
  }

  Future<void> createCategory({
    required String name,
    String color = '#4C956C',
    String icon = 'folder',
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await CreateCategory(ref.read(categoryRepositoryProvider))(
      name: trimmed,
      color: color,
      icon: icon,
    );
    state = AsyncData(await _loadSections());
  }

  Future<void> updateCategory({
    required Category category,
    required String name,
    required String color,
    required String icon,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final updated = category.copyWith(
      name: trimmed,
      color: color,
      icon: icon,
      updatedAt: DateTime.now().toUtc(),
    );
    await UpdateCategory(ref.read(categoryRepositoryProvider))(updated);
    state = AsyncData(await _loadSections());
  }

  Future<void> deleteCategory(String categoryId) async {
    final sections = state.valueOrNull ?? await _loadSections();
    final mattersToClear = <Matter>[];
    for (final section in sections.categorySections) {
      if (section.category.id == categoryId) {
        mattersToClear.addAll(section.matters);
        break;
      }
    }
    for (final matter in mattersToClear) {
      await ref
          .read(matterRepositoryProvider)
          .setMatterCategory(matter.id, null);
    }
    await DeleteCategory(ref.read(categoryRepositoryProvider))(categoryId);
    state = AsyncData(await _loadSections());
  }

  Future<void> updateMatterPhases({
    required Matter matter,
    required List<Phase> phases,
    required String currentPhaseId,
  }) async {
    final reordered = <Phase>[
      for (var i = 0; i < phases.length; i++) phases[i].copyWith(order: i),
    ];
    final updated = matter.copyWith(
      phases: reordered,
      currentPhaseId: currentPhaseId,
      updatedAt: DateTime.now().toUtc(),
    );
    await UpdateMatter(ref.read(matterRepositoryProvider)).call(updated);
    state = AsyncData(await _loadSections());

    if (ref.read(selectedMatterIdProvider) == matter.id) {
      final selectedPhaseId = ref.read(selectedPhaseIdProvider);
      final phaseExists =
          selectedPhaseId != null &&
          reordered.any((phase) => phase.id == selectedPhaseId);
      if (!phaseExists) {
        ref.read(selectedPhaseIdProvider.notifier).state = currentPhaseId;
      }
    }
  }

  Future<void> setMatterCurrentPhase({
    required Matter matter,
    required String phaseId,
  }) async {
    final phaseExists = matter.phases.any((phase) => phase.id == phaseId);
    if (!phaseExists) {
      return;
    }
    final updated = matter.copyWith(
      currentPhaseId: phaseId,
      updatedAt: DateTime.now().toUtc(),
    );
    await UpdateMatter(ref.read(matterRepositoryProvider)).call(updated);
    state = AsyncData(await _loadSections());
    if (ref.read(selectedMatterIdProvider) == matter.id) {
      ref.read(selectedPhaseIdProvider.notifier).state = phaseId;
    }
  }

  Future<void> addPhase({required Matter matter, required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final phase = Phase(
      id: ref.read(idGeneratorProvider).newId(),
      matterId: matter.id,
      name: trimmed,
      order: matter.phases.length,
    );
    final phases = <Phase>[...matter.phases, phase];
    final currentPhaseId = matter.currentPhaseId ?? phase.id;
    await updateMatterPhases(
      matter: matter,
      phases: phases,
      currentPhaseId: currentPhaseId,
    );
  }

  Future<void> deleteMatter(String matterId) async {
    await ref.read(matterRepositoryProvider).deleteMatter(matterId);
    final sections = await _loadSections();
    state = AsyncData(sections);

    final currentSelected = ref.read(selectedMatterIdProvider);
    if (currentSelected == matterId) {
      final remaining = _allMatters(sections);
      if (remaining.isEmpty) {
        ref.read(selectedMatterIdProvider.notifier).state = null;
        ref.read(selectedPhaseIdProvider.notifier).state = null;
      } else {
        final next = remaining.first;
        ref.read(selectedMatterIdProvider.notifier).state = next.id;
        ref.read(selectedPhaseIdProvider.notifier).state =
            next.currentPhaseId ??
            (next.phases.isEmpty ? null : next.phases.first.id);
      }
    }
  }

  Matter? findMatter(String id) {
    final value = state.valueOrNull;
    if (value == null) {
      return null;
    }

    for (final matter in _allMatters(value)) {
      if (matter.id == id) {
        return matter;
      }
    }
    return null;
  }

  Future<MatterSections> _loadSections() {
    return ListMatterSections(
      ref.read(matterRepositoryProvider),
      ref.read(categoryRepositoryProvider),
    ).call();
  }

  List<Matter> _allMatters(MatterSections sections) {
    return <Matter>[
      ...sections.pinned,
      ...sections.uncategorized,
      ...sections.categorySections.expand((section) => section.matters),
    ];
  }
}
