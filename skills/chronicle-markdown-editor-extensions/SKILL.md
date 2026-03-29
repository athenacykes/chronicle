---
name: chronicle-markdown-editor-extensions
description: Markdown parser, renderer, editor-extension, and note-session safety skill for Chronicle markdown and editor behavior changes.
---

# Chronicle Markdown Rendering & Editor Extensions

## Purpose
Define a safe extension workflow for Chronicle markdown and editor capabilities, including parsing, rendering, fallback behavior, and regression coverage.

## When to Use
- Adding markdown syntaxes or custom renderers.
- Changing code highlighting, math rendering, or mermaid rendering behavior.
- Updating markdown editor tooling that affects output fidelity.
- Changing note-loading, autosave, draft-session, or editor observer logic around `_NoteEditorPane`.

## Grounding Sources in This Repo
- `lib/presentation/common/markdown/chronicle_markdown.dart`
- `lib/presentation/common/markdown/markdown_code_controller.dart`
- `lib/presentation/common/markdown/markdown_code_highlighting.dart`
- `lib/presentation/common/shell/chronicle_home/editor.dart` (the `_NoteEditorPane`)
- `test/presentation/common/markdown/chronicle_markdown_test.dart`
- `test/presentation/common/markdown/markdown_code_highlighting_test.dart`
- Commit `0a3ebd4` (`feat(markdown): add syntax highlighting for code blocks`)
- Commit `454a865` (`feat(markdown): add markdown formatting toolbar`)
- Commit `2536b10` (`feat(assets): add mermaid.min.js for diagram rendering support`)

## Principles
- Extend parser/rendering behavior through explicit custom syntaxes and builders.
- Keep renderer fallbacks graceful when parsing/rendering fails.
- Ensure markdown features align with shipped assets and dependencies.
- Treat markdown rendering changes as regression-sensitive UI behavior.
- Keep read/edit mode behavior coherent for users.
- Treat editor session ownership as a safety boundary: content/title observers, debounced autosave callbacks, and draft restoration must target only the currently active note session.

## CodeController (flutter_code_editor) — Critical Safety Rules

The markdown editor uses `MarkdownCodeController` (extends `CodeController` from `flutter_code_editor`) for syntax-highlighted editing. `CodeController` has internal state (`_code` object) that tracks text, hidden ranges, and edit history. Misusing its API causes **silent data corruption**.

### NEVER use `.text =` to programmatically replace content

`CodeController` overrides `set value` and intercepts every `.text =` assignment. It treats the new text as a **user edit** and runs a diff algorithm (`Code.getEditResult`) between the old and new text:

1. The diff finds the "changed region" between old and new text.
2. Common prefixes/suffixes are treated as unchanged.
3. The internal `_code` is updated with a patched `fullTextAfter`.
4. If hidden ranges exist, the result can be further mangled.

**When switching between notes** (replacing note A's content with note B's content), this diff produces a **hybrid** of both notes — parts of note A that matched note B's structure survive as "unchanged" regions. This corrupted text then gets autosaved to disk, destroying the target note's content.

**Symptoms**: After clicking a different note/notebook/matter, the newly opened note shows partial content from the previous note (typically the "bottom part" — the body after front matter). The autosave then persists this to disk.

### ALWAYS use `.fullText =` for programmatic text replacement

```dart
// WRONG — goes through edit-diffing, can mangle content
_contentController.text = note.content;

// CORRECT — bypasses diff, cleanly resets internal Code object
_contentController.fullText = note.content;
```

`fullText =` directly calls `_updateCodeIfChanged()` and `super.value =`, bypassing the edit-diff pipeline entirely. It is the only safe way to replace the entire editor content programmatically.

### When `.text =` IS appropriate

- **Never** for replacing the full content (note switching, draft loading, undo/redo).
- The inherited `.text` setter is only safe when the change is a small incremental edit that matches what a user keystroke would produce, which in practice means: don't use it programmatically at all.

### Reading content back

- `.text` (getter) returns `value.text` (the visible text) — safe to read.
- `.fullText` (getter) returns `_code.text` (includes hidden ranges) — use when hidden ranges are active.
- When no hidden ranges are configured (Chronicle's current setup), both return the same value.

### `_lastObservedContentText` must sync after `fullText =`

After calling `_contentController.fullText = newContent`, always sync the observation tracker:
```dart
_contentController.fullText = note.content;
_lastObservedContentText = _contentController.text;
```
Do NOT use the input value directly (`_lastObservedContentText = note.content`) — always read back from the controller to account for any normalization (e.g., tab-to-space replacement).

## Autosave and Session Boundary Rules

- Programmatic hydration of title/content is read-intent. It must update editor/UI state without scheduling persistence for another note.
- Any debounced autosave closure must capture and re-check the active note/session identifiers before writing.
- Title and content observers must ignore stale callbacks from the previously selected note or draft context.
- Draft restoration must be scoped by context key and note identity together. Never apply a restored draft to a different note because the surrounding workspace context changed.
- When replacing note content and title during navigation, update all observer baselines after hydration before user edits resume.

## Workflow
1. Define extension contract (syntax pattern, AST node tag, builder behavior).
2. Implement parser and builder changes with explicit empty/error fallback.
3. Ensure required assets/dependencies are declared and loaded correctly.
4. Add or update focused markdown tests for parsing and rendering behavior.
5. Validate editor-related behavior if format toolbar, note loading, autosave, or edit helpers are affected.
6. When touching `_NoteEditorPane` or note loading logic, verify content integrity across note switches (open note A, switch to note B via different matter/notebook — note B must show its own content).
7. Add regression coverage for stale-listener cases: previous note callbacks, pending debounce timers, and restored drafts must not write into the newly selected note.
8. Re-run broader tests for shell/editor regressions.

## Verification Commands
- `flutter analyze`
- `flutter test test/presentation/common/markdown/chronicle_markdown_test.dart`
- `flutter test test/presentation/common/markdown/markdown_code_highlighting_test.dart`
- `flutter test test/presentation/common/markdown/markdown_edit_formatter_test.dart`
- `flutter test test/presentation/common/shell/chronicle_home_macos_main_pane_test.dart`
- `flutter test`

## Definition of Done
- New markdown/editor behavior is deterministic and backward-compatible where expected.
- Fallback behavior is safe for invalid or partial input.
- Required assets/dependencies are present and referenced correctly.
- No use of `_contentController.text =` for full content replacement anywhere in editor code.
- Note switching does not leak content between notes (verified manually or via test).
- Autosave and draft restoration only persist changes for the active note session.
- Title/content observer baselines are synchronized after hydration so stale callbacks cannot corrupt another note.
- Markdown-focused tests and full suite checks pass.
