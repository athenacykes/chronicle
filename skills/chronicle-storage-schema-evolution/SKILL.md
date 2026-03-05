# Chronicle Storage Schema Evolution

## Purpose
Guide safe evolution of Chronicle local storage layout and repository behavior while preserving compatibility and sync/search integrity.

## When to Use
- Changing filesystem layout paths, note/matter folder structure, or compatibility mappings.
- Updating local repository read/write logic or migration behavior.
- Introducing new storage metadata or file organization rules.

## Grounding Sources in This Repo
- `/Users/serenity/Workspace/startup/chronicle/lib/data/local_fs/chronicle_layout.dart`
- `/Users/serenity/Workspace/startup/chronicle/lib/data/local_fs/chronicle_storage_initializer.dart`
- `/Users/serenity/Workspace/startup/chronicle/lib/data/local_fs/local_note_repository.dart`
- Commit `c97060d` (`feat(notebook): replace orphan workspace with notebook system`)

## Principles
- Treat `ChronicleLayout` as schema contract for on-disk structure.
- Preserve compatibility with legacy paths where migration requires coexistence.
- Keep file writes atomic and initialization idempotent.
- Coordinate storage changes with sync and search expectations.
- Minimize migration blast radius; prefer incremental compatibility layers.

## Workflow
1. Document current and target path/schema behavior before implementation.
2. Add compatibility handling for legacy paths first, then canonical path usage.
3. Update repositories and initializer in lockstep.
4. Validate relative path handling and ignored sync paths remain correct.
5. Add/adjust repository and sync tests for migration/compat scenarios.
6. Confirm no data loss paths exist for partial upgrades.

## Verification Commands
- `flutter analyze`
- `flutter test test/data/local_fs/local_repositories_test.dart`
- `flutter test test/data/sync_webdav/webdav_sync_engine_test.dart`
- `flutter test`

## Definition of Done
- Canonical schema is implemented without breaking legacy data access.
- Repository behavior is deterministic and migration-safe.
- Sync/search assumptions remain valid after storage changes.
- Relevant storage and sync tests pass.
