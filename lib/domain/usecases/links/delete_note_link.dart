import '../../repositories/link_repository.dart';

class DeleteNoteLink {
  const DeleteNoteLink(this._linkRepository);

  final LinkRepository _linkRepository;

  Future<void> call(String linkId) {
    return _linkRepository.deleteLink(linkId);
  }
}
