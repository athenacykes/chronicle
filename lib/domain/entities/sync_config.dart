import 'enums.dart';

class SyncConfig {
  const SyncConfig({
    required this.type,
    required this.url,
    required this.username,
    required this.intervalMinutes,
    required this.failSafe,
  });

  final SyncTargetType type;
  final String url;
  final String username;
  final int intervalMinutes;
  final bool failSafe;

  SyncConfig copyWith({
    SyncTargetType? type,
    String? url,
    String? username,
    int? intervalMinutes,
    bool? failSafe,
  }) {
    return SyncConfig(
      type: type ?? this.type,
      url: url ?? this.url,
      username: username ?? this.username,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      failSafe: failSafe ?? this.failSafe,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'url': url,
      'username': username,
      'intervalMinutes': intervalMinutes,
      'failSafe': failSafe,
    };
  }

  static SyncConfig fromJson(Map<String, dynamic> json) {
    return SyncConfig(
      type: SyncTargetType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => SyncTargetType.none,
      ),
      url: (json['url'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      intervalMinutes: (json['intervalMinutes'] as num?)?.toInt() ?? 5,
      failSafe: (json['failSafe'] as bool?) ?? true,
    );
  }

  static SyncConfig initial() {
    return const SyncConfig(
      type: SyncTargetType.none,
      url: '',
      username: '',
      intervalMinutes: 5,
      failSafe: true,
    );
  }
}
