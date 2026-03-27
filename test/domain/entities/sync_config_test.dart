import 'package:chronicle/domain/entities/enums.dart';
import 'package:chronicle/domain/entities/sync_config.dart';
import 'package:chronicle/domain/entities/sync_proxy_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toJson/fromJson roundtrip preserves proxy configuration', () {
    const original = SyncConfig(
      type: SyncTargetType.webdav,
      url: 'https://uno.teracloud.jp/dav/Chronicle',
      username: 'chronicle-user',
      intervalMinutes: 7,
      failSafe: false,
      proxy: SyncProxyConfig(
        type: SyncProxyType.socks5,
        host: '127.0.0.1',
        port: 1080,
        username: 'proxy-user',
      ),
    );

    final restored = SyncConfig.fromJson(original.toJson());

    expect(restored.type, SyncTargetType.webdav);
    expect(restored.url, original.url);
    expect(restored.username, original.username);
    expect(restored.intervalMinutes, 7);
    expect(restored.failSafe, isFalse);
    expect(restored.proxy.type, SyncProxyType.socks5);
    expect(restored.proxy.host, '127.0.0.1');
    expect(restored.proxy.port, 1080);
    expect(restored.proxy.username, 'proxy-user');
  });

  test('fromJson defaults missing proxy config to disabled', () {
    final restored = SyncConfig.fromJson(<String, dynamic>{
      'type': 'webdav',
      'url': 'https://example.com/dav/Chronicle',
      'username': 'chronicle-user',
      'intervalMinutes': 5,
      'failSafe': true,
    });

    expect(restored.proxy.type, SyncProxyType.none);
    expect(restored.proxy.host, isEmpty);
    expect(restored.proxy.port, isNull);
    expect(restored.proxy.username, isEmpty);
  });
}
