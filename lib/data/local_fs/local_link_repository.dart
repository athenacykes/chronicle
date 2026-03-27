import '../../core/clock.dart';
import '../../core/file_system_utils.dart';
import '../../core/id_generator.dart';
import '../../domain/entities/note_link.dart';
import '../../domain/repositories/link_repository.dart';
import '../sync_webdav/sync_local_metadata_tracker.dart';
import 'chronicle_layout.dart';
import 'chronicle_storage_initializer.dart';
import 'link_file_codec.dart';
import 'storage_root_locator.dart';

class LocalLinkRepository implements LinkRepository {
  LocalLinkRepository({
    required StorageRootLocator storageRootLocator,
    required ChronicleStorageInitializer storageInitializer,
    required LinkFileCodec codec,
    required FileSystemUtils fileSystemUtils,
    required Clock clock,
    required IdGenerator idGenerator,
    SyncLocalMetadataTracker? syncMetadataTracker,
  }) : _storageRootLocator = storageRootLocator,
       _storageInitializer = storageInitializer,
       _codec = codec,
       _fileSystemUtils = fileSystemUtils,
       _clock = clock,
       _idGenerator = idGenerator,
       _syncMetadataTracker = syncMetadataTracker;

  final StorageRootLocator _storageRootLocator;
  final ChronicleStorageInitializer _storageInitializer;
  final LinkFileCodec _codec;
  final FileSystemUtils _fileSystemUtils;
  final Clock _clock;
  final IdGenerator _idGenerator;
  final SyncLocalMetadataTracker? _syncMetadataTracker;

  @override
  Future<List<NoteLink>> listLinks() async {
    final layout = await _layout();
    final files = await _fileSystemUtils.listFilesRecursively(
      layout.linksDirectory,
    );
    final links = <NoteLink>[];
    for (final file in files.where((file) => file.path.endsWith('.json'))) {
      try {
        final raw = await file.readAsString();
        links.add(_codec.decode(raw));
      } catch (_) {
        continue;
      }
    }
    return links;
  }

  @override
  Future<List<NoteLink>> listLinksForNote(String noteId) async {
    final links = await listLinks();
    return links
        .where(
          (link) => link.sourceNoteId == noteId || link.targetNoteId == noteId,
        )
        .toList();
  }

  @override
  Future<NoteLink> createLink({
    required String sourceNoteId,
    required String targetNoteId,
    required String context,
  }) async {
    final link = NoteLink(
      id: _idGenerator.newId(),
      sourceNoteId: sourceNoteId,
      targetNoteId: targetNoteId,
      context: context,
      createdAt: _clock.nowUtc(),
    );

    final layout = await _layout();
    final file = layout.linkFile(link.id);
    final encoded = _codec.encode(link);
    await _fileSystemUtils.atomicWriteString(file, encoded);
    await _syncMetadataTracker?.recordStringWrite(file, encoded);
    return link;
  }

  @override
  Future<void> deleteLink(String linkId) async {
    final layout = await _layout();
    final file = layout.linkFile(linkId);
    await _fileSystemUtils.deleteIfExists(file);
    await _syncMetadataTracker?.recordDelete(file);
  }

  Future<ChronicleLayout> _layout() async {
    final root = await _storageRootLocator.requireRootDirectory();
    await _storageInitializer.ensureInitialized(root);
    return ChronicleLayout(root);
  }
}
