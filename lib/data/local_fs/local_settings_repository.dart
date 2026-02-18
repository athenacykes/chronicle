import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import '../../core/app_directories.dart';
import '../../core/file_system_utils.dart';
import '../../core/id_generator.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository({
    required AppDirectories appDirectories,
    required FileSystemUtils fileSystemUtils,
    required IdGenerator idGenerator,
    FlutterSecureStorage? secureStorage,
  }) : _appDirectories = appDirectories,
       _fileSystemUtils = fileSystemUtils,
       _idGenerator = idGenerator,
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _settingsFileName = 'chronicle_settings.json';
  static const _syncPasswordKey = 'chronicle.sync.password';
  static const _syncPasswordFallbackFileName = 'chronicle_sync_password.txt';

  final AppDirectories _appDirectories;
  final FileSystemUtils _fileSystemUtils;
  final IdGenerator _idGenerator;
  final FlutterSecureStorage _secureStorage;

  @override
  Future<AppSettings> loadSettings() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      final settings = AppSettings.initial(_idGenerator.newId());
      await saveSettings(settings);
      return settings;
    }

    final raw = await file.readAsString();
    final decoded = json.decode(raw) as Map<String, dynamic>;
    var settings = AppSettings.fromJson(decoded);
    if (settings.clientId.isEmpty) {
      settings = settings.copyWith(clientId: _idGenerator.newId());
      await saveSettings(settings);
    }
    return settings;
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    final file = await _settingsFile();
    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert(settings.toJson());
    await _fileSystemUtils.atomicWriteString(file, encoded);
  }

  @override
  Future<void> setStorageRootPath(String path) async {
    final settings = await loadSettings();
    await saveSettings(settings.copyWith(storageRootPath: path));
  }

  @override
  Future<void> setLastSyncAt(DateTime value) async {
    final settings = await loadSettings();
    await saveSettings(settings.copyWith(lastSyncAt: value.toUtc()));
  }

  @override
  Future<void> saveSyncPassword(String password) async {
    try {
      await _secureStorage.write(key: _syncPasswordKey, value: password);
      await _deleteSyncPasswordFallbackIfExists();
    } on PlatformException catch (error) {
      if (!_isMissingKeychainEntitlement(error)) {
        rethrow;
      }
      await _writeSyncPasswordFallback(password);
    }
  }

  @override
  Future<String?> readSyncPassword() async {
    try {
      final secureValue = await _secureStorage.read(key: _syncPasswordKey);
      if (secureValue != null && secureValue.isNotEmpty) {
        await _deleteSyncPasswordFallbackIfExists();
        return secureValue;
      }
    } on PlatformException catch (error) {
      if (!_isMissingKeychainEntitlement(error)) {
        rethrow;
      }
    }

    return _readSyncPasswordFallback();
  }

  Future<File> _settingsFile() async {
    final appSupport = await _appDirectories.appSupportDirectory();
    await _fileSystemUtils.ensureDirectory(appSupport);
    return File(p.join(appSupport.path, _settingsFileName));
  }

  bool _isMissingKeychainEntitlement(PlatformException error) {
    final message = error.message ?? '';
    return message.contains('-34018') ||
        message.toLowerCase().contains('required entitlement');
  }

  Future<File> _syncPasswordFallbackFile() async {
    final appSupport = await _appDirectories.appSupportDirectory();
    await _fileSystemUtils.ensureDirectory(appSupport);
    return File(p.join(appSupport.path, _syncPasswordFallbackFileName));
  }

  Future<void> _writeSyncPasswordFallback(String password) async {
    final file = await _syncPasswordFallbackFile();
    await _fileSystemUtils.atomicWriteString(file, password);
  }

  Future<String?> _readSyncPasswordFallback() async {
    final file = await _syncPasswordFallbackFile();
    if (!await file.exists()) {
      return null;
    }

    final value = await file.readAsString();
    if (value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> _deleteSyncPasswordFallbackIfExists() async {
    final file = await _syncPasswordFallbackFile();
    await _fileSystemUtils.deleteIfExists(file);
  }
}
