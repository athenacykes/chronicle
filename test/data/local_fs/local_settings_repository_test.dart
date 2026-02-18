import 'dart:io';

import 'package:chronicle/core/app_directories.dart';
import 'package:chronicle/core/file_system_utils.dart';
import 'package:chronicle/core/id_generator.dart';
import 'package:chronicle/data/local_fs/local_settings_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Directory appSupportDir;
  late _FakeSecureStorage secureStorage;
  late LocalSettingsRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'chronicle-local-settings-test-',
    );
    appSupportDir = Directory('${tempDir.path}/Application Support/Chronicle');
    secureStorage = _FakeSecureStorage();
    repository = LocalSettingsRepository(
      appDirectories: FixedAppDirectories(
        appSupport: appSupportDir,
        home: tempDir,
      ),
      fileSystemUtils: const FileSystemUtils(),
      idGenerator: _FixedIdGenerator(),
      secureStorage: secureStorage,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'stores sync password in secure storage when keychain is available',
    () async {
      await repository.saveSyncPassword('secret-1');

      expect(await repository.readSyncPassword(), 'secret-1');

      final fallbackFile = File(
        '${appSupportDir.path}/chronicle_sync_password.txt',
      );
      expect(await fallbackFile.exists(), isFalse);
    },
  );

  test(
    'falls back to file storage when keychain entitlement is missing',
    () async {
      final entitlementError = PlatformException(
        code: 'Unexpected security result code',
        message: "Code: -34018, Message: A required entitlement isn't present.",
      );
      secureStorage.writeError = entitlementError;
      secureStorage.readError = entitlementError;

      await repository.saveSyncPassword('fallback-secret');

      expect(await repository.readSyncPassword(), 'fallback-secret');

      final fallbackFile = File(
        '${appSupportDir.path}/chronicle_sync_password.txt',
      );
      expect(await fallbackFile.exists(), isTrue);
      expect(await fallbackFile.readAsString(), 'fallback-secret');
    },
  );

  test('removes fallback file once secure storage works again', () async {
    final entitlementError = PlatformException(
      code: 'Unexpected security result code',
      message: "Code: -34018, Message: A required entitlement isn't present.",
    );
    secureStorage.writeError = entitlementError;
    secureStorage.readError = entitlementError;
    await repository.saveSyncPassword('fallback-secret');

    secureStorage.writeError = null;
    secureStorage.readError = null;
    await repository.saveSyncPassword('secure-secret');

    final fallbackFile = File(
      '${appSupportDir.path}/chronicle_sync_password.txt',
    );
    expect(await fallbackFile.exists(), isFalse);
    expect(await repository.readSyncPassword(), 'secure-secret');
  });

  test('rethrows non-entitlement secure storage errors', () async {
    secureStorage.writeError = PlatformException(
      code: 'io_error',
      message: 'unexpected failure',
    );

    await expectLater(
      () => repository.saveSyncPassword('secret-2'),
      throwsA(isA<PlatformException>()),
    );
  });
}

class _FixedIdGenerator implements IdGenerator {
  @override
  String newId() => 'client-fixed';
}

class _FakeSecureStorage extends FlutterSecureStorage {
  PlatformException? writeError;
  PlatformException? readError;
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (writeError != null) {
      throw writeError!;
    }

    if (value == null) {
      _values.remove(key);
      return;
    }

    _values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (readError != null) {
      throw readError!;
    }
    return _values[key];
  }
}
