import 'package:chronicle/app/app.dart';
import 'package:chronicle/app/app_providers.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
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
import 'package:chronicle/domain/repositories/matter_repository.dart';
import 'package:chronicle/domain/repositories/note_repository.dart';
import 'package:chronicle/domain/repositories/search_repository.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:chronicle/domain/repositories/sync_repository.dart';
import 'package:chronicle/presentation/matters/matters_controller.dart';
import 'package:chronicle/presentation/notes/notes_controller.dart';
import 'package:chronicle/presentation/sync/conflicts_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
        overrides: <Override>[
          selectedMatterIdProvider.overrideWith((ref) => 'matter-1'),
          selectedPhaseIdProvider.overrideWith((ref) => 'phase-start'),
          selectedNoteIdProvider.overrideWith((ref) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('macos_matter_mode_segmented_control')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('macos_matter_new_note_button')),
      findsOneWidget,
    );
    expect(find.byType(MacosSegmentedControl), findsWidgets);
    expect(find.byType(MacosPulldownButton), findsWidgets);
    expect(find.byKey(const Key('macos_note_editor_title')), findsOneWidget);
    expect(find.byType(SegmentedButton<MatterViewMode>), findsNothing);
  });

  testWidgets('macOS orphans mode uses native header and list controls', (
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
        overrides: <Override>[
          showOrphansProvider.overrideWith((ref) => true),
          selectedNoteIdProvider.overrideWith((ref) => 'note-2'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('macos_orphan_new_note_button')),
      findsOneWidget,
    );
    expect(find.byType(MacosPulldownButton), findsWidgets);
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
        overrides: <Override>[
          showConflictsProvider.overrideWith((ref) => true),
          selectedConflictPathProvider.overrideWith((ref) => 'conflict-note-1'),
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
        overrides: <Override>[
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
        overrides: <Override>[
          selectedMatterIdProvider.overrideWith((ref) => 'matter-1'),
          selectedPhaseIdProvider.overrideWith((ref) => 'phase-start'),
          selectedNoteIdProvider.overrideWith((ref) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('macos_note_editor_title')),
      'Editor Note Updated',
    );
    await tester.tap(find.byKey(const Key('macos_note_editor_save')));
    await tester.pumpAndSettle();

    final saveButtonTop = tester.getTopLeft(
      find.byKey(const Key('macos_note_editor_save')),
    );
    final utilitiesTop = tester.getTopLeft(
      find.byKey(const Key('note_editor_utility_tags')),
    );
    expect(saveButtonTop.dy, lessThan(utilitiesTop.dy));
    expect(find.textContaining('Updated:'), findsNothing);
    expect(noteRepository.updateCount, greaterThanOrEqualTo(1));
    expect(noteRepository.noteById('note-1')?.title, 'Editor Note Updated');
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
        overrides: <Override>[
          selectedMatterIdProvider.overrideWith((ref) => 'matter-1'),
          selectedPhaseIdProvider.overrideWith((ref) => 'phase-start'),
          selectedNoteIdProvider.overrideWith((ref) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('macos_note_editor_title')),
      'Autosaved Title',
    );
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
          overrides: <Override>[
            selectedMatterIdProvider.overrideWith((ref) => 'matter-1'),
            selectedPhaseIdProvider.overrideWith((ref) => 'phase-start'),
            selectedNoteIdProvider.overrideWith((ref) => 'note-1'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tags (comma separated)'), findsNothing);
      expect(find.text('Move to Orphans'), findsNothing);
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
        overrides: <Override>[
          selectedMatterIdProvider.overrideWith((ref) => 'matter-1'),
          selectedPhaseIdProvider.overrideWith((ref) => 'phase-start'),
          selectedNoteIdProvider.overrideWith((ref) => 'note-1'),
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
        overrides: <Override>[
          selectedMatterIdProvider.overrideWith((ref) => 'matter-1'),
          selectedPhaseIdProvider.overrideWith((ref) => 'phase-start'),
          selectedNoteIdProvider.overrideWith((ref) => 'note-1'),
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
        overrides: <Override>[
          syncRepositoryProvider.overrideWithValue(syncRepository),
          selectedMatterIdProvider.overrideWith((ref) => 'matter-1'),
          selectedPhaseIdProvider.overrideWith((ref) => 'phase-start'),
          selectedNoteIdProvider.overrideWith((ref) => 'note-1'),
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
        overrides: <Override>[
          syncRepositoryProvider.overrideWithValue(syncRepository),
          selectedMatterIdProvider.overrideWith((ref) => 'matter-1'),
          selectedPhaseIdProvider.overrideWith((ref) => 'phase-start'),
          selectedNoteIdProvider.overrideWith((ref) => 'note-1'),
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
        overrides: <Override>[
          selectedMatterIdProvider.overrideWith((ref) => 'matter-1'),
          selectedPhaseIdProvider.overrideWith((ref) => 'phase-start'),
          selectedNoteIdProvider.overrideWith((ref) => 'note-1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<MatterViewMode>), findsOneWidget);
    expect(
      find.byKey(const Key('macos_matter_mode_segmented_control')),
      findsNothing,
    );
  });
}

Widget _buildApp({
  required bool useMacOSNativeUI,
  required _TestRepos repos,
  List<Override> overrides = const <Override>[],
}) {
  final settingsRepository = _FakeSettingsRepository(
    AppSettings(
      storageRootPath: '/tmp/chronicle-test',
      clientId: 'test-client',
      syncConfig: SyncConfig.initial(),
      lastSyncAt: null,
    ),
  );

  return ProviderScope(
    overrides: <Override>[
      settingsRepositoryProvider.overrideWithValue(settingsRepository),
      matterRepositoryProvider.overrideWithValue(repos.matterRepository),
      noteRepositoryProvider.overrideWithValue(repos.noteRepository),
      linkRepositoryProvider.overrideWithValue(repos.linkRepository),
      searchRepositoryProvider.overrideWithValue(
        _MemorySearchRepository(repos.noteRepository),
      ),
      syncRepositoryProvider.overrideWithValue(_NoopSyncRepository()),
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

class _MemoryMatterRepository implements MatterRepository {
  _MemoryMatterRepository(List<Matter> matters)
    : _matters = List<Matter>.of(matters);

  final List<Matter> _matters;

  @override
  Future<Matter> createMatter({
    required String title,
    String description = '',
    String color = '#4C956C',
    String icon = 'description',
    bool isPinned = false,
  }) async {
    final now = DateTime.now().toUtc();
    final id = 'matter-${_matters.length + 1}';
    final matter = Matter(
      id: id,
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
  Future<void> moveNote({
    required String noteId,
    required String? matterId,
    required String? phaseId,
  }) async {
    final existing = _notes[noteId]!;
    _notes[noteId] = existing.copyWith(
      matterId: matterId,
      phaseId: phaseId,
      clearMatterId: matterId == null,
      clearPhaseId: phaseId == null,
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
    if (query.text.trim().isEmpty) {
      return const <NoteSearchHit>[];
    }
    final note = _noteRepository.noteById('note-2');
    if (note == null) {
      return const <NoteSearchHit>[];
    }
    return <NoteSearchHit>[
      NoteSearchHit(note: note, snippet: 'searchable content'),
    ];
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
  Future<void> openNoteInWorkspace(String noteId) async {
    openedNoteIds.add(noteId);
  }
}

void _setDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1720, 1120);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
