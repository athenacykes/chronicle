---
name: chronicle-ui-ux-principles
description: Adaptive shell, dialog, interaction consistency, localization, and regression-safety skill for Chronicle Material and macOS UI work.
---

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
- Keep navigation/read interactions side-effect free: selecting/opening notes, matters, phases, folders, or search results must not mutate persisted note title/content.

## Workflow
1. Identify target platform contexts (`useMacOSNativeUI` true/false) and expected parity behavior.
2. Define intended interaction model (tap, secondary-click, keyboard, dialog/sheet behavior).
3. Implement UI change in platform-specific or shared shell module with consistent semantics.
4. Route all new user-visible strings through ARB localization keys.
5. Validate with targeted shell/widget tests and run golden checks for visual impact.
6. If refactor-only, verify no functional UX deltas were introduced.
7. For sidebar/list/search/time-view navigation changes, verify no repository/content-title writes occur unless user performs explicit write-intent actions.

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
- Navigation/view interactions remain read-only for note title/content persistence.

## Dialog Design Guidelines

Dialogs should have fixed widths (not relative to main window size) and fit their content naturally:

### Sizing Principles
1. **Fixed width**: Use constant width values that don't change based on main window size:
   - Small forms (Category): 380px
   - Medium forms (Matter): 420px
   - Large forms (Settings with two-pane): 580px
   - Content dialogs (Note): 560px
2. **Content-fit height**: Do not use fixed `maxHeight` constraints that leave blank space at the bottom. Let dialogs size to their content naturally using `mainAxisSize: MainAxisSize.min` on Column widgets.
3. **Main window minimum size**: Set the main window minimum size larger than the largest dialog (e.g., 900x750) to prevent dialogs from overflowing.

### Implementation Pattern

#### For All Dialogs (Both Material and macOS Native)

```dart
const dialogWidth = 420.0; // or 380, 560, 580 depending on dialog type

// Content with fixed width - fits content naturally
final content = SizedBox(
  width: dialogWidth,
  child: SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [...],
    ),
  ),
);
```

#### macOS Native UI - Use `ChronicleMacosFixedDialog`

**DO NOT use `MacosSheet`** - it expands to fill the entire window. Instead, use `ChronicleMacosFixedDialog` which provides native macOS styling with fixed sizing:

```dart
import '../chronicle_macos_fixed_dialog.dart';

if (isMacOSNativeUI) {
  return ChronicleMacosFixedDialog(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 12),
          content,  // Your SizedBox with fixed width dialog content
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancelAction),
              ),
              const SizedBox(width: 8),
              PushButton(
                controlSize: ControlSize.large,
                onPressed: onSave,
                child: Text(l10n.saveAction),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// Fallback to Material AlertDialog for non-macOS platforms
return AlertDialog(
  title: Text(title),
  content: content,
  actions: [...],
);
```

**Why `ChronicleMacosFixedDialog`:**
- Uses `IntrinsicWidth` to shrink-wrap to content width
- Centers the dialog in the window
- Applies native macOS styling (same background, borders, and radius as `MacosSheet`)
- Respects the fixed width set on the content `SizedBox`
- Does NOT expand to fill the window

#### Material UI - Use `AlertDialog`

```dart
return AlertDialog(
  title: Text(title),
  content: content,  // Your SizedBox with fixed width
  actions: [
    TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(l10n.cancelAction),
    ),
    FilledButton(
      onPressed: onSave,
      child: Text(l10n.saveAction),
    ),
  ],
);
```

### macOS Window Configuration
Set minimum window size in `macos/Runner/MainFlutterWindow.swift`:
```swift
// Set minimum window size to accommodate largest dialog plus margins
self.minSize = NSSize(width: 900, height: 750)
```

### Platform Consistency
- Apply the same sizing rules to both macOS native (`ChronicleMacosFixedDialog`) and Material (`AlertDialog`) variants
- Keep internal padding consistent (typically 16-20px)
- Use `CrossAxisAlignment.start` instead of `stretch` to prevent fields from expanding to fill width
- Always wrap scrollable content in a fixed-width `SizedBox`
