---
name: chronicle-localization-workflow
description: ARB, locale resolution, string update, and localization generation skill for Chronicle UI copy and locale behavior changes.
---

# Chronicle Localization Workflow

## Purpose
Standardize localization changes so string updates remain consistent across ARB resources, generated localization files, and UI behavior.

## When to Use
- Adding, editing, or removing user-facing strings.
- Updating locale behavior, locale tags, or fallback logic.
- Implementing features that require new translated copy.

## Grounding Sources in This Repo
- `/Users/serenity/Workspace/startup/chronicle/l10n.yaml`
- `/Users/serenity/Workspace/startup/chronicle/lib/l10n/localization.dart`
- `/Users/serenity/Workspace/startup/chronicle/lib/l10n/app_en.arb`
- `/Users/serenity/Workspace/startup/chronicle/lib/l10n/app_zh.arb`
- Commit `99e8ec1` (`feat(l10n): add generated app localization file`)
- Commit `eb9c2ea` (`feat(l10n): add localization support and ARB file configuration`)

## Principles
- Keep ARB files as source of truth for localizable strings.
- Use stable, descriptive keys and keep interpolation patterns aligned across locales.
- Regenerate localization output after ARB edits.
- Resolve locale tags via existing fallback rules in `localization.dart`.
- Ensure UI changes use `context.l10n` and avoid hard-coded user strings.

## Workflow
1. Add or update keys in `app_en.arb` and `app_zh.arb` with matching semantics.
2. Run `flutter gen-l10n` to refresh generated localization classes.
3. Replace hard-coded UI strings with localized getters.
4. Validate locale resolution and fallback behavior for changed keys.
5. Run tests touching affected screens/controllers.
6. Confirm generated localization files are consistent with ARB changes.

## Verification Commands
- `flutter gen-l10n`
- `flutter analyze`
- `flutter test test/presentation/settings/settings_controller_test.dart`
- `flutter test`

## Definition of Done
- New/changed strings exist in both English and Chinese ARB files.
- Generated localization files are up to date.
- UI retrieves strings through localization APIs.
- Locale-related tests and analyzer checks pass.
