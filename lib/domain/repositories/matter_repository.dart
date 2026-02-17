import '../entities/enums.dart';
import '../entities/matter.dart';

abstract class MatterRepository {
  Future<List<Matter>> listMatters();
  Future<Matter?> getMatterById(String matterId);
  Future<Matter> createMatter({
    required String title,
    String description,
    String color,
    String icon,
    bool isPinned,
  });
  Future<void> updateMatter(Matter matter);
  Future<void> setMatterStatus(String matterId, MatterStatus status);
  Future<void> setMatterPinned(String matterId, bool isPinned);
  Future<void> deleteMatter(String matterId);
}
