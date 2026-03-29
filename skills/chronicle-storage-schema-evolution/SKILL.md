---
name: chronicle-storage-schema-evolution
description: Local storage layout, schema compatibility, repository path evolution, and metadata persistence safety skill for Chronicle filesystem changes.
---

# Chronicle Storage Schema Evolution

## Purpose
Guide safe evolution of Chronicle local storage layout and repository behavior while preserving compatibility and sync/search integrity.

## When to Use
- Changing filesystem layout paths, note/matter folder structure, or compatibility mappings.
- Updating local repository read/write logic or migration behavior.
- Introducing new storage metadata or file organization rules.
- Introducing or changing metadata stores that sync depends on for reconciliation.

## Grounding Sources in This Repo
- `/Users/serenity/Workspace/startup/chronicle/lib/data/local_fs/chronicle_layout.dart`
- `/Users/serenity/Workspace/startup/chronicle/lib/data/local_fs/chronicle_storage_initializer.dart`
- `/Users/serenity/Workspace/startup/chronicle/lib/data/local_fs/local_note_repository.dart`
- `/Users/serenity/Workspace/startup/chronicle/lib/data/sync_webdav/local_sync_metadata_store.dart`
- Commit `c97060d` (`feat(notebook): replace orphan workspace with notebook system`)
- Commit `b8d9da3` (`feat(sync): add local metadata tracking for WebDAV synchronization`)

## Principles
- Treat `ChronicleLayout` as schema contract for on-disk structure.
- Preserve compatibility with legacy paths where migration requires coexistence.
- Keep file writes atomic and initialization idempotent.
- Coordinate storage changes with sync and search expectations.
- Minimize migration blast radius; prefer incremental compatibility layers.
- Treat sync-local metadata as schema state, not cache trivia. Changes to metadata files/stores require the same compatibility discipline as note or notebook layout changes.
- Preserve note integrity and metadata integrity together: repository mutations must not update one without the other in ways that leave sync reconciliation ambiguous after restart.

## Workflow
1. Document current and target path/schema behavior before implementation.
2. Add compatibility handling for legacy paths first, then canonical path usage.
3. Update repositories, metadata stores, and initializer in lockstep.
4. Validate relative path handling, metadata persistence, and ignored sync paths remain correct.
5. Check initializer/idempotency behavior for new metadata stores so upgrades and repeated launches do not duplicate or corrupt state.
6. Add/adjust repository and sync tests for migration, compat, and metadata-tracking scenarios.
7. Confirm no data loss paths exist for partial upgrades.

## Verification Commands
- `flutter analyze`
- `flutter test test/data/local_fs/local_repositories_test.dart`
- `flutter test test/data/sync_webdav/local_sync_metadata_store_test.dart`
- `flutter test test/data/sync_webdav/webdav_sync_engine_test.dart`
- `flutter test`

## Definition of Done
- Canonical schema is implemented without breaking legacy data access.
- Repository behavior is deterministic and migration-safe.
- Sync/search assumptions remain valid after storage changes.
- Relevant storage and sync tests pass.
- Metadata store initialization is idempotent and compatible with existing workspaces.
- Sync reconciliation still has complete write/delete history after storage changes.
