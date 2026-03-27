import 'enums.dart';

class SyncProxyConfig {
  const SyncProxyConfig({
    required this.type,
    required this.host,
    required this.port,
    required this.username,
  });

  final SyncProxyType type;
  final String host;
  final int? port;
  final String username;

  bool get isEnabled => type != SyncProxyType.none;

  SyncProxyConfig copyWith({
    SyncProxyType? type,
    String? host,
    int? port,
    bool clearPort = false,
    String? username,
  }) {
    return SyncProxyConfig(
      type: type ?? this.type,
      host: host ?? this.host,
      port: clearPort ? null : port ?? this.port,
      username: username ?? this.username,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'host': host,
      'port': port,
      'username': username,
    };
  }

  static SyncProxyConfig fromJson(Map<String, dynamic> json) {
    return SyncProxyConfig(
      type: SyncProxyType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => SyncProxyType.none,
      ),
      host: (json['host'] as String?) ?? '',
      port: (json['port'] as num?)?.toInt(),
      username: (json['username'] as String?) ?? '',
    );
  }

  static SyncProxyConfig initial() {
    return const SyncProxyConfig(
      type: SyncProxyType.none,
      host: '',
      port: null,
      username: '',
    );
  }
}
