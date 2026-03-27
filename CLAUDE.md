# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Chronicle is a timeline-centric, local-first note app organized around **Matters** (projects with lifecycle phases). It's a desktop-first Flutter application targeting macOS, with plans to extend to other platforms.

## Tech Stack

- **Flutter**: 3.38.3
- **Dart**: 3.10.1
- **State Management**: Riverpod (flutter_riverpod)
- **DI**: Riverpod providers (`lib/app/app_providers.dart`)
- **Local Storage**: File-based (JSON + Markdown with YAML front matter)
- **Search Cache**: SQLite with FTS
- **Sync**: WebDAV with conflict detection
- **UI**: Adaptive (Material Design / macOS native via `macos_ui`)

## Common Commands

```bash
# Install dependencies
flutter pub get

# Run analysis
flutter analyze

# Run all tests
flutter test

# Run single test file
flutter test test/domain/entities/matter_test.dart

# Run tests matching a pattern
flutter test --name "createMatter"

# Run golden tests
flutter test test/golden/platform_shell_golden_test.dart

# Update golden baselines (after intentional UI changes)
flutter test test/golden/platform_shell_golden_test.dart --update-goldens

# Run integration test
flutter test integration_test/app_test.dart

# Run on macOS (Material shell)
flutter run -d macos

# Run on macOS with native macOS UI
flutter run -d macos --dart-define=CHRONICLE_MACOS_NATIVE_UI=true

# Build release macOS app
flutter build macos --release
# Output: build/macos/Build/Products/Release/chronicle.app

# Format code
dart format .

# Generate localization files (after editing ARB files)
flutter gen-l10n
```

## Architecture

### Layer Structure

```
lib/
├── domain/           # Entities, repository contracts, use cases
│   ├── entities/     # Immutable data classes (Matter, Note, Phase, etc.)
│   ├── repositories/ # Abstract repository interfaces
│   └── usecases/     # Business logic operations
├── data/             # Repository implementations
│   ├── local_fs/     # File-based storage implementation
│   ├── cache_sqlite/ # SQLite search index
│   └── sync_webdav/  # WebDAV sync engine
├── presentation/     # UI layer
│   ├── common/shell/ # Main app shell (being refactored)
│   ├── settings/     # Settings UI
│   ├── notes/        # Note editing UI
│   ├── matters/      # Matter management UI
│   └── sync/         # Sync status UI
├── app/              # App bootstrap and providers
│   ├── app.dart      # ChronicleApp widget
│   └── app_providers.dart  # Riverpod provider definitions
└── main.dart         # Entry point
```

### Key Architectural Patterns

**Repository Pattern**: Abstract contracts in `domain/repositories/`, implementations in `data/`. Repositories handle data persistence and retrieval.

**Use Cases**: Located in `domain/usecases/`, encapsulate single business operations. Use `lib/domain/usecases/usecases.dart` as barrel export.

**Riverpod Providers**: All dependencies wired in `lib/app/app_providers.dart`. Repositories are provided as singletons via `Provider<T>`, controllers use `StateNotifierProvider` or `AsyncNotifier`.

**File-Based Storage**: Notes stored as Markdown files with YAML front matter. Matters stored as JSON. Repository implementations in `data/local_fs/` use codec pattern (`MatterFileCodec`, `NoteFileCodec`).

**Platform Abstraction**: macOS native UI enabled via `--dart-define=CHRONICLE_MACOS_NATIVE_UI=true`. Checked via `PlatformInfo.useMacOSNativeUI` (`lib/presentation/common/platform/platform_info.dart`).

**Localization**: ARB files in `lib/l10n/`. Access via `context.l10n` extension (`lib/l10n/localization.dart`). Run `flutter gen-l10n` after editing ARB files.

### Core Entities

- **Matter**: A project with lifecycle phases (`start`, `process`, `end`)
- **Note**: Markdown note with YAML front matter, belongs to either a Matter phase or Notebook folder
- **Phase**: Stage within a Matter (e.g., "Planning", "Execution")
- **Category**: Optional grouping for Matters
- **NotebookFolder**: Folder structure for notes not in Matters
- **NoteLink**: Bi-directional links between notes

### Storage Layout

```
<storage_root>/
├── info.json              # App metadata
├── matters/
│   └── <matter_id>/
│       ├── matter.json    # Matter metadata
│       └── notes/
│           └── <phase_id>/
│               └── <note_id>.md
├── notebook/              # Notes not in matters
│   └── <folder_id>/
│       └── <note_id>.md
├── links/
│   └── <note_id>.json     # Outgoing links from note
└── resources/             # Attachments
```

### Shell Architecture (In Progress)

The home shell is undergoing staged refactoring:

- **Public API**: `ChronicleHomeScreen`, `showChronicleSettingsDialog`
- **Coordinator**: `lib/presentation/common/shell/chronicle_home_coordinator.dart` (orchestration state)
- **Part Files** (still coupled): `chronicle_home/helpers.dart`, `sidebar.dart`, `workspace.dart`, `graph.dart`, `editor.dart`
- **Extracted Modules**: Standalone widgets in `lib/presentation/common/shell/chronicle_*.dart`

After extraction changes, validate with:
```bash
flutter analyze
flutter test test/presentation/common/shell/chronicle_home_macos_main_pane_test.dart
flutter test
```

## Testing

- **Unit/Widget Tests**: Mirror source path structure in `test/`
- **Golden Tests**: `test/golden/` - run with `--update-goldens` to update baselines
- **Integration Tests**: `integration_test/`
- **Mocking**: Uses `mocktail`

Test files must end with `_test.dart`.

## Code Style

- 2-space indentation
- Trailing commas for stable formatting
- File names: `snake_case.dart`
- Classes: `PascalCase`
- Methods/fields: `camelCase`
- Lint rules: `package:flutter_lints/flutter.yaml`

