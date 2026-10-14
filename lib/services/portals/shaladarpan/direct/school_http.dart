/// Shared native HTTP transport for the ShalaDarpan HTTPX migration.
/// Requests are never retried here. Coordinator policy belongs above this layer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/direct/async_primitives.dart';

const schoolHeaders = <String, String>{
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Accept':
      'text/html,application/xhtml+xml,application/xml;q=0.9,'
      'image/avif,image/webp,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.5',
};

class SchoolHttpReply {
  const SchoolHttpReply(this.url, this.statusCode, this.bytes, this.headers);
  final Uri url;
  final int statusCode;
  final Uint8List bytes;
  final Map<String, List<String>> headers;

  String get text {
    final contentType = headers['content-type']?.join(';') ?? '';
    final charset = RegExp(
      r'charset\s*=\s*"?([^;"\s]+)',
      caseSensitive: false,
    ).firstMatch(contentType)?.group(1)?.toLowerCase();
    if (charset == 'iso-8859-1' || charset == 'latin1') {
      return latin1.decode(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Map<String, dynamic> jsonMap() =>
      Map<String, dynamic>.from(jsonDecode(text) as Map);
}

class _CookieEntry {
  const _CookieEntry(
    this.cookie,
    this.domain,
    this.path,
    this.hostOnly,
    this.expiresAt, [
    this.sameSite,
  ]);
  final Cookie cookie;
  final String domain, path;
  final bool hostOnly;
  final DateTime? expiresAt;
  final String? sameSite;
}

/// HTTPX-compatible legacy cookie seed (name -> value) plus scoped live cookies.
class SchoolCookieJar {
  SchoolCookieJar([Map<String, String> seed = const {}]) {
    for (final entry in seed.entries) {
      _entries.add(
        _CookieEntry(Cookie(entry.key, entry.value), '', '/', false, null),
      );
    }
  }
  final List<_CookieEntry> _entries = [];
  SchoolCookieJar copy() => SchoolCookieJar().._entries.addAll(_entries);
  void clear() => _entries.clear();

  /// Scoped cookie records for the Staff HTTPX persistence/native print bridge.
  /// Never flatten paths: different portal sessions own different jar instances.
  List<Map<String, dynamic>> records({bool includeHostOnly = false}) => [
    for (final entry in _entries)
      {
        'name': entry.cookie.name,
        'value': entry.cookie.value,
        'domain': entry.domain,
        'path': entry.path,
        'secure': entry.cookie.secure,
        'httpOnly': entry.cookie.httpOnly,
        if (includeHostOnly) 'hostOnly': entry.hostOnly,
        if (entry.sameSite != null) 'sameSite': entry.sameSite,
        'expires': entry.expiresAt == null
            ? -1
            : entry.expiresAt!.millisecondsSinceEpoch / 1000,
      },
  ];

  static bool pathMatches(String request, String cookie) =>
      request == cookie ||
      (request.startsWith(cookie) &&
          (cookie.endsWith('/') ||
              (request.length > cookie.length &&
                  request[cookie.length] == '/')));

  static String defaultPath(String request) {
    if (!request.startsWith('/')) return '/';
    final index = request.lastIndexOf('/');
    return index <= 0 ? '/' : request.substring(0, index);
  }

  void receive(
    List<Cookie> cookies,
    Uri url, {
    List<String> rawHeaders = const [],
  }) {
    final now = DateTime.now().toUtc();
    final host = url.host.toLowerCase();
    for (final cookie in cookies) {
      final hostOnly = cookie.domain == null || cookie.domain!.isEmpty;
      final domain = hostOnly
          ? host
          : cookie.domain!.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
      if (host != domain && !host.endsWith('.$domain')) continue;
      final rawPath = cookie.path ?? '';
      final path = rawPath.startsWith('/') ? rawPath : defaultPath(url.path);
      // Remove the legacy domainless shadow when ASP.NET rotates this cookie.
      _entries.removeWhere(
        (old) =>
            old.cookie.name == cookie.name &&
            (old.domain.isEmpty || (old.domain == domain && old.path == path)),
      );
      final expires = cookie.maxAge != null
          ? now.add(Duration(seconds: cookie.maxAge!))
          : cookie.expires?.toUtc();
      if (expires != null && !expires.isAfter(now)) continue;
      String? sameSite;
      for (final raw in rawHeaders) {
        try {
          final parsed = Cookie.fromSetCookieValue(raw);
          if (parsed.name != cookie.name ||
              parsed.path != cookie.path ||
              parsed.domain != cookie.domain)
            continue;
          final value = RegExp(
            r'(?:^|;)\s*SameSite\s*=\s*(none|strict|lax)\s*(?:;|$)',
            caseSensitive: false,
          ).firstMatch(raw)?.group(1)?.toLowerCase();
          if (value != null)
            sameSite = value[0].toUpperCase() + value.substring(1);
        } catch (_) {}
      }
      _entries.add(
        _CookieEntry(cookie, domain, path, hostOnly, expires, sameSite),
      );
    }
  }

  List<Cookie> matching(Uri url) {
    final now = DateTime.now().toUtc();
    _entries.removeWhere(
      (e) => e.expiresAt != null && !e.expiresAt!.isAfter(now),
    );
    final host = url.host.toLowerCase();
    final path = url.path.isEmpty ? '/' : url.path;
    final matches = _entries
        .where(
          (e) =>
              (e.domain.isEmpty ||
                  (e.hostOnly
                      ? host == e.domain
                      : host == e.domain || host.endsWith('.${e.domain}'))) &&
              pathMatches(path, e.path) &&
              (!e.cookie.secure || url.scheme == 'https'),
        )
        .toList();
    matches.sort((a, b) => b.path.length.compareTo(a.path.length));
    return matches.map((e) => e.cookie).toList();
  }

  /// Same flat persistence format as auth_manager.py. Runtime scoping is retained.
  Map<String, String> snapshot([Uri? responseUrl]) {
    final chosen = <String, _CookieEntry>{};
    final duplicates =
        _entries.map((e) => e.cookie.name).toSet().length != _entries.length;
    for (final e in _entries) {
      if (duplicates && responseUrl != null) {
        final host = responseUrl.host.toLowerCase();
        if (e.domain.isNotEmpty &&
            host != e.domain &&
            !host.endsWith('.${e.domain}'))
          continue;
        // Python's legacy duplicate-cookie export uses startswith here.
        if (!responseUrl.path.startsWith(e.path)) continue;
      }
      final old = chosen[e.cookie.name];
      final rank = e.domain.isNotEmpty ? 1 : 0;
      final oldRank = old?.domain.isNotEmpty == true ? 1 : 0;
      if (old == null ||
          rank > oldRank ||
          (rank == oldRank && e.path.length >= old.path.length)) {
        chosen[e.cookie.name] = e;
      }
    }
    return chosen.map((name, e) => MapEntry(name, e.cookie.value));
  }
}

class SchoolHttpClient {
  SchoolHttpClient({
    required this.baseUrl,
    Map<String, String> cookies = const {},
    this.timeout = const Duration(seconds: 25),
    this.onCookies,
    this.defaultHeaders = schoolHeaders,
    HttpClient? transport,
    bool Function(Uri)? allowUrl,
  }) : jar = SchoolCookieJar(cookies),
       _http = transport ?? HttpClient(),
       _allowUrl = allowUrl ?? _portalUrl {
    _http.connectionTimeout = timeout;
  }

  final Uri baseUrl;
  final Duration timeout;
  final Map<String, String> defaultHeaders;
  final SchoolCookieJar jar;
  final Future<void> Function(SchoolHttpClient, Uri)? onCookies;
  final HttpClient _http;
  final bool Function(Uri) _allowUrl;
  int _leases = 0, _requests = 0;
  bool _retired = false, _closed = false;
  bool get retired => _retired;
  bool get isClosed => _closed;

  static bool _portalUrl(Uri url) =>
      url.scheme == 'https' &&
      url.host.toLowerCase() == 'rajshaladarpan.rajasthan.gov.in' &&
      url.port == 443 &&
      url.userInfo.isEmpty;

  Uri resolve(String value) {
    final uri = Uri.parse(value);
    if (uri.hasScheme) return uri;
    // HTTPX base_url always has a trailing slash and appends relative paths.
    final base = baseUrl.toString().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base/')
        .resolve(value.startsWith('/') ? value.substring(1) : value);
  }

  Future<T> withLease<T>(Future<T> Function(SchoolHttpClient) operation) async {
    if (_retired || _closed) {
      throw StateError(
        'Shala Darpan HTTP session was replaced; '
        'retry through the coordinator.',
      );
    }
    _leases++;
    try {
      return await operation(this);
    } finally {
      _leases--;
      _closeIfIdle();
    }
  }

  void retire() {
    _retired = true;
    _closeIfIdle();
  }

  void _closeIfIdle() {
    if (_retired && _leases == 0 && _requests == 0 && !_closed) {
      _closed = true;
      _http.close();
    }
  }

  Future<SchoolHttpReply> get(String url, {Duration? timeout}) =>
      request('GET', resolve(url), timeout: timeout);

  Future<SchoolHttpReply> post(
    String url, {
    Map<String, String>? data,
    Map<String, dynamic>? json,
    Map<String, String> headers = const {},
    Duration? timeout,
    bool followRedirects = true,
  }) {
    if (data != null && json != null) {
      throw ArgumentError('Use either form data or JSON.');
    }
    final body = json != null
        ? jsonEncode(json)
        : data?.entries
              .map(
                (e) =>
                    '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
              )
              .join('&');
    return request(
      'POST',
      resolve(url),
      body: body == null ? null : utf8.encode(body),
      headers: {
        if (json != null) 'Content-Type': 'application/json',
        if (data != null) 'Content-Type': 'application/x-www-form-urlencoded',
        ...headers,
      },
      timeout: timeout,
      followRedirects: followRedirects,
    );
  }

  /// Explicit redirects preserve cookies at every hop; no network retry/replay.
  /// 307/308 replay the body as HTTPX does. Mutation workers must review this
  /// behavior before adoption; coordinator timeouts must not resubmit a request.
  Future<SchoolHttpReply> request(
    String method,
    Uri initial, {
    List<int>? body,
    Map<String, String> headers = const {},
    Duration? timeout,
    bool followRedirects = true,
    SchoolCookieJar? cookieJar,
  }) async {
    if (_closed) throw StateError('School HTTP client is closed.');
    final cancellation = OperationCancellation.current;
    cancellation?.check();
    HttpClientRequest? activeRequest;
    final stopCancellation = cancellation?.listen(
      () => activeRequest?.abort(const OperationCancelled()),
    );
    _requests++;
    final limit = timeout ?? this.timeout;
    var url = initial;
    var verb = method.toUpperCase();
    var payload = body;
    final requestHeaders = <String, String>{...defaultHeaders, ...headers};
    try {
      for (var redirects = 0; redirects <= 20; redirects++) {
        cancellation?.check();
        if (!_allowUrl(url))
          throw StateError('Blocked non-portal URL/redirect.');
        final request = await _http.openUrl(verb, url).timeout(limit);
        activeRequest = request;
        cancellation?.check();
        request.followRedirects = false;
        requestHeaders.forEach(request.headers.set);
        request.cookies.addAll((cookieJar ?? jar).matching(url));
        if (payload != null) {
          request.contentLength = payload.length;
          request.add(payload);
        }
        late HttpClientResponse response;
        try {
          response = await request.close().timeout(limit);
        } on TimeoutException catch (error, stack) {
          request.abort(error, stack);
          rethrow;
        }
        cancellation?.check();
        jar.receive(
          response.cookies,
          url,
          rawHeaders: response.headers[HttpHeaders.setCookieHeader] ?? [],
        );
        if (cookieJar != null && !identical(cookieJar, jar)) {
          cookieJar.receive(
            response.cookies,
            url,
            rawHeaders: response.headers[HttpHeaders.setCookieHeader] ?? [],
          );
        }
        if (response.headers[HttpHeaders.setCookieHeader] != null &&
            onCookies != null) {
          try {
            await onCookies!(this, url);
          } catch (_) {
            // Python persistence failures do not discard a portal response.
          }
        }
        final responseHeaders = <String, List<String>>{};
        response.headers.forEach((key, values) {
          responseHeaders[key.toLowerCase()] = List.of(values);
        });
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (followRedirects &&
            const [301, 302, 303, 307, 308].contains(response.statusCode) &&
            location != null) {
          await response.drain<void>().timeout(limit);
          if (redirects == 20) throw StateError('Too many redirects.');
          final next = url.resolve(location);
          if (!_allowUrl(next))
            throw StateError('Blocked non-portal redirect.');
          final toGet =
              (response.statusCode == 303 && verb != 'HEAD') ||
              (response.statusCode == 302 && verb != 'HEAD') ||
              (response.statusCode == 301 && verb == 'POST');
          if (toGet) {
            verb = 'GET';
            payload = null;
            requestHeaders.removeWhere(
              (key, _) => const {
                'content-type',
                'content-length',
                'transfer-encoding',
              }.contains(key.toLowerCase()),
            );
          }
          url = next;
          continue;
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.timeout(limit)) {
          cancellation?.check();
          bytes.add(chunk);
        }
        return SchoolHttpReply(
          url,
          response.statusCode,
          bytes.takeBytes(),
          responseHeaders,
        );
      }
      throw StateError('Too many redirects.');
    } finally {
      stopCancellation?.call();
      if (cancellation?.cancelled == true)
        activeRequest?.abort(const OperationCancelled());
      _requests--;
      _closeIfIdle();
    }
  }
}
