/// Behavior-preserving conversion of portals/shaladarpan/portal_state.py.
/// This module performs no login, navigation, retries, or submissions.
import 'dart:async';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class SchoolDocumentError implements Exception {
  SchoolDocumentError(this.result);

  final Map<String, dynamic> result;
  String? get code => result['code'] as String?;
  String get message => result['message'] as String;

  @override
  String toString() => message;
}

/// Optional adapter for callers that expose a page rather than an HTTP reply.
abstract interface class SchoolDocumentPage {
  Uri get url;
  FutureOr<String> content();
}

/// BeautifulSoup get_text(separator, strip=True) semantics for headings.
/// Trims each text node and excludes script/style contents.
String _headingText(dom.Element element) {
  final parts = <String>[];
  void visit(dom.Node node) {
    if (node is dom.Text) {
      final value = node.data.trim();
      if (value.isNotEmpty) parts.add(value);
    } else {
      if (node is dom.Element &&
          const {'script', 'style', 'template'}.contains(node.localName)) {
        return;
      }
      for (final child in node.nodes) {
        visit(child);
      }
    }
  }

  visit(element);
  return parts.join(' ');
}

/// Network/server failures never prove that credentials have expired.
/// Classification order deliberately matches the working Python source.
String? documentFailure(Object? url, String? html, [int status = 200]) {
  final source = html ?? '';
  final low = source.toLowerCase();
  if (status >= 500 ||
      const [
        'server error in',
        'nullreferenceexception',
        'validation of viewstate mac failed',
        'invalid postback or callback argument',
        'the state information is invalid',
      ].any(low.contains)) {
    return 'PAGE_NOT_READY';
  }
  if (status == 403) return 'ACCESS_DENIED';

  final soup = html_parser.parse(source);
  final schoolLogin =
      soup.querySelector('#bodyContent_txtUName') != null &&
      soup.querySelector('#bodyContent_txtUPswd') != null;
  final staffLogin =
      soup.querySelector('input#txt_Username') != null &&
      soup.querySelector('input#txtUPNswd, input#btn_StaffLogin') != null;
  final path = Uri.parse(url?.toString() ?? '').path.toLowerCase();
  final loginPath =
      RegExp(r'/(?:stafflogin|officelogin|login|default)(?:new)?\.aspx$')
          .hasMatch(path) ||
      RegExp(r'/public(?:\d+)?(?:/|$)').hasMatch(path);
  if (status == 401 || schoolLogin || staffLogin || loginPath) {
    return 'SESSION_EXPIRED';
  }
  if (status == 429) return 'RATE_LIMITED';
  if (status < 200 || status >= 300 || source.trim().isEmpty) {
    return 'PAGE_NOT_READY';
  }
  return null;
}

/// Returns already-read HTML, preserving Python result keys and messages.
String validateSchoolDocument(Object? url, String html, [int status = 200]) {
  final code = documentFailure(url, html, status);
  if (code == null) return html;

  final soup = html_parser.parse(html);
  final heading = soup.querySelector('h2') ?? soup.querySelector('h1');
  final message = switch (code) {
    'SESSION_EXPIRED' => 'School portal session expired.',
    'ACCESS_DENIED' => 'The School portal denied access to this document.',
    'RATE_LIMITED' =>
      'The School portal is limiting requests. Please retry later.',
    _ =>
      heading != null
          ? _headingText(heading)
          : 'The School portal document could not be read.',
  };
  throw SchoolDocumentError({
    'success': false,
    'code': code,
    'message': message,
  });
}

/// Supports package:http responses, the current DirectPortalAuth reply record,
/// and a page adapter. HTTP response status always overrides [status].
Future<String> requireSchoolDocument(Object page, [int? status]) async {
  if (page is http.Response) {
    final url = page.request?.url;
    if (url == null) {
      throw ArgumentError('An HTTP response with its request URL is required.');
    }
    return validateSchoolDocument(url, page.body, page.statusCode);
  }
  if (page is ({Uri url, int status, String html})) {
    return validateSchoolDocument(page.url, page.html, page.status);
  }
  if (page is SchoolDocumentPage) {
    return validateSchoolDocument(
      page.url,
      await page.content(),
      status ?? 200,
    );
  }
  throw ArgumentError('Expected an HTTP response or a portal page adapter.');
}
