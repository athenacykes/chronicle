import 'dart:io';

class FileSystemUtils {
  const FileSystemUtils();

  Future<void> ensureDirectory(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  Future<void> atomicWriteString(File file, String content) async {
    await ensureDirectory(file.parent);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(content, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }

  Future<void> atomicWriteBytes(File file, List<int> bytes) async {
    await ensureDirectory(file.parent);
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }

  Future<void> deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<List<File>> listFilesRecursively(Directory root) async {
    if (!await root.exists()) {
      return <File>[];
    }

    final result = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        result.add(entity);
      }
    }
    return result;
  }

  Future<void> moveFile(File from, File to) async {
    await ensureDirectory(to.parent);
    if (await to.exists()) {
      await to.delete();
    }
    await from.rename(to.path);
  }
}
