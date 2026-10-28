import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:shaladarpan/experiments/direct_portal_auth.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

import 'attendance_form_reuse_test.dart' show FormPortal;
import 'student_worker_test.dart' show date, students;

String frame(String type, String name, String content) =>
    '${content.length}|$type|$name|$content|';
String delta(
  String panel, {
  String state = 'new-state',
  String event = 'new-events',
}) =>
    '1|#||4|${frame('updatePanel', 'ContentPlaceHolder1_upPnl', panel)}${frame('hiddenField', '__VIEWSTATE', state)}${frame('hiddenField', '__EVENTVALIDATION', event)}';
String shell() =>
    '<form action="StudentdailyAttendanceStatus_Web_NewVersion.aspx"><input name="__VIEWSTATE" value="old"><input name="__EVENTVALIDATION" value="old"><div id="ContentPlaceHolder1_upPnl">old roster</div></form>';

class AjaxPortal extends FormPortal {
  AjaxPortal() {
    disabledDate = true;
  }
  String wrap(String raw) {
    final form = html.parse(raw).querySelector('form');
    if (form == null) return raw;
    final panel = dom.Element.tag('div')..id = 'ContentPlaceHolder1_upPnl';
    for (final n in form.nodes.toList()) {
      if (n is dom.Element && (n.attributes['name'] ?? '').startsWith('__'))
        continue;
      panel.append(n);
    }
    form.append(panel);
    return form.outerHtml;
  }

  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    final reply = await super.request(
      url,
      fields: fields,
      referer: referer,
      mutation: mutation,
    );
    if (reply.status != 200) return reply;
    final page = wrap(reply.html);
    if (fields?['__ASYNCPOST'] != 'true' || mutation)
      return (url: reply.url, status: reply.status, html: page);
    final soup = html.parse(page),
        panel = soup.getElementById('ContentPlaceHolder1_upPnl')!;
    return (
      url: reply.url,
      status: reply.status,
      html: delta(
        panel.innerHtml,
        state: soup
            .querySelector('input[name="__VIEWSTATE"]')!
            .attributes['value']!,
        event: soup
            .querySelector('input[name="__EVENTVALIDATION"]')!
            .attributes['value']!,
      ),
    );
  }
}

class VerifiedReadAuth extends DirectPortalAuth {
  @override
  bool get isVerified => true;
}

class CaptureHeaders implements HttpHeaders {
  final values = <String, Object>{};
  @override void set(String name, Object value, {bool preserveHeaderCase = false}) { values[name.toLowerCase()] = value; }
  @override dynamic noSuchMethod(Invocation invocation) => null;
}
class CaptureRequest implements HttpClientRequest {
  @override final CaptureHeaders headers = CaptureHeaders();
  @override final cookies = <Cookie>[];
  @override Future<HttpClientResponse> close() async => throw StateError('captured-before-network');
  @override dynamic noSuchMethod(Invocation invocation) => null;
}
class CaptureClient implements HttpClient {
  final request = CaptureRequest();
  @override Future<HttpClientRequest> openUrl(String method, Uri url) async => request;
  @override dynamic noSuchMethod(Invocation invocation) => null;
}
void main() {
  test('native attendance read transport sets captured Microsoft AJAX headers', () async {
    final client = CaptureClient();
    await HttpOverrides.runZoned(() async {
      final auth = VerifiedReadAuth(); addTearDown(auth.close);
      final uri = Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/Home/School/StudentdailyAttendanceStatus_Web_NewVersion.aspx');
      await expectLater(auth.attendanceRequest(uri, referer: uri, navigationFields: {
        '__READ_ONLY_ACTION': 'CLASS_ENTRY', '__EVENTTARGET': 'entry', '__ASYNCPOST': 'true',
        r'ctl00$ScriptManager1': r'ctl00$ContentPlaceHolder1$upPnl|entry',
      }), throwsStateError);
      expect(client.request.headers.values['x-microsoftajax'], 'Delta=true');
      expect(client.request.headers.values['x-requested-with'], 'XMLHttpRequest');
    }, createHttpClient: (_) => client);
  });
  test('native formAction updates the next form destination', () {
    final merged = StudentAttendanceWorker.mergeResponse(
      html.parse(shell()),
      delta('new') +
          frame(
            'formAction',
            '',
            './StudentdailyAttendanceStatus_Web_NewVersion.aspx',
          ),
    );
    expect(
      merged.querySelector('form')?.attributes['action'],
      './StudentdailyAttendanceStatus_Web_NewVersion.aspx',
    );
  });
  test('native delta replaces panel and hidden state without losing enclosing form', () {
    final merged = StudentAttendanceWorker.mergeResponse(
      html.parse(shell()),
      delta('<span id="fresh">new roster</span>'),
    );
    expect(merged.getElementById('fresh')?.text, 'new roster');
    expect(
      merged.querySelector('form')?.attributes['action'],
      'StudentdailyAttendanceStatus_Web_NewVersion.aspx',
    );
    expect(
      merged.querySelector('input[name="__VIEWSTATE"]')?.attributes['value'],
      'new-state',
    );
    expect(
      merged
          .querySelector('input[name="__EVENTVALIDATION"]')
          ?.attributes['value'],
      'new-events',
    );
    expect(merged.outerHtml, isNot(contains('old roster')));
  });
  test('Hindi, surrogate pairs and literal pipes respect native UTF-16 frame lengths', () {
    final merged = StudentAttendanceWorker.mergeResponse(
      html.parse(shell()),
      delta('<span id="fresh">उपस्थिति 😀 | verified</span>'),
    );
    expect(merged.getElementById('fresh')?.text, 'उपस्थिति 😀 | verified');
  });
  test(
    'malformed delta is rejected without treating fragments as a full page',
    () {
      expect(
        () => StudentAttendanceWorker.mergeResponse(
          html.parse(shell()),
          '99|updatePanel|ContentPlaceHolder1_upPnl|short|',
        ),
        throwsA(isA<AttendanceWorkerError>()),
      );
    },
  );
  test('missing previous form or update panel is rejected', () {
    expect(
      () => StudentAttendanceWorker.mergeResponse(null, delta('new')),
      throwsA(isA<AttendanceWorkerError>()),
    );
    expect(
      () => StudentAttendanceWorker.mergeResponse(
        html.parse('<form></form>'),
        delta('new'),
      ),
      throwsA(isA<AttendanceWorkerError>()),
    );
  });
  test('native portal AJAX errors retain original message', () {
    expect(
      () => StudentAttendanceWorker.mergeResponse(
        html.parse(shell()),
        frame('error', '500', 'Original portal error'),
      ),
      throwsA(
        isA<AttendanceWorkerError>().having(
          (e) => e.message,
          'message',
          'Original portal error',
        ),
      ),
    );
  });
  test(
    'native AJAX redirect reports expiry and is never treated as a roster',
    () {
      expect(
        () => StudentAttendanceWorker.mergeResponse(
          html.parse(shell()),
          frame('pageRedirect', '', '/Public/Default.aspx'),
        ),
        throwsA(
          isA<AttendanceWorkerError>().having(
            (e) => e.code,
            'code',
            'SESSION_EXPIRED',
          ),
        ),
      );
    },
  );
  test('new hidden fields are retained and full response fallback remains supported', () {
    final raw =
        delta('new') + frame('hiddenField', '__VIEWSTATEGENERATOR', 'GEN');
    final merged = StudentAttendanceWorker.mergeResponse(
      html.parse(shell()),
      raw,
    );
    expect(
      merged
          .querySelector('input[name="__VIEWSTATEGENERATOR"]')
          ?.attributes['value'],
      'GEN',
    );
    expect(
      StudentAttendanceWorker.mergeResponse(
        merged,
        '<form><span id="full">full</span></form>',
      ).getElementById('full')?.text,
      'full',
    );
  });
  test(
    'AJAX read sends exact captured panel/control and latest hidden fields',
    () async {
      final p = AjaxPortal();
      final w = StudentAttendanceWorker(
        request: p.request,
        baseUrl: () =>
            Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
        sessionIdentity: () => 'same',
      );
      final first = await w.fetchStudentAttendanceList(
        classId: '1',
        attendanceDate: date,
      );
      expect(first['success'], true);
      final n = p.requests.length;
      final next = await w.fetchStudentAttendanceList(
        classId: '1',
        attendanceDate: date,
      );
      expect(next['success'], true);
      expect(p.gets, 1);
      expect(p.requests.length - n, 2);
      for (final r in p.requests.where((r) => r['fields'] != null)) {
        final f = r['fields'] as Map;
        expect(f['__ASYNCPOST'], 'true');
        final control = '${f['__EVENTTARGET']}'.isNotEmpty
            ? f['__EVENTTARGET']
            : f['__READ_ONLY_ACTION'] == 'BACK'
            ? r'ctl00$ContentPlaceHolder1$btnback'
            : r'ctl00$ContentPlaceHolder1$btn_Show';
        expect(
          f[r'ctl00$ScriptManager1'],
          'ctl00\$ContentPlaceHolder1\$upPnl|$control',
        );
      }
      expect(
        (p.requests[n]['fields'] as Map)['__VIEWSTATE'],
        'ENTRY_VIEWSTATE_1',
      );
      expect(p.saves, 0);
    },
  );
  test('native AJAX Save remains single-dispatch with independent verification', () async {
    final p = AjaxPortal();
    final w = StudentAttendanceWorker(
      request: p.request,
      baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      sessionIdentity: () => 'same',
      indiaNow: () => DateTime(2026, 10, 10),
    );
    await w.fetchStudentAttendanceList(classId: '1', attendanceDate: date);
    final result = await w.saveStudentAttendance(
      classId: '1',
      attendanceDate: date,
      section: '1A',
      students: students,
      userConfirmed: true,
    );
    expect(result['success'], true);
    expect(result['attendance_verified'], true);
    expect(p.saves, 1);
    final save =
        p.requests.singleWhere((r) => r['mutation'] == true)['fields'] as Map;
    expect(save['__ASYNCPOST'], 'true');
    expect(save[r'ctl00$ScriptManager1'], r'ctl00$ContentPlaceHolder1$upPnl|ctl00$ContentPlaceHolder1$btnsubmit');
  });
  test('read transport blocks fabricated Back and unexpected AJAX panel before HTTP', () async {
    final auth = VerifiedReadAuth();
    addTearDown(auth.close);
    final uri = Uri.parse(
      'https://rajshaladarpan.rajasthan.gov.in/SD1/Home/School/StudentdailyAttendanceStatus_Web_NewVersion.aspx',
    );
    await expectLater(
      auth.attendanceRequest(
        uri,
        navigationFields: {
          '__READ_ONLY_ACTION': 'BACK',
          '__EVENTTARGET': 'other',
        },
      ),
      throwsStateError,
    );
    await expectLater(
      auth.attendanceRequest(
        uri,
        navigationFields: {
          '__READ_ONLY_ACTION': 'CLASS_ENTRY',
          '__EVENTTARGET': 'entry',
          '__ASYNCPOST': 'true',
          r'ctl00$ScriptManager1': 'other|entry',
        },
      ),
      throwsStateError,
    );
  });
}
