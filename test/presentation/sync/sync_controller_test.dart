import 'dart:async';

import 'package:chronicle/app/app_providers.dart';
import 'package:chronicle/domain/entities/note_search_hit.dart';
import 'package:chronicle/domain/entities/search_query.dart';
import 'package:chronicle/domain/entities/sync_blocker.dart';
import 'package:chronicle/domain/entities/sync_conflict.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/entities/sync_result.dart';
import 'package:chronicle/domain/entities/sync_run_options.dart';
import 'package:chronicle/domain/repositories/search_repository.dart';
import 'package:chronicle/domain/repositories/sync_repository.dart';
import 'package:chronicle/presentation/sync/conflicts_controller.dart';
import 'package:chronicle/presentation/sync/sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reloads conflicts when sync throws after local conflict creation',
    () async {
      final conflictsController = _TrackingConflictsController();
      final container = ProviderContainer(
        overrides: [
          syncRepositoryProvider.overrideWithValue(_ThrowingSyncRepository()),
          searchRepositoryProvider.overrideWithValue(_NoopSearchRepository()),
          conflictsControllerProvider.overrideWith(() => conflictsController),
        ],
      );
      addTearDown(container.dispose);

      await container.read(syncControllerProvider.future);
      await container.read(conflictsControllerProvider.future);

      await container.read(syncControllerProvider.notifier).runSyncNow();

      final syncStatus = container.read(syncControllerProvider).asData?.value;
      final conflicts = container
          .read(conflictsControllerProvider)
          .asData
          ?.value;

      expect(syncStatus, isNotNull);
      expect(syncStatus!.lastMessage, startsWith('Sync failed:'));
      expect(conflictsController.reloadCalls, 1);
      expect(conflicts, hasLength(1));
      expect(
        conflicts!.single.conflictPath,
        'notebook/root/demo.conflict.client.md',
      );
    },
  );

  test('concurrent sync requests only invoke repository once', () async {
    final syncRepository = _BlockingSyncRepository();
    final container = ProviderContainer(
      overrides: [
        syncRepositoryProvider.overrideWithValue(syncRepository),
        searchRepositoryProvider.overrideWithValue(_NoopSearchRepository()),
        conflictsControllerProvider.overrideWith(
          () => _TrackingConflictsController(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(syncControllerProvider.future);

    final firstRun = container
        .read(syncControllerProvider.notifier)
        .runSyncNow();
    final secondRun = container
        .read(syncControllerProvider.notifier)
        .runSyncNow();

    expect(syncRepository.callCount, 1);

    syncRepository.complete(
      SyncResult(
        uploadedCount: 0,
        downloadedCount: 0,
        conflictCount: 0,
        deletedCount: 0,
        startedAt: DateTime.utc(2026, 3, 27, 12),
        endedAt: DateTime.utc(2026, 3, 27, 12, 0, 1),
        errors: const <String>[],
        blocker: null,
      ),
    );

    await Future.wait(<Future<void>>[firstRun, secondRun]);

    expect(syncRepository.callCount, 1);
  });

  test('remote lock override uses one-shot override mode', () async {
    final syncRepository = _RecordingSyncRepository(
      SyncResult(
        uploadedCount: 0,
        downloadedCount: 0,
        conflictCount: 0,
        deletedCount: 0,
        startedAt: DateTime.utc(2026, 3, 27, 12),
        endedAt: DateTime.utc(2026, 3, 27, 12, 0, 1),
        errors: const <String>[],
        blocker: SyncBlocker(
          type: SyncBlockerType.activeRemoteLock,
          lockPath: 'locks/sync_desktop_other.json',
          lockClientId: 'other-client',
          lockClientType: 'desktop',
          lockUpdatedAt: DateTime.utc(2026, 3, 27, 11, 59, 40),
          competingLockCount: 1,
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        syncRepositoryProvider.overrideWithValue(syncRepository),
        searchRepositoryProvider.overrideWithValue(_NoopSearchRepository()),
        conflictsControllerProvider.overrideWith(
          () => _TrackingConflictsController(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(syncControllerProvider.future);

    await container
        .read(syncControllerProvider.notifier)
        .runForceBreakRemoteLockOnce();

    expect(
      syncRepository.lastOptions?.mode,
      SyncRunMode.forceBreakRemoteLockOnce,
    );
  });
}

class _ThrowingSyncRepository implements SyncRepository {
  @override
  Future<SyncConfig> getConfig() async => SyncConfig.initial();

  @override
  Future<String?> getPassword() async => null;

  @override
  Future<void> saveConfig(SyncConfig config, {String? password}) async {}

  @override
  Future<SyncResult> syncNow({
    SyncRunOptions options = const SyncRunOptions(),
    SyncProgressCallback? onProgress,
  }) async {
    throw Exception('late finalization failure');
  }
}

class _NoopSearchRepository implements SearchRepository {
  @override
  Future<List<String>> listTags() async => const <String>[];

  @override
  Future<void> rebuildIndex() async {}

  @override
  Future<List<NoteSearchHit>> search(SearchQuery query) async {
    return const <NoteSearchHit>[];
  }
}

class _BlockingSyncRepository implements SyncRepository {
  final Completer<SyncResult> _completer = Completer<SyncResult>();
  int callCount = 0;

  void complete(SyncResult result) {
    if (!_completer.isCompleted) {
      _completer.complete(result);
    }
  }

  @override
  Future<SyncConfig> getConfig() async => SyncConfig.initial();

  @override
  Future<String?> getPassword() async => null;

  @override
  Future<void> saveConfig(SyncConfig config, {String? password}) async {}

  @override
  Future<SyncResult> syncNow({
    SyncRunOptions options = const SyncRunOptions(),
    SyncProgressCallback? onProgress,
  }) async {
    callCount += 1;
    return _completer.future;
  }
}

class _RecordingSyncRepository implements SyncRepository {
  _RecordingSyncRepository(this._result);

  final SyncResult _result;
  SyncRunOptions? lastOptions;

  @override
  Future<SyncConfig> getConfig() async => SyncConfig.initial();

  @override
  Future<String?> getPassword() async => null;

  @override
  Future<void> saveConfig(SyncConfig config, {String? password}) async {}

  @override
  Future<SyncResult> syncNow({
    SyncRunOptions options = const SyncRunOptions(),
    SyncProgressCallback? onProgress,
  }) async {
    lastOptions = options;
    return _result;
  }
}

class _TrackingConflictsController extends ConflictsController {
  int reloadCalls = 0;

  @override
  Future<List<SyncConflict>> build() async => const <SyncConflict>[];

  @override
  Future<void> reload() async {
    reloadCalls += 1;
    state = AsyncData(<SyncConflict>[
      SyncConflict(
        conflictPath: 'notebook/root/demo.conflict.client.md',
        originalPath: 'notebook/root/demo.md',
        detectedAt: DateTime.utc(2026, 3, 27, 12),
        localDevice: 'desktop-client',
        remoteDevice: 'remote',
        title: 'demo',
        preview: 'conflict preview',
      ),
    ]);
  }

  @override
  Future<void> resolveConflict(
    String conflictPath, {
    required SyncConflictResolutionChoice choice,
  }) async {}

  @override
  void selectConflict(String? conflictPath) {}
}
