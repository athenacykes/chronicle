import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/clock.dart';
import '../../core/file_system_utils.dart';
import '../../core/id_generator.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/matter.dart';
import '../../domain/repositories/matter_repository.dart';
import 'chronicle_layout.dart';
import 'chronicle_storage_initializer.dart';
import 'default_phase_factory.dart';
import 'matter_file_codec.dart';
import 'storage_root_locator.dart';

class LocalMatterRepository implements MatterRepository {
  LocalMatterRepository({
    required StorageRootLocator storageRootLocator,
    required ChronicleStorageInitializer storageInitializer,
    required MatterFileCodec codec,
    required FileSystemUtils fileSystemUtils,
    required Clock clock,
    required IdGenerator idGenerator,
  }) : _storageRootLocator = storageRootLocator,
       _storageInitializer = storageInitializer,
       _codec = codec,
       _fileSystemUtils = fileSystemUtils,
       _clock = clock,
       _idGenerator = idGenerator;

  final StorageRootLocator _storageRootLocator;
  final ChronicleStorageInitializer _storageInitializer;
  final MatterFileCodec _codec;
  final FileSystemUtils _fileSystemUtils;
  final Clock _clock;
  final IdGenerator _idGenerator;

  @override
  Future<List<Matter>> listMatters() async {
    final layout = await _layout();
    if (!await layout.mattersDirectory.exists()) {
      return <Matter>[];
    }

    final matters = <Matter>[];
    await for (final entity in layout.mattersDirectory.list()) {
      if (entity is! Directory) {
        continue;
      }
      final file = File(p.join(entity.path, 'matter.json'));
      if (!await file.exists()) {
        continue;
      }
      try {
        final raw = await file.readAsString();
        final matter = _codec.decode(raw);
        matters.add(matter);
      } catch (_) {
        continue;
      }
    }

    matters.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matters;
  }

  @override
  Future<Matter?> getMatterById(String matterId) async {
    final layout = await _layout();
    final file = layout.matterJsonFile(matterId);
    if (!await file.exists()) {
      return null;
    }

    final raw = await file.readAsString();
    return _codec.decode(raw);
  }

  @override
  Future<Matter> createMatter({
    required String title,
    String description = '',
    String? categoryId,
    String color = '#4C956C',
    String icon = 'description',
    bool isPinned = false,
  }) async {
    final now = _clock.nowUtc();
    final id = _idGenerator.newId();
    final phases = buildDefaultPhases(matterId: id, idGenerator: _idGenerator);

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
      phases: phases,
      currentPhaseId: phases.isEmpty ? null : phases.first.id,
    );

    await _writeMatter(matter);
    return matter;
  }

  @override
  Future<void> updateMatter(Matter matter) async {
    final updated = matter.copyWith(updatedAt: _clock.nowUtc());
    await _writeMatter(updated);
  }

  @override
  Future<void> setMatterStatus(String matterId, MatterStatus status) async {
    final matter = await getMatterById(matterId);
    if (matter == null) {
      return;
    }

    final now = _clock.nowUtc();
    final shouldSetEnded =
        status == MatterStatus.completed || status == MatterStatus.archived;

    final updated = matter.copyWith(
      status: status,
      updatedAt: now,
      startedAt: matter.startedAt ?? now,
      endedAt: shouldSetEnded ? now : null,
      clearEndedAt: !shouldSetEnded,
    );

    await _writeMatter(updated);
  }

  @override
  Future<void> setMatterCategory(String matterId, String? categoryId) async {
    final matter = await getMatterById(matterId);
    if (matter == null) {
      return;
    }
    await _writeMatter(
      matter.copyWith(
        categoryId: categoryId,
        clearCategoryId: categoryId == null,
        updatedAt: _clock.nowUtc(),
      ),
    );
  }

  @override
  Future<void> setMatterPinned(String matterId, bool isPinned) async {
    final matter = await getMatterById(matterId);
    if (matter == null) {
      return;
    }
    await _writeMatter(
      matter.copyWith(isPinned: isPinned, updatedAt: _clock.nowUtc()),
    );
  }

  @override
  Future<void> deleteMatter(String matterId) async {
    final layout = await _layout();
    final directory = layout.matterDirectory(matterId);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> _writeMatter(Matter matter) async {
    final hasCurrent =
        matter.currentPhaseId != null &&
        matter.phases.any((phase) => phase.id == matter.currentPhaseId);
    final normalized = hasCurrent
        ? matter
        : matter.copyWith(
            currentPhaseId: matter.phases.isEmpty
                ? null
                : matter.phases.first.id,
          );
    final layout = await _layout();
    final matterDir = layout.matterDirectory(normalized.id);
    await _fileSystemUtils.ensureDirectory(matterDir);

    for (final phase in normalized.phases) {
      await _fileSystemUtils.ensureDirectory(
        layout.phaseDirectory(normalized.id, phase.id),
      );
    }

    final file = layout.matterJsonFile(normalized.id);
    final raw = _codec.encode(normalized);
    await _fileSystemUtils.atomicWriteString(file, raw);
  }

  Future<ChronicleLayout> _layout() async {
    final root = await _storageRootLocator.requireRootDirectory();
    await _storageInitializer.ensureInitialized(root);
    return ChronicleLayout(root);
  }
}
