# Chronicle

Chronicle is a timeline-centric, local-first note app organized around **Matters**.

## Implemented v0 Foundations

- Matter model with lifecycle phases: `start`, `process`, `end`
- Markdown note model with YAML front matter
- File-based source of truth (`info.json`, `matters/`, `orphans/`, `links/`, `resources/`)
- Rebuildable SQLite search index (FTS)
- WebDAV sync engine with lock files, conflict copies, and fail-safe deletion guard
- Riverpod-driven desktop UI shell:
  - storage root setup
  - sidebar matter sections
  - phase/timeline/list note views
  - orphan workspace
  - markdown editor + preview
  - manual sync + sync status
  - settings dialog for root/sync config

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
