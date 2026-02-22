import '../../entities/matter.dart';
import '../../repositories/matter_repository.dart';

class CreateMatter {
  const CreateMatter(this._matterRepository);

  final MatterRepository _matterRepository;

  Future<Matter> call({
    required String title,
    String description = '',
    String? categoryId,
    String color = '#4C956C',
    String icon = 'description',
    bool isPinned = false,
  }) {
    return _matterRepository.createMatter(
      title: title,
      description: description,
      categoryId: categoryId,
      color: color,
      icon: icon,
      isPinned: isPinned,
    );
  }
}
