import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:chronicle/core/clock.dart';
import 'package:chronicle/core/file_system_utils.dart';
import 'package:chronicle/core/id_generator.dart';
import 'package:chronicle/data/local_fs/chronicle_storage_initializer.dart';
import 'package:chronicle/data/local_fs/local_matter_repository.dart';
import 'package:chronicle/data/local_fs/local_note_repository.dart';
import 'package:chronicle/data/local_fs/local_notebook_import_repository.dart';
import 'package:chronicle/data/local_fs/local_notebook_repository.dart';
import 'package:chronicle/data/local_fs/matter_file_codec.dart';
import 'package:chronicle/data/local_fs/note_file_codec.dart';
import 'package:chronicle/data/local_fs/storage_root_locator.dart';
import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/note.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/repositories/settings_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Directory rootDir;
  late FileSystemUtils fileSystemUtils;
  late StorageRootLocator storageRootLocator;
  late ChronicleStorageInitializer storageInitializer;
  late LocalNotebookRepository notebookRepository;
  late LocalNoteRepository noteRepository;
  late LocalNotebookImportRepository importRepository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'chronicle-notebook-import-test-',
    );
    rootDir = Directory('${tempDir.path}/Chronicle');

    final settingsRepository = _InMemorySettingsRepository(
      AppSettings(
        storageRootPath: rootDir.path,
        clientId: 'client-1',
        syncConfig: SyncConfig.initial(),
        lastSyncAt: null,
      ),
    );

    fileSystemUtils = const FileSystemUtils();
    storageRootLocator = StorageRootLocator(settingsRepository);
    storageInitializer = ChronicleStorageInitializer(fileSystemUtils);

    final matterRepository = LocalMatterRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: storageInitializer,
      codec: const MatterFileCodec(),
      fileSystemUtils: fileSystemUtils,
      clock: _FixedClock(DateTime.utc(2026, 1, 1, 12)),
      idGenerator: _IncrementalIdGenerator(start: 5000),
    );

    notebookRepository = LocalNotebookRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: storageInitializer,
      fileSystemUtils: fileSystemUtils,
      clock: _FixedClock(DateTime.utc(2026, 1, 1, 12)),
      idGenerator: _IncrementalIdGenerator(start: 10_000),
      noteCodec: const NoteFileCodec(),
    );

    noteRepository = LocalNoteRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: storageInitializer,
      codec: const NoteFileCodec(),
      fileSystemUtils: fileSystemUtils,
      clock: _FixedClock(DateTime.utc(2026, 1, 1, 13)),
      idGenerator: _IncrementalIdGenerator(start: 20_000),
      matterRepository: matterRepository,
      notebookRepository: notebookRepository,
    );

    importRepository = LocalNotebookImportRepository(
      storageRootLocator: storageRootLocator,
      storageInitializer: storageInitializer,
      fileSystemUtils: fileSystemUtils,
      notebookRepository: notebookRepository,
      noteFileCodec: const NoteFileCodec(),
      idGenerator: _IncrementalIdGenerator(start: 100),
      clock: _FixedClock(DateTime.utc(2026, 2, 26, 0, 0)),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('imports ENEX notes with tags, timestamps, and resources', () async {
    final imageBytes = Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2, 3, 4]);
    final hash = md5.convert(imageBytes).toString();
    final enex =
        '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE en-export SYSTEM "http://xml.evernote.com/pub/evernote-export4.dtd">
<en-export>
  <note>
    <title>Photo Note</title>
    <created>20260101T101010Z</created>
    <updated>20260102T111111Z</updated>
    <tag>travel</tag>
    <content><![CDATA[
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">
<en-note><h1>Hello</h1><p>Body <strong>bold</strong></p><en-media type="image/png" hash="$hash"/></en-note>
    ]]></content>
    <resource>
      <data encoding="base64">${base64Encode(imageBytes)}</data>
      <mime>image/png</mime>
      <resource-attributes>
        <file-name>photo.png</file-name>
      </resource-attributes>
    </resource>
  </note>
  <note>
    <title>Second Note</title>
    <created>20260103T121314Z</created>
    <updated>20260103T121314Z</updated>
    <content><![CDATA[<en-note><p>Second body</p></en-note>]]></content>
  </note>
</en-export>
''';

    final file = File('${tempDir.path}/sample.enex');
    await file.writeAsString(enex);

    final result = await importRepository.importFiles(
      sourcePaths: <String>[file.path],
    );

    expect(result.files, hasLength(1));
    expect(
      result.importedNoteCount,
      2,
      reason: result.warnings.map((warning) => warning.message).join('\n'),
    );
    expect(result.importedResourceCount, 1);
    expect(result.warningCount, 0);

    final notes = await noteRepository.listNotebookNotes(folderId: null);
    expect(notes, hasLength(2));
    final byTitle = <String, Note>{for (final note in notes) note.title: note};

    final photo = byTitle['Photo Note'];
    expect(photo, isNotNull);
    expect(photo!.tags, equals(<String>['travel']));
    expect(photo.createdAt, DateTime.utc(2026, 1, 1, 10, 10, 10));
    expect(photo.updatedAt, DateTime.utc(2026, 1, 2, 11, 11, 11));
    expect(photo.attachments, hasLength(1));
    expect(photo.attachments.first, startsWith('resources/${photo.id}/'));
    expect(photo.content, contains('![photo.png]('));
    expect(photo.content, contains(photo.attachments.first));
  });

  test('imports ENEX with html fallback for unsupported blocks', () async {
    final enex = '''
<?xml version="1.0" encoding="UTF-8"?>
<en-export>
  <note>
    <title>Table Note</title>
    <created>20260101T101010Z</created>
    <updated>20260101T101010Z</updated>
    <content><![CDATA[<en-note><table><tr><td>A</td></tr></table></en-note>]]></content>
  </note>
</en-export>
''';

    final file = File('${tempDir.path}/table.enex');
    await file.writeAsString(enex);

    final result = await importRepository.importFiles(
      sourcePaths: <String>[file.path],
    );

    expect(
      result.importedNoteCount,
      1,
      reason: result.warnings.map((warning) => warning.message).join('\n'),
    );
    final notes = await noteRepository.listNotebookNotes(folderId: null);
    expect(notes, hasLength(1));
    expect(notes.single.content, contains('<table>'));
  });

  test(
    'imports JEX with hierarchy, tags, resource rewrite, and note links',
    () async {
      final resourceBytes = Uint8List.fromList(<int>[1, 3, 3, 7, 9]);
      final jexFile = File('${tempDir.path}/sample.jex');
      await jexFile.writeAsBytes(
        _buildJexArchive(<String, List<int>>{
          'folder_root.json': utf8.encode(
            json.encode(<String, dynamic>{
              'id': 'f1',
              'type_': 2,
              'title': 'Projects',
              'parent_id': '',
            }),
          ),
          'folder_sub.json': utf8.encode(
            json.encode(<String, dynamic>{
              'id': 'f2',
              'type_': 2,
              'title': 'Sub',
              'parent_id': 'f1',
            }),
          ),
          'note_alpha.json': utf8.encode(
            json.encode(<String, dynamic>{
              'id': 'n1',
              'type_': 1,
              'title': 'Alpha',
              'parent_id': 'f2',
              'body': '# Alpha',
              'created_time': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
              'updated_time': DateTime.utc(2026, 1, 2).millisecondsSinceEpoch,
            }),
          ),
          'note_beta.json': utf8.encode(
            json.encode(<String, dynamic>{
              'id': 'n2',
              'type_': 1,
              'title': 'Beta',
              'parent_id': 'f2',
              'body': 'Link to [alpha](:/n1) and ![](:/r1)',
              'created_time': DateTime.utc(2026, 1, 3).millisecondsSinceEpoch,
              'updated_time': DateTime.utc(2026, 1, 4).millisecondsSinceEpoch,
            }),
          ),
          'resource_r1.json': utf8.encode(
            json.encode(<String, dynamic>{
              'id': 'r1',
              'type_': 4,
              'title': 'chart',
              'mime': 'image/png',
              'filename': 'chart.png',
            }),
          ),
          'resources/r1': resourceBytes,
          'tag_t1.json': utf8.encode(
            json.encode(<String, dynamic>{
              'id': 't1',
              'type_': 5,
              'title': 'research',
            }),
          ),
          'note_tag_nt1.json': utf8.encode(
            json.encode(<String, dynamic>{
              'id': 'nt1',
              'type_': 6,
              'note_id': 'n1',
              'tag_id': 't1',
            }),
          ),
        }),
      );

      final result = await importRepository.importFiles(
        sourcePaths: <String>[jexFile.path],
      );

      expect(result.importedNoteCount, 2);
      expect(result.importedFolderCount, 2);
      expect(result.importedResourceCount, 1);

      final folders = await notebookRepository.listFolders();
      expect(
        folders.map((folder) => folder.name),
        containsAll(<String>['Projects', 'Sub']),
      );
      final subFolder = folders.firstWhere((folder) => folder.name == 'Sub');

      final subNotes = await noteRepository.listNotebookNotes(
        folderId: subFolder.id,
      );
      expect(subNotes, hasLength(2));
      final byTitle = <String, Note>{
        for (final note in subNotes) note.title: note,
      };

      final alpha = byTitle['Alpha']!;
      final beta = byTitle['Beta']!;
      expect(alpha.tags, equals(<String>['research']));
      expect(beta.attachments, hasLength(1));
      expect(beta.content, contains('chronicle://note/${alpha.id}'));
      expect(beta.content, contains(beta.attachments.first));
      expect(beta.attachments.first, startsWith('resources/${beta.id}/'));
    },
  );

  test('imports JEX raw markdown items without JSON sidecars', () async {
    final resourceBytes = Uint8List.fromList(<int>[8, 6, 7, 5, 3, 0, 9]);
    final jexFile = File('${tempDir.path}/raw-items.jex');
    await jexFile.writeAsBytes(
      _buildJexArchive(<String, List<int>>{
        'f1.md': utf8.encode('''
Projects

id: f1
parent_id: 
type_: 2
'''),
        'f2.md': utf8.encode('''
Sub

id: f2
parent_id: f1
type_: 2
'''),
        'n1.md': utf8.encode('''
Alpha

# Alpha body

id: n1
parent_id: f2
created_time: 2026-01-01T00:00:00.000Z
updated_time: 2026-01-02T00:00:00.000Z
type_: 1
'''),
        'n2.md': utf8.encode('''
Beta

Link to [alpha](:/n1) and ![](:/r1)

id: n2
parent_id: f2
created_time: 2026-01-03T00:00:00.000Z
updated_time: 2026-01-04T00:00:00.000Z
type_: 1
'''),
        'r1.md': utf8.encode('''
chart

id: r1
mime: image/png
filename: chart.png
type_: 4
'''),
        'resources/r1.png': resourceBytes,
        't1.md': utf8.encode('''
research

id: t1
type_: 5
'''),
        'nt1.md': utf8.encode('''
id: nt1
note_id: n1
tag_id: t1
type_: 6
'''),
      }),
    );

    final result = await importRepository.importFiles(
      sourcePaths: <String>[jexFile.path],
    );

    expect(result.importedNoteCount, 2);
    expect(result.importedFolderCount, 2);
    expect(result.importedResourceCount, 1);

    final folders = await notebookRepository.listFolders();
    expect(
      folders.map((folder) => folder.name),
      containsAll(<String>['Projects', 'Sub']),
    );
    final subFolder = folders.firstWhere((folder) => folder.name == 'Sub');
    final subNotes = await noteRepository.listNotebookNotes(
      folderId: subFolder.id,
    );
    expect(subNotes, hasLength(2));

    final byTitle = <String, Note>{
      for (final note in subNotes) note.title: note,
    };
    final alpha = byTitle['Alpha']!;
    final beta = byTitle['Beta']!;
    expect(alpha.tags, equals(<String>['research']));
    expect(beta.content, contains('chronicle://note/${alpha.id}'));
    expect(beta.attachments, hasLength(1));
    expect(beta.attachments.first, startsWith('resources/${beta.id}/'));
    expect(beta.content, contains(beta.attachments.first));
  });

  test('continues import when one JEX note is malformed', () async {
    final jexFile = File('${tempDir.path}/partial.jex');
    await jexFile.writeAsBytes(
      _buildJexArchive(<String, List<int>>{
        'folder.json': utf8.encode(
          json.encode(<String, dynamic>{
            'id': 'f1',
            'type_': 2,
            'title': 'Root',
            'parent_id': '',
          }),
        ),
        'good_note.json': utf8.encode(
          json.encode(<String, dynamic>{
            'id': 'n1',
            'type_': 1,
            'title': 'Good',
            'parent_id': 'f1',
            'body': 'ok',
          }),
        ),
        'bad_note.json': utf8.encode(
          json.encode(<String, dynamic>{
            'type_': 1,
            'title': 'Bad',
            'parent_id': 'f1',
            'body': 'bad',
          }),
        ),
      }),
    );

    final result = await importRepository.importFiles(
      sourcePaths: <String>[jexFile.path],
    );

    expect(
      result.importedNoteCount,
      1,
      reason: result.warnings.map((warning) => warning.message).join('\n'),
    );
    expect(result.warningCount, greaterThan(0));
    final notes = await noteRepository.listAllNotes();
    expect(notes.length, 1);
    expect(notes.single.title, 'Good');
  });
}

List<int> _buildJexArchive(Map<String, List<int>> filesByPath) {
  final archive = Archive();
  for (final entry in filesByPath.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return TarEncoder().encode(archive);
}

class _InMemorySettingsRepository implements SettingsRepository {
  _InMemorySettingsRepository(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<String?> readSyncPassword() async => null;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> saveSyncPassword(String password) async {}

  @override
  Future<void> setLastSyncAt(DateTime value) async {
    _settings = _settings.copyWith(lastSyncAt: value);
  }

  @override
  Future<void> setStorageRootPath(String path) async {
    _settings = _settings.copyWith(storageRootPath: path);
  }
}

class _FixedClock implements Clock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime nowUtc() => value;
}

class _IncrementalIdGenerator implements IdGenerator {
  _IncrementalIdGenerator({int start = 1}) : _counter = start;

  int _counter;

  @override
  String newId() {
    final value = _counter;
    _counter += 1;
    return 'id-$value';
  }
}
