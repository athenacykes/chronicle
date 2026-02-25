# Chronicle

Chronicle is a timeline-centric, local-first note app organized around **Matters**.

## Implemented v0 Foundations

- Matter model with lifecycle phases: `start`, `process`, `end`
- Markdown note model with YAML front matter
- File-based source of truth (`info.json`, `matters/`, `notebook/`, `links/`, `resources/`)
- Rebuildable SQLite search index (FTS)
- WebDAV sync engine with lock files, conflict copies, and fail-safe deletion guard
- Riverpod-driven desktop UI shell:
  - storage root setup
  - sidebar matter sections
  - phase/timeline/list note views
  - notebook workspace (root + nested folders)
  - markdown editor + preview
  - manual sync + sync status
  - settings dialog for root/sync config

## Home Shell Architecture (Refactor Status)

The Chronicle home shell refactor is in progress and follows a staged split with no public API change.

- Public surface remains:
  - `ChronicleHomeScreen`
  - `showChronicleSettingsDialog`
- Coordinator entrypoint:
  - `lib/presentation/common/shell/chronicle_home_coordinator.dart`
- Coordinator-internal `part` files still in use:
  - `lib/presentation/common/shell/chronicle_home/helpers.dart`
  - `lib/presentation/common/shell/chronicle_home/sidebar.dart`
  - `lib/presentation/common/shell/chronicle_home/workspace.dart`
  - `lib/presentation/common/shell/chronicle_home/graph.dart`
  - `lib/presentation/common/shell/chronicle_home/editor.dart`
- Extracted standalone modules (Phase 2 so far):
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

Refactor intent:

- Keep behavior and UX unchanged while reducing file size and implicit coupling.
- Promote leaf/reusable widgets first; keep orchestration state centralized until explicitly decoupled.
- Validate each extraction with `flutter analyze`, targeted shell widget tests, then full `flutter test`.

## Tooling

- Flutter `3.38.3`
- Dart `3.10.1`

## Development Run

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

## macOS Native UI Flag

Chronicle now includes an adaptive shell:

- Material shell for non-macOS targets
- macOS-native shell (using `macos_ui`) when enabled

Enable the macOS-native shell:

```bash
flutter run -d macos --dart-define=CHRONICLE_MACOS_NATIVE_UI=true
```

## Build Runnable macOS Application

Chronicle v0 is desktop-first and currently targets macOS.

### 1. One-time prerequisites

```bash
# Verify toolchains
flutter --version
dart --version
xcodebuild -version

# Enable macOS desktop support
flutter config --enable-macos-desktop

# Validate environment
flutter doctor -v
```

### 2. Build a release `.app`

```bash
flutter pub get
flutter build macos --release
```

Build output:

- `/Users/serenity/Workspace/startup/chronicle/build/macos/Build/Products/Release/chronicle.app`

### 3. Run the built app

```bash
open /Users/serenity/Workspace/startup/chronicle/build/macos/Build/Products/Release/chronicle.app
```

For local development, keep using:

```bash
flutter run -d macos
```

### 4. Debug build (optional)

```bash
flutter build macos --debug
open /Users/serenity/Workspace/startup/chronicle/build/macos/Build/Products/Debug/chronicle.app
```

## Extending to Other Platforms

The project structure is set up to expand beyond macOS. When you add a new platform:

1. Enable the platform in Flutter config (for example: `--enable-windows-desktop`, `--enable-linux-desktop`, `--enable-ios`, `--enable-android`).
2. Create/check platform folders as needed with `flutter create .`.
3. Build with the platform-specific command:
   - `flutter build windows`
   - `flutter build linux`
   - `flutter build ios`
   - `flutter build apk` or `flutter build appbundle`
4. Keep `lib/domain`, `lib/data`, and `lib/presentation` unchanged where possible; isolate platform-specific logic under platform integrations and app bootstrap.

## Key Paths

- App entry: `/Users/serenity/Workspace/startup/chronicle/lib/main.dart`
- App shell: `/Users/serenity/Workspace/startup/chronicle/lib/presentation/common/chronicle_home_screen.dart`
- Domain contracts: `/Users/serenity/Workspace/startup/chronicle/lib/domain/`
- Local file repositories: `/Users/serenity/Workspace/startup/chronicle/lib/data/local_fs/`
- Search cache: `/Users/serenity/Workspace/startup/chronicle/lib/data/cache_sqlite/`
- WebDAV sync: `/Users/serenity/Workspace/startup/chronicle/lib/data/sync_webdav/`
- Tests: `/Users/serenity/Workspace/startup/chronicle/test/`
