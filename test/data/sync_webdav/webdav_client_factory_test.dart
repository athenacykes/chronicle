import 'dart:io';

import 'package:chronicle/data/sync_webdav/webdav_client_factory.dart';
import 'package:chronicle/domain/entities/enums.dart';
import 'package:chronicle/domain/entities/sync_proxy_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'createHttpClient configures direct connections when proxy is disabled',
    () {
      final client = _InspectableHttpClient();
      final factory = WebDavClientFactory(httpClientCreator: () => client);

      final configuredClient = factory.createHttpClient(
        proxy: SyncProxyConfig.initial(),
      );

      expect(identical(configuredClient, client), isTrue);
      expect(
        client.resolveProxy(Uri.parse('https://example.com/dav/Chronicle')),
        'DIRECT',
      );
    },
  );

  test('createHttpClient configures HTTP proxy routing', () {
    final client = _InspectableHttpClient();
    final factory = WebDavClientFactory(httpClientCreator: () => client);

    final configuredClient = factory.createHttpClient(
      proxy: const SyncProxyConfig(
        type: SyncProxyType.http,
        host: '127.0.0.1',
        port: 8899,
        username: 'proxy-user',
      ),
      proxyPassword: 'proxy-secret',
    );

    expect(identical(configuredClient, client), isTrue);
    expect(
      client.resolveProxy(Uri.parse('https://example.com/dav/Chronicle')),
      'PROXY 127.0.0.1:8899',
    );
  });

  test('createHttpClient delegates SOCKS5 configuration', () {
    final client = _InspectableHttpClient();
    HttpClient? configuredClient;
    SyncProxyConfig? configuredProxy;
    String? configuredPassword;
    final factory = WebDavClientFactory(
      httpClientCreator: () => client,
      socks5HttpClientConfigurator: (client, proxy, password) {
        configuredClient = client;
        configuredProxy = proxy;
        configuredPassword = password;
      },
    );

    final configured = factory.createHttpClient(
      proxy: const SyncProxyConfig(
        type: SyncProxyType.socks5,
        host: '127.0.0.1',
        port: 1080,
        username: 'proxy-user',
      ),
      proxyPassword: 'proxy-secret',
    );

    expect(identical(configured, client), isTrue);
    expect(identical(configuredClient, client), isTrue);
    expect(configuredProxy?.type, SyncProxyType.socks5);
    expect(configuredProxy?.host, '127.0.0.1');
    expect(configuredProxy?.port, 1080);
    expect(configuredPassword, 'proxy-secret');
  });
}

class _InspectableHttpClient implements HttpClient {
  String Function(Uri url)? _proxyResolver;

  String resolveProxy(Uri url) => _proxyResolver?.call(url) ?? 'DIRECT';

  @override
  set findProxy(String Function(Uri url)? f) {
    _proxyResolver = f;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
