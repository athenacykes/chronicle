import 'enums.dart';
import 'sync_proxy_config.dart';

class SyncConfig {
  const SyncConfig({
    required this.type,
    required this.url,
    required this.username,
    required this.intervalMinutes,
    required this.failSafe,
    required this.proxy,
  });

  final SyncTargetType type;
  final String url;
  final String username;
  final int intervalMinutes;
  final bool failSafe;
  final SyncProxyConfig proxy;

  SyncConfig copyWith({
    SyncTargetType? type,
    String? url,
    String? username,
    int? intervalMinutes,
    bool? failSafe,
    SyncProxyConfig? proxy,
  }) {
    return SyncConfig(
      type: type ?? this.type,
      url: url ?? this.url,
      username: username ?? this.username,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      failSafe: failSafe ?? this.failSafe,
      proxy: proxy ?? this.proxy,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'url': url,
      'username': username,
      'intervalMinutes': intervalMinutes,
      'failSafe': failSafe,
      'proxy': proxy.toJson(),
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
      proxy: json['proxy'] is Map<String, dynamic>
          ? SyncProxyConfig.fromJson(json['proxy'] as Map<String, dynamic>)
          : SyncProxyConfig.initial(),
    );
  }

  static SyncConfig initial() {
    return SyncConfig(
      type: SyncTargetType.none,
      url: '',
      username: '',
      intervalMinutes: 5,
      failSafe: true,
      proxy: SyncProxyConfig.initial(),
    );
  }
}
