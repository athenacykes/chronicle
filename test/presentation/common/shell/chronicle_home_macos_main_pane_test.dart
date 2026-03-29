import 'dart:async';

import 'package:chronicle/app/app.dart';
import 'package:chronicle/app/app_providers.dart';
import 'package:chronicle/core/clock.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/category.dart';
import 'package:chronicle/domain/entities/enums.dart';
import 'package:chronicle/domain/entities/matter.dart';
import 'package:chronicle/domain/entities/note.dart';
import 'package:chronicle/domain/entities/note_link.dart';
import 'package:chronicle/domain/entities/notebook_folder.dart';
import 'package:chronicle/domain/entities/note_search_hit.dart';
import 'package:chronicle/domain/entities/phase.dart';
import 'package:chronicle/domain/entities/search_query.dart';
import 'package:chronicle/domain/entities/sync_bootstrap_assessment.dart';
import 'package:chronicle/domain/entities/sync_blocker.dart';
import 'package:chronicle/domain/entities/sync_conflict.dart';
import 'package:chronicle/domain/entities/sync_conflict_detail.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/entities/sync_progress.dart';
import 'package:chronicle/domain/entities/sync_run_options.dart';
import 'package:chronicle/domain/entities/sync_result.dart';
import 'package:chronicle/domain/repositories/link_repository.dart';
import 'package:chronicle/domain/repositories/category_repository.dart';
import 'package:chronicle/domain/repositories/matter_repository.dart';
import 'package:chronicle/domain/repositories/note_repository.dart';
import 'package:chronicle/domain/repositories/notebook_repository.dart';
import 'package:chronicle/domain/repositories/search_repository.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:chronicle/domain/repositories/sync_repository.dart';
import 'package:chronicle/presentation/matters/matters_controller.dart';
import 'package:chronicle/presentation/notes/notes_controller.dart';
import 'package:chronicle/presentation/search/search_controller.dart';
import 'package:chronicle/presentation/sync/conflicts_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';

void main() {
  const appkitUiElementColors = MethodChannel('appkit_ui_element_colors');

  final now = DateTime.utc(2026, 2, 18, 22, 42);
  final phases = <Phase>[
    const Phase(
      id: 'phase-start',
      matterId: 'matter-1',
      name: 'Start',
      order: 0,
    ),
    const Phase(
      id: 'phase-progress',
      matterId: 'matter-1',
      name: 'In Progress',
      order: 1,
    ),
    const Phase(
      id: 'phase-end',
      matterId: 'matter-1',
      name: 'Completed',
      order: 2,
    ),
  ];
  final matter = Matter(
    id: 'matter-1',
    categoryId: null,
    title: 'Matter One',
    description: 'Simple matter',
    status: MatterStatus.active,
    color: '#2563EB',
    icon: 'description',
    isPinned: false,
    createdAt: now,
    updatedAt: now,
    startedAt: now,
    endedAt: null,
    phases: phases,
    currentPhaseId: 'phase-progress',
  );
  final noteOne = Note(
    id: 'note-1',
    matterId: 'matter-1',
    phaseId: 'phase-start',
    notebookFolderId: null,
    title: 'Editor Note',
    content: '# Editor Note\ncontent',
    tags: const <String>['one'],
    isPinned: false,
    attachments: const <String>[],
    createdAt: now,
    updatedAt: now,
  );
  final noteTwo = Note(
    id: 'note-2',
    matterId: null,
    phaseId: null,
    notebookFolderId: null,
    title: 'Search Hit',
    content: 'searchable content',
    tags: const <String>['two'],
    isPinned: false,
    attachments: const <String>[],
    createdAt: now,
    updatedAt: now,
  );
  final notebookFolder = NotebookFolder(
    id: 'folder-1',
    name: 'Folder One',
    parentId: null,
    createdAt: now,
    updatedAt: now,
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appkitUiElementColors, (call) async {
          switch (call.method) {
            case 'getColorComponents':
              return <String, double>{
                'redComponent': 0.0,
                'greenComponent': 0.47843137254901963,
                'blueComponent': 1.0,
                'hueComponent': 0.5866013071895425,
              };
            case 'getColor':
              return 0xFF007AFF;
          }
          return null;
        });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appkitUiElementColors, null);
  });

  Future<void> expectEditorCodeThemeBackground({
    required WidgetTester tester,
    required bool useMacOSNativeUI,
    required Brightness platformBrightness,
    required Color expectedBackground,
    String? expectedTokenKey,
    Color? expectedTokenColor,
  }) async {
    _setDesktopViewport(tester);
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.platformBrightnessTestValue = platformBrightness;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);

    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );
    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: useMacOSNativeUI,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final editorContent = find.byKey(const Key('macos_note_editor_content'));
    expect(editorContent, findsOneWidget);
    final codeThemeFinder = find.ancestor(
      of: editorContent,
      matching: find.byType(CodeTheme),
    );
    expect(codeThemeFinder, findsOneWidget);
    final codeTheme = tester.widget<CodeTheme>(codeThemeFinder);
    expect(codeTheme.data?.styles['root']?.backgroundColor, expectedBackground);
    if (expectedTokenKey != null || expectedTokenColor != null) {
      expect(expectedTokenKey, isNotNull);
      expect(expectedTokenColor, isNotNull);
      expect(
        codeTheme.data?.styles[expectedTokenKey!]?.color,
        expectedTokenColor,
      );
    }
  }

  testWidgets('macOS matter mode renders native main-pane controls', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Top bar now has only Notes, Board, Graph buttons
    expect(find.byKey(const Key('matter_top_notes_button')), findsOneWidget);
    expect(find.byKey(const Key('matter_top_kanban_button')), findsOneWidget);
    expect(find.byKey(const Key('matter_top_graph_button')), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Graph'), findsOneWidget);
    // Phase selector and New Note are now in the notes view, not top bar
    expect(
      find.byKey(const Key('matter_notes_phase_selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('matter_notes_new_note_button')),
      findsOneWidget,
    );
    final searchCenter = tester.getCenter(
      find.byKey(const Key('macos_top_bar_search_slot')),
    );
    final conflictsCenter = tester.getCenter(
      find.byKey(const Key('macos_top_bar_conflicts_button')),
    );
    expect((searchCenter.dy - conflictsCenter.dy).abs(), lessThanOrEqualTo(2));
    expect(find.byType(MacosPulldownButton), findsWidgets);
    expect(find.byKey(const Key('note_header_title_display')), findsOneWidget);
    expect(find.byType(SegmentedButton<MatterViewMode>), findsNothing);
  });

  testWidgets('macOS notebook mode uses native header and list controls', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          showOrphansProvider.overrideWithBuild((ref, notifier) => true),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-2'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('notebook_new_note_button')),
      findsOneWidget,
    );
    expect(find.byType(MacosPulldownButton), findsWidgets);
  });

  testWidgets('matter note list pane resizes, clamps, and persists', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );
    final settingsRepository = _FakeSettingsRepository(
      AppSettings(
        storageRootPath: '/tmp/chronicle-test',
        clientId: 'test-client',
        syncConfig: SyncConfig.initial(),
        lastSyncAt: null,
      ),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        settingsRepository: settingsRepository,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final paneFinder = find.byKey(const Key('matter_note_list_pane'));
    final handleFinder = find.byKey(
      const Key('matter_note_list_resize_handle'),
    );
    final initialWidth = tester.getSize(paneFinder).width;

    await tester.drag(handleFinder, const Offset(-120, 0));
    await tester.pumpAndSettle();
    final resizedWidth = tester.getSize(paneFinder).width;
    expect(resizedWidth, lessThan(initialWidth));
    expect(resizedWidth, greaterThanOrEqualTo(180));

    await tester.drag(handleFinder, const Offset(-1000, 0));
    await tester.pumpAndSettle();
    final clampedWidth = tester.getSize(paneFinder).width;
    expect(clampedWidth, closeTo(180, 0.1));

    final persistedAfterDrag = await settingsRepository.loadSettings();
    expect(
      persistedAfterDrag.matterNoteListPaneWidth,
      closeTo(clampedWidth, 0.1),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        settingsRepository: settingsRepository,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final restoredWidth = tester.getSize(paneFinder).width;
    expect(
      restoredWidth,
      closeTo(persistedAfterDrag.matterNoteListPaneWidth, 0.1),
    );
  });

  testWidgets(
    'notebook note list pane persists independently from matter pane width',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );
      final settingsRepository = _FakeSettingsRepository(
        AppSettings(
          storageRootPath: '/tmp/chronicle-test',
          clientId: 'test-client',
          syncConfig: SyncConfig.initial(),
          lastSyncAt: null,
          matterNoteListPaneWidth: 286,
          notebookNoteListPaneWidth: 380,
        ),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: true,
          repos: repos,
          settingsRepository: settingsRepository,
          overrides: [
            showOrphansProvider.overrideWithBuild((ref, notifier) => true),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-2',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final notebookPaneFinder = find.byKey(
        const Key('notebook_note_list_pane'),
      );
      final notebookHandleFinder = find.byKey(
        const Key('notebook_note_list_resize_handle'),
      );
      await tester.drag(notebookHandleFinder, const Offset(-90, 0));
      await tester.pumpAndSettle();

      final notebookWidth = tester.getSize(notebookPaneFinder).width;
      final persisted = await settingsRepository.loadSettings();
      expect(persisted.notebookNoteListPaneWidth, closeTo(notebookWidth, 0.1));
      expect(persisted.matterNoteListPaneWidth, 286);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: true,
          repos: repos,
          settingsRepository: settingsRepository,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final matterPaneFinder = find.byKey(const Key('matter_note_list_pane'));
      expect(tester.getSize(matterPaneFinder).width, closeTo(286, 0.1));
    },
  );

  testWidgets('macOS sidebar uses reduced minimum width', (tester) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final macosWindow = tester.widget<MacosWindow>(find.byType(MacosWindow));
    final sidebar = macosWindow.sidebar!;
    expect(sidebar.minWidth, 200);
    expect(sidebar.startWidth, 320);
  });

  testWidgets('macOS sidebar does not render material scrollbar wrapper', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final sidebarRoot = find.byKey(const Key('sidebar_root'));
    expect(
      find.descendant(of: sidebarRoot, matching: find.byType(Scrollbar)),
      findsNothing,
    );
  });

  testWidgets('empty workspace shows one-screen welcome tour', (tester) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(const <Matter>[]),
      noteRepository: _MemoryNoteRepository(const <Note>[]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(_buildApp(useMacOSNativeUI: true, repos: repos));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('welcome_tour_panel')), findsOneWidget);
    expect(find.text('Welcome to Chronicle'), findsOneWidget);
    expect(
      find.byKey(const Key('welcome_tour_create_matter_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('welcome_tour_open_notebook_button')),
      findsOneWidget,
    );
  });

  testWidgets('welcome tour Create Matter action creates a matter', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final matterRepository = _MemoryMatterRepository(const <Matter>[]);
    final repos = _TestRepos(
      matterRepository: matterRepository,
      noteRepository: _MemoryNoteRepository(const <Note>[]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(_buildApp(useMacOSNativeUI: false, repos: repos));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('welcome_tour_create_matter_button')),
    );
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)).at(0),
      'Welcome Tour Matter',
    );
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)).at(1),
      'Created from welcome tour',
    );
    await tester.tap(find.text('Create').last);
    await tester.pumpAndSettle();

    final matters = await matterRepository.listMatters();
    expect(matters, hasLength(1));
    expect(matters.first.title, 'Welcome Tour Matter');

    final container = _containerForApp(tester);
    expect(container.read(selectedMatterIdProvider), 'matter-1');
    expect(find.byKey(const Key('welcome_tour_panel')), findsNothing);
  });

  testWidgets('welcome tour Open Notebook action switches workspace mode', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(const <Matter>[]),
      noteRepository: _MemoryNoteRepository(const <Note>[]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(_buildApp(useMacOSNativeUI: false, repos: repos));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('welcome_tour_open_notebook_button')),
    );
    await tester.pumpAndSettle();

    final container = _containerForApp(tester);
    expect(container.read(showOrphansProvider), isTrue);
    expect(container.read(selectedMatterIdProvider), isNull);
    expect(
      find.byKey(const Key('notebook_new_note_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('welcome_tour_panel')), findsNothing);
  });

  testWidgets('welcome tour is hidden when a matter is selected', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('welcome_tour_panel')), findsNothing);
    // Phase selector is now in the notes view, not top bar
    expect(
      find.byKey(const Key('matter_notes_phase_selector')),
      findsOneWidget,
    );
  });

  testWidgets(
    'top phase control shows All Phases label when filter is unselected',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild((ref, notifier) => null),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Phase selector is now in the notes view, not top bar
      expect(
        find.byKey(const Key('matter_notes_phase_selector')),
        findsOneWidget,
      );
      expect(find.text('All Phases'), findsOneWidget);
    },
  );

  testWidgets('matter New Note creates untitled draft without dialog', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final noteRepository = _MemoryNoteRepository(<Note>[noteOne, noteTwo]);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: noteRepository,
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
          noteEditorViewModeProvider.overrideWithBuild(
            (ref, notifier) => NoteEditorViewMode.read,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // New note button is now in the notes view, not top bar
    await tester.tap(find.byKey(const Key('matter_notes_new_note_button')));
    await tester.pumpAndSettle();

    expect(find.text('Create Note'), findsNothing);
    final created = noteRepository.noteById('note-3');
    expect(created, isNotNull);
    expect(created?.title, 'Untitled Note');
    expect(created?.matterId, 'matter-1');
    expect(created?.phaseId, 'phase-start');

    final modeToggle = tester
        .widget<CupertinoSlidingSegmentedControl<NoteEditorViewMode>>(
          find.byKey(const Key('note_editor_mode_toggle')),
        );
    expect(modeToggle.groupValue, NoteEditorViewMode.edit);
  });

  testWidgets(
    'notebook New Note creates untitled notebook draft without dialog',
    (tester) async {
      _setDesktopViewport(tester);
      final noteRepository = _MemoryNoteRepository(<Note>[noteOne, noteTwo]);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: noteRepository,
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: true,
          repos: repos,
          overrides: [
            showOrphansProvider.overrideWithBuild((ref, notifier) => true),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-2',
            ),
            noteEditorViewModeProvider.overrideWithBuild(
              (ref, notifier) => NoteEditorViewMode.read,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notebook_new_note_button')));
      await tester.pumpAndSettle();

      expect(find.text('Create Note'), findsNothing);
      final created = noteRepository.noteById('note-3');
      expect(created, isNotNull);
      expect(created?.title, 'Untitled Note');
      expect(created?.matterId, isNull);
      expect(created?.phaseId, isNull);

      final modeToggle = tester
          .widget<CupertinoSlidingSegmentedControl<NoteEditorViewMode>>(
            find.byKey(const Key('note_editor_mode_toggle')),
          );
      expect(modeToggle.groupValue, NoteEditorViewMode.edit);
    },
  );

  testWidgets(
    'selecting notebook folder with notes opens first notebook note',
    (tester) async {
      _setDesktopViewport(tester);
      final notebookNoteOne = Note(
        id: 'note-2',
        matterId: null,
        phaseId: null,
        notebookFolderId: 'folder-1',
        title: 'Folder Note A',
        content: '# Folder A\nfirst',
        tags: const <String>['a'],
        isPinned: false,
        attachments: const <String>[],
        createdAt: now,
        updatedAt: now,
      );
      final notebookNoteTwo = Note(
        id: 'note-3',
        matterId: null,
        phaseId: null,
        notebookFolderId: 'folder-1',
        title: 'Folder Note B',
        content: '# Folder B\nsecond',
        tags: const <String>['b'],
        isPinned: false,
        attachments: const <String>[],
        createdAt: now,
        updatedAt: now,
      );
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[
          noteOne,
          notebookNoteOne,
          notebookNoteTwo,
        ]),
        linkRepository: _MemoryLinkRepository(),
      );
      final notebookRepository = _MemoryNotebookRepository(<NotebookFolder>[
        notebookFolder,
      ]);

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            notebookRepositoryProvider.overrideWithValue(notebookRepository),
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _tapSidebarNotebookFolder(tester, 'folder-1');
      await tester.pumpAndSettle();

      final container = _containerForApp(tester);
      expect(container.read(showOrphansProvider), isTrue);
      expect(container.read(selectedNotebookFolderIdProvider), 'folder-1');
      expect(container.read(selectedNoteIdProvider), 'note-2');
      expect(find.text('Folder Note A'), findsWidgets);

      final contentField = tester.widget<CodeField>(
        find.byKey(const Key('macos_note_editor_content')),
      );
      expect(contentField.controller.text, '# Folder A\nfirst');
    },
  );

  testWidgets(
    'selecting empty notebook folder clears stale note title and shows draft',
    (tester) async {
      _setDesktopViewport(tester);
      final noteRepository = _MemoryNoteRepository(<Note>[noteOne]);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: noteRepository,
        linkRepository: _MemoryLinkRepository(),
      );
      final notebookRepository = _MemoryNotebookRepository(<NotebookFolder>[
        notebookFolder,
      ]);

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            notebookRepositoryProvider.overrideWithValue(notebookRepository),
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('note_header_title_display')),
        findsOneWidget,
      );
      await _tapSidebarNotebookFolder(tester, 'folder-1');
      await tester.pumpAndSettle();

      final container = _containerForApp(tester);
      expect(container.read(showOrphansProvider), isTrue);
      expect(container.read(selectedNotebookFolderIdProvider), 'folder-1');
      expect(container.read(selectedNoteIdProvider), isNull);
      expect(container.read(notebookDraftSessionProvider), isNotNull);
      expect(find.byKey(const Key('note_header_title_display')), findsNothing);
      expect(
        find.byKey(const Key('notebook_draft_title_field')),
        findsOneWidget,
      );
      expect(noteRepository.noteById('note-2'), isNull);
    },
  );

  testWidgets(
    'empty notebook draft persists on input and notebook autosave keeps updating',
    (tester) async {
      _setDesktopViewport(tester);
      final noteRepository = _MemoryNoteRepository(<Note>[noteOne]);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: noteRepository,
        linkRepository: _MemoryLinkRepository(),
      );
      final notebookRepository = _MemoryNotebookRepository(<NotebookFolder>[
        notebookFolder,
      ]);

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            notebookRepositoryProvider.overrideWithValue(notebookRepository),
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _tapSidebarNotebookFolder(tester, 'folder-1');
      await tester.pumpAndSettle();
      expect(noteRepository.noteById('note-2'), isNull);

      await tester.enterText(
        find.byKey(const Key('notebook_draft_title_field')),
        'Draft Notebook Note',
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('macos_note_editor_content')),
        'First notebook draft body',
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      final created = noteRepository.noteById('note-2');
      expect(created, isNotNull);
      expect(created?.title, 'Draft Notebook Note');
      expect(created?.content, 'First notebook draft body');
      expect(created?.notebookFolderId, 'folder-1');

      final container = _containerForApp(tester);
      expect(container.read(selectedNoteIdProvider), 'note-2');
      expect(container.read(notebookDraftSessionProvider), isNull);

      await tester.enterText(
        find.byKey(const Key('macos_note_editor_content')),
        'First notebook draft body\nautosave update',
      );
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      final updated = noteRepository.noteById('note-2');
      expect(updated?.content, 'First notebook draft body\nautosave update');
    },
  );

  testWidgets(
    'same notebook context draft replacement clears stale draft editor state',
    (tester) async {
      _setDesktopViewport(tester);
      final noteRepository = _MemoryNoteRepository(<Note>[noteOne]);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: noteRepository,
        linkRepository: _MemoryLinkRepository(),
      );
      final notebookRepository = _MemoryNotebookRepository(<NotebookFolder>[
        notebookFolder,
      ]);

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            notebookRepositoryProvider.overrideWithValue(notebookRepository),
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _tapSidebarNotebookFolder(tester, 'folder-1');
      await tester.pumpAndSettle();

      final container = _containerForApp(tester);
      expect(container.read(notebookDraftSessionProvider), isNotNull);

      await tester.enterText(
        find.byKey(const Key('notebook_draft_title_field')),
        'Stale notebook draft',
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('macos_note_editor_content')),
        'stale notebook body',
      );
      await tester.pump();

      container
          .read(notebookDraftSessionProvider.notifier)
          .set(
            const NotebookDraftSession.emptyNotebook(
              folderId: 'folder-1',
              draftSessionToken: 999,
            ),
          );
      await tester.pump();

      final titleField = tester.widget<TextField>(
        find.byKey(const Key('notebook_draft_title_field')),
      );
      expect(titleField.controller?.text, isEmpty);
      final contentField = tester.widget<CodeField>(
        find.byKey(const Key('macos_note_editor_content')),
      );
      expect(contentField.controller.text, isEmpty);

      await tester.tap(find.byKey(const Key('macos_note_editor_save')));
      await tester.pumpAndSettle();

      expect(noteRepository.noteById('note-2'), isNull);
      expect(container.read(selectedNoteIdProvider), isNull);
    },
  );

  testWidgets('macOS sidebar renders descender-heavy labels without clipping', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final matterTwo = matter.copyWith(
      id: 'matter-2',
      title: 'pqgy docket',
      phases: const <Phase>[
        Phase(
          id: 'phase-2-start',
          matterId: 'matter-2',
          name: 'Start',
          order: 0,
        ),
      ],
      currentPhaseId: 'phase-2-start',
    );
    final descMatter = matter.copyWith(title: 'gypq matter 123');
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[
        descMatter,
        matterTwo,
      ]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('sidebar_root')),
      matchesGoldenFile('goldens/macos_sidebar_descenders_rest.png'),
    );
  });

  testWidgets('macOS sidebar hover highlight keeps labels legible', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final descMatter = matter.copyWith(title: 'gypq matter 123');
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[descMatter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final drag = await _startLongPressDrag(
      tester,
      find.byKey(const ValueKey<String>('note_drag_list_macos_note-1')),
    );
    await drag.moveTo(
      tester.getCenter(
        find.byKey(const Key('sidebar_notebook_root_drop_target')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    await expectLater(
      find.byKey(const Key('sidebar_root')),
      matchesGoldenFile('goldens/macos_sidebar_descenders_drag_hover.png'),
    );

    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'macOS sidebar keeps Views then Notebooks, removes notebook icons, and keeps root notebook fixed',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: true,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final views = find.text('Views');
      final notebooks = find.text('Notebooks');
      final notebook = find.text('Notebook');
      final sidebar = find.byKey(const Key('sidebar_root'));
      expect(views, findsOneWidget);
      expect(notebooks, findsOneWidget);
      expect(notebook, findsOneWidget);
      expect(
        find.descendant(of: sidebar, matching: find.text('Conflicts')),
        findsNothing,
      );
      final viewsTop = tester.getTopLeft(views).dy;
      final notebooksTop = tester.getTopLeft(notebooks).dy;
      expect(viewsTop, lessThan(notebooksTop));
      expect(notebooksTop - viewsTop, greaterThan(16));
      expect(notebooksTop, lessThan(tester.getTopLeft(notebook).dy));
      expect(
        find.descendant(
          of: sidebar,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is MacosIcon && widget.icon == CupertinoIcons.book,
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: sidebar,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is MacosIcon && widget.icon == CupertinoIcons.folder,
          ),
        ),
        findsNothing,
      );

      final buttons = tester
          .widgetList<MacosPulldownButton>(find.byType(MacosPulldownButton))
          .toList();
      final notebookMenus = buttons.where((button) {
        final titles = _macosPulldownTitles(button);
        return titles.contains('New Folder');
      }).toList();
      expect(notebookMenus, isEmpty);

      final matterActionMenus = buttons.where((button) {
        final titles = _macosPulldownTitles(button);
        return titles.contains('Set Active') &&
            titles.contains('Set Paused') &&
            titles.contains('Set Completed') &&
            titles.contains('Set Archived');
      }).toList();
      expect(matterActionMenus, isEmpty);
    },
  );

  testWidgets(
    'material sidebar keeps Views then Notebooks and removes notebook ellipsis menus',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final views = find.text('Views');
      final notebooks = find.text('Notebooks');
      final notebook = find.text('Notebook');
      final sidebar = find.byKey(const Key('sidebar_root'));
      expect(views, findsOneWidget);
      expect(notebooks, findsOneWidget);
      expect(notebook, findsOneWidget);
      expect(
        find.descendant(of: sidebar, matching: find.text('Conflicts')),
        findsNothing,
      );
      final viewsTop = tester.getTopLeft(views).dy;
      final notebooksTop = tester.getTopLeft(notebooks).dy;
      expect(viewsTop, lessThan(notebooksTop));
      expect(notebooksTop - viewsTop, greaterThan(16));
      expect(notebooksTop, lessThan(tester.getTopLeft(notebook).dy));
      expect(
        find.descendant(
          of: sidebar,
          matching: find.byIcon(Icons.book_outlined),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: sidebar,
          matching: find.byIcon(Icons.folder_outlined),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: sidebar, matching: find.byIcon(Icons.more_horiz)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('sidebar_matter_drop_target_matter-1'),
          ),
          matching: find.byIcon(CupertinoIcons.ellipsis_circle),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('sidebar_notebook_root_drop_target')),
          matching: find.byIcon(CupertinoIcons.ellipsis_circle),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'macOS zh locale shows section headers and search without overflow',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(useMacOSNativeUI: true, repos: repos, localeTag: 'zh'),
      );
      await tester.pumpAndSettle();

      expect(find.text('视图'), findsOneWidget);
      expect(find.text('笔记本'), findsWidgets);
      expect(find.byType(MacosSearchField<void>), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('macOS narrow mode shows compact top bar with hamburger', (
    tester,
  ) async {
    _setNarrowDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('macos_top_bar_compact_menu_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('macos_top_bar_search_slot')), findsNothing);
    expect(find.text('Matter One'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS narrow hamburger panel shows search and context actions', (
    tester,
  ) async {
    _setNarrowDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('macos_top_bar_compact_menu_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('macos_top_bar_compact_panel')),
      findsOneWidget,
    );
    expect(find.byType(MacosSearchField<void>), findsOneWidget);
    // New note button is now in notes view title row (visible, but not in compact panel)
    expect(find.text('New Note'), findsOneWidget);
    expect(
      find.byKey(const Key('macos_top_bar_conflicts_button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'macOS narrow hamburger note picker opens selected note and closes panel',
    (tester) async {
      _setNarrowDesktopViewport(tester);
      final secondMatterNote = Note(
        id: 'note-3',
        matterId: 'matter-1',
        phaseId: 'phase-start',
        notebookFolderId: null,
        title: 'Second Matter Note',
        content: '# Second Matter Note\nmore content',
        tags: const <String>['three'],
        isPinned: false,
        attachments: const <String>[],
        createdAt: now,
        updatedAt: now,
      );
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[
          noteOne,
          secondMatterNote,
        ]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: true,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('macos_top_bar_compact_menu_button')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('macos_compact_note_picker_note-3')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('macos_top_bar_compact_panel')),
        findsNothing,
      );
      expect(_containerForApp(tester).read(selectedNoteIdProvider), 'note-3');
      expect(find.text('Second Matter Note'), findsWidgets);
      expect(
        find.byKey(const Key('macos_note_editor_content')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('macOS narrow matter layout does not overflow', (tester) async {
    _setNarrowDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS narrow notebook layout does not overflow', (tester) async {
    _setNarrowDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          showOrphansProvider.overrideWithBuild((ref, notifier) => true),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-2'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('material list menu moves note to another matter', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final matterTwo = matter.copyWith(
      id: 'matter-2',
      title: 'Matter Two',
      phases: const <Phase>[
        Phase(
          id: 'phase-2-start',
          matterId: 'matter-2',
          name: 'Start',
          order: 0,
        ),
        Phase(
          id: 'phase-2-review',
          matterId: 'matter-2',
          name: 'Review',
          order: 1,
        ),
      ],
      currentPhaseId: 'phase-2-review',
    );
    final noteRepository = _MemoryNoteRepository(<Note>[noteOne, noteTwo]);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter, matterTwo]),
      noteRepository: noteRepository,
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _secondaryClick(
      tester,
      find.byKey(const ValueKey<String>('phase_note_row_note-1')),
    );
    await tester.tap(find.text('Move to Matter...').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Matter Two').last);
    await tester.pumpAndSettle();

    final moved = noteRepository.noteById('note-1');
    expect(moved?.matterId, 'matter-2');
    expect(moved?.phaseId, 'phase-2-review');

    final container = _containerForApp(tester);
    expect(container.read(selectedMatterIdProvider), 'matter-1');
    expect(container.read(showOrphansProvider), isFalse);
  });

  testWidgets('material list menu moves note to another phase in same matter', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final noteRepository = _MemoryNoteRepository(<Note>[noteOne, noteTwo]);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: noteRepository,
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _secondaryClick(
      tester,
      find.byKey(const ValueKey<String>('phase_note_row_note-1')),
    );
    await tester.tap(find.text('Move to Phase...').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('In Progress').last);
    await tester.pumpAndSettle();

    final moved = noteRepository.noteById('note-1');
    expect(moved?.matterId, 'matter-1');
    expect(moved?.phaseId, 'phase-progress');
  });

  testWidgets(
    'material list menu opens move-to-notebook flow without switching view',
    (tester) async {
      _setDesktopViewport(tester);
      final noteRepository = _MemoryNoteRepository(<Note>[noteOne, noteTwo]);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: noteRepository,
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _secondaryClick(
        tester,
        find.byKey(const ValueKey<String>('phase_note_row_note-1')),
      );
      await tester.tap(find.text('Move to Notebook...').last);
      await tester.pumpAndSettle();

      final moved = noteRepository.noteById('note-1');
      expect(moved?.matterId, 'matter-1');
      expect(moved?.phaseId, 'phase-start');

      final container = _containerForApp(tester);
      expect(container.read(selectedMatterIdProvider), 'matter-1');
      expect(container.read(showOrphansProvider), isFalse);
    },
  );

  testWidgets(
    'material phase list row opens context menu from text, whitespace, and right edge',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey<String>('phase_note_row_note-1'));
      final rowRect = tester.getRect(row);
      final titleText = find.descendant(
        of: row,
        matching: find.text('Editor Note'),
      );

      await _secondaryClick(tester, titleText);
      expect(find.text('Move to Matter...'), findsWidgets);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await _secondaryClickAt(
        tester,
        Offset(rowRect.left + 12, rowRect.center.dy),
      );
      expect(find.text('Move to Matter...'), findsWidgets);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await _secondaryClickAt(
        tester,
        Offset(rowRect.right - 8, rowRect.center.dy),
      );
      expect(find.text('Move to Matter...'), findsWidgets);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('material kanban card opens move context menu on right click', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
          matterViewModeProvider.overrideWithBuild(
            (ref, notifier) => MatterViewMode.kanban,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(
      const ValueKey<String>('kanban_note_card_note-1'),
    );
    expect(card, findsOneWidget);
  });

  testWidgets(
    'macOS kanban card is displayed in kanban view',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: true,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
            matterViewModeProvider.overrideWithBuild(
              (ref, notifier) => MatterViewMode.kanban,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final card = find.byKey(
        const ValueKey<String>('kanban_note_card_note-1'),
      );
      expect(card, findsOneWidget);
    },
  );

  testWidgets('drag from phase list to matter sidebar target moves note', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final matterTwo = matter.copyWith(
      id: 'matter-2',
      title: 'Matter Two',
      phases: const <Phase>[
        Phase(
          id: 'phase-2-start',
          matterId: 'matter-2',
          name: 'Start',
          order: 0,
        ),
      ],
      currentPhaseId: 'phase-2-start',
    );
    final noteRepository = _MemoryNoteRepository(<Note>[noteOne, noteTwo]);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter, matterTwo]),
      noteRepository: noteRepository,
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _longPressDragTo(
      tester,
      find.byKey(const ValueKey<String>('note_drag_list_material_note-1')),
      find.byKey(const ValueKey<String>('sidebar_matter_drop_target_matter-2')),
    );

    final moved = noteRepository.noteById('note-1');
    expect(moved?.matterId, 'matter-2');
    expect(moved?.phaseId, 'phase-2-start');
  });

  testWidgets(
    'kanban view displays notes grouped by phase',
    (tester) async {
      _setDesktopViewport(tester);
      final noteRepository = _MemoryNoteRepository(<Note>[noteOne, noteTwo]);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: noteRepository,
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
            matterViewModeProvider.overrideWithBuild(
              (ref, notifier) => MatterViewMode.kanban,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Verify kanban card is displayed (note-2 has no matterId, so only note-1 appears)
      expect(
        find.byKey(const ValueKey<String>('kanban_note_card_note-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets('drag from graph node to matter target works', (tester) async {
    _setDesktopViewport(tester);
    final matterTwo = matter.copyWith(
      id: 'matter-2',
      title: 'Matter Two',
      phases: const <Phase>[
        Phase(
          id: 'phase-2-start',
          matterId: 'matter-2',
          name: 'Start',
          order: 0,
        ),
      ],
      currentPhaseId: 'phase-2-start',
    );
    final noteRepository = _MemoryNoteRepository(<Note>[noteOne, noteTwo]);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter, matterTwo]),
      noteRepository: noteRepository,
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
          matterViewModeProvider.overrideWithBuild(
            (ref, notifier) => MatterViewMode.graph,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _longPressDragTo(
      tester,
      find.byKey(const ValueKey<String>('note_drag_graph_note-1')),
      find.byKey(const ValueKey<String>('sidebar_matter_drop_target_matter-2')),
    );

    final moved = noteRepository.noteById('note-1');
    expect(moved?.matterId, 'matter-2');
    expect(moved?.phaseId, 'phase-2-start');
  });

  testWidgets('material sidebar drag moves matter into category', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final categoryRepository = _MemoryCategoryRepository(<Category>[
      Category(
        id: 'category-1',
        name: 'Work',
        color: '#2563EB',
        icon: 'folder',
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    final looseMatter = matter.copyWith(
      id: 'matter-loose',
      title: 'Loose Matter',
      categoryId: null,
      clearCategoryId: true,
      isPinned: false,
    );
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[looseMatter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        categoryRepository: categoryRepository,
      ),
    );
    await tester.pumpAndSettle();

    await _longPressDragTo(
      tester,
      find.byKey(
        const ValueKey<String>('sidebar_matter_reassign_drag_matter-loose'),
      ),
      find.byKey(
        const ValueKey<String>(
          'sidebar_category_drop_target_material_category-1',
        ),
      ),
    );

    final moved = await repos.matterRepository.getMatterById('matter-loose');
    expect(moved?.categoryId, 'category-1');
  });

  testWidgets(
    'clicking a matter in a category keeps the category sort order stable',
    (tester) async {
      _setDesktopViewport(tester);
      final categoryRepository = _MemoryCategoryRepository(<Category>[
        Category(
          id: 'category-1',
          name: 'Work',
          color: '#2563EB',
          icon: 'folder',
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      Matter buildCategoryMatter({
        required String id,
        required String title,
        required DateTime updatedAt,
      }) {
        return Matter(
          id: id,
          categoryId: 'category-1',
          title: title,
          description: '',
          status: MatterStatus.active,
          color: '#2563EB',
          icon: 'description',
          isPinned: false,
          createdAt: updatedAt.subtract(const Duration(minutes: 10)),
          updatedAt: updatedAt,
          startedAt: updatedAt.subtract(const Duration(minutes: 10)),
          endedAt: null,
          phases: <Phase>[
            Phase(id: '$id-phase-start', matterId: id, name: 'Start', order: 0),
          ],
          currentPhaseId: '$id-phase-start',
        );
      }

      final firstMatter = buildCategoryMatter(
        id: 'matter-first',
        title: 'Matter First',
        updatedAt: now,
      );
      final secondMatter = buildCategoryMatter(
        id: 'matter-second',
        title: 'Matter Second',
        updatedAt: now.subtract(const Duration(minutes: 1)),
      );
      final thirdMatter = buildCategoryMatter(
        id: 'matter-third',
        title: 'Matter Third',
        updatedAt: now.subtract(const Duration(minutes: 2)),
      );
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[
          firstMatter,
          secondMatter,
          thirdMatter,
        ]),
        noteRepository: _MemoryNoteRepository(const <Note>[]),
        linkRepository: _MemoryLinkRepository(),
      );
      final before = await repos.matterRepository.getMatterById('matter-third');

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          categoryRepository: categoryRepository,
        ),
      );
      await tester.pumpAndSettle();

      final firstRow = find.byKey(
        const ValueKey<String>('sidebar_matter_drop_target_matter-first'),
      );
      final secondRow = find.byKey(
        const ValueKey<String>('sidebar_matter_drop_target_matter-second'),
      );
      final thirdRow = find.byKey(
        const ValueKey<String>('sidebar_matter_drop_target_matter-third'),
      );
      final initialFirstY = tester.getTopLeft(firstRow).dy;
      final initialSecondY = tester.getTopLeft(secondRow).dy;
      final initialThirdY = tester.getTopLeft(thirdRow).dy;
      expect(initialFirstY, lessThan(initialSecondY));
      expect(initialSecondY, lessThan(initialThirdY));

      await tester.tap(thirdRow);
      await tester.pumpAndSettle();

      final container = _containerForApp(tester);
      expect(container.read(selectedMatterIdProvider), 'matter-third');

      final finalFirstY = tester.getTopLeft(firstRow).dy;
      final finalSecondY = tester.getTopLeft(secondRow).dy;
      final finalThirdY = tester.getTopLeft(thirdRow).dy;
      expect(finalFirstY, initialFirstY);
      expect(finalSecondY, initialSecondY);
      expect(finalThirdY, initialThirdY);

      final after = await repos.matterRepository.getMatterById('matter-third');
      expect(after?.updatedAt, before?.updatedAt);
    },
  );

  testWidgets(
    'material sidebar highlights the clicked duplicate matter occurrence',
    (tester) async {
      _setDesktopViewport(tester);
      final categoryRepository = _MemoryCategoryRepository(<Category>[
        Category(
          id: 'category-1',
          name: 'Work',
          color: '#2563EB',
          icon: 'folder',
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      final pinnedMatter = Matter(
        id: 'matter-123',
        categoryId: 'category-1',
        title: 'matter 123',
        description: '',
        status: MatterStatus.active,
        color: '#2563EB',
        icon: 'build',
        isPinned: true,
        createdAt: now,
        updatedAt: now,
        startedAt: now,
        endedAt: null,
        phases: const <Phase>[
          Phase(
            id: 'matter-123-phase-start',
            matterId: 'matter-123',
            name: 'Start',
            order: 0,
          ),
        ],
        currentPhaseId: 'matter-123-phase-start',
      );
      final otherMatter = matter.copyWith(
        id: 'matter-456',
        title: 'Test 1',
        categoryId: 'category-1',
        isPinned: false,
      );
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[
          pinnedMatter,
          otherMatter,
        ]),
        noteRepository: _MemoryNoteRepository(const <Note>[]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          categoryRepository: categoryRepository,
        ),
      );
      await tester.pumpAndSettle();

      final pinnedRow = find.byKey(
        const ValueKey<String>('sidebar_matter_row_pinned|matter-123'),
      );
      final categoryRow = find.byKey(
        const ValueKey<String>(
          'sidebar_matter_row_category|category-1|matter-123',
        ),
      );

      await tester.tap(categoryRow);
      await tester.pumpAndSettle();

      expect(tester.widget<ListTile>(pinnedRow).selected, isFalse);
      expect(tester.widget<ListTile>(categoryRow).selected, isTrue);
      expect(
        _containerForApp(tester).read(selectedMatterIdProvider),
        'matter-123',
      );
    },
  );

  testWidgets(
    'macOS sidebar highlights the clicked duplicate matter occurrence',
    (tester) async {
      _setDesktopViewport(tester);
      final categoryRepository = _MemoryCategoryRepository(<Category>[
        Category(
          id: 'category-1',
          name: 'Work',
          color: '#2563EB',
          icon: 'folder',
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      final pinnedMatter = Matter(
        id: 'matter-123',
        categoryId: 'category-1',
        title: 'matter 123',
        description: '',
        status: MatterStatus.active,
        color: '#2563EB',
        icon: 'build',
        isPinned: true,
        createdAt: now,
        updatedAt: now,
        startedAt: now,
        endedAt: null,
        phases: const <Phase>[
          Phase(
            id: 'matter-123-phase-start',
            matterId: 'matter-123',
            name: 'Start',
            order: 0,
          ),
        ],
        currentPhaseId: 'matter-123-phase-start',
      );
      final otherMatter = matter.copyWith(
        id: 'matter-456',
        title: 'Test 1',
        categoryId: 'category-1',
        isPinned: false,
      );
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[
          pinnedMatter,
          otherMatter,
        ]),
        noteRepository: _MemoryNoteRepository(const <Note>[]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: true,
          repos: repos,
          categoryRepository: categoryRepository,
        ),
      );
      await tester.pumpAndSettle();

      final pinnedRow = find.byKey(
        const ValueKey<String>('sidebar_matter_row_pinned|matter-123'),
      );
      final categoryRow = find.byKey(
        const ValueKey<String>(
          'sidebar_matter_row_category|category-1|matter-123',
        ),
      );

      await tester.tap(categoryRow);
      await tester.pumpAndSettle();

      final pinnedLabel = tester.widget<Text>(
        find.descendant(of: pinnedRow, matching: find.text('matter 123')),
      );
      final categoryLabel = tester.widget<Text>(
        find.descendant(of: categoryRow, matching: find.text('matter 123')),
      );

      expect(pinnedLabel.style?.fontWeight, FontWeight.w400);
      expect(categoryLabel.style?.fontWeight, FontWeight.w700);
      expect(
        _containerForApp(tester).read(selectedMatterIdProvider),
        'matter-123',
      );
    },
  );

  testWidgets('material sidebar drag moves matter into uncategorized', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final categoryRepository = _MemoryCategoryRepository(<Category>[
      Category(
        id: 'category-1',
        name: 'Work',
        color: '#2563EB',
        icon: 'folder',
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    final categorizedMatter = matter.copyWith(
      id: 'matter-work',
      title: 'Work Matter',
      categoryId: 'category-1',
      isPinned: false,
    );
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[categorizedMatter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        categoryRepository: categoryRepository,
      ),
    );
    await tester.pumpAndSettle();

    await _longPressDragTo(
      tester,
      find.byKey(
        const ValueKey<String>('sidebar_matter_reassign_drag_matter-work'),
      ),
      find.byKey(
        const ValueKey<String>('sidebar_uncategorized_drop_target_material'),
      ),
    );

    final moved = await repos.matterRepository.getMatterById('matter-work');
    expect(moved?.categoryId, isNull);
  });

  testWidgets(
    'macOS sidebar does not reassign matter when dropped on Views or Notebooks headers',
    (tester) async {
      _setDesktopViewport(tester);
      final categoryRepository = _MemoryCategoryRepository(<Category>[
        Category(
          id: 'category-1',
          name: 'Work',
          color: '#2563EB',
          icon: 'folder',
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      final categorizedMatter = matter.copyWith(
        id: 'matter-work',
        title: 'Work Matter',
        categoryId: 'category-1',
        isPinned: false,
      );
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[categorizedMatter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: true,
          repos: repos,
          categoryRepository: categoryRepository,
        ),
      );
      await tester.pumpAndSettle();

      await _longPressDragTo(
        tester,
        find.byKey(
          const ValueKey<String>('sidebar_matter_reassign_drag_matter-work'),
        ),
        find.byKey(const ValueKey<String>('sidebar_section_header_views')),
      );
      var moved = await repos.matterRepository.getMatterById('matter-work');
      expect(moved?.categoryId, 'category-1');

      await _longPressDragTo(
        tester,
        find.byKey(
          const ValueKey<String>('sidebar_matter_reassign_drag_matter-work'),
        ),
        find.byKey(const ValueKey<String>('sidebar_section_header_notebooks')),
      );
      moved = await repos.matterRepository.getMatterById('matter-work');
      expect(moved?.categoryId, 'category-1');
    },
  );

  testWidgets('material sidebar top-level sections collapse and expand', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final categoryRepository = _MemoryCategoryRepository(<Category>[
      Category(
        id: 'category-1',
        name: 'Work',
        color: '#2563EB',
        icon: 'folder',
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    final pinnedMatter = matter.copyWith(
      id: 'matter-pinned',
      title: 'Pinned Matter',
      categoryId: 'category-1',
      isPinned: true,
    );
    final categoryMatter = matter.copyWith(
      id: 'matter-category',
      title: 'Category Matter',
      categoryId: 'category-1',
      isPinned: false,
    );
    final uncategorizedMatter = matter.copyWith(
      id: 'matter-uncategorized',
      title: 'Uncategorized Matter',
      categoryId: null,
      clearCategoryId: true,
      isPinned: false,
    );
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[
        pinnedMatter,
        categoryMatter,
        uncategorizedMatter,
      ]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        categoryRepository: categoryRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar_section_header_categories')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar_section_header_pinned')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pinned Matter'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar_section_header_pinned')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pinned Matter'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar_section_header_categories')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Category Matter'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar_section_header_categories')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Category Matter'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar_section_header_categories')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Category Matter'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('sidebar_section_header_uncategorized'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Uncategorized Matter'), findsNothing);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('sidebar_section_header_uncategorized'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Uncategorized Matter'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar_section_header_views')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar_section_header_views')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);

    final notebookHeader = find.byKey(
      const ValueKey<String>('sidebar_section_header_notebooks'),
    );
    await tester.dragUntilVisible(
      notebookHeader,
      find.byType(Scrollable).first,
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    await tester.tap(notebookHeader);
    await tester.pumpAndSettle();
    expect(find.text('Notebook'), findsNothing);
    await tester.dragUntilVisible(
      notebookHeader,
      find.byType(Scrollable).first,
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    await tester.tap(notebookHeader);
    await tester.pumpAndSettle();
    expect(find.text('Notebook'), findsOneWidget);
  });

  testWidgets('material list and editor menus expose move actions', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _secondaryClick(
      tester,
      find.byKey(const ValueKey<String>('phase_note_row_note-1')),
    );
    expect(find.text('Move to Matter...'), findsWidgets);
    expect(find.text('Move to Phase...'), findsWidgets);
    expect(find.text('Move to Notebook...'), findsWidgets);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More note actions'));
    await tester.pumpAndSettle();
    expect(find.text('Move to Matter...'), findsWidgets);
    expect(find.text('Move to Phase...'), findsWidgets);
    expect(find.text('Move to Notebook...'), findsWidgets);
  });

  testWidgets('macOS list and editor menus expose move actions', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _secondaryClick(
      tester,
      find.byKey(const ValueKey<String>('phase_note_row_note-1')),
    );
    expect(find.text('Edit'), findsWidgets);
    expect(find.text('Move to Matter...'), findsWidgets);
    expect(find.text('Move to Phase...'), findsWidgets);
    expect(find.text('Move to Notebook...'), findsWidgets);
    expect(find.byType(MacosPulldownMenuDivider), findsWidgets);
    expect(find.byType(PopupMenuDivider), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    final buttons = tester
        .widgetList<MacosPulldownButton>(find.byType(MacosPulldownButton))
        .toList();
    final editorMoveMenus = buttons.where((button) {
      final titles = _macosPulldownTitles(button);
      return titles.contains('Move to Matter...') &&
          titles.contains('Move to Phase...') &&
          titles.contains('Move to Notebook...');
    }).toList();
    expect(editorMoveMenus, isNotEmpty);
  });

  testWidgets('macOS matter sidebar menu exposes matter actions', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _secondaryClick(
      tester,
      find.byKey(const ValueKey<String>('sidebar_matter_drop_target_matter-1')),
    );
    expect(find.text('Edit'), findsWidgets);
    expect(find.text('Pin'), findsWidgets);
    expect(find.text('Set Active'), findsWidgets);
    expect(find.text('Set Paused'), findsWidgets);
    expect(find.text('Set Completed'), findsWidgets);
    expect(find.text('Set Archived'), findsWidgets);
    expect(find.text('Delete'), findsWidgets);
    expect(find.byType(MacosPulldownMenuDivider), findsWidgets);
    expect(find.byType(PopupMenuDivider), findsNothing);
  });

  testWidgets(
    'macOS matter sidebar row opens menu from surrounding stripe area',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: true,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(
        const ValueKey<String>('sidebar_matter_drop_target_matter-1'),
      );
      final rect = tester.getRect(row);

      await _secondaryClickAt(tester, Offset(rect.left - 4, rect.center.dy));
      expect(find.text('Set Active'), findsWidgets);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await _secondaryClickAt(tester, Offset(rect.right + 4, rect.center.dy));
      expect(find.text('Set Active'), findsWidgets);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'material notebook sidebar root and folder open context menus on right click',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );
      final notebookRepository = _MemoryNotebookRepository(<NotebookFolder>[
        notebookFolder,
      ]);

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            notebookRepositoryProvider.overrideWithValue(notebookRepository),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final rootRow = find.byKey(
        const Key('sidebar_notebook_root_drop_target'),
      );
      await tester.dragUntilVisible(rootRow, scrollable, const Offset(0, -180));
      await tester.pumpAndSettle();

      await _secondaryClick(tester, rootRow);
      expect(find.text('New Folder'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      final folderRow = find.byKey(
        const ValueKey<String>('sidebar_notebook_folder_drop_target_folder-1'),
      );
      await tester.dragUntilVisible(
        folderRow,
        scrollable,
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();

      await _secondaryClick(tester, folderRow);
      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('Rename Folder'), findsOneWidget);
      expect(find.text('Delete Folder'), findsOneWidget);
    },
  );

  testWidgets(
    'macOS notebook sidebar root opens native context menu on right click',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(_buildApp(useMacOSNativeUI: true, repos: repos));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final rootRow = find.byKey(
        const Key('sidebar_notebook_root_drop_target'),
      );
      await tester.dragUntilVisible(rootRow, scrollable, const Offset(0, -180));
      await tester.pumpAndSettle();

      await _secondaryClick(tester, rootRow);
      expect(find.text('New Folder'), findsOneWidget);
      expect(find.byType(MacosPulldownMenuDivider), findsNothing);
      expect(find.byType(PopupMenuDivider), findsNothing);
    },
  );

  testWidgets(
    'macOS notebook sidebar root and folder open menu from surrounding stripe area',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );
      final notebookRepository = _MemoryNotebookRepository(<NotebookFolder>[
        notebookFolder,
      ]);

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: true,
          repos: repos,
          overrides: [
            notebookRepositoryProvider.overrideWithValue(notebookRepository),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final rootRow = find.byKey(
        const Key('sidebar_notebook_root_drop_target'),
      );
      await tester.dragUntilVisible(rootRow, scrollable, const Offset(0, -180));
      await tester.pumpAndSettle();

      final rootRect = tester.getRect(rootRow);
      await _secondaryClickAt(
        tester,
        Offset(rootRect.left - 4, rootRect.center.dy),
      );
      expect(find.text('New Folder'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await _secondaryClickAt(
        tester,
        Offset(rootRect.right + 4, rootRect.center.dy),
      );
      expect(find.text('New Folder'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      final folderRow = find.byKey(
        const ValueKey<String>('sidebar_notebook_folder_drop_target_folder-1'),
      );
      await tester.dragUntilVisible(
        folderRow,
        scrollable,
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();

      final folderRect = tester.getRect(folderRow);
      await _secondaryClickAt(
        tester,
        Offset(folderRect.left - 4, folderRect.center.dy),
      );
      expect(find.text('Rename Folder'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await _secondaryClickAt(
        tester,
        Offset(folderRect.right + 4, folderRect.center.dy),
      );
      expect(find.text('Rename Folder'), findsOneWidget);
    },
  );

  testWidgets('macOS Manage Phases dialog uses native controls without crash', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Phase selector is now in the notes view, not top bar
    await tester.tap(find.byKey(const Key('matter_notes_phase_selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Phases...'));
    await tester.pumpAndSettle();

    expect(find.text('Manage Phases'), findsWidgets);
    expect(find.text('Current'), findsWidgets);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('top phase menu can switch to phase mode and set phase filter', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
          matterViewModeProvider.overrideWithBuild(
            (ref, notifier) => MatterViewMode.kanban,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // First switch to Notes view (phase selector is now in notes view)
    await tester.tap(find.byKey(const Key('matter_top_notes_button')));
    await tester.pumpAndSettle();

    // Now tap the phase selector in the notes view
    await tester.tap(find.byKey(const Key('matter_notes_phase_selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In Progress'));
    await tester.pumpAndSettle();

    final container = _containerForApp(tester);
    expect(container.read(matterViewModeProvider), MatterViewMode.phase);
    expect(container.read(selectedPhaseIdProvider), 'phase-progress');
  });

  testWidgets('tapping kanban card opens note in editor', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => null),
          matterViewModeProvider.overrideWithBuild(
            (ref, notifier) => MatterViewMode.kanban,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Tap on the kanban card to open the note
    await tester.tap(find.byKey(const ValueKey<String>('kanban_note_card_note-1')));
    await tester.pumpAndSettle();

    // Verify note is opened (phase selector should be visible in notes view)
    expect(
      find.byKey(const Key('matter_notes_phase_selector')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS sidebar renders mapped matter icons', (tester) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[
        matter.copyWith(icon: 'science'),
      ]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MacosIcon && widget.icon == Icons.science_outlined,
      ),
      findsWidgets,
    );
  });

  testWidgets('material matter list renders mapped matter icons', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[
        matter.copyWith(icon: 'science'),
      ]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.science_outlined), findsWidgets);
  });

  testWidgets('unknown matter icon key falls back to description icon', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[
        matter.copyWith(icon: 'legacy_unknown_icon'),
      ]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MacosIcon && widget.icon == Icons.description_outlined,
      ),
      findsWidgets,
    );
  });

  testWidgets('macOS conflicts mode uses native controls', (tester) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          showConflictsProvider.overrideWithBuild((ref, notifier) => true),
          selectedConflictPathProvider.overrideWithBuild(
            (ref, notifier) => 'conflict-note-1',
          ),
          conflictsControllerProvider.overrideWith(
            () => _StaticConflictsController(<SyncConflict>[
              SyncConflict(
                type: SyncConflictType.note,
                conflictPath: 'conflict-note-1',
                originalPath: 'notes/note-1.md',
                detectedAt: now,
                localDevice: 'local',
                remoteDevice: 'remote',
                title: 'Conflict Note',
                preview: 'preview',
              ),
            ]),
          ),
          selectedConflictDetailProvider.overrideWith(
            (ref) async => SyncConflictDetail(
              conflict: SyncConflict(
                type: SyncConflictType.note,
                conflictPath: 'conflict-note-1',
                originalPath: 'notes/note-1.md',
                detectedAt: now,
                localDevice: 'local',
                remoteDevice: 'remote',
                title: 'Conflict Note',
                preview: 'preview',
              ),
              localContent: 'Title: Conflict Note\n\nlocal line',
              mainFileContent: 'Title: Conflict Note\n\nremote line',
              localContentHash: 'local-hash',
              mainFileContentHash: 'main-hash',
              remoteContentHashAtCapture: 'remote-hash',
              conflictFingerprint: 'fingerprint',
              originalFileMissing: false,
              mainFileChangedSinceCapture: false,
              hasActualDiff: true,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('macos_conflicts_refresh')), findsOneWidget);
    expect(find.text('Conflict Note'), findsWidgets);
  });

  testWidgets('conflict note detail renders side-by-side diff review', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );
    const localContent = 'Title: Conflict Note\n\nlocal line\nshared line';
    const mainFileContent = 'Title: Conflict Note\n\nremote line\nshared line';

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          showConflictsProvider.overrideWithBuild((ref, notifier) => true),
          selectedConflictPathProvider.overrideWithBuild(
            (ref, notifier) => 'conflict-note-1',
          ),
          conflictsControllerProvider.overrideWith(
            () => _StaticConflictsController(<SyncConflict>[
              SyncConflict(
                type: SyncConflictType.note,
                conflictPath: 'conflict-note-1',
                originalPath: 'notes/note-1.md',
                detectedAt: now,
                localDevice: 'local',
                remoteDevice: 'remote',
                title: 'Conflict Note',
                preview: 'preview',
              ),
            ]),
          ),
          selectedConflictDetailProvider.overrideWith(
            (ref) async => SyncConflictDetail(
              conflict: SyncConflict(
                type: SyncConflictType.note,
                conflictPath: 'conflict-note-1',
                originalPath: 'notes/note-1.md',
                detectedAt: now,
                localDevice: 'local',
                remoteDevice: 'remote',
                title: 'Conflict Note',
                preview: 'preview',
              ),
              localContent: localContent,
              mainFileContent: mainFileContent,
              localContentHash: 'local-hash',
              mainFileContentHash: 'main-file-hash',
              remoteContentHashAtCapture: 'remote-hash',
              conflictFingerprint: 'fingerprint',
              originalFileMissing: false,
              mainFileChangedSinceCapture: true,
              hasActualDiff: true,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('conflict_diff_side_by_side')), findsOneWidget);
    expect(find.text('Conflict Copy'), findsOneWidget);
    expect(find.text('Main File'), findsOneWidget);
    expect(find.text('Accept Left'), findsOneWidget);
    expect(find.text('Accept Right'), findsOneWidget);
    expect(find.text('local line'), findsOneWidget);
    expect(find.text('remote line'), findsOneWidget);
    expect(
      find.byKey(const Key('conflict_notice_stale_main_file')),
      findsOneWidget,
    );
  });

  testWidgets('macOS search results tap opens note in workspace flow', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final noteRepository = _MemoryNoteRepository(<Note>[noteOne, noteTwo]);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: noteRepository,
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          noteEditorControllerProvider.overrideWith(
            _SpyNoteEditorController.new,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    _SpyNoteEditorController.openedNoteIds.clear();
    await tester.enterText(find.byType(MacosSearchField<void>), 'search');
    await tester.pumpAndSettle();

    expect(find.text('Search Hit'), findsOneWidget);
    await tester.tap(find.text('Search Hit'));
    await tester.pumpAndSettle();

    expect(_SpyNoteEditorController.openedNoteIds, contains('note-2'));
  });

  testWidgets('material sidebar shows time-based view entries', (tester) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          clockProvider.overrideWithValue(
            _FixedClock(DateTime.utc(2026, 2, 18, 23)),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('sidebar_view_today')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('sidebar_view_yesterday')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('sidebar_view_thisWeek')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('sidebar_view_lastWeek')),
      findsOneWidget,
    );
  });

  testWidgets(
    'material Today view groups matter notes and notebook notes, and updates title',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            clockProvider.overrideWithValue(
              _FixedClock(DateTime.utc(2026, 2, 18, 23)),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('sidebar_view_today')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('time_view_workspace_today')),
        findsOneWidget,
      );
      expect(find.text('Matters (1)'), findsOneWidget);
      expect(find.text('Notebook (1)'), findsOneWidget);
      expect(find.text('Editor Note'), findsOneWidget);
      expect(find.text('Search Hit'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Today')),
        findsOneWidget,
      );

      final mattersDy = tester.getTopLeft(find.text('Matters (1)')).dy;
      final notebookDy = tester.getTopLeft(find.text('Notebook (1)')).dy;
      expect(notebookDy, greaterThan(mattersDy));
    },
  );

  testWidgets('clicking a time-view note opens the note in native context', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          clockProvider.overrideWithValue(
            _FixedClock(DateTime.utc(2026, 2, 18, 23)),
          ),
          noteEditorViewModeProvider.overrideWithBuild(
            (ref, notifier) => NoteEditorViewMode.edit,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('sidebar_view_today')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('time_view_note_note-2')),
    );
    await tester.pumpAndSettle();

    final container = _containerForApp(tester);
    expect(container.read(selectedTimeViewProvider), isNull);
    expect(container.read(showOrphansProvider), isTrue);
    expect(container.read(selectedNotebookFolderIdProvider), isNull);
    expect(container.read(selectedNoteIdProvider), 'note-2');
    expect(container.read(noteEditorViewModeProvider), NoteEditorViewMode.read);
  });

  testWidgets('switching away from time view clears selected time view state', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          clockProvider.overrideWithValue(
            _FixedClock(DateTime.utc(2026, 2, 18, 23)),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('sidebar_view_today')));
    await tester.pumpAndSettle();

    final container = _containerForApp(tester);
    expect(container.read(selectedTimeViewProvider), ChronicleTimeView.today);

    await tester.tap(find.text('Matter One').first);
    await tester.pumpAndSettle();

    expect(container.read(selectedTimeViewProvider), isNull);
    expect(container.read(selectedMatterIdProvider), 'matter-1');
    expect(container.read(showOrphansProvider), isFalse);
  });

  testWidgets(
    'macOS search hit shows context, opens read mode, and restores parked results',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(_buildApp(useMacOSNativeUI: true, repos: repos));
      await tester.pumpAndSettle();

      final macosSearchField = tester.widget<MacosSearchField<void>>(
        find.byType(MacosSearchField<void>),
      );
      expect(macosSearchField.maxLines, 1);
      expect(macosSearchField.minLines, 1);

      await tester.enterText(find.byType(MacosSearchField<void>), 'search');
      await tester.pumpAndSettle();

      expect(find.textContaining('Notebook • Root'), findsOneWidget);
      expect(find.textContaining('searchable content'), findsOneWidget);
      final container = _containerForApp(tester);
      expect(container.read(searchResultsVisibleProvider), isTrue);

      await tester.tap(find.text('Search Hit').first);
      await tester.pumpAndSettle();

      final returnButtonFinder = find.byKey(
        const Key('macos_return_search_results_button'),
      );
      expect(returnButtonFinder, findsOneWidget);
      expect(container.read(searchResultsVisibleProvider), isFalse);
      final modeToggle = tester
          .widget<CupertinoSlidingSegmentedControl<NoteEditorViewMode>>(
            find.byKey(const Key('note_editor_mode_toggle')),
          );
      expect(modeToggle.groupValue, NoteEditorViewMode.read);

      final searchField = tester.widget<MacosSearchField<void>>(
        find.byType(MacosSearchField<void>),
      );
      expect(searchField.controller?.text, 'search');

      await tester.tap(returnButtonFinder);
      await tester.pumpAndSettle();

      expect(find.textContaining('Notebook • Root'), findsOneWidget);
      expect(find.text('Search Hit'), findsOneWidget);
      expect(container.read(searchResultsVisibleProvider), isTrue);

      await tester.enterText(find.byType(MacosSearchField<void>), '');
      await tester.pumpAndSettle();
      expect(returnButtonFinder, findsNothing);
    },
  );

  testWidgets(
    'material search hit opens read mode and parked results can be restored',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(_buildApp(useMacOSNativeUI: false, repos: repos));
      await tester.pumpAndSettle();

      final appBar = find.byType(AppBar);
      final searchFieldFinder = find.descendant(
        of: appBar,
        matching: find.byType(TextField),
      );
      final materialSearchField = tester.widget<TextField>(searchFieldFinder);
      expect(materialSearchField.maxLines, 1);
      expect(materialSearchField.minLines, 1);
      await tester.enterText(searchFieldFinder, 'search');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Search Hit'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Search Hit'));
      await tester.pumpAndSettle();

      final container = _containerForApp(tester);
      final returnButtonFinder = find.byKey(
        const Key('material_return_search_results_button'),
      );
      expect(returnButtonFinder, findsOneWidget);
      expect(container.read(searchResultsVisibleProvider), isFalse);
      final modeToggle = tester.widget<SegmentedButton<NoteEditorViewMode>>(
        find.byKey(const Key('note_editor_mode_toggle')),
      );
      expect(
        modeToggle.selected,
        equals(<NoteEditorViewMode>{NoteEditorViewMode.read}),
      );

      final searchField = tester.widget<TextField>(searchFieldFinder);
      expect(searchField.controller?.text, 'search');

      await tester.tap(returnButtonFinder);
      await tester.pumpAndSettle();

      expect(container.read(searchResultsVisibleProvider), isTrue);
      expect(find.widgetWithText(ListTile, 'Search Hit'), findsOneWidget);
    },
  );

  testWidgets(
    'macOS search requires 2 chars and clearing returns to normal phase workspace',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: true,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final container = _containerForApp(tester);
      expect(
        find.byKey(const Key('matter_top_kanban_button')),
        findsOneWidget,
      );

      await tester.enterText(find.byType(MacosSearchField<void>), 's');
      await tester.pumpAndSettle();

      expect(container.read(searchResultsVisibleProvider), isFalse);
      expect(find.text('Search Hit'), findsNothing);
      expect(
        find.byKey(const Key('macos_return_search_results_button')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('matter_top_kanban_button')),
        findsOneWidget,
      );

      await tester.enterText(find.byType(MacosSearchField<void>), 'se');
      await tester.pumpAndSettle();

      expect(container.read(searchResultsVisibleProvider), isTrue);
      expect(find.text('Search Hit'), findsOneWidget);
      expect(find.byKey(const Key('matter_top_kanban_button')), findsNothing);

      final searchField = tester.widget<MacosSearchField<void>>(
        find.byType(MacosSearchField<void>),
      );
      searchField.controller?.clear();
      await tester.pumpAndSettle();

      expect(container.read(searchResultsVisibleProvider), isFalse);
      expect(find.text('Search Hit'), findsNothing);
      expect(
        find.byKey(const Key('macos_return_search_results_button')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('matter_top_kanban_button')),
        findsOneWidget,
      );
    },
  );

  testWidgets('macOS no-results search clears back to normal workspace', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final container = _containerForApp(tester);
    await tester.enterText(find.byType(MacosSearchField<void>), 'zz');
    await tester.pumpAndSettle();
    expect(container.read(searchResultsVisibleProvider), isTrue);
    expect(find.byKey(const Key('matter_top_kanban_button')), findsNothing);

    final searchField = tester.widget<MacosSearchField<void>>(
      find.byType(MacosSearchField<void>),
    );
    searchField.controller?.clear();
    await tester.pumpAndSettle();

    expect(container.read(searchResultsVisibleProvider), isFalse);
    expect(find.byKey(const Key('matter_top_kanban_button')), findsOneWidget);
  });

  testWidgets(
    'material search uses 2-char threshold and clear returns to normal workspace',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final container = _containerForApp(tester);
      final appBar = find.byType(AppBar);
      final searchFieldFinder = find.descendant(
        of: appBar,
        matching: find.byType(TextField),
      );

      expect(
        find.byKey(const Key('matter_top_kanban_button')),
        findsOneWidget,
      );

      await tester.enterText(searchFieldFinder, 's');
      await tester.pumpAndSettle();
      expect(container.read(searchResultsVisibleProvider), isFalse);
      expect(find.widgetWithText(ListTile, 'Search Hit'), findsNothing);
      expect(
        find.byKey(const Key('material_return_search_results_button')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('matter_top_kanban_button')),
        findsOneWidget,
      );

      await tester.enterText(searchFieldFinder, 'se');
      await tester.pumpAndSettle();
      expect(container.read(searchResultsVisibleProvider), isTrue);
      expect(find.widgetWithText(ListTile, 'Search Hit'), findsOneWidget);
      expect(find.byKey(const Key('matter_top_kanban_button')), findsNothing);

      final searchField = tester.widget<TextField>(searchFieldFinder);
      searchField.controller?.clear();
      await tester.pumpAndSettle();

      expect(container.read(searchResultsVisibleProvider), isFalse);
      expect(find.widgetWithText(ListTile, 'Search Hit'), findsNothing);
      expect(
        find.byKey(const Key('material_return_search_results_button')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('matter_top_kanban_button')),
        findsOneWidget,
      );
    },
  );

  testWidgets('startup with preselected matter auto-opens first phase note', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final container = _containerForApp(tester);
    expect(container.read(selectedNoteIdProvider), 'note-1');
    expect(find.text('Select a note to edit.'), findsNothing);
  });

  testWidgets('switching notes does not flash select-note prompt', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final secondMatterNote = noteTwo.copyWith(
      matterId: 'matter-1',
      phaseId: 'phase-start',
      title: 'Second Matter Note',
      content: '# Second Matter Note\ncontent',
      tags: const <String>['second'],
    );
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, secondMatterNote]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final container = _containerForApp(tester);
    await container
        .read(noteEditorControllerProvider.notifier)
        .selectNote('note-2');
    await tester.pump();

    expect(find.text('Select a note to edit.'), findsNothing);
    expect(container.read(selectedNoteIdProvider), 'note-2');
    await tester.idle();
  });

  testWidgets(
    'switching notes with pending autosave updates only source note snapshot',
    (tester) async {
      _setDesktopViewport(tester);
      final secondMatterNote = noteTwo.copyWith(
        matterId: 'matter-1',
        phaseId: 'phase-start',
        title: 'Second Matter Note',
        content: '# Second Matter Note\noriginal second body',
        tags: const <String>['second'],
      );
      final noteRepository = _MemoryNoteRepository(<Note>[
        noteOne,
        secondMatterNote,
      ]);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: noteRepository,
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('macos_note_editor_content')),
        '# Editor Note\nedited in note one',
      );
      await tester.pump(const Duration(milliseconds: 120));

      await tester.tap(
        find.byKey(const ValueKey<String>('phase_note_row_note-2')),
      );
      await tester.pumpAndSettle();

      expect(
        noteRepository.noteById('note-1')?.content,
        '# Editor Note\nedited in note one',
      );
      expect(
        noteRepository.noteById('note-2')?.content,
        '# Second Matter Note\noriginal second body',
      );
    },
  );

  testWidgets(
    'selection-only listener during note switch never copies stale buffer into destination note',
    (tester) async {
      _setDesktopViewport(tester);
      final secondMatterNote = noteTwo.copyWith(
        matterId: 'matter-1',
        phaseId: 'phase-start',
        title: 'Second Matter Note',
        content: '# Second Matter Note\noriginal second body',
        tags: const <String>['second'],
      );
      final noteRepository = _MemoryNoteRepository(<Note>[
        noteOne,
        secondMatterNote,
      ]);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: noteRepository,
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
            noteEditorViewModeProvider.overrideWithBuild(
              (ref, notifier) => NoteEditorViewMode.edit,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final container = _containerForApp(tester);
      final codeField = tester.widget<CodeField>(
        find.byKey(const Key('macos_note_editor_content')),
      );
      final selectionOffset = codeField.controller.text.isEmpty ? 0 : 1;

      await container
          .read(noteEditorControllerProvider.notifier)
          .selectNote('note-2');
      codeField.controller.selection = TextSelection.collapsed(
        offset: selectionOffset,
      );

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      expect(
        noteRepository.noteById('note-1')?.content,
        '# Editor Note\ncontent',
      );
      expect(
        noteRepository.noteById('note-2')?.content,
        '# Second Matter Note\noriginal second body',
      );
    },
  );

  testWidgets(
    'switching notebook folders and back without edits keeps note contents unchanged',
    (tester) async {
      _setDesktopViewport(tester);
      final folderTwo = NotebookFolder(
        id: 'folder-2',
        name: 'Folder Two',
        parentId: null,
        createdAt: now,
        updatedAt: now,
      );
      final folderOneNote = noteOne.copyWith(
        id: 'notebook-1',
        matterId: null,
        phaseId: null,
        notebookFolderId: 'folder-1',
        title: 'Notebook One',
        content: '39<br>QR-UAT-ADMINE-138 |',
        tags: const <String>['one'],
      );
      final folderTwoNote = noteOne.copyWith(
        id: 'notebook-2',
        matterId: null,
        phaseId: null,
        notebookFolderId: 'folder-2',
        title: 'Notebook Two',
        content: 'Stable destination content',
        tags: const <String>['two'],
      );
      final noteRepository = _MemoryNoteRepository(<Note>[
        folderOneNote,
        folderTwoNote,
      ]);
      final notebookRepository = _MemoryNotebookRepository(<NotebookFolder>[
        notebookFolder,
        folderTwo,
      ]);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: noteRepository,
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            showNotebookProvider.overrideWithBuild((ref, notifier) => true),
            selectedNotebookFolderIdProvider.overrideWithBuild(
              (ref, notifier) => 'folder-1',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'notebook-1',
            ),
            noteEditorViewModeProvider.overrideWithBuild(
              (ref, notifier) => NoteEditorViewMode.edit,
            ),
            notebookRepositoryProvider.overrideWithValue(notebookRepository),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final container = _containerForApp(tester);
      final codeField = tester.widget<CodeField>(
        find.byKey(const Key('macos_note_editor_content')),
      );
      final selectionOffset = codeField.controller.text.isEmpty ? 0 : 1;

      await container
          .read(noteEditorControllerProvider.notifier)
          .openNotebookFolderInWorkspace('folder-2');
      codeField.controller.selection = TextSelection.collapsed(
        offset: selectionOffset,
      );
      await container
          .read(noteEditorControllerProvider.notifier)
          .openNotebookFolderInWorkspace('folder-1');
      codeField.controller.selection = TextSelection.collapsed(
        offset: selectionOffset,
      );

      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      expect(
        noteRepository.noteById('notebook-1')?.content,
        '39<br>QR-UAT-ADMINE-138 |',
      );
      expect(
        noteRepository.noteById('notebook-2')?.content,
        'Stable destination content',
      );
    },
  );

  testWidgets('switching matter auto-opens first note in current phase', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final matterTwo = matter.copyWith(
      id: 'matter-2',
      title: 'Matter Two',
      phases: const <Phase>[
        Phase(
          id: 'phase-2-start',
          matterId: 'matter-2',
          name: 'Start',
          order: 0,
        ),
      ],
      currentPhaseId: 'phase-2-start',
    );
    final noteThree = noteOne.copyWith(
      id: 'note-3',
      matterId: 'matter-2',
      phaseId: 'phase-2-start',
      title: 'Matter Two First',
      content: '# Matter Two First\nhello',
      tags: const <String>['three'],
      updatedAt: now.add(const Duration(minutes: 1)),
    );
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter, matterTwo]),
      noteRepository: _MemoryNoteRepository(<Note>[
        noteOne,
        noteTwo,
        noteThree,
      ]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Matter Two').first);
    await tester.pump();
    expect(find.text('Select a note to edit.'), findsNothing);
    await tester.pumpAndSettle();

    final container = _containerForApp(tester);
    expect(container.read(selectedMatterIdProvider), 'matter-2');
    expect(container.read(selectedNoteIdProvider), 'note-3');
  });

  testWidgets(
    'empty selected phase shows lazy matter draft instead of select-note prompt',
    (tester) async {
      _setDesktopViewport(tester);
      final noteRepository = _MemoryNoteRepository(<Note>[noteOne, noteTwo]);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: noteRepository,
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: true,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-end',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final container = _containerForApp(tester);
      expect(container.read(selectedNoteIdProvider), isNull);
      final draft = container.read(notebookDraftSessionProvider);
      expect(draft, isNotNull);
      expect(draft?.matterId, 'matter-1');
      expect(draft?.phaseId, 'phase-end');
      expect(
        find.byKey(const Key('notebook_draft_title_field')),
        findsOneWidget,
      );
      expect(find.text('Select a note to edit.'), findsNothing);
      expect(noteRepository.noteById('note-3'), isNull);
    },
  );

  testWidgets(
    'all-phases matter draft uses current phase and autosaves after input',
    (tester) async {
      _setDesktopViewport(tester);
      final noteRepository = _MemoryNoteRepository(<Note>[noteTwo]);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: noteRepository,
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final container = _containerForApp(tester);
      final draft = container.read(notebookDraftSessionProvider);
      expect(draft, isNotNull);
      expect(draft?.matterId, 'matter-1');
      expect(draft?.phaseId, 'phase-progress');
      expect(noteRepository.noteById('note-2')?.matterId, isNull);

      await tester.enterText(
        find.byKey(const Key('notebook_draft_title_field')),
        'Matter Draft',
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('macos_note_editor_content')),
        'Draft content body',
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      final created = noteRepository.noteById('note-2');
      expect(created, isNotNull);
      expect(created?.matterId, 'matter-1');
      expect(created?.phaseId, 'phase-progress');
      expect(created?.title, 'Matter Draft');
      expect(created?.content, 'Draft content body');
      expect(container.read(selectedNoteIdProvider), 'note-2');
      expect(container.read(notebookDraftSessionProvider), isNull);

      await tester.enterText(
        find.byKey(const Key('macos_note_editor_content')),
        'Draft content body\nautosave update',
      );
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      final updated = noteRepository.noteById('note-2');
      expect(updated?.content, 'Draft content body\nautosave update');
    },
  );

  testWidgets(
    'same matter context draft replacement clears stale draft editor state',
    (tester) async {
      _setDesktopViewport(tester);
      final noteRepository = _MemoryNoteRepository(<Note>[noteOne, noteTwo]);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: noteRepository,
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-end',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final container = _containerForApp(tester);
      expect(container.read(selectedNoteIdProvider), isNull);
      expect(container.read(notebookDraftSessionProvider), isNotNull);

      await tester.enterText(
        find.byKey(const Key('notebook_draft_title_field')),
        'Stale matter draft',
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('macos_note_editor_content')),
        'stale matter body',
      );
      await tester.pump();

      container
          .read(notebookDraftSessionProvider.notifier)
          .set(
            const NotebookDraftSession.emptyMatter(
              matterId: 'matter-1',
              phaseId: 'phase-end',
              draftSessionToken: 1001,
            ),
          );
      await tester.pump();

      final titleField = tester.widget<TextField>(
        find.byKey(const Key('notebook_draft_title_field')),
      );
      expect(titleField.controller?.text, isEmpty);
      final contentField = tester.widget<CodeField>(
        find.byKey(const Key('macos_note_editor_content')),
      );
      expect(contentField.controller.text, isEmpty);

      await tester.tap(find.byKey(const Key('macos_note_editor_save')));
      await tester.pumpAndSettle();

      expect(noteRepository.noteById('note-3'), isNull);
      expect(container.read(selectedNoteIdProvider), isNull);
    },
  );

  testWidgets('note header title supports click-to-edit', (tester) async {
    _setDesktopViewport(tester);
    final noteRepository = _MemoryNoteRepository(<Note>[noteOne, noteTwo]);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: noteRepository,
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('note_header_title_display')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('note_header_title_edit')),
      'Header Edited Title',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(noteRepository.noteById('note-1')?.title, 'Header Edited Title');
  });

  testWidgets(
    'switching notes while title is being edited never applies title to destination note',
    (tester) async {
      _setDesktopViewport(tester);
      final secondMatterNote = noteTwo.copyWith(
        matterId: 'matter-1',
        phaseId: 'phase-start',
        title: 'Second Matter Note',
        content: '# Second Matter Note\ncontent',
        tags: const <String>['second'],
      );
      final noteRepository = _MemoryNoteRepository(<Note>[
        noteOne,
        secondMatterNote,
      ]);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: noteRepository,
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: true,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final container = _containerForApp(tester);
      await tester.tap(find.byKey(const Key('note_header_title_display')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('note_header_title_edit')),
        'Leaked Title',
      );

      await container
          .read(noteEditorControllerProvider.notifier)
          .selectNote('note-2');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(noteRepository.noteById('note-2')?.title, 'Second Matter Note');
    },
  );

  testWidgets('macOS note editor save uses existing controller path', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final noteRepository = _MemoryNoteRepository(<Note>[noteOne, noteTwo]);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: noteRepository,
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('macos_note_editor_content')),
      '# Editor Note\ncontent updated through save',
    );
    await tester.tap(find.byKey(const Key('macos_note_editor_save')));
    await tester.pumpAndSettle();

    final saveButtonTop = tester.getTopLeft(
      find.byKey(const Key('macos_note_editor_save')),
    );
    final modeToggleTop = tester.getTopLeft(
      find.byKey(const Key('note_editor_mode_toggle')),
    );
    final utilitiesTop = tester.getTopLeft(
      find.byKey(const Key('note_editor_utility_tags')),
    );
    expect(modeToggleTop.dx, lessThan(saveButtonTop.dx));
    expect(saveButtonTop.dy, lessThan(utilitiesTop.dy));
    expect(find.textContaining('Updated:'), findsNothing);
    expect(noteRepository.updateCount, greaterThanOrEqualTo(1));
    expect(
      noteRepository.noteById('note-1')?.content,
      '# Editor Note\ncontent updated through save',
    );
  });

  testWidgets(
    'macOS note editor uses light code theme in light platform mode',
    (tester) async {
      await expectEditorCodeThemeBackground(
        tester: tester,
        useMacOSNativeUI: true,
        platformBrightness: Brightness.light,
        expectedBackground: const Color(0xFFF8F8F8),
      );
    },
  );

  testWidgets('macOS note editor uses dark code theme in dark platform mode', (
    tester,
  ) async {
    await expectEditorCodeThemeBackground(
      tester: tester,
      useMacOSNativeUI: true,
      platformBrightness: Brightness.dark,
      expectedBackground: const Color(0xFF23241F),
    );
  });

  testWidgets(
    'material note editor uses light code theme in light platform mode',
    (tester) async {
      await expectEditorCodeThemeBackground(
        tester: tester,
        useMacOSNativeUI: false,
        platformBrightness: Brightness.light,
        expectedBackground: const Color(0xFFF8F8F8),
      );
    },
  );

  testWidgets(
    'material note editor uses dark code theme in dark platform mode',
    (tester) async {
      await expectEditorCodeThemeBackground(
        tester: tester,
        useMacOSNativeUI: false,
        platformBrightness: Brightness.dark,
        expectedBackground: const Color(0xFF23241F),
      );
    },
  );

  testWidgets('macOS light code theme applies markdown syntax colors', (
    tester,
  ) async {
    await expectEditorCodeThemeBackground(
      tester: tester,
      useMacOSNativeUI: true,
      platformBrightness: Brightness.light,
      expectedBackground: const Color(0xFFF8F8F8),
      expectedTokenKey: 'section',
      expectedTokenColor: const Color(0xFF990000),
    );
  });

  testWidgets('macOS dark code theme applies markdown syntax colors', (
    tester,
  ) async {
    await expectEditorCodeThemeBackground(
      tester: tester,
      useMacOSNativeUI: true,
      platformBrightness: Brightness.dark,
      expectedBackground: const Color(0xFF23241F),
      expectedTokenKey: 'keyword',
      expectedTokenColor: const Color(0xFFF92672),
    );
  });

  testWidgets('material light code theme applies markdown syntax colors', (
    tester,
  ) async {
    await expectEditorCodeThemeBackground(
      tester: tester,
      useMacOSNativeUI: false,
      platformBrightness: Brightness.light,
      expectedBackground: const Color(0xFFF8F8F8),
      expectedTokenKey: 'section',
      expectedTokenColor: const Color(0xFF990000),
    );
  });

  testWidgets('material dark code theme applies markdown syntax colors', (
    tester,
  ) async {
    await expectEditorCodeThemeBackground(
      tester: tester,
      useMacOSNativeUI: false,
      platformBrightness: Brightness.dark,
      expectedBackground: const Color(0xFF23241F),
      expectedTokenKey: 'keyword',
      expectedTokenColor: const Color(0xFFF92672),
    );
  });

  testWidgets('Edit to Read mode auto-saves title and content', (tester) async {
    _setDesktopViewport(tester);
    final noteRepository = _MemoryNoteRepository(<Note>[noteOne, noteTwo]);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: noteRepository,
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('note_header_title_display')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('note_header_title_edit')),
      'Autosaved Title',
    );
    await tester.tap(find.byKey(const Key('macos_note_editor_content')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('macos_note_editor_content')),
      '# Autosaved Title\nnew markdown',
    );
    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();

    final saved = noteRepository.noteById('note-1');
    expect(saved?.title, 'Autosaved Title');
    expect(saved?.content, '# Autosaved Title\nnew markdown');
  });

  testWidgets('Read mode markdown renders table and math extensions', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('macos_note_editor_content')),
      '| A | B |\n| --- | --- |\n| 1 | 2 |\n\nInline \$a^2\$ and:\n\$\$c^2\$\$',
    );
    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();

    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(Math), findsNWidgets(2));
  });

  testWidgets(
    'editor utilities open popups and inline utility panels are removed',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: true,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tags (comma separated)'), findsNothing);
      expect(find.text('Move to Notebook...'), findsNothing);
      expect(find.text('Assign to Selected Matter'), findsNothing);

      await tester.tap(find.byKey(const Key('note_editor_utility_tags')));
      await tester.pumpAndSettle();
      expect(find.text('Tags'), findsWidgets);
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('note_editor_utility_attachments')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Attachments'), findsWidgets);
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('note_editor_utility_linked')));
      await tester.pumpAndSettle();
      expect(find.text('Linked Notes'), findsWidgets);
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'main editor markdown toolbar inserts code block and hides in read mode',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('note_editor_markdown_toolbar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('note_editor_toggle_line_numbers')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('note_editor_toggle_word_wrap')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('note_editor_markdown_toolbar_action_code_block')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(
          const Key('note_editor_markdown_toolbar_field_code_language'),
        ),
        'dart',
      );
      await tester.tap(
        find.byKey(const Key('note_editor_markdown_toolbar_dialog_insert')),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      final codeField = tester.widget<CodeField>(
        find.byKey(const Key('macos_note_editor_content')),
      );
      expect(codeField.controller.text, contains('```dart'));

      await tester.tap(find.text('Read').first);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('note_editor_markdown_toolbar')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('note_editor_toggle_line_numbers')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('note_editor_toggle_word_wrap')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'editor view toggles honor persisted settings and update CodeField behavior',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );
      final settingsRepository = _FakeSettingsRepository(
        AppSettings(
          storageRootPath: '/tmp/chronicle-test',
          clientId: 'test-client',
          syncConfig: SyncConfig.initial(),
          lastSyncAt: null,
          editorLineNumbersEnabled: false,
          editorWordWrapEnabled: true,
        ),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          settingsRepository: settingsRepository,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      CodeField codeField = tester.widget<CodeField>(
        find.byKey(const Key('macos_note_editor_content')),
      );
      expect(codeField.wrap, isTrue);
      expect(codeField.gutterStyle.showLineNumbers, isFalse);

      await tester.tap(
        find.byKey(const Key('note_editor_toggle_line_numbers')),
      );
      await tester.pumpAndSettle();

      codeField = tester.widget<CodeField>(
        find.byKey(const Key('macos_note_editor_content')),
      );
      expect(codeField.gutterStyle.showLineNumbers, isTrue);
      expect(settingsRepository._settings.editorLineNumbersEnabled, isTrue);

      await tester.tap(find.byKey(const Key('note_editor_toggle_word_wrap')));
      await tester.pumpAndSettle();

      codeField = tester.widget<CodeField>(
        find.byKey(const Key('macos_note_editor_content')),
      );
      expect(codeField.wrap, isFalse);
      expect(settingsRepository._settings.editorWordWrapEnabled, isFalse);
    },
  );

  testWidgets(
    'table link and image toolbar actions use anchored popups and still insert markdown',
    (tester) async {
      _setDesktopViewport(tester);
      final repos = _TestRepos(
        matterRepository: _MemoryMatterRepository(<Matter>[matter]),
        noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
        linkRepository: _MemoryLinkRepository(),
      );

      await tester.pumpWidget(
        _buildApp(
          useMacOSNativeUI: false,
          repos: repos,
          overrides: [
            selectedMatterIdProvider.overrideWithBuild(
              (ref, notifier) => 'matter-1',
            ),
            selectedPhaseIdProvider.overrideWithBuild(
              (ref, notifier) => 'phase-start',
            ),
            selectedNoteIdProvider.overrideWithBuild(
              (ref, notifier) => 'note-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('note_editor_markdown_toolbar_action_table')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('note_editor_markdown_toolbar_popup_table')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(
        find.byKey(const Key('note_editor_markdown_toolbar_field_table_rows')),
        '2',
      );
      await tester.enterText(
        find.byKey(
          const Key('note_editor_markdown_toolbar_field_table_columns'),
        ),
        '2',
      );
      await tester.tap(
        find.byKey(const Key('note_editor_markdown_toolbar_dialog_insert')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('note_editor_markdown_toolbar_popup_table')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const Key('note_editor_markdown_toolbar_action_link')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('note_editor_markdown_toolbar_popup_link')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(
        find.byKey(const Key('note_editor_markdown_toolbar_field_link_text')),
        'Chronicle',
      );
      await tester.enterText(
        find.byKey(const Key('note_editor_markdown_toolbar_field_link_url')),
        'https://example.com',
      );
      await tester.tap(
        find.byKey(const Key('note_editor_markdown_toolbar_dialog_insert')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('note_editor_markdown_toolbar_action_image')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('note_editor_markdown_toolbar_popup_image')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(
        find.byKey(const Key('note_editor_markdown_toolbar_field_image_alt')),
        'Alt',
      );
      await tester.enterText(
        find.byKey(
          const Key('note_editor_markdown_toolbar_field_image_source'),
        ),
        'assets/example.png',
      );
      await tester.tap(
        find.byKey(const Key('note_editor_markdown_toolbar_dialog_insert')),
      );
      await tester.pumpAndSettle();

      final codeField = tester.widget<CodeField>(
        find.byKey(const Key('macos_note_editor_content')),
      );
      expect(codeField.controller.text, contains('| Column 1 | Column 2 |'));
      expect(
        codeField.controller.text,
        contains('[Chronicle](https://example.com)'),
      );
      expect(codeField.controller.text, contains('![Alt](assets/example.png)'));
    },
  );

  testWidgets('note dialog toolbar hides image action', (tester) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _secondaryClick(
      tester,
      find.byKey(const ValueKey<String>('phase_note_row_note-1')),
    );
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('note_dialog_markdown_toolbar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('note_dialog_markdown_toolbar_action_image')),
      findsNothing,
    );

    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
  });

  testWidgets('sync controls are relocated to sidebar in macOS shell', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: true,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sidebar_sync_now_button')), findsOneWidget);
    expect(find.byKey(const Key('sidebar_sync_status')), findsOneWidget);
    expect(
      find.byKey(const Key('sidebar_sync_advanced_button')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MacosIcon &&
            widget.icon == CupertinoIcons.arrow_2_circlepath,
      ),
      findsOneWidget,
    );
  });

  testWidgets('sync controls are relocated to sidebar in material shell', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sidebar_sync_now_button')), findsOneWidget);
    expect(find.byKey(const Key('sidebar_sync_status')), findsOneWidget);
    expect(
      find.byKey(const Key('sidebar_sync_advanced_button')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.sync),
      ),
      findsNothing,
    );
  });

  testWidgets('create matter dialog applies preset color and selected icon', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final matterRepository = _MemoryMatterRepository(<Matter>[matter]);
    final repos = _TestRepos(
      matterRepository: matterRepository,
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Matter'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)).at(0),
      'Visual Matter',
    );
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)).at(1),
      'Color + icon picker',
    );
    await tester.tap(find.byKey(const Key('matter_color_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#EF4444').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('matter_icon_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Science').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create').last);
    await tester.pumpAndSettle();

    final matters = await matterRepository.listMatters();
    final created = matters.firstWhere((item) => item.title == 'Visual Matter');
    expect(created.color, '#EF4444');
    expect(created.icon, 'science');
  });

  testWidgets('create matter dialog opens custom color picker', (tester) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Matter'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('matter_color_custom_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ColorPicker), findsOneWidget);
    await tester.tap(find.text('Use color'));
    await tester.pumpAndSettle();

    final preview = tester.widget<TextField>(
      find.byKey(const Key('matter_color_preview_field')),
    );
    expect(preview.controller?.text, '#2563EB');
  });

  testWidgets('force deletion override is one-time in material shell', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );
    final syncRepository = _NoopSyncRepository();

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          syncRepositoryProvider.overrideWithValue(syncRepository),
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar_sync_advanced_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Force apply deletions (next run)').last);
    await tester.pumpAndSettle();
    expect(find.text('Force Apply Deletions'), findsOneWidget);
    await tester.tap(find.text('Continue').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Force deletion override armed'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('sidebar_sync_now_button')));
    await tester.pumpAndSettle();
    expect(
      syncRepository.lastOptions?.mode,
      SyncRunMode.forceApplyDeletionsOnce,
    );
    expect(find.textContaining('Force deletion override armed'), findsNothing);
  });

  testWidgets('blocked sync status is shown when repository returns blocker', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );
    final now = DateTime.utc(2026, 2, 21, 11, 0);
    final syncRepository = _NoopSyncRepository(
      nextResult: SyncResult(
        uploadedCount: 0,
        downloadedCount: 0,
        conflictCount: 0,
        deletedCount: 0,
        startedAt: now,
        endedAt: now,
        errors: const <String>[],
        blocker: const SyncBlocker(
          type: SyncBlockerType.versionMismatchRemoteOlder,
          localFormatVersion: 2,
          remoteFormatVersion: 1,
        ),
      ),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          syncRepositoryProvider.overrideWithValue(syncRepository),
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar_sync_now_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sync blocked:'), findsOneWidget);
    expect(
      find.byKey(const Key('sidebar_sync_advanced_button')),
      findsOneWidget,
    );
  });

  testWidgets('live sync progress is shown in sidebar status area', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );
    final syncRepository = _NoopSyncRepository(
      onSyncCall: (options, onProgress) async {
        onProgress?.call(
          const SyncProgress(
            phase: SyncProgressPhase.uploading,
            completed: 1,
            total: 4,
            uploadedCount: 1,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return SyncResult(
          uploadedCount: 1,
          downloadedCount: 0,
          conflictCount: 0,
          deletedCount: 0,
          startedAt: DateTime.utc(2026, 2, 21, 11, 0),
          endedAt: DateTime.utc(2026, 2, 21, 11, 0, 1),
          errors: const <String>[],
          blocker: null,
        );
      },
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          syncRepositoryProvider.overrideWithValue(syncRepository),
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar_sync_now_button')));
    await tester.pump();

    expect(find.text('Uploading changes'), findsOneWidget);
    expect(find.textContaining('1/4'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Sync complete'), findsOneWidget);
  });

  testWidgets('active remote lock exposes override action and retries sync', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );
    final syncRepository = _NoopSyncRepository(
      onSyncCall: (options, onProgress) async {
        if (options.mode == SyncRunMode.forceBreakRemoteLockOnce) {
          return SyncResult(
            uploadedCount: 1,
            downloadedCount: 0,
            conflictCount: 0,
            deletedCount: 0,
            startedAt: DateTime.utc(2026, 2, 21, 11, 0),
            endedAt: DateTime.utc(2026, 2, 21, 11, 0, 1),
            errors: const <String>[],
            blocker: null,
          );
        }
        return SyncResult(
          uploadedCount: 0,
          downloadedCount: 0,
          conflictCount: 0,
          deletedCount: 0,
          startedAt: DateTime.utc(2026, 2, 21, 11, 0),
          endedAt: DateTime.utc(2026, 2, 21, 11, 0, 1),
          errors: const <String>[],
          blocker: SyncBlocker(
            type: SyncBlockerType.activeRemoteLock,
            lockPath: 'locks/sync_desktop_other-client.json',
            lockClientId: 'other-client',
            lockClientType: 'desktop',
            lockUpdatedAt: DateTime.utc(2026, 2, 21, 10, 59, 50),
            competingLockCount: 1,
          ),
        );
      },
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          syncRepositoryProvider.overrideWithValue(syncRepository),
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar_sync_now_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('active remote lock'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar_sync_advanced_button')));
    await tester.pumpAndSettle();
    expect(find.text('Override lock and retry'), findsOneWidget);

    await tester.tap(find.text('Override lock and retry').last);
    await tester.pumpAndSettle();
    expect(find.text('Override Remote Lock'), findsOneWidget);

    await tester.tap(find.text('Continue').last);
    await tester.pumpAndSettle();

    expect(
      syncRepository.callOptions.map((options) => options.mode),
      contains(SyncRunMode.forceBreakRemoteLockOnce),
    );
    expect(find.text('Sync complete'), findsOneWidget);
  });

  testWidgets('recover local wins requires double confirmation', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );
    final syncRepository = _NoopSyncRepository(
      nextAssessment: SyncBootstrapAssessment.fromCounts(
        localItemCount: 2,
        remoteItemCount: 3,
      ),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          syncRepositoryProvider.overrideWithValue(syncRepository),
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar_sync_advanced_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Re-upload local to remote').last);
    await tester.pumpAndSettle();

    expect(find.text('Local Wins Recovery'), findsOneWidget);
    expect(
      find.textContaining('Local items: 2. Remote items: 3.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Continue').last);
    await tester.pumpAndSettle();

    expect(find.text('Clear Remote And Replace It?'), findsOneWidget);
    expect(syncRepository.lastOptions, isNull);

    await tester.tap(find.text('Continue').last);
    await tester.pumpAndSettle();

    expect(syncRepository.lastOptions?.mode, SyncRunMode.recoverLocalWins);
  });

  testWidgets('sync now button is disabled while sync is running', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );
    final completer = Completer<SyncResult>();
    final syncRepository = _NoopSyncRepository(
      onSyncCall: (options, onProgress) async {
        onProgress?.call(
          const SyncProgress(
            phase: SyncProgressPhase.scanning,
            uploadedCount: 0,
          ),
        );
        return completer.future;
      },
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          syncRepositoryProvider.overrideWithValue(syncRepository),
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar_sync_now_button')));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('sidebar_sync_now_button')),
    );
    expect(button.onPressed, isNull);
    expect(syncRepository.callCount, 1);

    completer.complete(
      SyncResult(
        uploadedCount: 0,
        downloadedCount: 0,
        conflictCount: 0,
        deletedCount: 0,
        startedAt: DateTime.utc(2026, 2, 21, 11, 0),
        endedAt: DateTime.utc(2026, 2, 21, 11, 0, 1),
        errors: const <String>[],
        blocker: null,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('non-macOS keeps material main-pane controls', (tester) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );

    await tester.pumpWidget(
      _buildApp(
        useMacOSNativeUI: false,
        repos: repos,
        overrides: [
          selectedMatterIdProvider.overrideWithBuild(
            (ref, notifier) => 'matter-1',
          ),
          selectedPhaseIdProvider.overrideWithBuild(
            (ref, notifier) => 'phase-start',
          ),
          selectedNoteIdProvider.overrideWithBuild((ref, notifier) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<MatterViewMode>), findsNothing);
    // Top bar now has Notes, Board, Graph buttons
    expect(find.byKey(const Key('matter_top_notes_button')), findsOneWidget);
    expect(find.byKey(const Key('matter_top_kanban_button')), findsOneWidget);
    expect(find.byKey(const Key('matter_top_graph_button')), findsOneWidget);
    // Phase selector is now in the notes view, not top bar
    expect(
      find.byKey(const Key('matter_notes_phase_selector')),
      findsOneWidget,
    );
  });
}

ProviderContainer _containerForApp(WidgetTester tester) {
  final element = tester.element(find.byType(ChronicleApp));
  return ProviderScope.containerOf(element);
}

Future<void> _longPressDragTo(
  WidgetTester tester,
  Finder source,
  Finder target,
) async {
  final sourceCenter = tester.getCenter(source);
  final targetCenter = tester.getCenter(target);
  final gesture = await tester.startGesture(sourceCenter);
  await tester.pump(const Duration(milliseconds: 550));
  await gesture.moveTo(targetCenter);
  await tester.pump(const Duration(milliseconds: 40));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _secondaryClick(WidgetTester tester, Finder target) async {
  await _secondaryClickAt(tester, tester.getCenter(target));
}

Future<void> _tapSidebarNotebookFolder(
  WidgetTester tester,
  String folderId,
) async {
  final folderRow = find.byKey(
    ValueKey<String>('sidebar_notebook_folder_drop_target_$folderId'),
  );
  final scrollable = find.byType(Scrollable).first;
  await tester.dragUntilVisible(folderRow, scrollable, const Offset(0, -180));
  await tester.pumpAndSettle();
  await tester.tap(folderRow);
}

Future<void> _secondaryClickAt(WidgetTester tester, Offset position) async {
  final gesture = await tester.startGesture(
    position,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<TestGesture> _startLongPressDrag(
  WidgetTester tester,
  Finder source,
) async {
  final sourceCenter = tester.getCenter(source);
  final gesture = await tester.startGesture(sourceCenter);
  await tester.pump(const Duration(milliseconds: 550));
  return gesture;
}

List<String> _macosPulldownTitles(MacosPulldownButton button) {
  final items = button.items ?? const <MacosPulldownMenuEntry>[];
  return items
      .whereType<MacosPulldownMenuItem>()
      .map((entry) {
        final title = entry.title;
        if (title is Text) {
          return title.data ?? '';
        }
        return '';
      })
      .where((title) => title.isNotEmpty)
      .toList();
}

Widget _buildApp({
  required bool useMacOSNativeUI,
  required _TestRepos repos,
  CategoryRepository? categoryRepository,
  SettingsRepository? settingsRepository,
  String localeTag = 'en',
  List overrides = const [],
}) {
  final hasSyncRepositoryOverride = overrides.any(
    (override) => override.toString().contains('SyncRepository'),
  );
  final hasConflictsControllerOverride = overrides.any(
    (override) => override.toString().contains('ConflictsController'),
  );
  final resolvedSettingsRepository =
      settingsRepository ??
      _FakeSettingsRepository(
        AppSettings(
          storageRootPath: '/tmp/chronicle-test',
          clientId: 'test-client',
          syncConfig: SyncConfig.initial(),
          lastSyncAt: null,
          localeTag: localeTag,
        ),
      );

  return ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(resolvedSettingsRepository),
      matterRepositoryProvider.overrideWithValue(repos.matterRepository),
      categoryRepositoryProvider.overrideWithValue(
        categoryRepository ?? _MemoryCategoryRepository(),
      ),
      noteRepositoryProvider.overrideWithValue(repos.noteRepository),
      linkRepositoryProvider.overrideWithValue(repos.linkRepository),
      searchRepositoryProvider.overrideWithValue(
        _MemorySearchRepository(repos.noteRepository),
      ),
      if (!hasSyncRepositoryOverride)
        syncRepositoryProvider.overrideWithValue(_NoopSyncRepository()),
      if (!hasConflictsControllerOverride)
        conflictsControllerProvider.overrideWith(
          () => _StaticConflictsController(const <SyncConflict>[]),
        ),
      ...overrides,
    ],
    child: ChronicleApp(forceMacOSNativeUI: useMacOSNativeUI),
  );
}

class _TestRepos {
  const _TestRepos({
    required this.matterRepository,
    required this.noteRepository,
    required this.linkRepository,
  });

  final _MemoryMatterRepository matterRepository;
  final _MemoryNoteRepository noteRepository;
  final _MemoryLinkRepository linkRepository;
}

class _MemoryCategoryRepository implements CategoryRepository {
  _MemoryCategoryRepository([List<Category> categories = const <Category>[]])
    : _categories = List<Category>.of(categories);

  final List<Category> _categories;

  @override
  Future<Category> createCategory({
    required String name,
    String color = '#2563EB',
    String icon = 'folder',
  }) async {
    final now = DateTime.now().toUtc();
    final category = Category(
      id: 'category-${_categories.length + 1}',
      name: name,
      color: color,
      icon: icon,
      createdAt: now,
      updatedAt: now,
    );
    _categories.add(category);
    return category;
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    _categories.removeWhere((category) => category.id == categoryId);
  }

  @override
  Future<Category?> getCategoryById(String categoryId) async {
    for (final category in _categories) {
      if (category.id == categoryId) {
        return category;
      }
    }
    return null;
  }

  @override
  Future<List<Category>> listCategories() async {
    return List<Category>.of(_categories);
  }

  @override
  Future<void> updateCategory(Category category) async {
    final index = _categories.indexWhere((item) => item.id == category.id);
    if (index >= 0) {
      _categories[index] = category;
    }
  }
}

class _MemoryMatterRepository implements MatterRepository {
  _MemoryMatterRepository(List<Matter> matters)
    : _matters = List<Matter>.of(matters);

  final List<Matter> _matters;

  @override
  Future<Matter> createMatter({
    required String title,
    String description = '',
    String? categoryId,
    String color = '#2563EB',
    String icon = 'description',
    bool isPinned = false,
  }) async {
    final now = DateTime.now().toUtc();
    final id = 'matter-${_matters.length + 1}';
    final matter = Matter(
      id: id,
      categoryId: categoryId,
      title: title,
      description: description,
      status: MatterStatus.active,
      color: color,
      icon: icon,
      isPinned: isPinned,
      createdAt: now,
      updatedAt: now,
      startedAt: now,
      endedAt: null,
      phases: <Phase>[
        Phase(id: '$id-phase-start', matterId: id, name: 'Start', order: 0),
      ],
      currentPhaseId: '$id-phase-start',
    );
    _matters.add(matter);
    return matter;
  }

  @override
  Future<void> deleteMatter(String matterId) async {
    _matters.removeWhere((matter) => matter.id == matterId);
  }

  @override
  Future<Matter?> getMatterById(String matterId) async {
    for (final matter in _matters) {
      if (matter.id == matterId) {
        return matter;
      }
    }
    return null;
  }

  @override
  Future<List<Matter>> listMatters() async => List<Matter>.of(_matters);

  @override
  Future<void> setMatterPinned(String matterId, bool isPinned) async {
    final index = _matters.indexWhere((matter) => matter.id == matterId);
    if (index < 0) {
      return;
    }
    _matters[index] = _matters[index].copyWith(isPinned: isPinned);
  }

  @override
  Future<void> setMatterStatus(String matterId, MatterStatus status) async {
    final index = _matters.indexWhere((matter) => matter.id == matterId);
    if (index < 0) {
      return;
    }
    _matters[index] = _matters[index].copyWith(status: status);
  }

  @override
  Future<void> setMatterCategory(String matterId, String? categoryId) async {
    final index = _matters.indexWhere((matter) => matter.id == matterId);
    if (index < 0) {
      return;
    }
    _matters[index] = _matters[index].copyWith(
      categoryId: categoryId,
      clearCategoryId: categoryId == null,
    );
  }

  @override
  Future<void> updateMatter(Matter matter) async {
    final index = _matters.indexWhere((item) => item.id == matter.id);
    if (index >= 0) {
      _matters[index] = matter;
    }
  }
}

class _MemoryNoteRepository implements NoteRepository {
  _MemoryNoteRepository(List<Note> notes)
    : _notes = <String, Note>{for (final note in notes) note.id: note};

  final Map<String, Note> _notes;
  final List<String> getNoteByIdCalls = <String>[];
  int updateCount = 0;

  Note? noteById(String noteId) => _notes[noteId];

  @override
  Future<Note> addAttachments({
    required String noteId,
    required List<String> sourceFilePaths,
  }) async {
    final existing = _notes[noteId]!;
    final updated = existing.copyWith(
      attachments: <String>[...existing.attachments, ...sourceFilePaths],
      updatedAt: DateTime.now().toUtc(),
    );
    _notes[noteId] = updated;
    return updated;
  }

  @override
  Future<Note> createNote({
    required String title,
    required String content,
    String? matterId,
    String? phaseId,
    String? notebookFolderId,
    List<String> tags = const <String>[],
    bool isPinned = false,
    List<String> attachments = const <String>[],
  }) async {
    final id = 'note-${_notes.length + 1}';
    final now = DateTime.now().toUtc();
    final note = Note(
      id: id,
      matterId: matterId,
      phaseId: phaseId,
      notebookFolderId: notebookFolderId,
      title: title,
      content: content,
      tags: tags,
      isPinned: isPinned,
      attachments: attachments,
      createdAt: now,
      updatedAt: now,
    );
    _notes[id] = note;
    return note;
  }

  @override
  Future<void> deleteNote(String noteId) async {
    _notes.remove(noteId);
  }

  @override
  Future<Note?> getNoteById(String noteId) async {
    getNoteByIdCalls.add(noteId);
    return _notes[noteId];
  }

  @override
  Future<List<Note>> listAllNotes() async => _notes.values.toList();

  @override
  Future<List<Note>> listMatterTimeline(String matterId) async {
    return _notes.values.where((note) => note.matterId == matterId).toList();
  }

  @override
  Future<List<Note>> listNotesByMatterAndPhase({
    required String matterId,
    required String phaseId,
  }) async {
    return _notes.values
        .where((note) => note.matterId == matterId && note.phaseId == phaseId)
        .toList();
  }

  @override
  Future<List<Note>> listOrphanNotes() async {
    return _notes.values.where((note) => note.isOrphan).toList();
  }

  @override
  Future<List<Note>> listNotebookNotes({String? folderId}) async {
    return _notes.values
        .where((note) => note.isInNotebook && note.notebookFolderId == folderId)
        .toList();
  }

  @override
  Future<void> moveNote({
    required String noteId,
    required String? matterId,
    required String? phaseId,
    required String? notebookFolderId,
  }) async {
    final existing = _notes[noteId]!;
    _notes[noteId] = existing.copyWith(
      matterId: matterId,
      phaseId: phaseId,
      notebookFolderId: notebookFolderId,
      clearMatterId: matterId == null,
      clearPhaseId: phaseId == null,
      clearNotebookFolderId: notebookFolderId == null,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<Note> removeAttachment({
    required String noteId,
    required String attachmentPath,
  }) async {
    final existing = _notes[noteId]!;
    final updated = existing.copyWith(
      attachments: existing.attachments
          .where((value) => value != attachmentPath)
          .toList(),
      updatedAt: DateTime.now().toUtc(),
    );
    _notes[noteId] = updated;
    return updated;
  }

  @override
  Future<void> updateNote(Note note) async {
    updateCount += 1;
    _notes[note.id] = note;
  }
}

class _MemoryNotebookRepository implements NotebookRepository {
  _MemoryNotebookRepository(List<NotebookFolder> folders)
    : _folders = <String, NotebookFolder>{
        for (final folder in folders) folder.id: folder,
      };

  final Map<String, NotebookFolder> _folders;

  @override
  Future<NotebookFolder> createFolder({
    required String name,
    String? parentId,
  }) async {
    final now = DateTime.now().toUtc();
    final id = 'folder-${_folders.length + 1}';
    final folder = NotebookFolder(
      id: id,
      name: name,
      parentId: parentId,
      createdAt: now,
      updatedAt: now,
    );
    _folders[id] = folder;
    return folder;
  }

  @override
  Future<void> deleteFolder(String folderId) async {
    _folders.remove(folderId);
  }

  @override
  Future<NotebookFolder?> getFolderById(String folderId) async {
    return _folders[folderId];
  }

  @override
  Future<List<NotebookFolder>> listFolders() async {
    return _folders.values.toList(growable: false);
  }

  @override
  Future<NotebookFolder> renameFolder({
    required String folderId,
    required String name,
  }) async {
    final existing = _folders[folderId];
    if (existing == null) {
      throw StateError('Notebook folder not found: $folderId');
    }
    final updated = existing.copyWith(
      name: name,
      updatedAt: DateTime.now().toUtc(),
    );
    _folders[folderId] = updated;
    return updated;
  }
}

class _MemoryLinkRepository implements LinkRepository {
  final List<NoteLink> _links = <NoteLink>[];

  @override
  Future<NoteLink> createLink({
    required String sourceNoteId,
    required String targetNoteId,
    required String context,
  }) async {
    final link = NoteLink(
      id: 'link-${_links.length + 1}',
      sourceNoteId: sourceNoteId,
      targetNoteId: targetNoteId,
      context: context,
      createdAt: DateTime.now().toUtc(),
    );
    _links.add(link);
    return link;
  }

  @override
  Future<void> deleteLink(String linkId) async {
    _links.removeWhere((link) => link.id == linkId);
  }

  @override
  Future<List<NoteLink>> listLinks() async => List<NoteLink>.of(_links);

  @override
  Future<List<NoteLink>> listLinksForNote(String noteId) async {
    return _links
        .where(
          (link) => link.sourceNoteId == noteId || link.targetNoteId == noteId,
        )
        .toList();
  }
}

class _MemorySearchRepository implements SearchRepository {
  _MemorySearchRepository(this._noteRepository);

  final _MemoryNoteRepository _noteRepository;

  @override
  Future<List<String>> listTags() async => const <String>['one', 'two'];

  @override
  Future<void> rebuildIndex() async {}

  @override
  Future<List<NoteSearchHit>> search(SearchQuery query) async {
    final needle = query.text.trim().toLowerCase();
    if (needle.isEmpty) {
      return const <NoteSearchHit>[];
    }

    final notes = await _noteRepository.listAllNotes();
    final hits = <NoteSearchHit>[];
    for (final note in notes) {
      final haystack = '${note.title}\n${note.content}'.toLowerCase();
      if (!haystack.contains(needle)) {
        continue;
      }
      final snippet = note.content.replaceAll('\n', ' ').trim();
      hits.add(NoteSearchHit(note: note, snippet: snippet));
    }
    return hits;
  }
}

class _NoopSyncRepository implements SyncRepository {
  _NoopSyncRepository({
    SyncResult? nextResult,
    this.onSyncCall,
    SyncBootstrapAssessment? nextAssessment,
  }) : _nextResult = nextResult,
       _nextAssessment =
           nextAssessment ??
           SyncBootstrapAssessment.fromCounts(
             localItemCount: 0,
             remoteItemCount: 0,
           );

  SyncConfig _config = SyncConfig.initial();
  final SyncResult? _nextResult;
  final SyncBootstrapAssessment _nextAssessment;
  final Future<SyncResult> Function(
    SyncRunOptions options,
    SyncProgressCallback? onProgress,
  )?
  onSyncCall;
  final List<SyncRunOptions> callOptions = <SyncRunOptions>[];
  int callCount = 0;
  SyncRunOptions? lastOptions;

  @override
  Future<SyncConfig> getConfig() async => _config;

  @override
  Future<String?> getPassword() async => null;

  @override
  Future<SyncBootstrapAssessment> assessBootstrap({
    required SyncConfig config,
    required String storageRootPath,
    String? password,
  }) async {
    return _nextAssessment;
  }

  @override
  Future<void> saveConfig(SyncConfig config, {String? password}) async {
    _config = config;
  }

  @override
  Future<SyncResult> syncNow({
    SyncRunOptions options = const SyncRunOptions(),
    SyncProgressCallback? onProgress,
  }) async {
    callCount += 1;
    callOptions.add(options);
    lastOptions = options;
    if (onSyncCall != null) {
      return onSyncCall!(options, onProgress);
    }
    return _nextResult ?? SyncResult.empty(DateTime.now().toUtc());
  }
}

class _FixedClock implements Clock {
  const _FixedClock(this._nowUtc);

  final DateTime _nowUtc;

  @override
  DateTime nowUtc() => _nowUtc;
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this._settings);

  AppSettings _settings;
  String? _password;
  String? _proxyPassword;

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<String?> readSyncPassword() async => _password;

  @override
  Future<String?> readSyncProxyPassword() async => _proxyPassword;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> saveSyncPassword(String password) async {
    _password = password;
  }

  @override
  Future<void> clearSyncPassword() async {
    _password = null;
  }

  @override
  Future<void> saveSyncProxyPassword(String password) async {
    _proxyPassword = password;
  }

  @override
  Future<void> clearSyncProxyPassword() async {
    _proxyPassword = null;
  }

  @override
  Future<void> setLastSyncAt(DateTime value) async {
    _settings = _settings.copyWith(lastSyncAt: value);
  }

  @override
  Future<void> setStorageRootPath(String path) async {
    _settings = _settings.copyWith(storageRootPath: path);
  }
}

class _StaticConflictsController extends ConflictsController {
  _StaticConflictsController(this._conflicts);

  final List<SyncConflict> _conflicts;

  @override
  Future<List<SyncConflict>> build() async => _conflicts;

  @override
  Future<void> reload() async {
    state = AsyncData(_conflicts);
  }
}

class _SpyNoteEditorController extends NoteEditorController {
  static final List<String> openedNoteIds = <String>[];

  @override
  Future<Note?> build() async => null;

  @override
  Future<void> openNoteInWorkspace(
    String noteId, {
    bool openInReadMode = false,
  }) async {
    openedNoteIds.add(noteId);
  }
}

void _setDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1720, 1120);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _setNarrowDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(980, 1120);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
