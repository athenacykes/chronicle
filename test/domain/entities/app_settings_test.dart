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
    expect(settings.collapsedSidebarSectionIds, isEmpty);
    expect(settings.matterNoteListPaneWidth, 380);
    expect(settings.notebookNoteListPaneWidth, 380);
    expect(settings.editorLineNumbersEnabled, isTrue);
    expect(settings.editorWordWrapEnabled, isFalse);
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
      collapsedSidebarSectionIds: const <String>['views', 'notebooks'],
    );

    final restored = AppSettings.fromJson(original.toJson());
    expect(restored.collapsedCategoryIds, <String>['a', 'b']);
    expect(restored.collapsedSidebarSectionIds, <String>['views', 'notebooks']);
  });

  test('toJson/fromJson roundtrip preserves note list pane widths', () {
    final original = AppSettings(
      storageRootPath: '/tmp/chronicle',
      clientId: 'client-id',
      syncConfig: SyncConfig.initial(),
      lastSyncAt: null,
      matterNoteListPaneWidth: 244,
      notebookNoteListPaneWidth: 312,
    );

    final restored = AppSettings.fromJson(original.toJson());

    expect(restored.matterNoteListPaneWidth, 244);
    expect(restored.notebookNoteListPaneWidth, 312);
  });

  test('toJson/fromJson roundtrip preserves editor view options', () {
    final original = AppSettings(
      storageRootPath: '/tmp/chronicle',
      clientId: 'client-id',
      syncConfig: SyncConfig.initial(),
      lastSyncAt: null,
      editorLineNumbersEnabled: false,
      editorWordWrapEnabled: true,
    );

    final restored = AppSettings.fromJson(original.toJson());

    expect(restored.editorLineNumbersEnabled, isFalse);
    expect(restored.editorWordWrapEnabled, isTrue);
  });
}
