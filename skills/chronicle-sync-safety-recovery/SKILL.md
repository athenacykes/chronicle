# Chronicle Sync Safety & Recovery

## Purpose
Provide a safety-first implementation guide for WebDAV sync changes, including blocker handling, recovery modes, and post-sync consistency updates.

## When to Use
- Changing WebDAV sync engine logic, sync controller behavior, or sync status messaging.
- Modifying conflict handling, fail-safe deletion rules, or format-version checks.
- Introducing or adjusting recovery flows.

## Grounding Sources in This Repo
- `/Users/serenity/Workspace/startup/chronicle/lib/data/sync_webdav/webdav_sync_engine.dart`
- `/Users/serenity/Workspace/startup/chronicle/lib/presentation/sync/sync_controller.dart`
- `/Users/serenity/Workspace/startup/chronicle/test/data/sync_webdav/webdav_sync_engine_test.dart`
- Commit `dcbe9df` (`feat(sync): add namespace support and recovery modes`)
- Commit `fc5e536` (`feat(sync): add fallback storage for sync password and improve WebDAV client`)

## Principles
- Treat fail-safe and version blockers as hard safety gates.
- Keep recovery modes explicit and intentional (`recoverLocalWins`, `recoverRemoteWins`, force apply deletions once).
- Do not bypass blocker logic with implicit fallbacks.
- Ensure sync side effects keep app state coherent (rebuild search index, reload conflicts, invalidate link graph state).
- Preserve namespace/state-isolation behavior across runs.

## Workflow
1. Classify change type: normal sync path, blocker path, or recovery path.
2. Define expected blocker and user-facing status behavior before code changes.
3. Implement engine/controller adjustments with explicit mode handling.
4. Verify post-sync side effects remain complete and ordered.
5. Add/adjust tests for affected blocker/recovery scenarios.
6. Validate no regressions in normal sync behavior.

## Verification Commands
- `flutter analyze`
- `flutter test test/data/sync_webdav/webdav_sync_engine_test.dart`
- `flutter test`

## Definition of Done
- Blockers and recovery modes behave exactly as specified.
- Post-sync consistency steps execute correctly.
- Sync tests cover changed paths and pass.
- No safety gate was weakened unintentionally.
