/// HTTP document-evidence helpers from Staff portal_state.py.
/// Browser-native postback observation belongs to the later Staff browser workers.
import 'package:html/parser.dart' as html;

import 'http_session.dart';

class StaffPortalError extends StaffHttpError {
  const StaffPortalError(super.code, super.message);
}

String staffServerBase(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host != staffHost) return '';
  final match = RegExp(
    r'^/(SD[1-5])(?:/|$)',
    caseSensitive: false,
  ).firstMatch(uri.path);
  return match == null ? '' : 'https://$staffHost/${match[1]!.toUpperCase()}';
}

String? staffDocumentFailure(String url, String text, [int status = 200]) {
  final low = text.toLowerCase();
  if (status >= 500 ||
      [
        'server error in',
        'nullreferenceexception',
        'validation of viewstate mac failed',
        'invalid postback or callback argument',
        'the state information is invalid',
      ].any(low.contains))
    return 'PAGE_NOT_READY';
  if (status == 403) return 'ACCESS_DENIED';
  final doc = html.parse(text);
  final login =
      doc.querySelector('input#txt_Username') != null &&
      doc.querySelector('input#txtUPNswd,input#btn_StaffLogin') != null;
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  if (status == 401 ||
      login ||
      RegExp(r'/(?:stafflogin|officelogin|login|default)\.aspx$')
          .hasMatch(path))
    return 'SESSION_EXPIRED';
  return null;
}
