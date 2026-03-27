# Chronicle Architecture Principles

## Purpose
Provide a repeatable architecture decision framework for Chronicle changes so refactors stay behavior-safe and layer boundaries stay explicit.

## When to Use
- Adding or changing repository contracts, use cases, controllers, or provider wiring.
- Refactoring home shell structure or extracting `part`-file logic.
- Introducing new feature flows that touch `domain`, `data`, and `presentation` together.

## Grounding Sources in This Repo
- `/Users/serenity/Workspace/startup/chronicle/lib/app/app_providers.dart`
- `/Users/serenity/Workspace/startup/chronicle/lib/presentation/common/shell/chronicle_home_coordinator.dart`
- `/Users/serenity/Workspace/startup/chronicle/AGENTS.md`
- Commit `e4b3aa4` (`refactor(state): migrate StateProvider to ValueNotifierController`)
- Commit `352f96f` (`refactor(presentation): extract entity dialogs from home shell`)
- Commit `c97060d` (`feat(notebook): replace orphan workspace with notebook system`)

## Principles
- Keep layer directions strict: `presentation -> domain contracts`, `data -> domain implementations`.
- Wire dependencies through Riverpod providers in `lib/app/app_providers.dart`; avoid ad-hoc object construction in UI.
- Prefer backward-compatible refactors over behavior changes unless feature scope explicitly requires UX changes.
- Home shell refactor: preserve public entrypoints (`ChronicleHomeScreen`, `showChronicleSettingsDialog`) while extracting reusable leaf modules.
- Keep orchestration state centralized in coordinator until extraction reduces coupling and keeps constructor contracts explicit.
- Preserve note integrity: read-intent flows (select/view/navigation) must not mutate note content/title or on-disk note state.
- Restrict note mutations to explicit write-intent operations (edit input, explicit save, create/move/delete/rename, attachment add/remove).

## Workflow
1. Identify impacted layer(s) and list all affected contracts first.
2. If changing behavior, separate behavior change from structure-only refactor in design notes and commits.
3. Update/extend domain contracts and use cases before touching data implementations.
4. Wire new dependencies in `app_providers.dart` and keep provider graph explicit.
5. For shell refactors, extract leaf widgets/helpers first, then reduce coordinator responsibilities incrementally.
6. Re-check public API stability for shell and settings entrypoints after edits.
7. Classify touched paths as read-intent vs write-intent and ensure repository writes are reachable only from explicit write-intent triggers.

## Verification Commands
- `flutter analyze`
- `flutter test test/presentation/common/shell/chronicle_home_macos_main_pane_test.dart`
- `flutter test`

## Definition of Done
- Layer boundaries remain explicit and dependency direction is preserved.
- Provider wiring is centralized in `app_providers.dart`.
- Public shell API remains unchanged unless explicitly intended.
- Refactor changes preserve existing behavior and pass analyzer/tests.
- Navigation/view/selection behavior does not persist note content/title changes without explicit write-intent user action.
