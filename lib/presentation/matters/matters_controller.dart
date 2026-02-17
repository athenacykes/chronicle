import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/matter.dart';
import '../../domain/entities/matter_sections.dart';
import '../../domain/usecases/matters/create_matter.dart';
import '../../domain/usecases/matters/update_matter.dart';
import '../../domain/usecases/matters/list_matter_sections.dart';

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
    MatterStatus status = MatterStatus.active,
    String color = '#4C956C',
    String icon = 'description',
    bool isPinned = false,
  }) async {
    final created = await CreateMatter(ref.read(matterRepositoryProvider))(
      title: title,
      description: description,
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
    ref.read(selectedPhaseIdProvider.notifier).state = created.phases.first.id;
  }

  Future<void> setMatterStatus(String matterId, MatterStatus status) async {
    await ref.read(matterRepositoryProvider).setMatterStatus(matterId, status);
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
    required MatterStatus status,
    required String color,
    required String icon,
    required bool isPinned,
  }) async {
    final updated = matter.copyWith(
      title: title,
      description: description,
      status: status,
      color: color,
      icon: icon,
      isPinned: isPinned,
      updatedAt: DateTime.now().toUtc(),
    );

    await UpdateMatter(ref.read(matterRepositoryProvider)).call(updated);
    if (matter.status != status) {
      await ref
          .read(matterRepositoryProvider)
          .setMatterStatus(matter.id, status);
    }

    state = AsyncData(await _loadSections());
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
        ref.read(selectedPhaseIdProvider.notifier).state = next.phases.isEmpty
            ? null
            : next.phases.first.id;
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
    return ListMatterSections(ref.read(matterRepositoryProvider)).call();
  }

  List<Matter> _allMatters(MatterSections sections) {
    return <Matter>{
      ...sections.pinned,
      ...sections.active,
      ...sections.paused,
      ...sections.completed,
      ...sections.archived,
    }.toList();
  }
}
