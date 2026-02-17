import '../../entities/note_link.dart';
import '../../repositories/link_repository.dart';
import '../../repositories/note_repository.dart';

class CreateNoteLink {
  const CreateNoteLink(this._linkRepository, this._noteRepository);

  final LinkRepository _linkRepository;
  final NoteRepository _noteRepository;

  Future<NoteLink> call({
    required String sourceNoteId,
    required String targetNoteId,
    String context = '',
  }) async {
    final source = sourceNoteId.trim();
    final target = targetNoteId.trim();
    if (source.isEmpty || target.isEmpty) {
      throw ArgumentError('Source and target note ids are required');
    }

    if (source == target) {
      throw ArgumentError('A note cannot link to itself');
    }

    final sourceNote = await _noteRepository.getNoteById(source);
    if (sourceNote == null) {
      throw StateError('Source note does not exist: $source');
    }

    final targetNote = await _noteRepository.getNoteById(target);
    if (targetNote == null) {
      throw StateError('Target note does not exist: $target');
    }

    final normalizedSource = _pairLeft(source, target);
    final normalizedTarget = _pairRight(source, target);

    final existing = await _linkRepository.listLinks();
    for (final link in existing) {
      final left = _pairLeft(link.sourceNoteId, link.targetNoteId);
      final right = _pairRight(link.sourceNoteId, link.targetNoteId);
      if (left == normalizedSource && right == normalizedTarget) {
        throw StateError('Link already exists between the selected notes');
      }
    }

    return _linkRepository.createLink(
      sourceNoteId: source,
      targetNoteId: target,
      context: context.trim(),
    );
  }

  String _pairLeft(String a, String b) {
    return a.compareTo(b) <= 0 ? a : b;
  }

  String _pairRight(String a, String b) {
    return a.compareTo(b) <= 0 ? b : a;
  }
}
