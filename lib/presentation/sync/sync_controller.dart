import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/entities/sync_status.dart';
import '../links/links_controller.dart';
import 'conflicts_controller.dart';

final syncControllerProvider =
    AsyncNotifierProvider<SyncController, SyncStatus>(SyncController.new);

class SyncController extends AsyncNotifier<SyncStatus> {
  Timer? _timer;

  @override
  Future<SyncStatus> build() async {
    ref.onDispose(() {
      _timer?.cancel();
    });

    return SyncStatus.idle;
  }

  Future<void> runSyncNow() async {
    state = AsyncData(
      SyncStatus(
        isRunning: true,
        lastMessage: 'Sync in progress...',
        lastUpdatedAt: DateTime.now().toUtc(),
      ),
    );

    try {
      final result = await ref.read(syncRepositoryProvider).syncNow();
      await ref.read(searchRepositoryProvider).rebuildIndex();
      await ref.read(conflictsControllerProvider.notifier).reload();
      ref.read(linksControllerProvider).invalidateAll();

      if (result.errors.isNotEmpty) {
        state = AsyncData(
          SyncStatus(
            isRunning: false,
            lastMessage: 'Sync completed with ${result.errors.length} errors',
            lastUpdatedAt: result.endedAt,
          ),
        );
        return;
      }

      state = AsyncData(
        SyncStatus(
          isRunning: false,
          lastMessage:
              'Synced: +${result.uploadedCount} / ↓${result.downloadedCount} / !${result.conflictCount}',
          lastUpdatedAt: result.endedAt,
        ),
      );
    } catch (error) {
      state = AsyncData(
        SyncStatus(
          isRunning: false,
          lastMessage: 'Sync failed: $error',
          lastUpdatedAt: DateTime.now().toUtc(),
        ),
      );
    }
  }

  Future<void> startAutoSync(int intervalMinutes) async {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(minutes: intervalMinutes), (_) async {
      await runSyncNow();
    });
  }

  void stopAutoSync() {
    _timer?.cancel();
    _timer = null;
  }
}
