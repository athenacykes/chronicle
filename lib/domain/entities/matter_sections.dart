import 'matter.dart';

class MatterSections {
  const MatterSections({
    required this.pinned,
    required this.active,
    required this.paused,
    required this.completed,
    required this.archived,
  });

  final List<Matter> pinned;
  final List<Matter> active;
  final List<Matter> paused;
  final List<Matter> completed;
  final List<Matter> archived;
}
