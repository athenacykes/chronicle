import '../../core/id_generator.dart';
import '../../domain/entities/phase.dart';

List<Phase> buildDefaultPhases({
  required String matterId,
  required IdGenerator idGenerator,
}) {
  return <Phase>[
    Phase(id: idGenerator.newId(), matterId: matterId, name: 'Start', order: 0),
    Phase(
      id: idGenerator.newId(),
      matterId: matterId,
      name: 'In Progress',
      order: 1,
    ),
    Phase(
      id: idGenerator.newId(),
      matterId: matterId,
      name: 'Completed',
      order: 2,
    ),
  ];
}
