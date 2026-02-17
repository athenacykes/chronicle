import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/app_directories.dart';
import '../../core/file_system_utils.dart';
import '../../domain/entities/note_search_hit.dart';
import '../../domain/entities/search_query.dart';
import '../../domain/repositories/matter_repository.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/repositories/search_repository.dart';

class SqliteSearchRepository implements SearchRepository {
  SqliteSearchRepository({
    required AppDirectories appDirectories,
    required FileSystemUtils fileSystemUtils,
    required MatterRepository matterRepository,
    required NoteRepository noteRepository,
  }) : _appDirectories = appDirectories,
       _fileSystemUtils = fileSystemUtils,
       _matterRepository = matterRepository,
       _noteRepository = noteRepository {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final AppDirectories _appDirectories;
  final FileSystemUtils _fileSystemUtils;
  final MatterRepository _matterRepository;
  final NoteRepository _noteRepository;

  Database? _database;

  @override
  Future<void> rebuildIndex() async {
    final db = await _db();
    final notes = await _noteRepository.listAllNotes();
    final matters = await _matterRepository.listMatters();

    await db.transaction((txn) async {
      await txn.delete('notes_index');
      await txn.delete('note_tags');
      await txn.delete('matters_index');
      await txn.delete('fts_notes');

      for (final matter in matters) {
        await txn.insert('matters_index', <String, Object?>{
          'matter_id': matter.id,
          'title': matter.title,
          'status': matter.status.name,
          'is_pinned': matter.isPinned ? 1 : 0,
          'updated_at': matter.updatedAt.toIso8601String(),
        });
      }

      for (final note in notes) {
        final plain = _plainText(note.content);
        await txn.insert('notes_index', <String, Object?>{
          'note_id': note.id,
          'title': note.title,
          'content_plain': plain,
          'matter_id': note.matterId,
          'phase_id': note.phaseId,
          'created_at': note.createdAt.toIso8601String(),
          'updated_at': note.updatedAt.toIso8601String(),
          'is_pinned': note.isPinned ? 1 : 0,
        });

        await txn.insert('fts_notes', <String, Object?>{
          'note_id': note.id,
          'title': note.title,
          'content_plain': plain,
        });

        for (final tag in note.tags) {
          await txn.insert('note_tags', <String, Object?>{
            'note_id': note.id,
            'tag': tag,
          });
        }
      }
    });
  }

  @override
  Future<List<NoteSearchHit>> search(SearchQuery query) async {
    final db = await _db();
    final sql = StringBuffer(
      'SELECT n.note_id, n.content_plain FROM notes_index n WHERE 1=1',
    );
    final args = <Object?>[];

    if (query.text.trim().isNotEmpty) {
      sql.write(
        ' AND n.note_id IN '
        '(SELECT note_id FROM fts_notes WHERE fts_notes MATCH ?)',
      );
      args.add(query.text.trim());
    }

    if (query.matterId != null && query.matterId!.isNotEmpty) {
      sql.write(' AND n.matter_id = ?');
      args.add(query.matterId);
    }

    if (query.from != null) {
      sql.write(' AND n.updated_at >= ?');
      args.add(query.from!.toUtc().toIso8601String());
    }

    if (query.to != null) {
      sql.write(' AND n.updated_at <= ?');
      args.add(query.to!.toUtc().toIso8601String());
    }

    for (final tag in query.tags) {
      sql.write(
        ' AND EXISTS (SELECT 1 FROM note_tags t '
        'WHERE t.note_id = n.note_id AND t.tag = ?)',
      );
      args.add(tag);
    }

    sql.write(' ORDER BY n.updated_at DESC LIMIT 200');

    final rows = await db.rawQuery(sql.toString(), args);
    final hits = <NoteSearchHit>[];
    for (final row in rows) {
      final noteId = row['note_id'] as String;
      final note = await _noteRepository.getNoteById(noteId);
      if (note == null) {
        continue;
      }
      final plain = (row['content_plain'] as String?) ?? '';
      final snippet = _snippet(plain, query.text);
      hits.add(NoteSearchHit(note: note, snippet: snippet));
    }

    return hits;
  }

  @override
  Future<List<String>> listTags() async {
    final db = await _db();
    final rows = await db.rawQuery(
      'SELECT DISTINCT tag FROM note_tags ORDER BY tag COLLATE NOCASE ASC',
    );
    return rows.map((row) => row['tag'] as String).toList();
  }

  Future<Database> _db() async {
    if (_database != null) {
      return _database!;
    }

    final appSupport = await _appDirectories.appSupportDirectory();
    await _fileSystemUtils.ensureDirectory(appSupport);
    final dbPath = p.join(appSupport.path, 'chronicle_index.sqlite');

    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE notes_index('
          'note_id TEXT PRIMARY KEY, '
          'title TEXT NOT NULL, '
          'content_plain TEXT NOT NULL, '
          'matter_id TEXT, '
          'phase_id TEXT, '
          'created_at TEXT NOT NULL, '
          'updated_at TEXT NOT NULL, '
          'is_pinned INTEGER NOT NULL'
          ')',
        );

        await db.execute(
          'CREATE TABLE note_tags('
          'note_id TEXT NOT NULL, '
          'tag TEXT NOT NULL'
          ')',
        );

        await db.execute(
          'CREATE INDEX idx_note_tags_note_id ON note_tags(note_id)',
        );
        await db.execute('CREATE INDEX idx_note_tags_tag ON note_tags(tag)');

        await db.execute(
          'CREATE TABLE matters_index('
          'matter_id TEXT PRIMARY KEY, '
          'title TEXT NOT NULL, '
          'status TEXT NOT NULL, '
          'is_pinned INTEGER NOT NULL, '
          'updated_at TEXT NOT NULL'
          ')',
        );

        await db.execute(
          'CREATE VIRTUAL TABLE fts_notes '
          'USING fts5(note_id UNINDEXED, title, content_plain)',
        );
      },
    );

    return _database!;
  }

  String _plainText(String markdown) {
    return markdown
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'`[^`]*`'), ' ')
        .replaceAll(RegExp(r'[#>*_\-\[\]()!]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _snippet(String plain, String searchText) {
    if (plain.isEmpty) {
      return '';
    }

    if (searchText.trim().isEmpty) {
      return plain.length <= 180 ? plain : '${plain.substring(0, 180)}...';
    }

    final lower = plain.toLowerCase();
    final needle = searchText.toLowerCase();
    final index = lower.indexOf(needle);
    if (index == -1) {
      return plain.length <= 180 ? plain : '${plain.substring(0, 180)}...';
    }

    final start = (index - 60).clamp(0, plain.length);
    final end = (index + needle.length + 80).clamp(0, plain.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < plain.length ? '...' : '';
    return '$prefix${plain.substring(start, end)}$suffix';
  }
}
