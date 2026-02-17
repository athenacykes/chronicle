import '../../entities/matter.dart';
import '../../repositories/matter_repository.dart';

class UpdateMatter {
  const UpdateMatter(this._matterRepository);

  final MatterRepository _matterRepository;

  Future<void> call(Matter matter) {
    return _matterRepository.updateMatter(matter);
  }
}
