import 'package:chronicle/domain/entities/app_settings.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromJson defaults localeTag to en when missing', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'storageRootPath': '/tmp/chronicle',
      'clientId': 'client-id',
      'syncConfig': SyncConfig.initial().toJson(),
      'lastSyncAt': null,
    });

    expect(settings.localeTag, 'en');
    expect(settings.collapsedCategoryIds, isEmpty);
  });

  test('toJson/fromJson roundtrip preserves localeTag', () {
    final original = AppSettings(
      storageRootPath: '/tmp/chronicle',
      clientId: 'client-id',
      syncConfig: SyncConfig.initial(),
      lastSyncAt: null,
      localeTag: 'zh',
    );

    final restored = AppSettings.fromJson(original.toJson());

    expect(restored.localeTag, 'zh');
  });

  test('toJson/fromJson roundtrip preserves collapsedCategoryIds', () {
    final original = AppSettings(
      storageRootPath: '/tmp/chronicle',
      clientId: 'client-id',
      syncConfig: SyncConfig.initial(),
      lastSyncAt: null,
      localeTag: 'en',
      collapsedCategoryIds: const <String>['a', 'b'],
    );

    final restored = AppSettings.fromJson(original.toJson());
    expect(restored.collapsedCategoryIds, <String>['a', 'b']);
  });
}
