// Compatibility adapter for existing direct-login/attendance signatures.
// Automatic login uses the shared native School runtime; manual diagnostics remain available.
import 'dart:async';

import '../services/core/direct/mutation_dispatch.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../services/core/direct/coordinator.dart';
import '../services/portals/shaladarpan/direct/school_runtime.dart';
import '../services/portals/shaladarpan/direct/student_attendance_worker.dart';
import '../services/portals/shaladarpan/direct/leave_approvals.dart';
import '../services/portals/shaladarpan/direct/monthly_tasks_worker.dart';
import '../services/portals/shaladarpan/direct/school_http.dart';

class DirectLoginResult {
  const DirectLoginResult(
    this.success,
    this.message,
    this.node,
    this.elapsedMs, {
    this.response = const {},
  });
  final bool success;
  final String message;
  final String node;
  final int elapsedMs;

  /// Original auth/coordinator response, including portal messages and codes.
  final Map<String, dynamic> response;
}

class _Reply {
  const _Reply(
    this.url,
    this.status,
    this.body,
    this.mime, [
    this.headers = const {},
  ]);
  final Map<String, List<String>> headers;
  final Uri url;
  final int status;
  final Uint8List body;
  final String mime;
  String get text => utf8.decode(body, allowMalformed: true);
}

class _StoredCookie {
  _StoredCookie(this.cookie, this.domain, this.path, this.hostOnly);
  final Cookie cookie;
  final String domain;
  final String path;
  final bool hostOnly;
}

class DirectPortalAuth {
  DirectPortalAuth({this.node = 'SD1'}) {
    if (!RegExp(r'^SD[1-5]$').hasMatch(node)) {
      throw ArgumentError.value(node, 'node', 'Expected SD1..SD5');
    }
    _http.connectionTimeout = const Duration(seconds: 10);
  }

  DirectPortalAuth._shared(SchoolDirectRuntime runtime)
    : node = runtime.auth.activeServerBase.split('/').last {
    _runtime = runtime;
    _boundSchoolId = runtime.auth.activeSchoolId;
    _verified = runtime.coordinator.contextIsCurrent();
    _verifiedNode = node;
  }

  SchoolDirectRuntime? _runtime;
  String? _boundSchoolId;
  PortalCoordinator? get coordinator => _runtime?.coordinator;
  String? get authenticatedSchoolId {
    final runtime = _runtime;
    if (runtime == null) return null;
    final active = runtime.auth.activeSchoolId;
    // Recovery intentionally clears persisted auth state before the next login.
    // Retain handle ownership while verification remains false; never fabricate
    // an authenticated context or transfer a handle to a different account.
    return active.isEmpty ? _boundSchoolId : active;
  }

  /// Opaque identity matching Python school/generation/cookie review guards.
  /// Cookie values are never returned to screens or logs.
  String get schoolSessionIdentity {
    if (!isVerified) return '';
    final cookies =
        _runtime?.auth.loadSessionCookies() ??
        {
          for (final entry in _matching(Uri.https(_host, '/$verifiedNode/')))
            entry.name: entry.value,
        };
    if (cookies.isEmpty) return '';
    final names = cookies.keys.toList()..sort();
    final digest = sha256.convert(
      utf8.encode(jsonEncode({for (final name in names) name: cookies[name]})),
    );
    return '${authenticatedSchoolId ?? ''}/${coordinator?.generation}/$digest';
  }

  /// Ephemeral browser handoff used only inside a coordinated native print.
  /// No credentials are sent and the Dart authenticated session is retained.
  Map<String, String> nativePrintCookies() {
    if (!isVerified) return {};
    final cookies =
        _runtime?.auth.loadSessionCookies() ??
        {
          for (final cookie in _matching(Uri.https(_host, '/$verifiedNode/')))
            cookie.name: cookie.value,
        };
    if (cookies.isEmpty)
      throw StateError('School portal session is unavailable');
    return Map<String, String>.from(cookies);
  }

  bool sharesSessionWith(DirectPortalAuth other) =>
      _runtime != null && identical(_runtime, other._runtime);
  void detachSharedView() {
    _verified = false;
  }

  static Future<({DirectPortalAuth? auth, DirectLoginResult result})>
  automaticLogin({required String user, required String password}) async {
    final clock = Stopwatch()..start();
    final runtime = await SchoolDirectRuntime.get();
    final result = await runtime.coordinator.authenticate(user, password);
    final node = runtime.auth.activeServerBase.split('/').last;
    final success = result['success'] == true;
    return (
      auth: success ? DirectPortalAuth._shared(runtime) : null,
      result: DirectLoginResult(
        success,
        (result['portal_message'] ??
                result['message'] ??
                (success
                    ? 'Portal Live on HOME!'
                    : result['code'] ?? 'LOGIN_FAILED'))
            .toString(),
        node,
        clock.elapsedMilliseconds,
        response: Map<String, dynamic>.from(result),
      ),
    );
  }

  final String node;
  static const _host = 'rajshaladarpan.rajasthan.gov.in';
  static const _maxBytes = 2 * 1024 * 1024;
  final HttpClient _http = HttpClient();
  final List<_StoredCookie> _jar = [];
  final Map<String, String> _form = {};
  final Map<String, String> _fieldNames = {};
  Uri? _loginUrl;
  Uint8List? _captcha;
  String _salt = '';
  bool _prepared = false;
  bool _used = false;

  // Phase 3: shared authenticated transport. Never expose raw cookies.
  bool _verified = false;
  String _verifiedNode = '';
  bool get isVerified =>
      _verified &&
      (_runtime == null ||
          (_runtime!.coordinator.contextIsCurrent() &&
              _runtime!.auth.activeSchoolId == _boundSchoolId));

  /// An attached same-account runtime may be temporarily synchronizing. Its
  /// existing coordinator, rather than a UI getter, owns readiness/recovery.
  bool get canRecover =>
      _verified &&
      _runtime != null &&
      _runtime!.coordinator.status()['closed'] != true &&
      (_runtime!.auth.activeSchoolId.isEmpty ||
          _runtime!.auth.activeSchoolId == _boundSchoolId);

  String get verifiedNode =>
      _runtime?.auth.activeServerBase.split('/').last ?? _verifiedNode;

  Future<void> observeAttendanceUrl(Uri url) async {
    if (!_allowed(url)) throw StateError('Unexpected portal destination');
    final match = RegExp(
      r'^/(SD[1-5])/',
      caseSensitive: false,
    ).firstMatch(url.path);
    if (match == null) return;
    final resolved = match.group(1)!.toUpperCase();
    final runtime = _runtime;
    if (runtime != null) {
      final base = Uri.https(_host, '/$resolved').toString();
      if (runtime.auth.activeServerBase.toLowerCase() != base.toLowerCase()) {
        await runtime.auth.saveActiveServerBase(base);
      }
    } else {
      _verifiedNode = resolved;
    }
  }

  /// Original incharge GET, dependent selectors and explicitly confirmed actions.
  Future<AttendanceHttpReply> inchargeRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? action,
    String? control,
    String? controlId,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 25),
    bool userConfirmed = false,
  }) async {
    final path = RegExp(
      r'^/SD[1-5]/Home/School/AddSDSchemeIncharge\.aspx$',
      caseSensitive: false,
    );
    if (!isVerified || !_allowed(url) || !path.hasMatch(url.path)) {
      throw StateError('Incharge destination blocked');
    }
    if (fields != null) {
      if (!userConfirmed ||
          referer == null ||
          !_allowed(referer) ||
          referer.authority != url.authority ||
          !path.hasMatch(referer.path) ||
          control == null ||
          control.isEmpty ||
          controlId == null ||
          controlId.isEmpty) {
        throw StateError('Explicit incharge action confirmation required');
      }
      final commits = fields.keys
          .where(
            (name) => RegExp(
              r'btnAdd|btndeactive',
              caseSensitive: false,
            ).hasMatch(name),
          )
          .map((name) => name.replaceFirst(RegExp(r'\.[xy]$'), ''))
          .toSet();
      if (action == 'SELECTOR') {
        if (mutation ||
            commits.isNotEmpty ||
            fields['__EVENTTARGET'] != control ||
            !fields.containsKey(control) ||
            !{
              'ContentPlaceHolder1_ddlrole',
              'ContentPlaceHolder1_ddlTeacher',
            }.contains(controlId)) {
          throw StateError('Incharge selector navigation blocked');
        }
      } else {
        final expected = action == 'add'
            ? 'btnAdd'
            : action == 'deactive'
            ? 'btndeactive'
            : '';
        final named =
            fields.containsKey(control) ||
            (fields.containsKey('$control.x') &&
                fields.containsKey('$control.y'));
        if (!mutation ||
            expected.isEmpty ||
            !RegExp(expected, caseSensitive: false).hasMatch(controlId) ||
            (!named && fields['__EVENTTARGET'] != control) ||
            commits.any((name) => name != control)) {
          throw StateError('Reviewed incharge action control missing');
        }
      }
    } else if (mutation || action != null || control != null) {
      throw StateError('Incharge GET cannot be a commit');
    }
    final reply = await _send(
      url,
      method: fields == null ? 'GET' : 'POST',
      body: fields == null ? null : utf8.encode(AttendanceForm.encode(fields)),
      headers: fields == null
          ? const {}
          : {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Referer': referer.toString(),
            },
      timeout: timeout,
      followRedirects: fields == null,
    );
    await observeAttendanceUrl(reply.url);
    return (url: reply.url, status: reply.status, html: reply.text);
  }

  /// The original category report follows redirects for GET and session POST.
  /// Monthly workers validate current tokens, destination and reviewed action.
  /// POST redirects are disabled; the worker never retries a commit.
  Future<MonthlyReply> monthlyRequest(
    Uri url, {
    String? body,
    Uri? referer,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 30),
    bool followRedirects = true,
    SchoolCookieJar? cookies,
  }) async {
    if (!isVerified ||
        !_allowed(url) ||
        !RegExp(
          r'^/SD[1-5]/Home/School/(?:StudentAwardEntry|RMSA_SchoolMonthly_NP_tablets)\.aspx$',
          caseSensitive: false,
        ).hasMatch(url.path))
      throw StateError('Monthly portal destination blocked');
    if (body != null &&
        (referer == null ||
            referer.scheme != url.scheme ||
            referer.authority != url.authority ||
            referer.path.toLowerCase() != url.path.toLowerCase() ||
            followRedirects)) {
      throw StateError(
        'Monthly POST requires its native form and no redirects',
      );
    }
    final runtime = _runtime;
    if (runtime != null) {
      return runtime.auth.withAuthenticatedClient((client) async {
        final jar = cookies?.copy();
        final response = await client.request(
          body == null ? 'GET' : 'POST',
          url,
          body: body == null ? null : utf8.encode(body),
          headers: {
            if (body != null)
              'Content-Type': 'application/x-www-form-urlencoded',
            if (referer != null) 'Referer': referer.toString(),
            ...headers,
          },
          timeout: timeout,
          followRedirects: followRedirects,
          cookieJar: jar,
        );
        return (
          url: response.url,
          status: response.statusCode,
          html: response.text,
          cookies: (jar ?? client.jar).copy(),
        );
      });
    }
    final jar =
        cookies?.copy() ??
        SchoolCookieJar({
          for (final cookie in _matching(url)) cookie.name: cookie.value,
        });
    final response = await _send(
      url,
      method: body == null ? 'GET' : 'POST',
      body: body == null ? null : utf8.encode(body),
      headers: {
        if (body != null) 'Content-Type': 'application/x-www-form-urlencoded',
        if (referer != null) 'Referer': referer.toString(),
        ...headers,
      },
      timeout: timeout,
      followRedirects: followRedirects,
      cookieJar: jar,
    );
    return (
      url: response.url,
      status: response.status,
      html: response.text,
      cookies: jar,
    );
  }

  /// Read-only NIC catalog: only its reviewed academic-session postback.
  Future<AttendanceHttpReply> nicCatalogRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    const session = r'ctl00$ContentPlaceHolder1$ddlSession';
    if (!isVerified ||
        !_allowed(url) ||
        !RegExp(
          r'^/SD[1-5]/Home/School/SchoolStudentProfiles_New\.aspx$',
          caseSensitive: false,
        ).hasMatch(url.path)) {
      throw StateError('NIC catalog destination blocked');
    }
    if (fields != null &&
        (referer == null ||
            referer != url ||
            fields['__EVENTTARGET'] != session ||
            fields['__EVENTARGUMENT'] != '' ||
            fields[session] is! String ||
            fields.keys.any(
              (key) => RegExp(
                r'(?:btn|button|imagebutton|bt_).*|finalconfirm',
                caseSensitive: false,
              ).hasMatch(key),
            ))) {
      throw StateError('Reviewed NIC academic session postback required');
    }
    final reply = await _send(
      url,
      method: fields == null ? 'GET' : 'POST',
      body: fields == null ? null : utf8.encode(AttendanceForm.encode(fields)),
      headers: fields == null
          ? const {}
          : {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Referer': referer.toString(),
            },
      timeout: timeout,
      followRedirects: true,
    );
    await observeAttendanceUrl(reply.url);
    return (url: reply.url, status: reply.status, html: reply.text);
  }

  Future<AttendanceHttpReply> categoryEnrolmentRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? sessionControl,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final path = RegExp(
      r'^/SD[1-5]/Home/School/GenderWiseSchoolStudentReport\.aspx$',
      caseSensitive: false,
    );
    if (!isVerified || !_allowed(url) || !path.hasMatch(url.path))
      throw StateError('Enrolment report destination blocked');
    if (fields != null) {
      if (referer == null ||
          !_allowed(referer) ||
          referer.authority != url.authority ||
          referer.path.toLowerCase() != url.path.toLowerCase() ||
          sessionControl == null ||
          sessionControl.isEmpty ||
          fields['__EVENTTARGET'] != sessionControl ||
          fields[sessionControl] is! String ||
          !RegExp(r'^\d{4}-\d{2}$')
              .hasMatch(fields[sessionControl] as String)) {
        throw StateError('Reviewed academic session selector required');
      }
      if (fields.keys.any(
        (k) => RegExp(
          r'btn(?:save|submit|approve|deactive)|finalconfirm',
          caseSensitive: false,
        ).hasMatch(k),
      )) {
        throw StateError('Enrolment report mutation blocked');
      }
    }
    final reply = await _send(
      url,
      method: fields == null ? 'GET' : 'POST',
      body: fields == null ? null : utf8.encode(AttendanceForm.encode(fields)),
      headers: fields == null
          ? const {}
          : {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Referer': referer.toString(),
            },
      timeout: timeout,
      followRedirects: true,
    );
    await observeAttendanceUrl(reply.url);
    return (url: reply.url, status: reply.status, html: reply.text);
  }

  /// Read-only native KPI Show; POST redirects follow the Python worker policy.
  Future<AttendanceHttpReply> studentKpiRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? showControl,
    String? showControlId,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final path = RegExp(
      r'^/SD[1-5]/Home/School/StudentdailyAttendanceStatus_Web_NewVersion\.aspx$',
      caseSensitive: false,
    );
    if (!isVerified || !_allowed(url) || !path.hasMatch(url.path)) {
      throw StateError('Student KPI destination blocked');
    }
    if (fields != null) {
      if (referer == null ||
          !_allowed(referer) ||
          referer.authority != url.authority ||
          referer.path != url.path) {
        throw StateError('Student KPI form destination blocked');
      }
      final commits = RegExp(
        r'btn(?:submit|save|verify|attendance)|finalconfirm',
        caseSensitive: false,
      );
      if (fields.keys.any(commits.hasMatch) ||
          commits.hasMatch(fields['__EVENTTARGET']?.toString() ?? '')) {
        throw StateError('Student KPI mutation blocked');
      }
      final show = RegExp(r'(?:^|_)btn_Show$');
      if (showControl == null ||
          showControl.isEmpty ||
          showControlId == null ||
          !show.hasMatch(showControlId) ||
          (!fields.containsKey(showControl) &&
              !(fields.containsKey('$showControl.x') &&
                  fields.containsKey('$showControl.y')) &&
              fields['__EVENTTARGET'] != showControl)) {
        throw StateError('Student KPI Show control missing');
      }
    }
    final reply = await _send(
      url,
      method: fields == null ? 'GET' : 'POST',
      body: fields == null ? null : utf8.encode(AttendanceForm.encode(fields)),
      headers: fields == null
          ? const {}
          : {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Referer': referer.toString(),
            },
      timeout: timeout,
      followRedirects: fields == null,
    );
    await observeAttendanceUrl(reply.url);
    return (url: reply.url, status: reply.status, html: reply.text);
  }

  /// Class-mapping GET and a single explicitly reviewed native Save control.
  Future<AttendanceHttpReply> classMappingRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? saveControl,
    Duration timeout = const Duration(seconds: 25),
    bool userConfirmed = false,
  }) async {
    final path = RegExp(
      r'^/SD[1-5]/Home/School/TeacherClassMapping\.aspx$',
      caseSensitive: false,
    );
    if (!isVerified || !_allowed(url) || !path.hasMatch(url.path)) {
      throw StateError('Class mapping destination blocked');
    }
    if (fields != null) {
      if (!userConfirmed ||
          referer == null ||
          !_allowed(referer) ||
          referer.authority != url.authority ||
          !path.hasMatch(referer.path) ||
          saveControl == null ||
          saveControl.isEmpty) {
        throw StateError('Explicit class mapping confirmation required');
      }
      final named =
          fields.containsKey(saveControl) ||
          (fields.containsKey('$saveControl.x') &&
              fields.containsKey('$saveControl.y'));
      if (!named && fields['__EVENTTARGET'] != saveControl) {
        throw StateError('Reviewed mapping Save control missing');
      }
    } else if (saveControl != null) {
      throw StateError('Mapping GET cannot be a commit');
    }
    final reply = await _send(
      url,
      method: fields == null ? 'GET' : 'POST',
      body: fields == null ? null : utf8.encode(AttendanceForm.encode(fields)),
      headers: fields == null
          ? const {}
          : {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Referer': referer.toString(),
            },
      timeout: timeout,
      followRedirects: fields == null,
    );
    await observeAttendanceUrl(reply.url);
    return (url: reply.url, status: reply.status, html: reply.text);
  }

  /// The staff HTTPX worker follows GET redirects, but every POST explicitly
  /// uses follow_redirects=False. Only observed staff controls are admitted.
  Future<AttendanceHttpReply> staffAttendanceRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? action,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 25),
    bool userConfirmed = false,
  }) async {
    final path = RegExp(
      r'^/SD[1-5]/Home/School/Staff_DailyAttendanceEntry\.aspx$',
      caseSensitive: false,
    );
    if (!isVerified ||
        !_allowed(url) ||
        !path.hasMatch(url.path) ||
        (fields != null &&
            (referer == null ||
                !_allowed(referer) ||
                !path.hasMatch(referer.path) ||
                referer.authority != url.authority))) {
      throw StateError('Staff attendance destination blocked');
    }
    if (fields != null) {
      if (action == 'SCHOOL_ENTRY') {
        if (mutation ||
            !RegExp(
              r'lnkSchoolName|lnkbtnSchool',
              caseSensitive: false,
            ).hasMatch('${fields['__EVENTTARGET'] ?? ''}'))
          throw StateError('Staff school navigation blocked');
      } else if (!mutation ||
          !userConfirmed ||
          !{'SELECTOR', 'SAVE', 'FINAL'}.contains(action)) {
        throw StateError('Explicit staff attendance confirmation required');
      }
      final controls = fields.keys
          .where(
            (key) => RegExp(
              r'btnMarkAttendance|btn_Save|btnFinalConifrm|btnFinalConfirm',
              caseSensitive: false,
            ).hasMatch(key),
          )
          .toList();
      final event = fields['__EVENTTARGET']?.toString() ?? '';
      if (action == 'SELECTOR') {
        if (controls.isNotEmpty || event.isEmpty || !fields.containsKey(event))
          throw StateError('Staff selector postback blocked');
      } else if (action == 'SAVE' || action == 'FINAL') {
        final approved = action == 'SAVE'
            ? r'btnMarkAttendance|btn_Save'
            : r'btnFinalConifrm|btnFinalConfirm';
        final valid = controls
            .where(
              (key) => RegExp(approved, caseSensitive: false).hasMatch(key),
            )
            .length;
        if (!(valid == 1 && controls.length == 1) &&
            !(controls.isEmpty &&
                RegExp(approved, caseSensitive: false).hasMatch(event)))
          throw StateError('Staff commit control blocked');
      } else if (controls.isNotEmpty) {
        throw StateError('Mutation in staff read navigation blocked');
      }
    } else if (mutation || action != null) {
      throw StateError('Staff GET cannot be a commit');
    }
    final reply = await _send(
      url,
      method: fields == null ? 'GET' : 'POST',
      body: fields == null ? null : utf8.encode(AttendanceForm.encode(fields)),
      headers: fields == null
          ? const {}
          : {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Referer': referer.toString(),
            },
      timeout: timeout,
      followRedirects: fields == null,
    );
    await observeAttendanceUrl(reply.url);
    return (url: reply.url, status: reply.status, html: reply.text);
  }

  /// Leave navigation and explicitly confirmed actions share the School pool.
  Future<LeaveHttpReply> leaveApprovalRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? action,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 25),
    bool userConfirmed = false,
  }) async {
    final path = RegExp(
      r'^/SD[1-5]/Home/School/Staff_LeaveApproval\.aspx$',
      caseSensitive: false,
    );
    if (!isVerified ||
        !_allowed(url) ||
        !path.hasMatch(url.path) ||
        (fields != null &&
            (referer == null ||
                !_allowed(referer) ||
                referer.authority != url.authority ||
                !path.hasMatch(referer.path))))
      throw StateError('Leave approval destination blocked');
    if (fields != null) {
      final target = fields['__EVENTTARGET']?.toString() ?? '';
      final commits = fields.keys
          .where(
            (name) => RegExp(
              r'btnApprove|btnYes|btnReject',
              caseSensitive: false,
            ).hasMatch(name),
          )
          .map((name) => name.replaceFirst(RegExp(r'\.[xy]$'), ''))
          .toSet();
      if (action == 'APPROVE') {
        if (!mutation ||
            !userConfirmed ||
            commits.length != 1 ||
            !RegExp(
              'btnApprove',
              caseSensitive: false,
            ).hasMatch(commits.single))
          throw StateError('Explicit leave approval confirmation required');
      } else {
        if (mutation || commits.isNotEmpty)
          throw StateError('Mutation control in leave READ blocked');
        if (action == 'SCHOOL_ENTRY') {
          if (!target.contains('lnkSchoolName'))
            throw StateError('Leave school navigation blocked');
        } else if (action == 'HISTORY') {
          if (target != LeaveApprovalsWorker.historyTarget)
            throw StateError('Leave history navigation blocked');
        } else {
          throw StateError('Unrecognized leave navigation');
        }
      }
    } else if (mutation || action != null) {
      throw StateError('Leave GET cannot be a mutation');
    }
    final reply = await _send(
      url,
      method: fields == null ? 'GET' : 'POST',
      body: fields == null ? null : utf8.encode(AttendanceForm.encode(fields)),
      headers: fields == null
          ? const {}
          : {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Referer': referer.toString(),
            },
      timeout: timeout,
      followRedirects: fields == null,
    );
    await observeAttendanceUrl(reply.url);
    return (
      url: reply.url,
      status: reply.status,
      html: reply.text,
      headers: reply.headers,
    );
  }

  Future<AttendanceHttpReply> schoolReportRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    if (!isVerified ||
        mutation ||
        !_allowed(url) ||
        !RegExp(
          r'^/SD[1-5]/Home/School/(Home_New|StudentDetails)\.aspx$',
          caseSensitive: false,
        ).hasMatch(url.path)) {
      throw StateError('School report destination/action blocked');
    }
    final payload = fields == null ? null : Map<String, Object?>.from(fields);
    if (payload != null) {
      if (!url.path.toLowerCase().endsWith('/studentdetails.aspx') ||
          payload.remove('__READ_ONLY_ACTION') != 'GENDER_SHOW' ||
          referer == null ||
          !_allowed(referer) ||
          !referer.path.toLowerCase().endsWith('/studentdetails.aspx')) {
        throw StateError('Only approved gender Show postback is allowed');
      }
      if (payload.keys.any(
        (key) => RegExp(
          r'btnsubmit|btnsave|btnverify|finalconfirm|btnattendance',
          caseSensitive: false,
        ).hasMatch(key),
      )) {
        throw StateError('Mutation control blocked in report');
      }
    }
    final reply = await _send(
      url,
      method: payload == null ? 'GET' : 'POST',
      body: payload == null
          ? null
          : utf8.encode(AttendanceForm.encode(payload)),
      headers: payload == null
          ? const {}
          : {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Referer': referer.toString(),
            },
    );
    await observeAttendanceUrl(reply.url);
    return (url: reply.url, status: reply.status, html: reply.text);
  }

  Future<({Uri url, int status, Uint8List bytes, String contentType})>
  schoolReportLogo(Uri url) async {
    if (!isVerified || !_allowed(url))
      throw StateError('School logo URL blocked');
    final runtime = _runtime;
    if (runtime != null) {
      final reply = await runtime.auth.withAuthenticatedClient(
        (client) =>
            client.get(url.toString(), timeout: const Duration(seconds: 10)),
      );
      return (
        url: reply.url,
        status: reply.statusCode,
        bytes: reply.bytes,
        contentType: reply.headers['content-type']?.join(';') ?? '',
      );
    }
    final reply = await _send(url);
    return (
      url: reply.url,
      status: reply.status,
      bytes: reply.body,
      contentType: reply.mime,
    );
  }

  Future<({Uri url, int status, String html})> attendanceRequest(
    Uri url, {
    Map<String, Object?>? navigationFields,
    Uri? referer,
  }) async {
    if (!isVerified) throw StateError('Direct login must be verified first');
    final safePath = RegExp(
      r'^/SD[1-5]/Home/School/(StudentdailyAttendanceStatus_Web_NewVersion|Home_New)\.aspx$',
      caseSensitive: false,
    );
    if (!_allowed(url) ||
        !safePath.hasMatch(url.path) ||
        url.query.isNotEmpty) {
      throw StateError('Attendance diagnostic URL blocked');
    }
    if (navigationFields != null) {
      if (url.path.toLowerCase().endsWith('/home_new.aspx')) {
        throw StateError('Home recovery supports GET only');
      }
      final keys = navigationFields.keys.map((e) => e.toLowerCase()).toList();
      if (keys.any(
        (k) =>
            k.contains('btnsubmit') ||
            k.contains('btnsave') ||
            k.contains('btnverify') ||
            k.contains('finalconfirm') ||
            k.contains('btnattendance'),
      )) {
        throw StateError('Mutation control blocked');
      }
      if (navigationFields['__READ_ONLY_ACTION'] != 'SHOW' &&
          navigationFields['__READ_ONLY_ACTION'] != 'CLASS_ENTRY') {
        throw StateError('Only approved read-navigation actions allowed');
      }
      final fields = Map<String, Object?>.from(navigationFields)
        ..remove('__READ_ONLY_ACTION');
      final payload = AttendanceForm.encode(fields);
      final reply = await _send(
        url,
        method: 'POST',
        body: utf8.encode(payload),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer': (referer ?? url).toString(),
        },
      );
      return (url: reply.url, status: reply.status, html: reply.text);
    }
    final reply = await _send(url);
    return (url: reply.url, status: reply.status, html: reply.text);
  }

  // EXPLICIT mutation transport: one POST only, never retries after uncertainty.
  // It is intentionally separate from attendanceRequest's READ-only allowlist.
  Future<({Uri url, int status, String html})> submitStudentAttendanceOnce(
    Uri url, {
    required Map<String, Object?> fields,
    required Uri referer,
    required bool userConfirmed,
  }) async {
    MutationDispatch.current?.observeNativeTransport();
    if (!isVerified || !userConfirmed) {
      throw StateError(
        'Verified session and explicit user confirmation required',
      );
    }
    final allowedPath = RegExp(
      r'^/SD[1-5]/Home/School/StudentdailyAttendanceStatus_Web_NewVersion\.aspx$',
      caseSensitive: false,
    );
    if (!_allowed(url) ||
        !allowedPath.hasMatch(url.path) ||
        url.query.isNotEmpty ||
        !_allowed(referer) ||
        !allowedPath.hasMatch(referer.path)) {
      throw StateError('Student attendance mutation destination blocked');
    }
    const saveButtons = {
      'ContentPlaceHolder1_btnsubmit',
      'ContentPlaceHolder1_btnSave',
      'ContentPlaceHolder1_btn_Save',
      'ContentPlaceHolder1_btnSubmit',
      'ContentPlaceHolder1_btn_Submit',
      'ContentPlaceHolder1_btnAttendanceSubmit',
      'ContentPlaceHolder1_btnVerify',
    };
    final payloadFields = Map<String, Object?>.from(fields);
    final observedId = payloadFields
        .remove('__APPROVED_SAVE_CONTROL')
        ?.toString();
    final observedName = payloadFields
        .remove('__APPROVED_SAVE_NAME')
        ?.toString();
    final active = payloadFields.keys
        .where(
          (name) => saveButtons.any(
            (id) =>
                name == id ||
                name.endsWith('\$${id.split('_').last}') ||
                name.endsWith('\$${id.split('_').last}.x'),
          ),
        )
        .toList();
    final observed =
        observedId != null &&
        observedId.isNotEmpty &&
        observedName != null &&
        observedName.isNotEmpty &&
        (payloadFields.containsKey(observedName) ||
            payloadFields.containsKey('$observedName.x') ||
            payloadFields['__EVENTTARGET'] == observedName);
    if (active.length != 1 && !(active.isEmpty && observed)) {
      throw StateError('Exactly one approved portal save control required');
    }
    if (fields.containsKey('__READ_ONLY_ACTION')) {
      throw StateError('Read-only marker cannot appear in mutation');
    }
    final payload = AttendanceForm.encode(payloadFields);
    final response = await _send(
      url,
      method: 'POST',
      allowPostRedirects: false,
      body: utf8.encode(payload),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': referer.toString(),
      },
    );
    return (url: response.url, status: response.status, html: response.text);
  }

  Uint8List? get captchaImage => _captcha;
  void close() {
    final runtime = _runtime;
    if (runtime != null) {
      // The old signature stays synchronous; retirement drains in the background.
      unawaited(
        runtime.close().then<void>(
          (_) {
            _verified = false;
            _verifiedNode = '';
          },
          onError: (Object _, StackTrace __) {
            // Runtime retains its retirement barrier if work has not settled.
          },
        ),
      );
      _http.close();
      return;
    }
    _http.close(force: true);
    _jar.clear();
    _form.clear();
    _fieldNames.clear();
    _captcha = null;
    _verified = false;
    _verifiedNode = '';
  }

  bool _allowed(Uri url) =>
      url.scheme == 'https' &&
      url.host.toLowerCase() == _host &&
      url.port == 443 &&
      url.userInfo.isEmpty;

  String _cookiePath(String path) {
    if (!path.startsWith('/')) return '/';
    final n = path.lastIndexOf('/');
    return path.substring(0, n + 1);
  }

  void _storeCookies(HttpClientResponse res, Uri url) {
    for (final c in res.cookies) {
      final hostOnly = c.domain == null || c.domain!.isEmpty;
      final domain = hostOnly
          ? url.host
          : c.domain!.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
      if (domain != _host) continue;
      final path = c.path?.isNotEmpty == true ? c.path! : _cookiePath(url.path);
      _jar.removeWhere(
        (v) => v.cookie.name == c.name && v.domain == domain && v.path == path,
      );
      if (c.maxAge == 0 ||
          (c.expires != null && c.expires!.isBefore(DateTime.now())))
        continue;
      _jar.add(_StoredCookie(c, domain, path, hostOnly));
    }
  }

  List<Cookie> _matching(Uri url) {
    final now = DateTime.now();
    return _jar
        .where((entry) {
          final c = entry.cookie;
          if (c.expires != null && c.expires!.isBefore(now)) return false;
          final host = url.host.toLowerCase();
          if (entry.hostOnly
              ? host != entry.domain
              : !(host == entry.domain || host.endsWith('.${entry.domain}')))
            return false;
          if (!url.path.startsWith(entry.path)) return false;
          if (c.secure && url.scheme != 'https') return false;
          return true;
        })
        .map((e) => e.cookie)
        .toList();
  }

  Future<_Reply> _send(
    Uri initial, {
    String method = 'GET',
    List<int>? body,
    Map<String, String> headers = const {},
    Duration? timeout,
    bool followRedirects = true,
    bool allowPostRedirects = true,
    SchoolCookieJar? cookieJar,
  }) async {
    final runtime = _runtime;
    if (runtime != null) {
      final reply = await runtime.auth.withAuthenticatedClient(
        (client) => client.request(
          method,
          initial,
          body: body,
          headers: headers,
          timeout: timeout,
          followRedirects: followRedirects,
          allowPostRedirects: allowPostRedirects,
          cookieJar: cookieJar,
        ),
      );
      final mime = reply.headers['content-type']?.join(';') ?? '';
      return _Reply(
        reply.url,
        reply.statusCode,
        reply.bytes,
        mime,
        reply.headers,
      );
    }
    var url = initial;
    var verb = method;
    var data = body;
    for (var hops = 0; hops <= 5; hops++) {
      if (!_allowed(url)) throw StateError('Blocked non-portal URL/redirect');
      if (verb == 'POST') MutationDispatch.current?.startDispatch();
      final req = await _http
          .openUrl(verb, url)
          .timeout(timeout ?? const Duration(seconds: 12));
      req.followRedirects = false;
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36',
      );
      req.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,image/*;q=0.9,*/*;q=0.8',
      );
      req.headers.set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.5');
      for (final e in headers.entries) {
        req.headers.set(e.key, e.value);
      }
      req.cookies.addAll(cookieJar?.matching(url) ?? _matching(url));
      if (data != null) {
        req.contentLength = data.length;
        req.add(data);
      }
      final res = await req.close().timeout(
        timeout ?? const Duration(seconds: 15),
      );
      _storeCookies(res, url);
      cookieJar?.receive(res.cookies, url);
      final blockedPostReplay =
          !allowPostRedirects &&
          verb == 'POST' &&
          [307, 308].contains(res.statusCode);
      if (followRedirects &&
          !blockedPostReplay &&
          [301, 302, 303, 307, 308].contains(res.statusCode)) {
        final location = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (location == null) throw StateError('Redirect missing Location');
        final next = url.resolve(location);
        if (!_allowed(next)) throw StateError('Blocked non-portal redirect');
        if ([301, 302, 303].contains(res.statusCode) && verb == 'POST') {
          verb = 'GET';
          data = null;
        }
        url = next;
        continue;
      }
      final builder = BytesBuilder(copy: false);
      final responseHeaders = <String, List<String>>{};
      res.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = List.of(values);
      });
      await for (final chunk in res.timeout(
        timeout ?? const Duration(seconds: 15),
      )) {
        if (builder.length + chunk.length > _maxBytes) {
          throw StateError('Response too large');
        }
        builder.add(chunk);
      }
      return _Reply(
        url,
        res.statusCode,
        builder.takeBytes(),
        res.headers.contentType?.mimeType ?? '',
        responseHeaders,
      );
    }
    throw StateError('Too many redirects');
  }

  String _decode(String v) => v
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  String? _attr(String tag, String name) {
    final m = RegExp(
      '(?:^|\\s)${RegExp.escape(name)}\\s*=\\s*(["\\\'])(.*?)\\1',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(tag);
    if (m != null) return _decode(m.group(2)!);
    final unquoted = RegExp(
      '(?:^|\\s)${RegExp.escape(name)}\\s*=\\s*([^\\s>]+)',
      caseSensitive: false,
    ).firstMatch(tag);
    return unquoted == null ? null : _decode(unquoted.group(1)!);
  }

  String? _inputId(Map<String, String> fields, String pattern) {
    final r = RegExp(pattern, caseSensitive: false);
    for (final e in fields.keys) {
      if (r.hasMatch(e)) return e;
    }
    return null;
  }

  String? _imageSrc(String html) {
    for (final m in RegExp(
      r'<img\b[^>]*>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html)) {
      final tag = m.group(0)!;
      final id = _attr(tag, 'id') ?? '';
      if (id == 'bodyContent_Img2' || id == 'imgCaptcha')
        return _attr(tag, 'src');
    }
    return null;
  }

  Future<void> prepare() async {
    if (_prepared) throw StateError('Already prepared; create a fresh test');
    _jar.clear();
    _form.clear();
    _fieldNames.clear();
    final url = Uri.https(_host, '/$node/Home/Public2/OfficeLoginNew.aspx');
    final page = await _send(url);
    if (page.status != 200 || !page.mime.contains('html')) {
      throw StateError('Login page HTTP ${page.status}');
    }
    final html = page.text;
    final byId = <String, String>{};
    for (final m in RegExp(
      r'<input\b[^>]*>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html)) {
      final tag = m.group(0)!;
      final key = _attr(tag, 'name');
      final id = _attr(tag, 'id');
      final val = _attr(tag, 'value') ?? '';
      final type = (_attr(tag, 'type') ?? 'text').toLowerCase();
      if (key != null && type == 'hidden') _form[key] = val;
      if (id != null && key != null) byId[id] = key;
    }
    _fieldNames.addAll(byId);
    final vs = _form['__VIEWSTATE'];
    final ev = _form['__EVENTVALIDATION'];
    if (vs == null || ev == null)
      throw StateError('WebForms hidden tokens missing');
    final saltKey = _inputId(byId, 'hdnfld');
    _salt = saltKey == null ? '' : (_form[byId[saltKey]] ?? '');
    final src = _imageSrc(html) ?? 'Captcha.aspx';
    final image = await _send(page.url.resolve(src));
    if (image.status != 200 ||
        image.body.isEmpty ||
        !(image.mime.startsWith('image/') ||
            (image.body.length > 3 &&
                image.body[0] == 0x89 &&
                image.body[1] == 0x50))) {
      throw StateError('CAPTCHA image unavailable');
    }
    _captcha = image.body;
    _loginUrl = page.url;
    _prepared = true;
  }

  String _sha(String v) => sha512.convert(utf8.encode(v)).toString();
  String _md5(String v) => md5.convert(utf8.encode(v)).toString();

  Future<DirectLoginResult> login({
    required String user,
    required String password,
    required String captcha,
  }) async {
    if (!_prepared || _loginUrl == null || _used)
      throw StateError('Prepare a fresh CAPTCHA first');
    _used = true; // Never replay a login POST on ambiguous outcome.
    final sw = Stopwatch()..start();
    user = user.trim();
    captcha = captcha.trim();
    if (user.isEmpty || password.isEmpty || captcha.isEmpty) {
      return const DirectLoginResult(
        false,
        'School ID, password and CAPTCHA required',
        '',
        0,
      );
    }
    final loginUrl = _loginUrl!;
    var loginId = user;
    try {
      final ajax = await _send(
        loginUrl.resolve('OfficeLoginNew.aspx/getUserid'),
        method: 'POST',
        body: utf8.encode(jsonEncode({'Userid': user})),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'X-Requested-With': 'XMLHttpRequest',
        },
      );
      if (ajax.status == 200) {
        final decoded = jsonDecode(ajax.text);
        if (decoded is Map && decoded['d'] != null)
          loginId = decoded['d'].toString();
      }
    } catch (_) {
      /* Python auth uses supplied user as fallback. */
    }

    String findField(String part, String fallback) {
      for (final field in _fieldNames.entries) {
        if (field.key.toLowerCase() == part.toLowerCase() ||
            field.key.toLowerCase().endsWith('_${part.toLowerCase()}')) {
          return field.value;
        }
      }
      return fallback;
    }

    final userField = findField('txtUName', 'ctl00\$bodyContent\$txtUName');
    final passField = findField('txtUPswd', 'ctl00\$bodyContent\$txtUPswd');
    final capField = findField(
      'txt_Captchaname',
      'ctl00\$bodyContent\$txt_Captchaname',
    );
    final btnField = findField('btn_Login', 'ctl00\$bodyContent\$btn_Login');
    final hashedPass = _sha(password);
    final values = <String, String>{
      ..._form,
      userField: user,
      passField: _sha(_salt + _sha(loginId.toLowerCase() + password)),
      'ctl00\$bodyContent\$hdnLoginid': loginId,
      'ctl00\$bodyContent\$hdnfld': _salt,
      'ctl00\$bodyContent\$hdntxtop': _sha(_md5(loginId + password)),
      'ctl00\$bodyContent\$hdntxtUPswdname': hashedPass,
      'ctl00\$bodyContent\$hdntxtUPswdname1': _sha(_salt + hashedPass),
      capField: captcha,
      btnField: 'Login',
    };
    final form = values.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    final submitted = await _send(
      loginUrl,
      method: 'POST',
      body: utf8.encode(form),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': loginUrl.toString(),
      },
    );
    final postPath = submitted.url.path.toLowerCase();
    final resolvedNode =
        RegExp(
          r'^/(SD[1-5])/',
          caseSensitive: false,
        ).firstMatch(submitted.url.path)?.group(1)?.toUpperCase() ??
        node;
    if (submitted.status != 200) {
      return DirectLoginResult(
        false,
        'LOGIN_POST HTTP ${submitted.status}; path=$postPath',
        resolvedNode,
        sw.elapsedMilliseconds,
      );
    }

    String portalCode(String html) {
      // Classify only; never expose untrusted response text or form secrets.
      final match = RegExp(
        r'''<(?:span|div|label)\b[^>]*(?:lblMsg|lblError)[^>]*>(.*?)</(?:span|div|label)>''',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(html);
      if (match == null) return 'none';
      final msg = match
          .group(1)!
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .toLowerCase()
          .trim();
      if (msg.isEmpty) return 'none';
      if (msg.contains('captcha') || msg.contains('कैप्चा')) return 'captcha';
      if (msg.contains('password') || msg.contains('पासवर्ड'))
        return 'password';
      if (msg.contains('invalid') ||
          msg.contains('incorrect') ||
          msg.contains('गलत'))
        return 'invalid-input';
      return 'portal-message';
    }

    final rejection = portalCode(submitted.text);
    _Reply home;
    try {
      home = await _send(
        Uri.https(_host, '/$resolvedNode/Home/School/Home_New.aspx'),
      );
    } catch (e) {
      return DirectLoginResult(
        false,
        'HOME_GET ${e.runtimeType}; postPath=$postPath; portal=$rejection',
        resolvedNode,
        sw.elapsedMilliseconds,
      );
    }
    final homePath = home.url.path.toLowerCase();
    final loginForm = RegExp(
      r'''id\s*=\s*["'](?:bodycontent_txtuname|txtuserid)["']''',
      caseSensitive: false,
    ).hasMatch(home.text);
    final dead =
        homePath.contains('officelogin') ||
        homePath.contains('/public/') ||
        homePath.contains('default.aspx') ||
        homePath.contains('login.aspx');
    final schoolLabel = RegExp(
      r'''id\s*=\s*["'][^"']*lblschoolname["'][^>]*>\s*[^<\s]''',
      caseSensitive: false,
    ).hasMatch(home.text);
    final logout = RegExp(
      r'''(?:id|href)\s*=\s*["'][^"']*logout[^"']*["']''',
      caseSensitive: false,
    ).hasMatch(home.text);
    final success =
        home.status == 200 &&
        home.mime.contains('html') &&
        !dead &&
        !loginForm &&
        (schoolLabel || logout);
    _verified = success;
    _verifiedNode = success ? resolvedNode : '';
    return DirectLoginResult(
      success,
      success
          ? 'Authenticated home verified (READ-only)'
          : 'HOME_CHECK status=${home.status}; postPath=$postPath; '
                'homePath=$homePath; loginForm=$loginForm; '
                'schoolLabel=$schoolLabel; logout=$logout; portal=$rejection',
      resolvedNode,
      sw.elapsedMilliseconds,
    );
  }
}
