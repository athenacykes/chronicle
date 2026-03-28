# Repository Guidelines

## Project Structure & Module Organization
- `lib/` contains production code, organized by layer:
  - `lib/domain/` for entities, repository contracts, and use cases.
  - `lib/data/` for implementations (`local_fs/`, `cache_sqlite/`, `sync_webdav/`).
  - `lib/presentation/` for UI/controllers, with platform-specific shell code under `presentation/common/shell/`.
  - `lib/app/` and `lib/main.dart` wire app bootstrap and providers.
- `test/` holds unit/widget/golden tests; goldens live in `test/golden/goldens/`.
- `integration_test/` contains end-to-end widget flows.
- `macos/` includes desktop runner and native macOS project files.

## Build, Test, and Development Commands
- `flutter pub get` installs dependencies.
- `flutter analyze` runs static analysis with `flutter_lints`.
- `flutter test` runs unit/widget tests.
- `flutter test integration_test/app_test.dart` runs the integration test.
- `flutter test test/golden/platform_shell_golden_test.dart` validates shell goldens.
- `flutter test test/golden/platform_shell_golden_test.dart --update-goldens` refreshes golden baselines after intentional UI changes.
- `flutter run -d macos` runs locally on macOS.
- `flutter run -d macos --dart-define=CHRONICLE_MACOS_NATIVE_UI=true` enables the native macOS shell.

## Coding Style & Naming Conventions
- Follow Dart/Flutter defaults: 2-space indentation and trailing commas for stable formatting.
- File names use `snake_case.dart`; classes/types use `PascalCase`; fields/methods use `camelCase`.
- Keep layer boundaries explicit: `presentation` depends on `domain` contracts, `data` implements repositories.
- Run `dart format .` before opening a PR.

## Testing Guidelines
- Use `flutter_test` for unit/widget tests and `integration_test` for app flows; `mocktail` is available for mocks.
- Test files must end with `_test.dart` and mirror source paths where practical (example: `lib/presentation/settings/...` -> `test/presentation/settings/...`).
- Add regression tests for bug fixes and update goldens when UI behavior intentionally changes.

## Commit & Pull Request Guidelines
- Prefer Conventional Commit style seen in history (examples: `feat(ui): ...`, `refactor(presentation): ...`).
- Keep commits focused and include tests with code changes.
- PRs should include: concise summary, linked issue (if any), test commands run, and screenshots for UI changes (especially golden-impacting updates).

## Security & Configuration Tips
- Do not commit real sync credentials or local absolute paths.
- Keep WebDAV secrets in secure storage (`flutter_secure_storage`), not in source-controlled config.

## Chronicle Home Shell Refactor Status (Phase 1/2)
- The large home shell has been split from a single monolith into a staged architecture.
- Public API is intentionally unchanged:
  - `ChronicleHomeScreen`
  - `showChronicleSettingsDialog`
- `lib/presentation/common/shell/chronicle_home_coordinator.dart` is now the library entrypoint plus orchestration state (`_ChronicleHomeScreenState`).
- Remaining `part` files (still coupled to coordinator internals):
  - `lib/presentation/common/shell/chronicle_home/helpers.dart`
  - `lib/presentation/common/shell/chronicle_home/sidebar.dart`
  - `lib/presentation/common/shell/chronicle_home/workspace.dart`
  - `lib/presentation/common/shell/chronicle_home/graph.dart`
  - `lib/presentation/common/shell/chronicle_home/editor.dart`
- Promoted standalone modules (Phase 2 so far):
  - `lib/presentation/common/shell/chronicle_root_shell.dart`
  - `lib/presentation/common/shell/chronicle_search_results_view.dart`
  - `lib/presentation/common/shell/chronicle_settings_dialog.dart`
  - `lib/presentation/common/shell/chronicle_entity_dialogs.dart`
  - `lib/presentation/common/shell/chronicle_manage_phases_dialog.dart`
  - `lib/presentation/common/shell/chronicle_graph_canvas.dart`
  - `lib/presentation/common/shell/chronicle_note_editor_utilities.dart`
  - `lib/presentation/common/shell/chronicle_note_title_header.dart`
  - `lib/presentation/common/shell/chronicle_macos_widgets.dart`
  - `lib/presentation/common/shell/chronicle_top_bar_controls.dart`
  - `lib/presentation/common/shell/chronicle_sidebar_sync_panel.dart`
  - `lib/presentation/common/shell/chronicle_sidebar_matter_actions.dart`

### Refactor Guardrails
- Prefer promoting reusable/leaf UI from `part` files into standalone imported files with explicit constructor contracts.
- Keep orchestration and provider wiring centralized in coordinator unless a promotion clearly reduces coupling.
- Avoid functional/UX changes during this refactor; target maintainability only.
- After each extraction, run:
  - `flutter analyze`
  - `flutter test test/presentation/common/shell/chronicle_home_macos_main_pane_test.dart`
  - `flutter test`

### Note Integrity Invariant
- Treat note title/content and on-disk note files as integrity-critical state.
- Selection/view/navigation actions are read-only:
  - Clicking or opening a note/matter/phase/notebook folder/search result/time view must never mutate note content/title on disk.
  - State hydration while loading/switching views must never copy content/title across notes or draft sessions.
- Mutations are allowed only from explicit write-intent actions:
  - Direct user editing input, explicit save, create, move, delete, rename, attachment add/remove, or equivalent explicit operations.
- Autosave is allowed only for active user edits of the same note/draft session; never from passive viewing/navigation.

## Skills

### Available project skills
- `chronicle-architecture-principles`: architecture boundary, provider wiring, and refactor guardrail skill. (`/Users/serenity/Workspace/startup/chronicle/skills/chronicle-architecture-principles/SKILL.md`)
- `chronicle-ui-ux-principles`: adaptive shell and interaction consistency skill for Material/macOS UI. (`/Users/serenity/Workspace/startup/chronicle/skills/chronicle-ui-ux-principles/SKILL.md`)
- `chronicle-testing-playbook`: test planning, execution, and regression-safety skill. (`/Users/serenity/Workspace/startup/chronicle/skills/chronicle-testing-playbook/SKILL.md`)
- `chronicle-sync-safety-recovery`: WebDAV sync blocker/recovery/safety skill. (`/Users/serenity/Workspace/startup/chronicle/skills/chronicle-sync-safety-recovery/SKILL.md`)
- `chronicle-storage-schema-evolution`: local storage layout/schema compatibility skill. (`/Users/serenity/Workspace/startup/chronicle/skills/chronicle-storage-schema-evolution/SKILL.md`)
- `chronicle-localization-workflow`: ARB, locale resolution, and l10n generation skill. (`/Users/serenity/Workspace/startup/chronicle/skills/chronicle-localization-workflow/SKILL.md`)
- `chronicle-markdown-editor-extensions`: markdown parser/renderer/editor extension skill. (`/Users/serenity/Workspace/startup/chronicle/skills/chronicle-markdown-editor-extensions/SKILL.md`)

### Trigger rules for AI coding agents
- Architecture/refactor/provider/repository contract changes -> `chronicle-architecture-principles`.
- UI/layout/interaction/platform shell work -> `chronicle-ui-ux-principles`.
- Any code change or review -> `chronicle-testing-playbook`.
- Sync flow, blockers, recovery, or conflict behavior -> `chronicle-sync-safety-recovery`.
- Local storage layout/schema/repository path evolution -> `chronicle-storage-schema-evolution`.
- String copy, locale behavior, or ARB changes -> `chronicle-localization-workflow`.
- Markdown parsing/rendering/editor feature work -> `chronicle-markdown-editor-extensions`.

### Skill application order
- First: `chronicle-architecture-principles`.
- Second: domain-specific skill for task (`sync`, `storage`, `l10n`, `markdown`, or `ui/ux`).
- Third: `chronicle-testing-playbook`.

### Minimum execution checklist
- Identify and load all relevant skills before editing code.
- Follow architecture and domain guardrails from loaded skills during implementation.
- Run verification commands defined by the testing skill (and domain skill when applicable).
- Report which skills were applied, commands run, and outcomes.
