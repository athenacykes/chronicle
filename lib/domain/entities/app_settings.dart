import '../../core/time_utils.dart';
import 'sync_config.dart';

class AppSettings {
  const AppSettings({
    required this.storageRootPath,
    required this.clientId,
    required this.syncConfig,
    required this.lastSyncAt,
    this.localeTag = 'en',
    this.collapsedCategoryIds = const <String>[],
  });

  final String? storageRootPath;
  final String clientId;
  final SyncConfig syncConfig;
  final DateTime? lastSyncAt;
  final String localeTag;
  final List<String> collapsedCategoryIds;

  AppSettings copyWith({
    String? storageRootPath,
    bool clearStorageRootPath = false,
    String? clientId,
    SyncConfig? syncConfig,
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
    String? localeTag,
    List<String>? collapsedCategoryIds,
  }) {
    return AppSettings(
      storageRootPath: clearStorageRootPath
          ? null
          : storageRootPath ?? this.storageRootPath,
      clientId: clientId ?? this.clientId,
      syncConfig: syncConfig ?? this.syncConfig,
      lastSyncAt: clearLastSyncAt ? null : lastSyncAt ?? this.lastSyncAt,
      localeTag: localeTag ?? this.localeTag,
      collapsedCategoryIds: collapsedCategoryIds ?? this.collapsedCategoryIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'storageRootPath': storageRootPath,
      'clientId': clientId,
      'syncConfig': syncConfig.toJson(),
      'lastSyncAt': lastSyncAt == null ? null : formatIsoUtc(lastSyncAt!),
      'localeTag': localeTag,
      'collapsedCategoryIds': collapsedCategoryIds,
    };
  }

  static AppSettings fromJson(Map<String, dynamic> json) {
    return AppSettings(
      storageRootPath: json['storageRootPath'] as String?,
      clientId: (json['clientId'] as String?) ?? '',
      syncConfig: json['syncConfig'] is Map<String, dynamic>
          ? SyncConfig.fromJson(json['syncConfig'] as Map<String, dynamic>)
          : SyncConfig.initial(),
      lastSyncAt: json['lastSyncAt'] == null
          ? null
          : parseIsoUtc(json['lastSyncAt'] as String),
      localeTag: (json['localeTag'] as String?) ?? 'en',
      collapsedCategoryIds:
          (json['collapsedCategoryIds'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .toList(growable: false),
    );
  }

  static AppSettings initial(String clientId) {
    return AppSettings(
      storageRootPath: null,
      clientId: clientId,
      syncConfig: SyncConfig.initial(),
      lastSyncAt: null,
      localeTag: 'en',
      collapsedCategoryIds: const <String>[],
    );
  }
}
