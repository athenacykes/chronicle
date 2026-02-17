import '../../repositories/note_repository.dart';

class MoveNote {
  const MoveNote(this._noteRepository);

  final NoteRepository _noteRepository;

  Future<void> call({
    required String noteId,
    required String? matterId,
    required String? phaseId,
  }) {
    return _noteRepository.moveNote(
      noteId: noteId,
      matterId: matterId,
      phaseId: phaseId,
    );
  }
}
