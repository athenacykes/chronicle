import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../core/clock.dart';
import '../../core/file_system_utils.dart';
import '../../core/id_generator.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/notebook_folder.dart';
import '../../domain/entities/notebook_import_result.dart';
import '../../domain/repositories/notebook_import_repository.dart';
import '../../domain/repositories/notebook_repository.dart';
import 'chronicle_layout.dart';
import 'chronicle_storage_initializer.dart';
import 'note_file_codec.dart';
import 'storage_root_locator.dart';

class LocalNotebookImportRepository implements NotebookImportRepository {
  LocalNotebookImportRepository({
    required StorageRootLocator storageRootLocator,
    required ChronicleStorageInitializer storageInitializer,
    required FileSystemUtils fileSystemUtils,
    required NotebookRepository notebookRepository,
    required NoteFileCodec noteFileCodec,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _storageRootLocator = storageRootLocator,
       _storageInitializer = storageInitializer,
       _fileSystemUtils = fileSystemUtils,
       _notebookRepository = notebookRepository,
       _noteFileCodec = noteFileCodec,
       _idGenerator = idGenerator,
       _clock = clock;

  final StorageRootLocator _storageRootLocator;
  final ChronicleStorageInitializer _storageInitializer;
  final FileSystemUtils _fileSystemUtils;
  final NotebookRepository _notebookRepository;
  final NoteFileCodec _noteFileCodec;
  final IdGenerator _idGenerator;
  final Clock _clock;

  @override
  Future<NotebookImportBatchResult> importFiles({
    required List<String> sourcePaths,
  }) async {
    final normalizedPaths = sourcePaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (normalizedPaths.isEmpty) {
      return const NotebookImportBatchResult(
        files: <NotebookImportFileResult>[],
      );
    }

    final results = <NotebookImportFileResult>[];
    for (final sourcePath in normalizedPaths) {
      try {
        results.add(await _importSingleFile(sourcePath));
      } catch (error) {
        results.add(
          NotebookImportFileResult(
            sourcePath: sourcePath,
            importedNoteCount: 0,
            importedFolderCount: 0,
            importedResourceCount: 0,
            warnings: <NotebookImportWarning>[
              NotebookImportWarning(
                sourcePath: sourcePath,
                message: 'Import failed: $error',
              ),
            ],
          ),
        );
      }
    }

    return NotebookImportBatchResult(files: results);
  }

  Future<NotebookImportFileResult> _importSingleFile(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return NotebookImportFileResult(
        sourcePath: sourcePath,
        importedNoteCount: 0,
        importedFolderCount: 0,
        importedResourceCount: 0,
        warnings: <NotebookImportWarning>[
          NotebookImportWarning(
            sourcePath: sourcePath,
            message: 'Source file does not exist.',
          ),
        ],
      );
    }

    final extension = p.extension(sourcePath).toLowerCase();
    if (extension == '.enex') {
      return _importEnexFile(sourceFile);
    }
    if (extension == '.jex') {
      return _importJexFile(sourceFile);
    }

    return NotebookImportFileResult(
      sourcePath: sourcePath,
      importedNoteCount: 0,
      importedFolderCount: 0,
      importedResourceCount: 0,
      warnings: <NotebookImportWarning>[
        NotebookImportWarning(
          sourcePath: sourcePath,
          message: 'Unsupported import format: $extension',
        ),
      ],
    );
  }

  Future<NotebookImportFileResult> _importEnexFile(File sourceFile) async {
    final sourcePath = sourceFile.path;
    final warnings = <NotebookImportWarning>[];
    final layout = await _layout();
    final folderResolver = await _newFolderResolver();
    final now = _clock.nowUtc();

    String raw;
    try {
      raw = await sourceFile.readAsString();
    } catch (error) {
      return NotebookImportFileResult(
        sourcePath: sourcePath,
        importedNoteCount: 0,
        importedFolderCount: 0,
        importedResourceCount: 0,
        warnings: <NotebookImportWarning>[
          NotebookImportWarning(
            sourcePath: sourcePath,
            message: 'Unable to read ENEX file: $error',
          ),
        ],
      );
    }

    XmlDocument document;
    try {
      document = XmlDocument.parse(raw);
    } catch (error) {
      return NotebookImportFileResult(
        sourcePath: sourcePath,
        importedNoteCount: 0,
        importedFolderCount: 0,
        importedResourceCount: 0,
        warnings: <NotebookImportWarning>[
          NotebookImportWarning(
            sourcePath: sourcePath,
            message: 'Invalid ENEX XML: $error',
          ),
        ],
      );
    }

    var importedNotes = 0;
    var importedResources = 0;
    for (final noteElement in document.findAllElements('note')) {
      final noteTitle = _directChildText(noteElement, 'title').trim().isEmpty
          ? 'Untitled Note'
          : _directChildText(noteElement, 'title').trim();
      final noteId = _idGenerator.newId();
      final createdAt = _parseEnexDate(
        _directChildText(noteElement, 'created'),
        defaultValue: now,
      );
      final updatedAt = _parseEnexDate(
        _directChildText(noteElement, 'updated'),
        defaultValue: createdAt,
      );
      final tags = noteElement
          .findElements('tag')
          .map((tag) => tag.innerText.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList(growable: false);

      final resourceRefs = <String, _ImportedResourceRef>{};
      final attachments = <String>[];

      try {
        final resources = noteElement.findElements('resource').toList();
        for (var i = 0; i < resources.length; i++) {
          final resource = resources[i];
          final dataElement = resource.getElement('data');
          final dataEncoding =
              dataElement?.getAttribute('encoding')?.trim().toLowerCase() ??
              'base64';
          if (dataElement == null) {
            warnings.add(
              NotebookImportWarning(
                sourcePath: sourcePath,
                itemId: noteId,
                message: 'Skipped ENEX resource with no <data>.',
              ),
            );
            continue;
          }
          if (dataEncoding != 'base64') {
            warnings.add(
              NotebookImportWarning(
                sourcePath: sourcePath,
                itemId: noteId,
                message:
                    'Skipped ENEX resource with unsupported encoding "$dataEncoding".',
              ),
            );
            continue;
          }

          Uint8List decodedBytes;
          try {
            final compactData = dataElement.innerText.replaceAll(
              RegExp(r'\s+'),
              '',
            );
            decodedBytes = Uint8List.fromList(base64Decode(compactData));
          } catch (error) {
            warnings.add(
              NotebookImportWarning(
                sourcePath: sourcePath,
                itemId: noteId,
                message: 'Failed to decode ENEX resource: $error',
              ),
            );
            continue;
          }

          final mime = _directChildText(resource, 'mime').trim();
          final attributes = resource.getElement('resource-attributes');
          final fileName = attributes
              ?.getElement('file-name')
              ?.innerText
              .trim();
          final fallbackName = _defaultResourceFileName(
            mime: mime,
            hash: md5.convert(decodedBytes).toString(),
          );
          final relativePath = await _writeResourceBytes(
            layout: layout,
            noteId: noteId,
            originalName: fileName ?? fallbackName,
            bytes: decodedBytes,
            sequence: i,
          );
          attachments.add(relativePath);
          importedResources += 1;
          resourceRefs[md5
              .convert(decodedBytes)
              .toString()] = _ImportedResourceRef(
            relativePath: relativePath,
            mime: mime,
            label: fileName ?? fallbackName,
          );
        }

        final contentXml = _directChildText(noteElement, 'content');
        final markdown = _convertEnexContentToMarkdown(
          enml: contentXml,
          resourceRefs: resourceRefs,
          warnings: warnings,
          sourcePath: sourcePath,
          noteId: noteId,
        );
        await _writeImportedNotebookNote(
          layout: layout,
          noteId: noteId,
          folderId: null,
          title: noteTitle,
          body: markdown,
          tags: tags,
          attachments: attachments,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );
        importedNotes += 1;
      } catch (error) {
        warnings.add(
          NotebookImportWarning(
            sourcePath: sourcePath,
            itemId: noteId,
            message: 'Failed to import ENEX note "$noteTitle": $error',
          ),
        );
      }
    }

    return NotebookImportFileResult(
      sourcePath: sourcePath,
      importedNoteCount: importedNotes,
      importedFolderCount: folderResolver.createdCount,
      importedResourceCount: importedResources,
      warnings: warnings,
    );
  }

  Future<NotebookImportFileResult> _importJexFile(File sourceFile) async {
    final sourcePath = sourceFile.path;
    final warnings = <NotebookImportWarning>[];
    final layout = await _layout();
    final folderResolver = await _newFolderResolver();
    final now = _clock.nowUtc();

    final tempDir = await Directory.systemTemp.createTemp('chronicle-jex-');
    try {
      final archiveBytes = await sourceFile.readAsBytes();
      Archive archive;
      try {
        archive = TarDecoder().decodeBytes(archiveBytes);
      } catch (error) {
        return NotebookImportFileResult(
          sourcePath: sourcePath,
          importedNoteCount: 0,
          importedFolderCount: 0,
          importedResourceCount: 0,
          warnings: <NotebookImportWarning>[
            NotebookImportWarning(
              sourcePath: sourcePath,
              message: 'Failed to extract JEX archive: $error',
            ),
          ],
        );
      }

      final extractedFilesByRelativePath = <String, File>{};
      for (final entry in archive) {
        if (!entry.isFile) {
          continue;
        }
        final relativePath = _normalizeArchiveEntryPath(entry.name);
        if (relativePath == null) {
          warnings.add(
            NotebookImportWarning(
              sourcePath: sourcePath,
              message: 'Skipped unsafe archive entry: ${entry.name}',
            ),
          );
          continue;
        }

        final target = File(p.join(tempDir.path, relativePath));
        await _fileSystemUtils.ensureDirectory(target.parent);
        await _fileSystemUtils.atomicWriteBytes(
          target,
          _archiveEntryBytes(entry),
        );
        extractedFilesByRelativePath[relativePath] = target;
      }

      final parsed = await _parseJexItems(
        sourcePath: sourcePath,
        filesByRelativePath: extractedFilesByRelativePath,
        warnings: warnings,
      );

      final folderIdByOldId = <String, String?>{};
      Future<String?> ensureFolder(String? oldFolderId) async {
        final trimmed = oldFolderId?.trim();
        if (trimmed == null || trimmed.isEmpty) {
          return null;
        }
        if (folderIdByOldId.containsKey(trimmed)) {
          return folderIdByOldId[trimmed];
        }
        final folder = parsed.foldersById[trimmed];
        if (folder == null) {
          folderIdByOldId[trimmed] = null;
          return null;
        }
        final parentId = await ensureFolder(folder.parentId);
        final created = await folderResolver.ensureFolder(
          folder.title.trim().isEmpty ? 'Untitled Folder' : folder.title.trim(),
          parentId: parentId,
        );
        folderIdByOldId[trimmed] = created;
        return created;
      }

      for (final folderId in parsed.foldersById.keys) {
        await ensureFolder(folderId);
      }

      final newNoteIdByOldId = <String, String>{
        for (final noteId in parsed.notesById.keys)
          noteId: _idGenerator.newId(),
      };

      var importedNotes = 0;
      var importedResources = 0;

      final sortedNotes = parsed.notesById.values.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      for (final note in sortedNotes) {
        final newNoteId = newNoteIdByOldId[note.id];
        if (newNoteId == null) {
          warnings.add(
            NotebookImportWarning(
              sourcePath: sourcePath,
              itemId: note.id,
              message: 'Skipped note because no mapped destination id exists.',
            ),
          );
          continue;
        }

        try {
          final folderId = await ensureFolder(note.parentId);
          final originalBody = note.body.trim().isNotEmpty
              ? note.body
              : '# ${note.title}\n';
          final rewritten = await _rewriteJoplinLinksAndResources(
            sourcePath: sourcePath,
            oldNoteId: note.id,
            newNoteId: newNoteId,
            originalBody: originalBody,
            resourceById: parsed.resourcesById,
            resourceBinaryPathById: parsed.resourceBinaryPathById,
            newNoteIdByOldId: newNoteIdByOldId,
            layout: layout,
            warnings: warnings,
          );
          importedResources += rewritten.importedResourceCount;

          final tagIds = parsed.tagIdsByNoteId[note.id] ?? const <String>{};
          final tags = tagIds
              .map((tagId) => parsed.tagsById[tagId]?.title.trim() ?? '')
              .where((title) => title.isNotEmpty)
              .toSet()
              .toList(growable: false);

          await _writeImportedNotebookNote(
            layout: layout,
            noteId: newNoteId,
            folderId: folderId,
            title: note.title.trim().isEmpty
                ? 'Untitled Note'
                : note.title.trim(),
            body: rewritten.body,
            tags: tags,
            attachments: rewritten.attachments,
            createdAt: note.createdAt ?? now,
            updatedAt: note.updatedAt ?? note.createdAt ?? now,
          );

          importedNotes += 1;
        } catch (error) {
          warnings.add(
            NotebookImportWarning(
              sourcePath: sourcePath,
              itemId: note.id,
              message: 'Failed to import JEX note "${note.title}": $error',
            ),
          );
        }
      }

      return NotebookImportFileResult(
        sourcePath: sourcePath,
        importedNoteCount: importedNotes,
        importedFolderCount: folderResolver.createdCount,
        importedResourceCount: importedResources,
        warnings: warnings,
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<_ParsedJexItems> _parseJexItems({
    required String sourcePath,
    required Map<String, File> filesByRelativePath,
    required List<NotebookImportWarning> warnings,
  }) async {
    final foldersById = <String, _JexFolder>{};
    final notesById = <String, _JexNote>{};
    final resourcesById = <String, _JexResource>{};
    final tagsById = <String, _JexTag>{};
    final tagIdsByNoteId = <String, Set<String>>{};
    final resourceBinaryPathById = <String, String>{};

    final markdownBodyByNoteId = <String, String>{};
    for (final entry in filesByRelativePath.entries) {
      final relativePath = entry.key;
      final lowerExt = p.extension(relativePath).toLowerCase();
      if (lowerExt == '.md') {
        final basename = p.basenameWithoutExtension(relativePath);
        try {
          markdownBodyByNoteId[basename] = await entry.value.readAsString();
        } catch (_) {
          // Ignore markdown read errors here; json body may still exist.
        }
      }
    }

    for (final entry in filesByRelativePath.entries) {
      final relativePath = entry.key;
      if (p.extension(relativePath).toLowerCase() != '.json') {
        continue;
      }

      Map<String, dynamic> jsonMap;
      try {
        final raw = await entry.value.readAsString();
        final parsed = json.decode(raw);
        if (parsed is! Map<String, dynamic>) {
          throw const FormatException('JSON root is not an object.');
        }
        jsonMap = parsed;
      } catch (error) {
        warnings.add(
          NotebookImportWarning(
            sourcePath: sourcePath,
            message: 'Skipped malformed JEX JSON "$relativePath": $error',
          ),
        );
        continue;
      }

      final itemType = _asInt(jsonMap['type_']);
      final itemId = _asString(jsonMap['id']).trim();
      if (itemType == null || itemId.isEmpty) {
        warnings.add(
          NotebookImportWarning(
            sourcePath: sourcePath,
            message:
                'Skipped JEX item with missing id/type in "$relativePath".',
          ),
        );
        continue;
      }

      switch (itemType) {
        case 1:
          final bodyFromJson = _asString(jsonMap['body']);
          final noteBody = bodyFromJson.trim().isEmpty
              ? (markdownBodyByNoteId[itemId] ?? '')
              : bodyFromJson;
          notesById[itemId] = _JexNote(
            id: itemId,
            parentId: _asString(jsonMap['parent_id']).trim(),
            title: _asString(jsonMap['title']),
            body: noteBody,
            createdAt: _parseMillisTimestamp(
              jsonMap['user_created_time'] ?? jsonMap['created_time'],
            ),
            updatedAt: _parseMillisTimestamp(
              jsonMap['user_updated_time'] ?? jsonMap['updated_time'],
            ),
          );
          break;
        case 2:
          foldersById[itemId] = _JexFolder(
            id: itemId,
            parentId: _asString(jsonMap['parent_id']).trim(),
            title: _asString(jsonMap['title']),
          );
          break;
        case 4:
          resourcesById[itemId] = _JexResource(
            id: itemId,
            title: _asString(jsonMap['title']),
            mime: _asString(jsonMap['mime']),
            fileName: _asString(jsonMap['filename']),
          );
          break;
        case 5:
          tagsById[itemId] = _JexTag(
            id: itemId,
            title: _asString(jsonMap['title']),
          );
          break;
        case 6:
          final noteId = _asString(jsonMap['note_id']).trim();
          final tagId = _asString(jsonMap['tag_id']).trim();
          if (noteId.isNotEmpty && tagId.isNotEmpty) {
            tagIdsByNoteId.putIfAbsent(noteId, () => <String>{}).add(tagId);
          }
          break;
      }
    }

    for (final resourceId in resourcesById.keys) {
      final resolved = _resolveJexResourceBinaryPath(
        resourceId: resourceId,
        filesByRelativePath: filesByRelativePath,
      );
      if (resolved != null) {
        resourceBinaryPathById[resourceId] = resolved;
      }
    }

    return _ParsedJexItems(
      foldersById: foldersById,
      notesById: notesById,
      resourcesById: resourcesById,
      tagsById: tagsById,
      tagIdsByNoteId: tagIdsByNoteId,
      resourceBinaryPathById: resourceBinaryPathById,
    );
  }

  Future<_RewriteResult> _rewriteJoplinLinksAndResources({
    required String sourcePath,
    required String oldNoteId,
    required String newNoteId,
    required String originalBody,
    required Map<String, _JexResource> resourceById,
    required Map<String, String> resourceBinaryPathById,
    required Map<String, String> newNoteIdByOldId,
    required ChronicleLayout layout,
    required List<NotebookImportWarning> warnings,
  }) async {
    final attachments = <String>[];
    final resolvedResourcePathById = <String, String>{};
    var importedResourceCount = 0;

    final rewrittenBody = originalBody.replaceAllMapped(
      RegExp(r':/([A-Za-z0-9_-]+)'),
      (match) {
        final targetId = match.group(1) ?? '';
        if (targetId.isEmpty) {
          return match.group(0) ?? '';
        }

        final resource = resourceById[targetId];
        if (resource != null) {
          final existing = resolvedResourcePathById[targetId];
          if (existing != null) {
            return existing;
          }
          final binaryPath = resourceBinaryPathById[targetId];
          if (binaryPath == null) {
            warnings.add(
              NotebookImportWarning(
                sourcePath: sourcePath,
                itemId: oldNoteId,
                message:
                    'Resource "$targetId" referenced by note has no binary payload.',
              ),
            );
            return match.group(0) ?? '';
          }
          try {
            final bytes = File(binaryPath).readAsBytesSync();
            final fallbackName = _defaultResourceFileName(
              mime: resource.mime,
              hash: targetId,
            );
            final relativePath = _writeResourceBytesSync(
              layout: layout,
              noteId: newNoteId,
              originalName: resource.fileName.isNotEmpty
                  ? resource.fileName
                  : (resource.title.isNotEmpty ? resource.title : fallbackName),
              bytes: bytes,
              sequence: attachments.length,
            );
            resolvedResourcePathById[targetId] = relativePath;
            attachments.add(relativePath);
            importedResourceCount += 1;
            return relativePath;
          } catch (error) {
            warnings.add(
              NotebookImportWarning(
                sourcePath: sourcePath,
                itemId: oldNoteId,
                message: 'Failed to materialize resource "$targetId": $error',
              ),
            );
            return match.group(0) ?? '';
          }
        }

        final mappedNoteId = newNoteIdByOldId[targetId];
        if (mappedNoteId != null) {
          return 'chronicle://note/$mappedNoteId';
        }

        return match.group(0) ?? '';
      },
    );

    return _RewriteResult(
      body: rewrittenBody,
      attachments: attachments,
      importedResourceCount: importedResourceCount,
    );
  }

  String _convertEnexContentToMarkdown({
    required String enml,
    required Map<String, _ImportedResourceRef> resourceRefs,
    required List<NotebookImportWarning> warnings,
    required String sourcePath,
    required String noteId,
  }) {
    final trimmed = enml.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    XmlDocument document;
    try {
      var cleaned = trimmed;
      cleaned = cleaned.replaceAll(
        RegExp(r'<\?xml[^>]*\?>', multiLine: true),
        '',
      );
      cleaned = cleaned.replaceAll(
        RegExp(r'<!DOCTYPE[^>]*>', multiLine: true),
        '',
      );
      document = XmlDocument.parse(cleaned);
    } catch (error) {
      warnings.add(
        NotebookImportWarning(
          sourcePath: sourcePath,
          itemId: noteId,
          message: 'Failed to parse ENML content: $error',
        ),
      );
      return trimmed;
    }

    final enNote = document.findAllElements('en-note').isNotEmpty
        ? document.findAllElements('en-note').first
        : document.rootElement;
    final renderer = _EnmlToMarkdownRenderer(resourceRefs: resourceRefs);
    return renderer.renderRoot(enNote);
  }

  Future<void> _writeImportedNotebookNote({
    required ChronicleLayout layout,
    required String noteId,
    required String? folderId,
    required String title,
    required String body,
    required List<String> tags,
    required List<String> attachments,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final note = Note(
      id: noteId,
      matterId: null,
      phaseId: null,
      notebookFolderId: folderId,
      title: title,
      content: body,
      tags: tags,
      isPinned: false,
      attachments: attachments,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
    );

    final target = folderId == null
        ? layout.notebookRootNoteFile(note.id)
        : layout.notebookFolderNoteFile(folderId: folderId, noteId: note.id);
    await _fileSystemUtils.atomicWriteString(
      target,
      _noteFileCodec.encode(note),
    );
  }

  Future<String> _writeResourceBytes({
    required ChronicleLayout layout,
    required String noteId,
    required String originalName,
    required Uint8List bytes,
    required int sequence,
  }) async {
    final relativePath = _nextResourceRelativePath(
      layout: layout,
      noteId: noteId,
      originalName: originalName,
      sequence: sequence,
    );
    await _fileSystemUtils.atomicWriteBytes(
      layout.fromRelativePath(relativePath),
      bytes,
    );
    return relativePath;
  }

  String _writeResourceBytesSync({
    required ChronicleLayout layout,
    required String noteId,
    required String originalName,
    required List<int> bytes,
    required int sequence,
  }) {
    final relativePath = _nextResourceRelativePath(
      layout: layout,
      noteId: noteId,
      originalName: originalName,
      sequence: sequence,
    );
    final file = layout.fromRelativePath(relativePath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes, flush: true);
    return relativePath;
  }

  String _nextResourceRelativePath({
    required ChronicleLayout layout,
    required String noteId,
    required String originalName,
    required int sequence,
  }) {
    final sanitizedName = _sanitizeFileName(originalName);
    final stamp = _clock.nowUtc().millisecondsSinceEpoch;
    var attempt = 0;

    while (true) {
      final suffix = attempt == 0
          ? '${stamp}_${sequence}_$sanitizedName'
          : '${stamp}_${sequence}_${attempt}_$sanitizedName';
      final relativePath = p.posix.join('resources', noteId, suffix);
      if (!layout.fromRelativePath(relativePath).existsSync()) {
        return relativePath;
      }
      attempt += 1;
    }
  }

  String _sanitizeFileName(String input) {
    final base = p.basename(input).trim();
    final sanitized = base
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (sanitized.isEmpty) {
      return 'attachment.bin';
    }
    return sanitized;
  }

  String _defaultResourceFileName({
    required String mime,
    required String hash,
  }) {
    final extension = _defaultExtensionForMime(mime);
    if (extension.isEmpty) {
      return 'resource_$hash.bin';
    }
    return 'resource_$hash.$extension';
  }

  String _defaultExtensionForMime(String mime) {
    final normalized = mime.trim().toLowerCase();
    return switch (normalized) {
      'image/png' => 'png',
      'image/jpeg' => 'jpg',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      'application/pdf' => 'pdf',
      'text/plain' => 'txt',
      _ => '',
    };
  }

  DateTime _parseEnexDate(String value, {required DateTime defaultValue}) {
    final raw = value.trim();
    if (raw.isEmpty) {
      return defaultValue.toUtc();
    }

    final normalMatch = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{1,2})(\d{2})(\d{2})Z$',
    ).firstMatch(raw);
    if (normalMatch != null) {
      return DateTime.utc(
        int.parse(normalMatch.group(1)!),
        int.parse(normalMatch.group(2)!),
        int.parse(normalMatch.group(3)!),
        int.parse(normalMatch.group(4)!),
        int.parse(normalMatch.group(5)!),
        int.parse(normalMatch.group(6)!),
      );
    }

    final amPmMatch = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{1,2})(\d{2})(\d{2})\s*([AP]M)Z$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (amPmMatch != null) {
      var hour = int.parse(amPmMatch.group(4)!);
      final marker = amPmMatch.group(7)!.toUpperCase();
      if (marker == 'PM' && hour < 12) {
        hour += 12;
      }
      if (marker == 'AM' && hour == 12) {
        hour = 0;
      }
      return DateTime.utc(
        int.parse(amPmMatch.group(1)!),
        int.parse(amPmMatch.group(2)!),
        int.parse(amPmMatch.group(3)!),
        hour,
        int.parse(amPmMatch.group(5)!),
        int.parse(amPmMatch.group(6)!),
      );
    }

    try {
      return DateTime.parse(raw).toUtc();
    } catch (_) {
      return defaultValue.toUtc();
    }
  }

  DateTime? _parseMillisTimestamp(dynamic value) {
    final millis = _asInt(value);
    if (millis == null || millis <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  String _directChildText(XmlElement parent, String childName) {
    final child = parent.getElement(childName);
    return child?.innerText ?? '';
  }

  Uint8List _archiveEntryBytes(ArchiveFile entry) {
    final content = entry.content as List<int>;
    return Uint8List.fromList(content);
  }

  String? _normalizeArchiveEntryPath(String rawPath) {
    final normalized = rawPath.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) {
      return null;
    }

    final posixPath = p.posix.normalize(normalized);
    if (posixPath == '.' ||
        posixPath == '..' ||
        posixPath.startsWith('../') ||
        posixPath.contains('/../') ||
        posixPath.startsWith('/')) {
      return null;
    }
    return posixPath;
  }

  String? _resolveJexResourceBinaryPath({
    required String resourceId,
    required Map<String, File> filesByRelativePath,
  }) {
    final candidateNames = <String>[
      resourceId,
      '$resourceId.bin',
      'resources/$resourceId',
      'resources/$resourceId.bin',
    ];
    for (final candidate in candidateNames) {
      final file = filesByRelativePath[candidate];
      if (file != null) {
        return file.path;
      }
    }

    for (final entry in filesByRelativePath.entries) {
      final basename = p.basename(entry.key);
      if (basename == resourceId || basename.startsWith('$resourceId.')) {
        if (p.extension(basename).toLowerCase() == '.json') {
          continue;
        }
        return entry.value.path;
      }
    }

    return null;
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  String _asString(dynamic value) {
    if (value == null) {
      return '';
    }
    return '$value';
  }

  Future<ChronicleLayout> _layout() async {
    final root = await _storageRootLocator.requireRootDirectory();
    await _storageInitializer.ensureInitialized(root);
    return ChronicleLayout(root);
  }

  Future<_FolderResolver> _newFolderResolver() async {
    final folders = await _notebookRepository.listFolders();
    return _FolderResolver(_notebookRepository, folders);
  }
}

class _FolderResolver {
  _FolderResolver(this._repository, List<NotebookFolder> existingFolders)
    : _folderIdByKey = <String, String>{} {
    for (final folder in existingFolders) {
      _folderIdByKey[_key(folder.parentId, folder.name)] = folder.id;
    }
  }

  final NotebookRepository _repository;
  final Map<String, String> _folderIdByKey;
  int createdCount = 0;

  Future<String> ensureFolder(String name, {String? parentId}) async {
    final trimmed = name.trim().isEmpty ? 'Untitled Folder' : name.trim();
    final key = _key(parentId, trimmed);
    final existing = _folderIdByKey[key];
    if (existing != null) {
      return existing;
    }

    try {
      final created = await _repository.createFolder(
        name: trimmed,
        parentId: parentId,
      );
      _folderIdByKey[key] = created.id;
      createdCount += 1;
      return created.id;
    } catch (_) {
      final reloaded = await _repository.listFolders();
      for (final folder in reloaded) {
        _folderIdByKey[_key(folder.parentId, folder.name)] = folder.id;
      }
      final reloadedExisting = _folderIdByKey[key];
      if (reloadedExisting != null) {
        return reloadedExisting;
      }
      rethrow;
    }
  }

  String _key(String? parentId, String name) {
    return '${parentId ?? ''}::${name.trim().toLowerCase()}';
  }
}

class _ImportedResourceRef {
  const _ImportedResourceRef({
    required this.relativePath,
    required this.mime,
    required this.label,
  });

  final String relativePath;
  final String mime;
  final String label;

  bool get isImage => mime.toLowerCase().startsWith('image/');
}

class _EnmlToMarkdownRenderer {
  const _EnmlToMarkdownRenderer({required this.resourceRefs});

  final Map<String, _ImportedResourceRef> resourceRefs;

  String renderRoot(XmlElement root) {
    final rendered = _renderNode(root, listDepth: 0).trim();
    return rendered.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  String _renderNode(XmlNode node, {required int listDepth}) {
    if (node is XmlText) {
      return node.value;
    }
    if (node is! XmlElement) {
      return '';
    }

    final name = node.name.local.toLowerCase();
    switch (name) {
      case 'en-note':
        return _renderChildren(node, listDepth: listDepth);
      case 'p':
      case 'div':
        return '${_renderChildren(node, listDepth: listDepth).trim()}\n\n';
      case 'br':
        return '\n';
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.tryParse(name.substring(1)) ?? 1;
        return '${'#' * level} ${_renderChildren(node, listDepth: listDepth).trim()}\n\n';
      case 'ul':
        return _renderList(node, ordered: false, listDepth: listDepth);
      case 'ol':
        return _renderList(node, ordered: true, listDepth: listDepth);
      case 'li':
        return _renderChildren(node, listDepth: listDepth);
      case 'strong':
      case 'b':
        return '**${_renderChildren(node, listDepth: listDepth)}**';
      case 'em':
      case 'i':
        return '*${_renderChildren(node, listDepth: listDepth)}*';
      case 'code':
        return '`${_renderChildren(node, listDepth: listDepth).replaceAll('`', '\\`')}`';
      case 'pre':
        return '```\n${node.innerText}\n```\n\n';
      case 'a':
        final href = node.getAttribute('href')?.trim() ?? '';
        final label = _renderChildren(node, listDepth: listDepth).trim();
        if (href.isEmpty) {
          return label;
        }
        return '[${label.isEmpty ? href : label}]($href)';
      case 'img':
        final src = node.getAttribute('src')?.trim() ?? '';
        final alt = node.getAttribute('alt')?.trim() ?? '';
        if (src.isEmpty) {
          return '';
        }
        return '![${alt.isEmpty ? 'image' : alt}]($src)';
      case 'en-todo':
        final checkedRaw = node.getAttribute('checked')?.trim().toLowerCase();
        final checked = checkedRaw == 'true' || checkedRaw == '1';
        return checked ? '- [x] ' : '- [ ] ';
      case 'en-media':
        final hash = node.getAttribute('hash')?.trim().toLowerCase() ?? '';
        final fallbackMime =
            node.getAttribute('type')?.trim().toLowerCase() ?? '';
        final resource = resourceRefs[hash];
        if (resource == null) {
          return node.toXmlString(pretty: false);
        }
        final label = resource.label.trim().isEmpty
            ? 'resource'
            : resource.label;
        final asImage = resource.isImage || fallbackMime.startsWith('image/');
        if (asImage) {
          return '![$label](${resource.relativePath})';
        }
        return '[$label](${resource.relativePath})';
      case 'span':
        return _renderChildren(node, listDepth: listDepth);
      default:
        return '${node.toXmlString(pretty: false)}\n\n';
    }
  }

  String _renderChildren(XmlElement element, {required int listDepth}) {
    final buffer = StringBuffer();
    for (final child in element.children) {
      buffer.write(_renderNode(child, listDepth: listDepth));
    }
    return buffer.toString();
  }

  String _renderList(
    XmlElement listElement, {
    required bool ordered,
    required int listDepth,
  }) {
    final itemElements = listElement.children
        .whereType<XmlElement>()
        .where((child) => child.name.local.toLowerCase() == 'li')
        .toList(growable: false);
    if (itemElements.isEmpty) {
      return '\n';
    }

    final buffer = StringBuffer();
    final indent = '  ' * listDepth;
    for (var i = 0; i < itemElements.length; i++) {
      final item = itemElements[i];
      final rendered = _renderChildren(item, listDepth: listDepth + 1).trim();
      final marker = ordered ? '${i + 1}.' : '-';
      if (rendered.contains('\n')) {
        final lines = rendered.split('\n');
        buffer.writeln('$indent$marker ${lines.first}');
        for (final line in lines.skip(1)) {
          buffer.writeln('$indent  $line');
        }
      } else {
        buffer.writeln('$indent$marker $rendered');
      }
    }
    buffer.writeln();
    return buffer.toString();
  }
}

class _ParsedJexItems {
  const _ParsedJexItems({
    required this.foldersById,
    required this.notesById,
    required this.resourcesById,
    required this.tagsById,
    required this.tagIdsByNoteId,
    required this.resourceBinaryPathById,
  });

  final Map<String, _JexFolder> foldersById;
  final Map<String, _JexNote> notesById;
  final Map<String, _JexResource> resourcesById;
  final Map<String, _JexTag> tagsById;
  final Map<String, Set<String>> tagIdsByNoteId;
  final Map<String, String> resourceBinaryPathById;
}

class _JexFolder {
  const _JexFolder({
    required this.id,
    required this.parentId,
    required this.title,
  });

  final String id;
  final String parentId;
  final String title;
}

class _JexNote {
  const _JexNote({
    required this.id,
    required this.parentId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String parentId;
  final String title;
  final String body;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class _JexResource {
  const _JexResource({
    required this.id,
    required this.title,
    required this.mime,
    required this.fileName,
  });

  final String id;
  final String title;
  final String mime;
  final String fileName;
}

class _JexTag {
  const _JexTag({required this.id, required this.title});

  final String id;
  final String title;
}

class _RewriteResult {
  const _RewriteResult({
    required this.body,
    required this.attachments,
    required this.importedResourceCount,
  });

  final String body;
  final List<String> attachments;
  final int importedResourceCount;
}
