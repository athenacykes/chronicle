import '../../entities/enums.dart';
import '../../repositories/matter_repository.dart';

class ArchiveMatter {
  const ArchiveMatter(this._matterRepository);

  final MatterRepository _matterRepository;

  Future<void> call(String matterId) {
    return _matterRepository.setMatterStatus(matterId, MatterStatus.archived);
  }
}
