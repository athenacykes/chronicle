import 'package:chronicle/app/app.dart';
import 'package:chronicle/app/app_providers.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/category.dart';
import 'package:chronicle/domain/entities/enums.dart';
import 'package:chronicle/domain/entities/matter.dart';
import 'package:chronicle/domain/entities/note.dart';
import 'package:chronicle/domain/entities/note_link.dart';
import 'package:chronicle/domain/entities/note_search_hit.dart';
import 'package:chronicle/domain/entities/phase.dart';
import 'package:chronicle/domain/entities/search_query.dart';
import 'package:chronicle/domain/entities/sync_blocker.dart';
import 'package:chronicle/domain/entities/sync_conflict.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/entities/sync_run_options.dart';
import 'package:chronicle/domain/entities/sync_result.dart';
import 'package:chronicle/domain/repositories/link_repository.dart';
import 'package:chronicle/domain/repositories/category_repository.dart';
import 'package:chronicle/domain/repositories/matter_repository.dart';
import 'package:chronicle/domain/repositories/note_repository.dart';
import 'package:chronicle/domain/repositories/search_repository.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:chronicle/domain/repositories/sync_repository.dart';
import 'package:chronicle/presentation/matters/matters_controller.dart';
import 'package:chronicle/presentation/notes/notes_controller.dart';
import 'package:chronicle/presentation/search/search_controller.dart';
import 'package:chronicle/presentation/sync/conflicts_controller.dart';
import 'package:flutter/cupertino.dart';
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
    color: '#4C956C',
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

    expect(
      find.byKey(const Key('macos_matter_new_note_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('matter_top_phase_menu_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('matter_top_timeline_button')), findsOneWidget);
    expect(find.byKey(const Key('matter_top_graph_button')), findsOneWidget);
    expect(find.text('New Note'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Graph'), findsOneWidget);
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
      find.byKey(const Key('macos_notebook_new_note_button')),
      findsOneWidget,
    );
    expect(find.byType(MacosPulldownButton), findsWidgets);
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
          useMacOSNativeUI: true,
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

      expect(
        find.byKey(const Key('matter_top_phase_menu_button')),
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

    await tester.tap(find.byKey(const Key('macos_matter_new_note_button')));
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

      await tester.tap(find.byKey(const Key('macos_notebook_new_note_button')));
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
      expect(views, findsOneWidget);
      expect(notebooks, findsOneWidget);
      expect(notebook, findsOneWidget);
      expect(
        tester.getTopLeft(views).dy,
        lessThan(tester.getTopLeft(notebooks).dy),
      );
      expect(
        tester.getTopLeft(notebooks).dy,
        lessThan(tester.getTopLeft(notebook).dy),
      );

      final sidebar = find.byKey(const Key('sidebar_root'));
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
      final rootNotebookMenus = buttons.where((button) {
        final titles = _macosPulldownTitles(button);
        return titles.contains('New Folder') &&
            !titles.contains('Rename Folder') &&
            !titles.contains('Delete Folder');
      }).toList();
      expect(rootNotebookMenus, isNotEmpty);
      expect(rootNotebookMenus.first.icon, CupertinoIcons.ellipsis_circle);

      final matterActionMenus = buttons.where((button) {
        final titles = _macosPulldownTitles(button);
        return titles.contains('Set Active') &&
            titles.contains('Set Paused') &&
            titles.contains('Set Completed') &&
            titles.contains('Set Archived');
      }).toList();
      expect(matterActionMenus, isNotEmpty);
      expect(matterActionMenus.first.icon, CupertinoIcons.ellipsis_circle);
    },
  );

  testWidgets(
    'material sidebar keeps Views then Notebooks and uses circular notebook/matter menus',
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
      expect(views, findsOneWidget);
      expect(notebooks, findsOneWidget);
      expect(notebook, findsOneWidget);
      expect(
        tester.getTopLeft(views).dy,
        lessThan(tester.getTopLeft(notebooks).dy),
      );
      expect(
        tester.getTopLeft(notebooks).dy,
        lessThan(tester.getTopLeft(notebook).dy),
      );

      final sidebar = find.byKey(const Key('sidebar_root'));
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
          of: sidebar,
          matching: find.byIcon(CupertinoIcons.ellipsis_circle),
        ),
        findsWidgets,
      );
    },
  );

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

    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
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

    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
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

      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();
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
    'drag from timeline card to notebook root target creates notebook note',
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
              (ref, notifier) => MatterViewMode.timeline,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _longPressDragTo(
        tester,
        find.byKey(const ValueKey<String>('note_drag_timeline_note-1')),
        find.byKey(const Key('sidebar_notebook_root_drop_target')),
      );

      final moved = noteRepository.noteById('note-1');
      expect(moved?.matterId, isNull);
      expect(moved?.phaseId, isNull);
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

    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
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

    final buttons = tester
        .widgetList<MacosPulldownButton>(find.byType(MacosPulldownButton))
        .toList();
    final moveMenuButtons = buttons.where((button) {
      final titles = _macosPulldownTitles(button);
      return titles.contains('Move to Matter...') &&
          titles.contains('Move to Phase...') &&
          titles.contains('Move to Notebook...');
    }).toList();

    expect(moveMenuButtons.length, greaterThanOrEqualTo(2));

    final rowMenus = moveMenuButtons.where(
      (button) => _macosPulldownTitles(button).contains('Edit'),
    );
    final editorMenus = moveMenuButtons.where(
      (button) => !_macosPulldownTitles(button).contains('Edit'),
    );

    expect(rowMenus, isNotEmpty);
    expect(editorMenus, isNotEmpty);
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

    final buttons = tester
        .widgetList<MacosPulldownButton>(find.byType(MacosPulldownButton))
        .toList();
    final matterActionMenus = buttons.where((button) {
      final titles = _macosPulldownTitles(button);
      return titles.contains('Set Active') &&
          titles.contains('Set Paused') &&
          titles.contains('Set Completed') &&
          titles.contains('Set Archived');
    }).toList();

    expect(matterActionMenus, isNotEmpty);
    expect(
      _macosPulldownTitles(matterActionMenus.first),
      containsAll(<String>[
        'Edit',
        'Pin',
        'Set Active',
        'Set Paused',
        'Set Completed',
        'Set Archived',
        'Delete',
      ]),
    );
  });

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

    await tester.tap(find.byKey(const Key('matter_top_phase_menu_button')));
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
            (ref, notifier) => MatterViewMode.timeline,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('matter_top_phase_menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In Progress'));
    await tester.pumpAndSettle();

    final container = _containerForApp(tester);
    expect(container.read(matterViewModeProvider), MatterViewMode.phase);
    expect(container.read(selectedPhaseIdProvider), 'phase-progress');
  });

  testWidgets('Edit in Phase does not use disposed ref after timeline switch', (
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
            (ref, notifier) => MatterViewMode.timeline,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit in Phase').first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('matter_top_phase_menu_button')),
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
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('macos_conflicts_refresh')), findsOneWidget);
    expect(find.text('Conflict Note'), findsWidgets);
  });

  testWidgets('conflict note markdown preview renders table and math', (
    tester,
  ) async {
    _setDesktopViewport(tester);
    final repos = _TestRepos(
      matterRepository: _MemoryMatterRepository(<Matter>[matter]),
      noteRepository: _MemoryNoteRepository(<Note>[noteOne, noteTwo]),
      linkRepository: _MemoryLinkRepository(),
    );
    const conflictMarkdown = '''
| key | value |
| --- | --- |
| a | 1 |

Inline \$x^2\$ and:
\$\$x^2 + y^2 = z^2\$\$
''';

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
          selectedConflictContentProvider.overrideWith(
            (ref) async => conflictMarkdown,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(Math), findsNWidgets(2));
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
        find.byKey(const Key('matter_top_timeline_button')),
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
        find.byKey(const Key('matter_top_timeline_button')),
        findsOneWidget,
      );

      await tester.enterText(find.byType(MacosSearchField<void>), 'se');
      await tester.pumpAndSettle();

      expect(container.read(searchResultsVisibleProvider), isTrue);
      expect(find.text('Search Hit'), findsOneWidget);
      expect(find.byKey(const Key('matter_top_timeline_button')), findsNothing);

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
        find.byKey(const Key('matter_top_timeline_button')),
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
    expect(find.byKey(const Key('matter_top_timeline_button')), findsNothing);

    final searchField = tester.widget<MacosSearchField<void>>(
      find.byType(MacosSearchField<void>),
    );
    searchField.controller?.clear();
    await tester.pumpAndSettle();

    expect(container.read(searchResultsVisibleProvider), isFalse);
    expect(find.byKey(const Key('matter_top_timeline_button')), findsOneWidget);
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
        find.byKey(const Key('matter_top_timeline_button')),
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
        find.byKey(const Key('matter_top_timeline_button')),
        findsOneWidget,
      );

      await tester.enterText(searchFieldFinder, 'se');
      await tester.pumpAndSettle();
      expect(container.read(searchResultsVisibleProvider), isTrue);
      expect(find.widgetWithText(ListTile, 'Search Hit'), findsOneWidget);
      expect(find.byKey(const Key('matter_top_timeline_button')), findsNothing);

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
        find.byKey(const Key('matter_top_timeline_button')),
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

    await tester.tap(find.text('Second Matter Note').first);
    await tester.pump();

    expect(find.text('Select a note to edit.'), findsNothing);

    await tester.pumpAndSettle();
    final container = _containerForApp(tester);
    expect(container.read(selectedNoteIdProvider), 'note-2');
  });

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
    'empty selected phase does not fallback and keeps select-note prompt',
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
              (ref, notifier) => 'phase-end',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final container = _containerForApp(tester);
      expect(container.read(selectedNoteIdProvider), isNull);
      expect(find.text('Select a note to edit.'), findsWidgets);
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

    final noteTile = find.widgetWithText(ListTile, 'Editor Note').first;
    final noteMenu = find.descendant(
      of: noteTile,
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.tap(noteMenu);
    await tester.pumpAndSettle();
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
    await tester.tap(find.byTooltip('#EF4444'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Science'));
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
    expect(preview.controller?.text, '#4C956C');
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
    expect(
      find.byKey(const Key('matter_top_phase_menu_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('matter_top_timeline_button')), findsOneWidget);
    expect(find.byKey(const Key('matter_top_graph_button')), findsOneWidget);
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
  await tester.pump(const Duration(milliseconds: 220));
  await gesture.moveTo(targetCenter);
  await tester.pump(const Duration(milliseconds: 40));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<TestGesture> _startLongPressDrag(
  WidgetTester tester,
  Finder source,
) async {
  final sourceCenter = tester.getCenter(source);
  final gesture = await tester.startGesture(sourceCenter);
  await tester.pump(const Duration(milliseconds: 220));
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
  List overrides = const [],
}) {
  final hasSyncRepositoryOverride = overrides.any(
    (override) => override.toString().contains('SyncRepository'),
  );
  final hasConflictsControllerOverride = overrides.any(
    (override) => override.toString().contains('ConflictsController'),
  );
  final settingsRepository = _FakeSettingsRepository(
    AppSettings(
      storageRootPath: '/tmp/chronicle-test',
      clientId: 'test-client',
      syncConfig: SyncConfig.initial(),
      lastSyncAt: null,
    ),
  );

  return ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(settingsRepository),
      matterRepositoryProvider.overrideWithValue(repos.matterRepository),
      categoryRepositoryProvider.overrideWithValue(_MemoryCategoryRepository()),
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
    String color = '#4C956C',
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
    String color = '#4C956C',
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
  _NoopSyncRepository({SyncResult? nextResult}) : _nextResult = nextResult;

  SyncConfig _config = SyncConfig.initial();
  final SyncResult? _nextResult;
  SyncRunOptions? lastOptions;

  @override
  Future<SyncConfig> getConfig() async => _config;

  @override
  Future<String?> getPassword() async => null;

  @override
  Future<void> saveConfig(SyncConfig config, {String? password}) async {
    _config = config;
  }

  @override
  Future<SyncResult> syncNow({
    SyncRunOptions options = const SyncRunOptions(),
  }) async {
    lastOptions = options;
    return _nextResult ?? SyncResult.empty(DateTime.now().toUtc());
  }
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this._settings);

  AppSettings _settings;
  String? _password;

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<String?> readSyncPassword() async => _password;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> saveSyncPassword(String password) async {
    _password = password;
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
