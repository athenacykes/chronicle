import '../../entities/enums.dart';
import '../../entities/matter.dart';
import '../../entities/matter_sections.dart';
import '../../repositories/matter_repository.dart';

class ListMatterSections {
  const ListMatterSections(this._matterRepository);

  final MatterRepository _matterRepository;

  Future<MatterSections> call() async {
    final matters = await _matterRepository.listMatters();

    final pinned = <Matter>[];
    final active = <Matter>[];
    final paused = <Matter>[];
    final completed = <Matter>[];
    final archived = <Matter>[];

    for (final matter in matters) {
      if (matter.isPinned) {
        pinned.add(matter);
      }

      switch (matter.status) {
        case MatterStatus.active:
          active.add(matter);
        case MatterStatus.paused:
          paused.add(matter);
        case MatterStatus.completed:
          completed.add(matter);
        case MatterStatus.archived:
          archived.add(matter);
      }
    }

    int byPinnedAndUpdatedDesc(Matter a, Matter b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    }

    pinned.sort(byPinnedAndUpdatedDesc);
    active.sort(byPinnedAndUpdatedDesc);
    paused.sort(byPinnedAndUpdatedDesc);
    completed.sort(byPinnedAndUpdatedDesc);
    archived.sort(byPinnedAndUpdatedDesc);

    return MatterSections(
      pinned: pinned,
      active: active,
      paused: paused,
      completed: completed,
      archived: archived,
    );
  }
}
