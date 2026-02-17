import 'dart:io';

import 'package:path_provider/path_provider.dart' as path_provider;

abstract class AppDirectories {
  Future<Directory> appSupportDirectory();
  Future<Directory> homeDirectory();
}

class FlutterAppDirectories implements AppDirectories {
  const FlutterAppDirectories();

  @override
  Future<Directory> appSupportDirectory() async {
    final directory = await path_provider.getApplicationSupportDirectory();
    return directory;
  }

  @override
  Future<Directory> homeDirectory() async {
    final path = Platform.environment['HOME'];
    if (path == null || path.isEmpty) {
      return Directory.current;
    }
    return Directory(path);
  }
}

class FixedAppDirectories implements AppDirectories {
  const FixedAppDirectories({required this.appSupport, required this.home});

  final Directory appSupport;
  final Directory home;

  @override
  Future<Directory> appSupportDirectory() async => appSupport;

  @override
  Future<Directory> homeDirectory() async => home;
}
