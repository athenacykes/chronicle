# Chronicle Markdown Rendering & Editor Extensions

## Purpose
Define a safe extension workflow for Chronicle markdown and editor capabilities, including parsing, rendering, fallback behavior, and regression coverage.

## When to Use
- Adding markdown syntaxes or custom renderers.
- Changing code highlighting, math rendering, or mermaid rendering behavior.
- Updating markdown editor tooling that affects output fidelity.

## Grounding Sources in This Repo
- `/Users/serenity/Workspace/startup/chronicle/lib/presentation/common/markdown/chronicle_markdown.dart`
- `/Users/serenity/Workspace/startup/chronicle/lib/presentation/common/markdown/markdown_code_highlighting.dart`
- `/Users/serenity/Workspace/startup/chronicle/test/presentation/common/markdown/chronicle_markdown_test.dart`
- `/Users/serenity/Workspace/startup/chronicle/test/presentation/common/markdown/markdown_code_highlighting_test.dart`
- Commit `0a3ebd4` (`feat(markdown): add syntax highlighting for code blocks`)
- Commit `454a865` (`feat(markdown): add markdown formatting toolbar`)
- Commit `2536b10` (`feat(assets): add mermaid.min.js for diagram rendering support`)

## Principles
- Extend parser/rendering behavior through explicit custom syntaxes and builders.
- Keep renderer fallbacks graceful when parsing/rendering fails.
- Ensure markdown features align with shipped assets and dependencies.
- Treat markdown rendering changes as regression-sensitive UI behavior.
- Keep read/edit mode behavior coherent for users.

## Workflow
1. Define extension contract (syntax pattern, AST node tag, builder behavior).
2. Implement parser and builder changes with explicit empty/error fallback.
3. Ensure required assets/dependencies are declared and loaded correctly.
4. Add or update focused markdown tests for parsing and rendering behavior.
5. Validate editor-related behavior if format toolbar or edit helpers are affected.
6. Re-run broader tests for shell/editor regressions.

## Verification Commands
- `flutter analyze`
- `flutter test test/presentation/common/markdown/chronicle_markdown_test.dart`
- `flutter test test/presentation/common/markdown/markdown_code_highlighting_test.dart`
- `flutter test test/presentation/common/markdown/markdown_edit_formatter_test.dart`
- `flutter test`

## Definition of Done
- New markdown/editor behavior is deterministic and backward-compatible where expected.
- Fallback behavior is safe for invalid or partial input.
- Required assets/dependencies are present and referenced correctly.
- Markdown-focused tests and full suite checks pass.
