import 'package:chronicle/domain/entities/enums.dart';
import 'package:chronicle/domain/entities/matter.dart';
import 'package:chronicle/domain/entities/phase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromJson defaults categoryId to null when missing', () {
    final json = <String, dynamic>{
      'id': 'matter-1',
      'title': 'Matter',
      'description': '',
      'status': 'active',
      'color': '#4C956C',
      'icon': 'description',
      'createdAt': '2026-02-22T12:00:00Z',
      'updatedAt': '2026-02-22T12:00:00Z',
      'startedAt': '2026-02-22T12:00:00Z',
      'endedAt': null,
      'isPinned': false,
      'phases': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'phase-1',
          'matterId': 'matter-1',
          'name': 'Start',
          'order': 0,
        },
      ],
      'currentPhaseId': 'phase-1',
    };

    final matter = Matter.fromJson(json);
    expect(matter.categoryId, isNull);
  });

  test('toJson includes categoryId when set', () {
    final matter = Matter(
      id: 'matter-1',
      categoryId: 'category-1',
      title: 'Matter',
      description: '',
      status: MatterStatus.active,
      color: '#4C956C',
      icon: 'description',
      isPinned: false,
      createdAt: DateTime.utc(2026, 2, 22, 12),
      updatedAt: DateTime.utc(2026, 2, 22, 12),
      startedAt: DateTime.utc(2026, 2, 22, 12),
      endedAt: null,
      phases: const <Phase>[
        Phase(id: 'phase-1', matterId: 'matter-1', name: 'Start', order: 0),
      ],
      currentPhaseId: 'phase-1',
    );

    expect(matter.toJson()['categoryId'], 'category-1');
  });
}
