# Chronicle UI/UX Principles

## Purpose
Guide UI and interaction changes so Chronicle stays platform-consistent, localized, and visually stable across Material and macOS-native shells.

## When to Use
- Updating layout, controls, menus, dialogs, or shell structure.
- Implementing interactions in sidebar, top bar, editor, workspace, or context menus.
- Refactoring UI code where behavior should remain unchanged.

## Grounding Sources in This Repo
- `/Users/serenity/Workspace/startup/chronicle/lib/presentation/common/shell/chronicle_root_shell.dart`
- `/Users/serenity/Workspace/startup/chronicle/lib/presentation/common/shell/chronicle_top_bar_controls.dart`
- `/Users/serenity/Workspace/startup/chronicle/test/presentation/common/shell/chronicle_home_macos_main_pane_test.dart`
- Commit `4e8e5f6` (`feat(sidebar): add context menu support for notebook items`)
- Commit `291196d` (`feat(sidebar): add secondary click context menu support`)
- Commit `37d4738` (`feat(sidebar): add collapsible sections`)
- Commit `475df77` (`feat(timeView): add time-based view functionality`)

## Principles
- Keep adaptive behavior explicit: macOS-native controls when enabled, Material equivalents otherwise.
- Maintain interaction parity across platforms for core actions (create/select/manage/navigation).
- Favor contextual actions (e.g., secondary-click menus) when platform conventions support them.
- During refactors, preserve user-facing behavior unless the task explicitly includes UX changes.
- Localize user-facing strings via `l10n` resources; do not hard-code user copy.
- Treat visual diffs as regressions unless intentional and documented.

## Workflow
1. Identify target platform contexts (`useMacOSNativeUI` true/false) and expected parity behavior.
2. Define intended interaction model (tap, secondary-click, keyboard, dialog/sheet behavior).
3. Implement UI change in platform-specific or shared shell module with consistent semantics.
4. Route all new user-visible strings through ARB localization keys.
5. Validate with targeted shell/widget tests and run golden checks for visual impact.
6. If refactor-only, verify no functional UX deltas were introduced.

## Verification Commands
- `flutter analyze`
- `flutter test test/presentation/common/shell/chronicle_home_macos_main_pane_test.dart`
- `flutter test test/golden/platform_shell_golden_test.dart`
- `flutter test`

## Definition of Done
- Material and macOS-native variants behave consistently for the same user intent.
- All new UI strings are localized.
- No unintended golden or interaction regressions remain.
- Refactor-only changes do not alter UX behavior.
