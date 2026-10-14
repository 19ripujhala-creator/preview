// lib/experiments/direct_portal_probe.dart
// Android/iOS only. GET-only diagnostic; no login and no portal mutations.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PortalProbeResult {
  const PortalProbeResult({required this.ok, required this.httpStatus,
    required this.loginLatencyMs, required this.captchaLatencyMs,
    required this.captchaBytes, required this.details});
  final bool ok;
  final int httpStatus, loginLatencyMs, captchaLatencyMs, captchaBytes;
  final String details;
  Map<String, Object> toJson() => {
    'ok': ok, 'http_status': httpStatus,
    'login_latency_ms': loginLatencyMs,
    'captcha_latency_ms': captchaLatencyMs,
    'captcha_bytes': captchaBytes, 'details': details,
  };
}

class DirectPortalProbe {
  static const _host = 'rajshaladarpan.rajasthan.gov.in';
  static const _maxBytes = 2 * 1024 * 1024;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final Map<String, Cookie> _cookies = {};

  void close() { _http.close(force: true); _cookies.clear(); }

  bool _allowed(Uri uri) => uri.scheme == 'https' &&
      uri.host.toLowerCase() == _host && uri.userInfo.isEmpty &&
      (uri.port == 443);

  Future<({Uri url, int status, Uint8ListBody body, String contentType})> _get(Uri uri) async {
    for (var redirect = 0; redirect <= 4; redirect++) {
      if (!_allowed(uri)) throw StateError('Blocked non-portal redirect');
      final req = await _http.getUrl(uri).timeout(const Duration(seconds: 12));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.acceptHeader, 'text/html,image/*;q=0.9,*/*;q=0.8');
      for (final cookie in _cookies.values) {
        if (!cookie.secure || uri.scheme == 'https') req.cookies.add(cookie);
      }
      final res = await req.close().timeout(const Duration(seconds: 15));
      for (final cookie in res.cookies) {
        // Probe cookie jar is memory-only. Never log or upload cookies.
        _cookies[cookie.name] = cookie;
      }
      if ([301, 302, 303, 307, 308].contains(res.statusCode)) {
        final location = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (location == null) throw StateError('Redirect without Location');
        uri = uri.resolve(location);
        continue;
      }
      final chunks = <int>[];
      await for (final chunk in res.timeout(const Duration(seconds: 15))) {
        if (chunks.length + chunk.length > _maxBytes) {
          throw StateError('Response exceeds diagnostic size limit');
        }
        chunks.addAll(chunk);
      }
      return (url: uri, status: res.statusCode,
        body: Uint8ListBody(chunks),
        contentType: res.headers.contentType?.mimeType ?? '');
    }
    throw StateError('Too many redirects');
  }

  // No passwords, no form submissions, no attendance endpoints.
  Future<PortalProbeResult> run({String node = 'SD1'}) async {
    if (!RegExp(r'^SD[1-5]$').hasMatch(node)) {
      throw ArgumentError.value(node, 'node', 'Expected SD1..SD5');
    }
    final url = Uri.https(_host, '/$node/Home/Public2/OfficeLoginNew.aspx');
    var pageMs = -1, captchaMs = -1, size = 0, status = 0;
    try {
      final sw = Stopwatch()..start();
      final page = await _get(url);
      pageMs = sw.elapsedMilliseconds;
      status = page.status;
      if (page.status != 200 || !page.contentType.contains('html')) {
        return PortalProbeResult(ok: false, httpStatus: status,
          loginLatencyMs: pageMs, captchaLatencyMs: captchaMs,
          captchaBytes: size, details: 'Login page was not HTML 200');
      }
      final html = utf8.decode(page.body.bytes, allowMalformed: true);
      if (!html.contains('__VIEWSTATE') || !html.contains('__EVENTVALIDATION')) {
        return PortalProbeResult(ok: false, httpStatus: status,
          loginLatencyMs: pageMs, captchaLatencyMs: captchaMs,
          captchaBytes: size, details: 'Expected WebForms controls missing');
      }
      // Extract only the src of the portal CAPTCHA image. Never expose the image or tokens in logs.
      final imgTags = RegExp(r'<img\b[^>]*>', caseSensitive: false, dotAll: true)
          .allMatches(html).map((m) => m.group(0)!).toList();
      String? captchaSrc;
      for (final tag in imgTags) {
        if (!RegExp(r'\b(?:bodyContent_Img2|imgCaptcha)\b', caseSensitive: false).hasMatch(tag)) continue;
        final match = RegExp('\\bsrc\\s*=\\s*["\\\']([^"\\\']+)["\\\']', caseSensitive: false).firstMatch(tag);
        captchaSrc = match?.group(1)?.replaceAll('&amp;', '&');
        if (captchaSrc != null) break;
      }
      if (captchaSrc == null) {
        return PortalProbeResult(ok: false, httpStatus: status,
          loginLatencyMs: pageMs, captchaLatencyMs: captchaMs,
          captchaBytes: size, details: 'CAPTCHA image source not found');
      }
      sw.reset(); sw.start();
      final image = await _get(page.url.resolve(captchaSrc));
      captchaMs = sw.elapsedMilliseconds;
      size = image.body.bytes.length;
      final imageOk = image.status == 200 && size > 0 &&
          (image.contentType.startsWith('image/') ||
           (size > 3 && image.body.bytes[0] == 0x89 && image.body.bytes[1] == 0x50));
      return PortalProbeResult(ok: imageOk, httpStatus: status,
        loginLatencyMs: pageMs, captchaLatencyMs: captchaMs,
        captchaBytes: size, details: imageOk ? 'GET-only connection verified' : 'CAPTCHA response was not an image');
    } catch (e) {
      return PortalProbeResult(ok: false, httpStatus: status,
        loginLatencyMs: pageMs, captchaLatencyMs: captchaMs,
        captchaBytes: size, details: 'GET-only probe failed: ${e.runtimeType}');
    }
  }
}

// Simple transport wrapper to avoid exposing a dependency on typed_data in API.
class Uint8ListBody {
  Uint8ListBody(this.bytes);
  final List<int> bytes;
}
