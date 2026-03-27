import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:socks5_proxy/socks_client.dart';

import '../../domain/entities/enums.dart';
import '../../domain/entities/sync_config.dart';
import '../../domain/entities/sync_proxy_config.dart';
import 'webdav_client.dart';

typedef Socks5HttpClientConfigurator =
    void Function(HttpClient client, SyncProxyConfig config, String? password);
typedef HttpClientCreator = HttpClient Function();

class WebDavClientFactory {
  WebDavClientFactory({
    Socks5HttpClientConfigurator? socks5HttpClientConfigurator,
    HttpClientCreator? httpClientCreator,
  }) : _socks5HttpClientConfigurator =
           socks5HttpClientConfigurator ?? _configureSocks5HttpClient,
       _httpClientCreator = httpClientCreator ?? HttpClient.new;

  final Socks5HttpClientConfigurator _socks5HttpClientConfigurator;
  final HttpClientCreator _httpClientCreator;

  WebDavClient create({
    required SyncConfig config,
    required String password,
    String? proxyPassword,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: _normalizeBaseUrl(config.url),
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: <String, Object>{
          'Authorization':
              'Basic ${base64Encode(utf8.encode('${config.username}:$password'))}',
        },
      ),
    );

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () =>
          createHttpClient(proxy: config.proxy, proxyPassword: proxyPassword),
    );

    return DioWebDavClient(
      baseUrl: config.url,
      username: config.username,
      password: password,
      dio: dio,
    );
  }

  HttpClient createHttpClient({
    required SyncProxyConfig proxy,
    String? proxyPassword,
  }) {
    final client = _httpClientCreator();
    _configureProxy(client: client, proxy: proxy, proxyPassword: proxyPassword);
    return client;
  }

  void _configureProxy({
    required HttpClient client,
    required SyncProxyConfig proxy,
    required String? proxyPassword,
  }) {
    if (!proxy.isEnabled) {
      client.findProxy = (_) => 'DIRECT';
      return;
    }

    switch (proxy.type) {
      case SyncProxyType.none:
        client.findProxy = (_) => 'DIRECT';
      case SyncProxyType.http:
        _configureHttpProxy(client, proxy, proxyPassword);
      case SyncProxyType.socks5:
        _socks5HttpClientConfigurator(client, proxy, proxyPassword);
    }
  }

  void _configureHttpProxy(
    HttpClient client,
    SyncProxyConfig proxy,
    String? proxyPassword,
  ) {
    final host = proxy.host.trim();
    final port = proxy.port ?? 0;
    client.findProxy = (_) => 'PROXY $host:$port';
    if (proxy.username.trim().isEmpty || (proxyPassword ?? '').isEmpty) {
      return;
    }
    client.addProxyCredentials(
      host,
      port,
      '',
      HttpClientBasicCredentials(proxy.username.trim(), proxyPassword!.trim()),
    );
  }

  static void _configureSocks5HttpClient(
    HttpClient client,
    SyncProxyConfig proxy,
    String? proxyPassword,
  ) {
    final port = proxy.port ?? 1080;
    SocksTCPClient.assignToHttpClient(client, <ProxySettings>[
      ProxySettings(
        InternetAddress(proxy.host.trim()),
        port,
        username: proxy.username.trim().isEmpty ? null : proxy.username.trim(),
        password: (proxyPassword ?? '').trim().isEmpty
            ? null
            : proxyPassword!.trim(),
      ),
    ]);
  }

  static String _normalizeBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }
}
