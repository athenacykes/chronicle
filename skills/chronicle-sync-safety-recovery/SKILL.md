# Chronicle Sync Safety & Recovery

## Purpose
Provide a safety-first implementation guide for WebDAV sync changes, including blocker handling, recovery modes, and post-sync consistency updates.

## When to Use
- Changing WebDAV sync engine logic, sync controller behavior, or sync status messaging.
- Modifying conflict handling, fail-safe deletion rules, or format-version checks.
- Introducing or adjusting recovery flows.
- Adding sync-local metadata tracking, conflict history persistence, or proxy-backed sync settings.

## Grounding Sources in This Repo
- `/Users/serenity/Workspace/startup/chronicle/lib/data/sync_webdav/webdav_sync_engine.dart`
- `/Users/serenity/Workspace/startup/chronicle/lib/data/local_fs/conflict_service.dart`
- `/Users/serenity/Workspace/startup/chronicle/lib/data/sync_webdav/local_conflict_history_store.dart`
- `/Users/serenity/Workspace/startup/chronicle/lib/data/sync_webdav/local_sync_metadata_store.dart`
- `/Users/serenity/Workspace/startup/chronicle/lib/presentation/sync/sync_controller.dart`
- `/Users/serenity/Workspace/startup/chronicle/test/data/sync_webdav/webdav_sync_engine_test.dart`
- Commit `dcbe9df` (`feat(sync): add namespace support and recovery modes`)
- Commit `fc5e536` (`feat(sync): add fallback storage for sync password and improve WebDAV client`)
- Commit `5f14370` (`feat(sync): add proxy password support and enhance conflict resolution`)
- Commit `b8d9da3` (`feat(sync): add local metadata tracking for WebDAV synchronization`)

## Principles
- Treat fail-safe and version blockers as hard safety gates.
- Keep recovery modes explicit and intentional (`recoverLocalWins`, `recoverRemoteWins`, force apply deletions once).
- Do not bypass blocker logic with implicit fallbacks.
- Ensure sync side effects keep app state coherent (rebuild search index, reload conflicts, invalidate link graph state).
- Preserve namespace/state-isolation behavior across runs.
- Conflict detection must be explainable: prefer explicit fingerprints, content/detail comparisons, and persisted history over opaque last-writer-wins behavior.
- Sync credentials remain safety-sensitive state: proxy password support must follow the same secure-storage and fallback discipline as primary sync credentials.
- Local writes and deletes that affect sync state must be recorded in sync metadata tracking; an untracked repository mutation is a sync correctness bug.
- Recovery and conflict-resolution flows must preserve ordering: resolve blocker state, apply chosen recovery/conflict action, then run post-sync consistency invalidations.

## Workflow
1. Classify change type: normal sync path, blocker path, or recovery path.
2. Define expected blocker and user-facing status behavior before code changes.
3. If local mutation paths change, enumerate every create/update/delete operation that must emit sync metadata and verify each one is tracked.
4. Implement engine/controller adjustments with explicit mode handling.
5. When conflicts are involved, define the detail payload, history persistence, and user-review path before changing resolution logic.
6. Verify post-sync side effects remain complete and ordered.
7. Add/adjust tests for affected blocker, recovery, conflict-detail, and metadata-tracking scenarios.
8. Validate no regressions in normal sync behavior.

## Verification Commands
- `flutter analyze`
- `flutter test test/data/sync_webdav/webdav_sync_engine_test.dart`
- `flutter test test/data/sync_webdav/local_sync_metadata_store_test.dart`
- `flutter test test/presentation/sync/sync_controller_test.dart`
- `flutter test test/data/local_fs/local_settings_repository_test.dart`
- `flutter test`

## Definition of Done
- Blockers and recovery modes behave exactly as specified.
- Post-sync consistency steps execute correctly.
- Sync tests cover changed paths and pass.
- No safety gate was weakened unintentionally.
- Conflict review data is precise enough to explain why a conflict exists and how it was resolved.
- Sync-local metadata correctly records all sync-relevant local writes/deletes.
- Proxy credential handling does not weaken secure storage expectations.
