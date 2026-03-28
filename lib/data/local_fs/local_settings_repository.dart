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
  static const _syncProxyPasswordKey = 'chronicle.sync.proxy.password';
  static const _syncPasswordFallbackFileName = 'chronicle_sync_password.txt';
  static const _syncProxyPasswordFallbackFileName =
      'chronicle_sync_proxy_password.txt';

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
    await _saveSecret(
      key: _syncPasswordKey,
      fallbackFileName: _syncPasswordFallbackFileName,
      value: password,
    );
  }

  @override
  Future<String?> readSyncPassword() async {
    return _readSecret(
      key: _syncPasswordKey,
      fallbackFileName: _syncPasswordFallbackFileName,
    );
  }

  @override
  Future<void> clearSyncPassword() async {
    try {
      await _secureStorage.delete(key: _syncPasswordKey);
    } on PlatformException catch (error) {
      if (!_isMissingKeychainEntitlement(error)) {
        rethrow;
      }
    }
    await _deleteSecretFallbackIfExists(_syncPasswordFallbackFileName);
  }

  @override
  Future<void> saveSyncProxyPassword(String password) async {
    await _saveSecret(
      key: _syncProxyPasswordKey,
      fallbackFileName: _syncProxyPasswordFallbackFileName,
      value: password,
    );
  }

  @override
  Future<String?> readSyncProxyPassword() async {
    return _readSecret(
      key: _syncProxyPasswordKey,
      fallbackFileName: _syncProxyPasswordFallbackFileName,
    );
  }

  @override
  Future<void> clearSyncProxyPassword() async {
    try {
      await _secureStorage.delete(key: _syncProxyPasswordKey);
    } on PlatformException catch (error) {
      if (!_isMissingKeychainEntitlement(error)) {
        rethrow;
      }
    }
    await _deleteSecretFallbackIfExists(_syncProxyPasswordFallbackFileName);
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

  Future<File> _secretFallbackFile(String fileName) async {
    final appSupport = await _appDirectories.appSupportDirectory();
    await _fileSystemUtils.ensureDirectory(appSupport);
    return File(p.join(appSupport.path, fileName));
  }

  Future<void> _saveSecret({
    required String key,
    required String fallbackFileName,
    required String value,
  }) async {
    try {
      await _secureStorage.write(key: key, value: value);
      await _deleteSecretFallbackIfExists(fallbackFileName);
    } on PlatformException catch (error) {
      if (!_isMissingKeychainEntitlement(error)) {
        rethrow;
      }
      await _writeSecretFallback(fallbackFileName, value);
    }
  }

  Future<String?> _readSecret({
    required String key,
    required String fallbackFileName,
  }) async {
    try {
      final secureValue = await _secureStorage.read(key: key);
      if (secureValue != null && secureValue.isNotEmpty) {
        await _deleteSecretFallbackIfExists(fallbackFileName);
        return secureValue;
      }
    } on PlatformException catch (error) {
      if (!_isMissingKeychainEntitlement(error)) {
        rethrow;
      }
    }

    return _readSecretFallback(fallbackFileName);
  }

  Future<void> _writeSecretFallback(String fileName, String value) async {
    final file = await _secretFallbackFile(fileName);
    await _fileSystemUtils.atomicWriteString(file, value);
  }

  Future<String?> _readSecretFallback(String fileName) async {
    final file = await _secretFallbackFile(fileName);
    if (!await file.exists()) {
      return null;
    }

    final value = await file.readAsString();
    if (value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> _deleteSecretFallbackIfExists(String fileName) async {
    final file = await _secretFallbackFile(fileName);
    await _fileSystemUtils.deleteIfExists(file);
  }
}
