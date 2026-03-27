# Chronicle Testing Playbook

## Purpose
Define a consistent test strategy for Chronicle changes, with mandatory targeted validation and full-suite confidence before completion.

## When to Use
- Any code change, bug fix, refactor, or feature.
- Any code review that needs regression-risk assessment.
- Any UI work that may affect golden baselines.

## Grounding Sources in This Repo
- `/Users/serenity/Workspace/startup/chronicle/test/`
- `/Users/serenity/Workspace/startup/chronicle/integration_test/app_test.dart`
- `/Users/serenity/Workspace/startup/chronicle/test/golden/platform_shell_golden_test.dart`
- `/Users/serenity/Workspace/startup/chronicle/AGENTS.md`

## Principles
- Place tests by layer: `domain`, `data`, `presentation`, plus `golden` and `integration_test`.
- Always add/adjust targeted tests for touched behavior before relying on full-suite pass.
- Keep tests deterministic with fake repositories, fixed clocks, and method-channel mocking where needed.
- Golden updates are allowed only for intentional UI changes.
- Large refactors require targeted shell tests plus full `flutter test`.
- Note integrity is mandatory: read-only flows (select/view/navigation) must produce zero note content/title persistence changes.

## Workflow
1. Map changed files to existing test locations and identify coverage gaps.
2. Add/update focused tests for changed behavior first.
3. Run analyzer and targeted tests for impacted area.
4. Run golden tests for UI-impacting changes; update goldens only when intentional.
5. Run full test suite before finalizing.
6. Report commands executed and outcomes.
7. When editor/draft/autosave/navigation paths are touched, include regressions for:
   - switching/selecting notes does not mutate non-edited notes,
   - matter/folder/search navigation does not write note title/content,
   - draft/session switches do not leak title/content across notes or sessions.

## Verification Commands
- `flutter analyze`
- `flutter test test/presentation/common/shell/chronicle_home_macos_main_pane_test.dart`
- `flutter test`
- `flutter test test/golden/platform_shell_golden_test.dart`
- `flutter test test/golden/platform_shell_golden_test.dart --update-goldens` (intentional UI changes only)

## Definition of Done
- Targeted tests cover changed behavior and pass.
- Full suite passes or failures are explicitly documented with root cause.
- Golden changes are intentional and reviewed.
- Analyzer passes without new issues.
- Test evidence confirms note title/content persistence changes occur only under explicit write-intent operations.
