import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_directories.dart';
import '../core/clock.dart';
import '../core/file_system_utils.dart';
import '../core/id_generator.dart';
import '../data/cache_sqlite/sqlite_search_repository.dart';
import '../data/local_fs/chronicle_storage_initializer.dart';
import '../data/local_fs/conflict_service.dart';
import '../data/local_fs/link_file_codec.dart';
import '../data/local_fs/local_link_repository.dart';
import '../data/local_fs/local_matter_repository.dart';
import '../data/local_fs/local_note_repository.dart';
import '../data/local_fs/local_settings_repository.dart';
import '../data/local_fs/matter_file_codec.dart';
import '../data/local_fs/note_file_codec.dart';
import '../data/local_fs/storage_root_locator.dart';
import '../data/sync_webdav/local_sync_state_store.dart';
import '../data/sync_webdav/webdav_sync_engine.dart';
import '../data/sync_webdav/webdav_sync_repository.dart';
import '../domain/repositories/link_repository.dart';
import '../domain/repositories/matter_repository.dart';
import '../domain/repositories/note_repository.dart';
import '../domain/repositories/search_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/sync_repository.dart';

final appDirectoriesProvider = Provider<AppDirectories>((ref) {
  return const FlutterAppDirectories();
});

final fileSystemUtilsProvider = Provider<FileSystemUtils>((ref) {
  return const FileSystemUtils();
});

final clockProvider = Provider<Clock>((ref) {
  return const SystemClock();
});

final idGeneratorProvider = Provider<IdGenerator>((ref) {
  return UuidV7Generator();
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return LocalSettingsRepository(
    appDirectories: ref.watch(appDirectoriesProvider),
    fileSystemUtils: ref.watch(fileSystemUtilsProvider),
    idGenerator: ref.watch(idGeneratorProvider),
  );
});

final storageRootLocatorProvider = Provider<StorageRootLocator>((ref) {
  return StorageRootLocator(ref.watch(settingsRepositoryProvider));
});

final storageInitializerProvider = Provider<ChronicleStorageInitializer>((ref) {
  return ChronicleStorageInitializer(ref.watch(fileSystemUtilsProvider));
});

final matterRepositoryProvider = Provider<MatterRepository>((ref) {
  return LocalMatterRepository(
    storageRootLocator: ref.watch(storageRootLocatorProvider),
    storageInitializer: ref.watch(storageInitializerProvider),
    codec: const MatterFileCodec(),
    fileSystemUtils: ref.watch(fileSystemUtilsProvider),
    clock: ref.watch(clockProvider),
    idGenerator: ref.watch(idGeneratorProvider),
  );
});

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  return LocalNoteRepository(
    storageRootLocator: ref.watch(storageRootLocatorProvider),
    storageInitializer: ref.watch(storageInitializerProvider),
    codec: const NoteFileCodec(),
    fileSystemUtils: ref.watch(fileSystemUtilsProvider),
    clock: ref.watch(clockProvider),
    idGenerator: ref.watch(idGeneratorProvider),
    matterRepository: ref.watch(matterRepositoryProvider),
  );
});

final linkRepositoryProvider = Provider<LinkRepository>((ref) {
  return LocalLinkRepository(
    storageRootLocator: ref.watch(storageRootLocatorProvider),
    storageInitializer: ref.watch(storageInitializerProvider),
    codec: const LinkFileCodec(),
    fileSystemUtils: ref.watch(fileSystemUtilsProvider),
    clock: ref.watch(clockProvider),
    idGenerator: ref.watch(idGeneratorProvider),
  );
});

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SqliteSearchRepository(
    appDirectories: ref.watch(appDirectoriesProvider),
    fileSystemUtils: ref.watch(fileSystemUtilsProvider),
    matterRepository: ref.watch(matterRepositoryProvider),
    noteRepository: ref.watch(noteRepositoryProvider),
  );
});

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  return WebDavSyncRepository(
    settingsRepository: ref.watch(settingsRepositoryProvider),
    syncEngine: WebDavSyncEngine(
      storageRootLocator: ref.watch(storageRootLocatorProvider),
      storageInitializer: ref.watch(storageInitializerProvider),
      fileSystemUtils: ref.watch(fileSystemUtilsProvider),
      clock: ref.watch(clockProvider),
      syncStateStore: LocalSyncStateStore(
        appDirectories: ref.watch(appDirectoriesProvider),
        fileSystemUtils: ref.watch(fileSystemUtilsProvider),
      ),
    ),
    clock: ref.watch(clockProvider),
  );
});

final conflictServiceProvider = Provider<ConflictService>((ref) {
  return ConflictService(
    storageRootLocator: ref.watch(storageRootLocatorProvider),
    storageInitializer: ref.watch(storageInitializerProvider),
    fileSystemUtils: ref.watch(fileSystemUtilsProvider),
  );
});
