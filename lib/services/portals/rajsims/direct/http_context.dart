/// Page-free HTTP session contract from rajsims_sso_httpx.HttpxContext.
/// Separate cookie jar; reuses the existing native HTTPS transport implementation.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../shaladarpan/direct/school_http.dart';

const rajsimsBootstrap =
    'https://rajsims-mdm.rajasthan.gov.in/Gateway/api/Authenticate/GetSSOlogin';
const rajsimsGateway =
    'https://rajsims-mdm.rajasthan.gov.in/Gateway/api/Gateway_PostAuthAdminService/GetData';
const rajsimsHosts = {
  'sso.rajasthan.gov.in',
  'rajsims.rajasthan.gov.in',
  'rajsims-mdm.rajasthan.gov.in',
};

bool rajsimsTrustedUrl(Uri url) =>
    url.scheme == 'https' &&
    rajsimsHosts.contains(url.host) &&
    url.port == 443 &&
    url.userInfo.isEmpty;

class RajsimsSessionChanged implements Exception {
  const RajsimsSessionChanged(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class RajsimsHttpTransport {
  SchoolCookieJar get jar;
  Future<SchoolHttpReply> request(
    String method,
    Uri url, {
    String? content,
    Map<String, String> headers = const {},
    Duration? timeout,
  });
  Future<void> close();
}

class NativeRajsimsHttpTransport implements RajsimsHttpTransport {
  NativeRajsimsHttpTransport({
    String? userAgent,
    Duration timeout = const Duration(seconds: 25),
    HttpClient? transport,
  }) : client = SchoolHttpClient(
         baseUrl: Uri.parse('https://sso.rajasthan.gov.in/'),
         timeout: timeout,
         transport: transport,
         allowUrl: rajsimsTrustedUrl,
         defaultHeaders: {
           'Accept': '*/*',
           if (userAgent != null) 'User-Agent': userAgent,
         },
       );
  final SchoolHttpClient client;
  @override
  SchoolCookieJar get jar => client.jar;
  @override
  Future<SchoolHttpReply> request(
    String method,
    Uri url, {
    String? content,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) {
    if (!rajsimsTrustedUrl(url))
      throw ArgumentError('RajSIMS request left the official HTTPS hosts.');
    return client.request(
      method,
      url,
      body: content == null ? null : utf8.encode(content),
      headers: headers,
      timeout: timeout,
      followRedirects: false,
    );
  }

  @override
  Future<void> close() async {
    client.retire();
  }
}

/// Import the same scoped browser/HTTPX cookie format without flattening paths.
void importRajsimsCookie(SchoolCookieJar jar, Map<String, dynamic> item) {
  final domain = item['domain'] as String;
  final host = domain.replaceFirst(RegExp(r'^\.'), '');
  if (!(host == 'rajasthan.gov.in' || rajsimsHosts.contains(host)))
    throw ArgumentError('Unexpected RajSIMS cookie domain.');
  final cookie = Cookie(item['name'] as String, item['value'] as String)
    ..path = (item['path'] ?? '/') as String
    ..secure = item['secure'] == true
    ..httpOnly = item['httpOnly'] == true;
  if (domain.startsWith('.')) cookie.domain = domain;
  final expires = item['expires'];
  if (expires is num && expires > 0)
    cookie.expires = DateTime.fromMillisecondsSinceEpoch(
      (expires * 1000).toInt(),
      isUtc: true,
    );
  jar.receive([cookie], Uri(scheme: 'https', host: host, path: cookie.path));
}

class RajsimsHttpContext {
  RajsimsHttpContext(this.client) {
    _contexts.add(this);
  }
  final RajsimsHttpTransport client;
  bool closed = false;
  final pages = <Object>[];
  final _handlers =
      <String, List<FutureOr<void> Function(RajsimsHttpContext)>>{};
  static final _contexts = <RajsimsHttpContext>{};
  late final request = RajsimsProbeRequest(this);
  void on(String event, FutureOr<void> Function(RajsimsHttpContext) callback) =>
      (_handlers[event] ??= []).add(callback);
  void check() {
    if (closed)
      throw const RajsimsSessionChanged('RajSIMS HTTPX session is closed.');
  }

  Future<List<Map<String, dynamic>>> cookies([List<Uri>? urls]) async {
    check();
    // matching purges expired records, including when exporting all state.
    client.jar.matching(Uri.parse('https://sso.rajasthan.gov.in/'));
    final records = client.jar.records(includeHostOnly: true);
    return [
      for (final item in records)
        if (urls == null ||
            urls.any((url) {
              final domain = item['domain'] as String,
                  path = item['path'] as String;
              final hostMatches =
                  url.host == domain ||
                  item['hostOnly'] != true && url.host.endsWith('.$domain');
              return hostMatches &&
                  SchoolCookieJar.pathMatches(
                    url.path.isEmpty ? '/' : url.path,
                    path,
                  ) &&
                  (item['secure'] != true || url.scheme == 'https');
            }))
          {
            'name': item['name'],
            'value': item['value'],
            'domain': item['hostOnly'] == true
                ? item['domain']
                : '.${item['domain']}',
            'path': item['path'],
            'secure': item['secure'],
            'httpOnly': item['httpOnly'],
            if ((item['expires'] as num) > 0) 'expires': item['expires'],
          },
    ];
  }

  Future<void> addCookies(List<Map<String, dynamic>> items) async {
    check();
    for (final item in items) {
      importRajsimsCookie(client.jar, item);
    }
  }

  Future<Map<String, dynamic>> storageState({String? path}) async {
    final state = <String, dynamic>{
      'cookies': await cookies(),
      'origins': <Object>[],
    };
    if (path != null) {
      final target = File(path), temp = File('$path.httpx.tmp');
      await target.parent.create(recursive: true);
      await temp.writeAsString(jsonEncode(state), flush: true);
      await temp.rename(path);
    }
    return state;
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    _contexts.remove(this);
    try {
      for (final callback
          in _handlers['close'] ??
              <FutureOr<void> Function(RajsimsHttpContext)>[]) {
        await callback(this);
      }
    } finally {
      await client.close();
    }
  }

  static Future<void> closeAll() async {
    for (final context in _contexts.toList()) {
      await context.close();
    }
  }
}

class RajsimsProbeRequest {
  RajsimsProbeRequest(this.context);
  final RajsimsHttpContext context;
  Future<SchoolHttpReply> post(
    String url, {
    required Map<String, String> headers,
    required Object data,
    required int timeout,
    int maxRedirects = 0,
  }) async {
    final payload = data is String ? jsonDecode(data) : data;
    if (url != rajsimsGateway ||
        payload is! Map ||
        payload['ApiKey'] != 'ValidateTokenAndGetUserDetail' ||
        maxRedirects != 0)
      throw ArgumentError(
        'Only the existing read-only token probe is permitted here.',
      );
    final incoming = {
      for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
    };
    final params = payload['ApiParams'];
    if ((incoming['authid'] ?? '').isEmpty ||
        (incoming['authkey'] ?? '').isEmpty ||
        params is! Map ||
        params['AuthId'] != incoming['authid'] ||
        params['AuthKey'] != incoming['authkey'])
      throw ArgumentError(
        'Token probe payload does not match its session headers.',
      );
    context.check();
    return context.client.request(
      'POST',
      Uri.parse(rajsimsBootstrap),
      content: jsonEncode(payload),
      timeout: Duration(milliseconds: timeout),
      headers: {
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json',
        'Origin': 'https://rajsims-mdm.rajasthan.gov.in',
        'Referer': 'https://rajsims-mdm.rajasthan.gov.in/',
      },
    );
  }
}
