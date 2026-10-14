/// Complete Staff http_login.py conversion: one submitted login, no blind replay.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;

import '../../shaladarpan/direct/school_http.dart';
import '../../shaladarpan/direct/monthly_tasks_worker.dart'
    show MonthlyTasksWorker;
import 'http_session.dart';

typedef StaffCaptchaSolver = FutureOr<String> Function(Uint8List bytes);

class StaffLoginOutcome {
  const StaffLoginOutcome(
    this.success,
    this.code,
    this.message, [
    this.portalMessage = '',
  ]);
  final bool success;
  final String code, message, portalMessage;
}

String _sha(String value) => sha512.convert(utf8.encode(value)).toString();

/// Python str.lower/portal JS use full, contextual Unicode lowercasing.
/// Dart's simple lowercase differs for dotted I and Greek final sigma.
String staffLower(String value) {
  final units = value.runes.toList();
  final cased = RegExp(r'\p{Cased}', unicode: true);
  final ignored = RegExp(r'\p{Case_Ignorable}', unicode: true);
  final result = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    final rune = units[i];
    if (rune == 0x130) {
      result.write('i\u0307');
      continue;
    }
    if (rune == 0x3a3) {
      var before = i - 1, after = i + 1;
      while (before >= 0 &&
          ignored.hasMatch(String.fromCharCode(units[before]))) {
        before--;
      }
      while (after < units.length &&
          ignored.hasMatch(String.fromCharCode(units[after]))) {
        after++;
      }
      final finalSigma =
          before >= 0 &&
          cased.hasMatch(String.fromCharCode(units[before])) &&
          (after == units.length ||
              !cased.hasMatch(String.fromCharCode(units[after])));
      result.write(finalSigma ? '\u03c2' : '\u03c3');
    } else {
      result.write(String.fromCharCode(rune).toLowerCase());
    }
  }
  return result.toString();
}

String portalStaffMd5(String value) {
  const ascii =
      '01234567890123456789012345678901'
      ' !"#\$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ'
      '[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~';
  return md5
      .convert(
        value.codeUnits
            .map((c) => ascii.lastIndexOf(String.fromCharCode(c)) & 255)
            .toList(),
      )
      .toString();
}

Map<String, String> staffPasswordFields(
  String username,
  String password,
  String loginId,
  String nonce,
) {
  final first = _sha(staffLower(username) + password);
  final transformed = _sha(nonce + first), plain = _sha(password);
  return {
    'hdnLoginname': loginId,
    'hdntxtop': _sha(portalStaffMd5(loginId + password)),
    'txtUPNswd': transformed,
    'hdntxtUPswdname': transformed,
    'hdntxtUPswdname1': plain,
    'hdntxtUPswdname2': _sha(nonce + plain),
  };
}

String staffPortalNotice(String text) {
  final doc = html.parse(text);
  for (final id in ['spnmsg_p10', 'lblMessage', 'lblMsg', 'msgDiv']) {
    final element = doc.getElementById(id);
    if (element != null && staffText(element, ' ').isNotEmpty)
      return staffText(element, ' ');
  }
  final scripts = doc.querySelectorAll('script').map((s) => s.text).toList();
  final alert = RegExp(
    r'''^\s*(?:window\.)?alert\(\s*((?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'))\s*\)\s*;?\s*$''',
  );
  for (final script in scripts) {
    final match = alert.firstMatch(script);
    if (match != null) {
      final notice = MonthlyTasksWorker.literal(match[1]!);
      if (notice != null && notice.trim().isNotEmpty) return notice.trim();
    }
  }
  for (final (function, id) in [
    ('LogedUser', 'divLogedUser'),
    ('MsgUserPop', 'divimpmsg'),
  ]) {
    if (RegExp('\\b$function\\(\\s*\\)\\s*;').hasMatch(scripts.join('\n'))) {
      final node = doc.getElementById(id);
      if (node != null) return staffText(node, ' ');
    }
  }
  return '';
}

String staffAjaxUserId(SchoolHttpReply response) {
  if (response.statusCode != 200)
    throw const StaffHttpError(
      'LOGIN_AJAX_FAILED',
      'Portal user-ID lookup was unsuccessful.',
    );
  Object? value;
  try {
    value = (jsonDecode(response.text) as Map)['d'];
  } catch (_) {
    throw const StaffHttpError(
      'LOGIN_AJAX_CHANGED',
      'Unexpected Portal user-ID response.',
    );
  }
  // Python bool is an int subtype; retain that input behavior as well.
  if (!(value is String || value is int || value is bool) ||
      value.toString().trim().isEmpty)
    throw const StaffHttpError(
      'LOGIN_AJAX_CHANGED',
      'Portal did not return a login ID.',
    );
  return value is bool ? (value ? 'True' : 'False') : value.toString();
}

Future<StaffLoginOutcome> staffLoginOnce(
  StaffHttpSession session,
  String base,
  String username,
  String password,
  StaffCaptchaSolver solve,
) async {
  base = staffNodeBase(base);
  final user = username.trim();
  if (user.runes.isEmpty ||
      user.runes.length > 15 ||
      !RegExp(r'^[\p{L}\p{N}_]+$', unicode: true).hasMatch(user) ||
      password.isEmpty) {
    return const StaffLoginOutcome(
      false,
      'INVALID_PAYLOAD',
      'Username or password missing/invalid.',
    );
  }
  return session.exclusive(() async {
    if (session.authenticated)
      return const StaffLoginOutcome(
        false,
        'SESSION_ALREADY_ACTIVE',
        'Close the active Staff session before logging in again.',
      );
    final client = session.client;
    final doc = await client.get('$base$staffLoginPath');
    if (doc.statusCode != 200)
      throw const StaffHttpError(
        'PORTAL_UNAVAILABLE',
        'Could not load Staff login form.',
      );
    final form = parseStaffLoginForm(base, doc.text, doc.url.toString());
    final nonce = form.fields['hdnfld'] ?? '';
    if (nonce.isEmpty)
      throw const StaffHttpError(
        'LOGIN_FORM_CHANGED',
        'Portal nonce field missing.',
      );
    final ajax = doc.url.resolve('About.aspx/getStaff_Userid').toString();
    if (!staffSameNode(base, ajax))
      throw const StaffHttpError(
        'INVALID_REDIRECT',
        'Unexpected user ID endpoint.',
      );
    final lookup = await client.post(
      ajax,
      content: '{"Userid": ${jsonEncode(user)}}',
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Referer': doc.url.toString(),
      },
    );
    final loginId = staffAjaxUserId(lookup);
    final image = await client.get(
      form.captchaUrl,
      headers: {'Referer': doc.url.toString()},
    );
    if (image.statusCode != 200 ||
        image.bytes.isEmpty ||
        !(image.headers['content-type']?.join(',').toLowerCase() ?? '')
            .startsWith('image/'))
      throw const StaffHttpError(
        'CAPTCHA_UNAVAILABLE',
        'Portal CAPTCHA image is unavailable.',
      );
    final captcha = (await solve(image.bytes)).trim();
    if (captcha.isEmpty)
      return const StaffLoginOutcome(
        false,
        'CAPTCHA_UNREADABLE',
        'CAPTCHA could not be read.',
      );
    final payload = {
      ...form.fields,
      ...staffPasswordFields(user, password, loginId, nonce),
      form.userName: user,
      form.captchaName: captcha,
      form.submitName: form.submitValue,
    };
    final response = await client.post(
      form.action,
      data: payload,
      headers: {'Referer': doc.url.toString()},
    );
    if (!staffSameNode(base, response.url.toString()))
      throw const StaffHttpError(
        'INVALID_REDIRECT',
        'Portal login redirected outside selected node.',
      );
    final home = authenticatedStaffHome(response)
        ? response
        : await client.get('$base$staffHomePath');
    if (authenticatedStaffHome(home)) {
      session.base = base;
      session.user = user;
      session.authenticated = true;
      return const StaffLoginOutcome(
        true,
        'AUTHENTICATED',
        'Staff session verified.',
      );
    }
    final initial = staffPortalNotice(response.text);
    final notice = initial.isNotEmpty ? initial : staffPortalNotice(home.text);
    return StaffLoginOutcome(
      false,
      'LOGIN_NOT_VERIFIED',
      notice.isNotEmpty
          ? notice
          : 'Login was not verified by protected Staff Home.',
      notice,
    );
  });
}
