import 'package:chronicle/domain/entities/note.dart';
import 'package:chronicle/domain/entities/note_link.dart';
import 'package:chronicle/domain/repositories/link_repository.dart';
import 'package:chronicle/domain/repositories/note_repository.dart';
import 'package:chronicle/domain/usecases/links/build_matter_graph.dart';
import 'package:chronicle/domain/usecases/links/create_note_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreateNoteLink', () {
    test('rejects self-link', () async {
      final noteRepository = _InMemoryNoteRepository(
        notes: <Note>[
          _note(
            id: 'n1',
            matterId: 'm1',
            phaseId: 'p1',
            updatedAt: DateTime.utc(2026, 2, 17, 10),
          ),
        ],
      );
      final linkRepository = _InMemoryLinkRepository();
      final useCase = CreateNoteLink(linkRepository, noteRepository);

      await expectLater(
        () => useCase.call(sourceNoteId: 'n1', targetNoteId: 'n1'),
        throwsArgumentError,
      );
    });

    test('rejects duplicate undirected pair', () async {
      final noteRepository = _InMemoryNoteRepository(
        notes: <Note>[
          _note(
            id: 'n1',
            matterId: 'm1',
            phaseId: 'p1',
            updatedAt: DateTime.utc(2026, 2, 17, 10),
          ),
          _note(
            id: 'n2',
            matterId: 'm2',
            phaseId: 'p2',
            updatedAt: DateTime.utc(2026, 2, 17, 11),
          ),
        ],
      );
      final linkRepository = _InMemoryLinkRepository();
      final useCase = CreateNoteLink(linkRepository, noteRepository);

      await useCase.call(sourceNoteId: 'n1', targetNoteId: 'n2', context: 'a');

      await expectLater(
        () =>
            useCase.call(sourceNoteId: 'n2', targetNoteId: 'n1', context: 'b'),
        throwsStateError,
      );
    });

    test('allows cross-matter and orphan links', () async {
      final noteRepository = _InMemoryNoteRepository(
        notes: <Note>[
          _note(
            id: 'n1',
            matterId: 'm1',
            phaseId: 'p1',
            updatedAt: DateTime.utc(2026, 2, 17, 10),
          ),
          _note(
            id: 'n2',
            matterId: 'm2',
            phaseId: 'p2',
            updatedAt: DateTime.utc(2026, 2, 17, 11),
          ),
          _note(
            id: 'n3',
            matterId: null,
            phaseId: null,
            updatedAt: DateTime.utc(2026, 2, 17, 12),
          ),
        ],
      );
      final linkRepository = _InMemoryLinkRepository();
      final useCase = CreateNoteLink(linkRepository, noteRepository);

      final linkA = await useCase.call(
        sourceNoteId: 'n1',
        targetNoteId: 'n2',
        context: 'cross',
      );
      final linkB = await useCase.call(
        sourceNoteId: 'n1',
        targetNoteId: 'n3',
        context: 'orphan',
      );

      expect(linkA.id, isNotEmpty);
      expect(linkB.id, isNotEmpty);
      expect(await linkRepository.listLinks(), hasLength(2));
    });
  });

  group('BuildMatterGraph', () {
    test(
      'includes selected matter notes plus directly-linked external neighbors',
      () async {
        final notes = <Note>[
          _note(
            id: 'n1',
            matterId: 'm-selected',
            phaseId: 'p1',
            updatedAt: DateTime.utc(2026, 2, 17, 10),
          ),
          _note(
            id: 'n2',
            matterId: 'm-selected',
            phaseId: 'p2',
            updatedAt: DateTime.utc(2026, 2, 17, 9),
          ),
          _note(
            id: 'n3',
            matterId: 'm-external',
            phaseId: 'p3',
            updatedAt: DateTime.utc(2026, 2, 17, 8),
          ),
          _note(
            id: 'n4',
            matterId: 'm-external',
            phaseId: 'p4',
            updatedAt: DateTime.utc(2026, 2, 17, 7),
          ),
          _note(
            id: 'n5',
            matterId: null,
            phaseId: null,
            updatedAt: DateTime.utc(2026, 2, 17, 6),
          ),
        ];

        final linkRepository = _InMemoryLinkRepository(
          links: <NoteLink>[
            _link(id: 'l1', source: 'n1', target: 'n3'),
            _link(id: 'l2', source: 'n2', target: 'n5'),
            _link(id: 'l3', source: 'n3', target: 'n4'),
          ],
        );

        final useCase = BuildMatterGraph(
          _InMemoryNoteRepository(notes: notes),
          linkRepository,
          nowUtc: () => DateTime.utc(2026, 2, 17, 13),
        );

        final graph = await useCase.call(matterId: 'm-selected');
        final nodeIds = graph.nodes.map((node) => node.noteId).toSet();
        final edgeIds = graph.edges.map((edge) => edge.linkId).toSet();

        expect(nodeIds, equals(<String>{'n1', 'n2', 'n3', 'n5'}));
        expect(edgeIds, equals(<String>{'l1', 'l2'}));
        expect(
          graph.nodes
              .where((node) => node.isInSelectedMatter)
              .map((n) => n.noteId),
          containsAll(<String>['n1', 'n2']),
        );
        expect(graph.generatedAt, DateTime.utc(2026, 2, 17, 13));
      },
    );
  });
}

Note _note({
  required String id,
  required String? matterId,
  required String? phaseId,
  required DateTime updatedAt,
}) {
  return Note(
    id: id,
    matterId: matterId,
    phaseId: phaseId,
    title: id,
    content: '# $id',
    tags: const <String>[],
    isPinned: false,
    attachments: const <String>[],
    createdAt: DateTime.utc(2026, 2, 17, 1),
    updatedAt: updatedAt,
  );
}

NoteLink _link({
  required String id,
  required String source,
  required String target,
}) {
  return NoteLink(
    id: id,
    sourceNoteId: source,
    targetNoteId: target,
    context: '',
    createdAt: DateTime.utc(2026, 2, 17, 2),
  );
}

class _InMemoryLinkRepository implements LinkRepository {
  _InMemoryLinkRepository({List<NoteLink> links = const <NoteLink>[]})
    : _links = <NoteLink>[...links];

  final List<NoteLink> _links;
  int _counter = 1;

  @override
  Future<NoteLink> createLink({
    required String sourceNoteId,
    required String targetNoteId,
    required String context,
  }) async {
    final link = NoteLink(
      id: 'id-${_counter++}',
      sourceNoteId: sourceNoteId,
      targetNoteId: targetNoteId,
      context: context,
      createdAt: DateTime.utc(2026, 2, 17, 3),
    );
    _links.add(link);
    return link;
  }

  @override
  Future<void> deleteLink(String linkId) async {
    _links.removeWhere((link) => link.id == linkId);
  }

  @override
  Future<List<NoteLink>> listLinks() async {
    return <NoteLink>[..._links];
  }

  @override
  Future<List<NoteLink>> listLinksForNote(String noteId) async {
    return _links
        .where(
          (link) => link.sourceNoteId == noteId || link.targetNoteId == noteId,
        )
        .toList();
  }
}

class _InMemoryNoteRepository implements NoteRepository {
  _InMemoryNoteRepository({required List<Note> notes})
    : _notes = <String, Note>{for (final note in notes) note.id: note};

  final Map<String, Note> _notes;

  @override
  Future<Note?> getNoteById(String noteId) async {
    return _notes[noteId];
  }

  @override
  Future<List<Note>> listAllNotes() async {
    return _notes.values.toList();
  }

  @override
  Future<Note> createNote({
    required String title,
    required String content,
    String? matterId,
    String? phaseId,
    List<String> tags = const <String>[],
    bool isPinned = false,
    List<String> attachments = const <String>[],
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteNote(String noteId) {
    throw UnimplementedError();
  }

  @override
  Future<List<Note>> listMatterTimeline(String matterId) {
    throw UnimplementedError();
  }

  @override
  Future<List<Note>> listNotesByMatterAndPhase({
    required String matterId,
    required String phaseId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Note>> listOrphanNotes() {
    throw UnimplementedError();
  }

  @override
  Future<void> moveNote({
    required String noteId,
    required String? matterId,
    required String? phaseId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateNote(Note note) {
    throw UnimplementedError();
  }
}
