import 'dart:io';
import 'dart:async';
import 'package:shaladarpan/experiments/direct_student_attendance_service.dart';
import 'package:shaladarpan/services/core/direct/coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:shaladarpan/experiments/direct_portal_auth.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

import 'attendance_form_reuse_test.dart' show FormPortal;
import 'student_worker_test.dart' show date, students, FakeAuth;

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


// Sanitized contract from the 29-Oct native browser capture:
// all five Back posts retain disabled txtdate and ddlClass.
class CapturedDisabledAjaxPortal extends AjaxPortal {
  @override
  String entry() => super.entry().replaceFirst('</form>', r'''
    <select disabled="disabled" name="ctl00$ContentPlaceHolder1$ddlClass">
      <option selected="selected" value="0">All</option>
    </select>
    <input disabled="disabled" type="checkbox" name="unchecked" value="on">
    <input disabled="disabled" type="radio" name="unselected" value="2">
    </form>''');
}


// Protocol fixture derived from the observed sequence, without private tokens:
// 28-Oct Entry -> SD4 public default -> protected GET -> 27-Oct Entry succeeds.
class PublicDefaultPortal extends AjaxPortal {
  String selected = date;
  bool redirected = false, deltaRedirect = false, expired = false, unknown = false;
  bool probeTimeout = false, changeAccount = false;
  int entries = 0, protectedGets = 0;
  String identity = 'school/original';
  final defaultPage = Uri.parse('https://rajshaladarpan.rajasthan.gov.in/sd4/Home/Public2/Default.aspx');
  @override String summary() => super.summary().replaceAll(date, selected);
  @override String entry() => super.entry().replaceAll(date, selected);
  @override Future<AttendanceHttpReply> request(Uri url, {Map<String,Object?>? fields, Uri? referer, bool mutation=false}) async {
    if (fields == null) {
      protectedGets++;
      expect(url.path, '/SD1/Home/School/StudentdailyAttendanceStatus_Web_NewVersion.aspx');
      if (redirected) {
        if (changeAccount) identity = 'school/another';
        if (probeTimeout) throw TimeoutException('synthetic recovery read timeout');
        if (expired) return (url:url.resolve('../Public2/OfficeLoginNew.aspx'),status:200,html:'<input id="txtUserId">');
        if (unknown) return (url:url,status:200,html:'<html>unavailable</html>');
      }
      selected = date;
    }
    if (fields?['__READ_ONLY_ACTION'] == 'SHOW') selected = fields![r'ctl00$ContentPlaceHolder1$txtdate'] as String;
    if (fields?['__READ_ONLY_ACTION'] == 'CLASS_ENTRY') {
      entries++;
      if (selected == '28/10/2026') {
        redirected = true;
        requests.add({'url':url.toString(),'fields':fields,'mutation':mutation});
        if(deltaRedirect) return (url:url,status:200,html:frame('pageRedirect','',defaultPage.toString()));
        return (url:defaultPage,status:200,html:'<html><title>Portal public page</title></html>');
      }
    }
    return super.request(url,fields:fields,referer:referer,mutation:mutation);
  }
}
class RedirectBackend implements PortalBackend {
  int authentications = 0, probes = 0;
  final context=Object();
  @override Object? currentContext()=>context;
  @override Future<Probe> probe(Object context) async {probes++;return Probe.alive;}
  @override Future<Map<String,dynamic>> authenticate(String u,String p,bool f) async {authentications++;return {'success':true};}
}
class RedirectAuth extends FakeAuth {
  RedirectAuth(super.portal,this.co);
  final PortalCoordinator co;
  @override PortalCoordinator? get coordinator=>co;
  @override String get schoolSessionIdentity=>(portal as PublicDefaultPortal).identity;
}

class RedirectAfterSubmitPortal extends AjaxPortal {
  @override Future<AttendanceHttpReply> request(Uri url, {Map<String,Object?>? fields,Uri? referer,bool mutation=false}) async {
    final reply=await super.request(url,fields:fields,referer:referer,mutation:mutation);
    if(!mutation)return reply;
    return (url:Uri.parse('https://rajshaladarpan.rajasthan.gov.in/sd4/Home/Public2/Default.aspx'),status:200,html:'<html>public landing</html>');
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

  StudentAttendanceWorker redirectWorker(PublicDefaultPortal portal) => StudentAttendanceWorker(
    request:portal.request,
    baseUrl:()=>Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
    sessionIdentity:()=>portal.identity,
    indiaNow:()=>DateTime(2026,10,29),
  );

  test('superseded public redirect does not add a session verification request',() async {
    final portal=PublicDefaultPortal();
    final result=await redirectWorker(portal).fetchStudentAttendanceList(
      classId:'1',attendanceDate:'28/10/2026',shouldContinue:()=>!portal.redirected);
    expect(result['code'],'STALE_ATTENDANCE_READ');expect(portal.protectedGets,1);expect(portal.entries,1);
  });
  test('public redirect after Submit stays unconfirmed and never repeats Submit or probes during mutation',() async {
    final portal=RedirectAfterSubmitPortal();
    final worker=StudentAttendanceWorker(request:portal.request,
      baseUrl:()=>Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      sessionIdentity:()=> 'one/session',activityStamp:()=>0,indiaNow:()=>DateTime(2026,10,10));
    expect((await worker.fetchStudentAttendanceList(classId:'1',attendanceDate:date))['success'],true);
    final before=portal.requests.length;
    final result=await worker.saveStudentAttendance(classId:'1',attendanceDate:date,students:students,userConfirmed:true);
    expect(result['code'],'SAVE_UNCONFIRMED');expect(result['submission_attempted'],true);
    final saving=portal.requests.skip(before).toList();
    expect(portal.saves,1);expect(saving.where((r)=>r['mutation']==true),hasLength(1));
    // This generic fixture requires a legitimate preflight. The dispatched
    // Submit must be the final request: no replay or verification after it.
    expect(saving.last['mutation'],true);expect(worker.hasFreshSessionForm,false);
  });

  for(final deltaRedirect in [false,true]) {
    test('28-Oct public default redirect ($deltaRedirect AJAX) does not expire an active school session',() async {
      final portal=PublicDefaultPortal()..deltaRedirect=deltaRedirect;
      final worker=redirectWorker(portal);
      final result=await worker.fetchStudentAttendanceList(classId:'1',attendanceDate:'28/10/2026');
      expect(result['success'],false);expect(result['code'],'PORTAL_RESPONSE_ERROR');
      expect(result['portal_session_alive'],true);expect(result['students'],isEmpty);
      expect(portal.entries,1);expect(portal.protectedGets,2);expect(portal.saves,0);
      expect(worker.hasFreshSessionForm,true);
      final otherDate=await worker.fetchStudentAttendanceList(classId:'1',attendanceDate:'27/10/2026');
      expect(otherDate['success'],true,reason:'$otherDate');expect(otherDate['date'],'27/10/2026');
      expect((otherDate['students'] as List).map((s)=>s['status']),['Present','Absent']);
      expect(portal.protectedGets,2);expect(portal.saves,0);
    });
  }
  test('public redirect followed by a real login form retains actual session-expiry recovery',() async {
    final portal=PublicDefaultPortal()..expired=true;
    final result=await redirectWorker(portal).fetchStudentAttendanceList(classId:'1',attendanceDate:'28/10/2026');
    expect(result['code'],'SESSION_EXPIRED');expect(portal.entries,1);expect(portal.protectedGets,2);
  });
  for(final timeout in [false,true]) {
    test('public redirect with an unknown recovery read ($timeout timeout) never claims the session is alive or expired',() async {
      final portal=PublicDefaultPortal()..unknown=!timeout..probeTimeout=timeout;
      final worker=redirectWorker(portal);
      final result=await worker.fetchStudentAttendanceList(classId:'1',attendanceDate:'28/10/2026');
      expect(result['code'],'PORTAL_RESPONSE_ERROR');expect(result['portal_session_alive'],isNull);
      expect(worker.hasFreshSessionForm,false);expect(portal.entries,1);expect(portal.protectedGets,2);
    });
  }
  test('account change during public redirect verification cannot authorize the previous read',() async {
    final portal=PublicDefaultPortal()..changeAccount=true;
    final worker=redirectWorker(portal);
    final result=await worker.fetchStudentAttendanceList(classId:'1',attendanceDate:'28/10/2026');
    expect(result['code'],'ACCOUNT_CHANGED');expect(result['portal_session_alive'],isNull);
    expect(worker.hasFreshSessionForm,false);expect(portal.saves,0);
  });
  test('real coordinator does not relogin or repeat the failing class when a protected read succeeds',() async {
    final portal=PublicDefaultPortal(),backend=RedirectBackend();
    final co=PortalCoordinator(name:'sd',backend:backend);
    final auth=RedirectAuth(portal,co);
    try {
      await co.authenticate('offline-school','fixture-password');
      final service=DirectStudentAttendanceService(auth);
      final bad=await service.fetchStudentsResponse(classId:'1',date:'28/10/2026');
      expect(bad['code'],'PORTAL_RESPONSE_ERROR');expect(bad['portal_session_alive'],true);
      expect(backend.authentications,1);expect(portal.entries,1);
      final good=await service.fetchStudentsResponse(classId:'1',date:'27/10/2026');
      expect(good['success'],true);expect(backend.authentications,1);expect(portal.saves,0);
    } finally {await co.shutdown();auth.close();}
  });


  test('29-Oct captured AJAX Back retains disabled date and class controls', () async {
    final portal = CapturedDisabledAjaxPortal();
    final worker = StudentAttendanceWorker(
      request: portal.request,
      baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      sessionIdentity: () => 'captured/session',
    );
    expect((await worker.fetchStudentAttendanceList(classId: '1', attendanceDate: date))['success'], true);
    final start = portal.requests.length;
    expect((await worker.fetchStudentAttendanceList(classId: '1', attendanceDate: date))['success'], true);
    final posted = portal.requests.skip(start).map((r) => r['fields'] as Map).toList();
    expect(posted, hasLength(2));
    final back = posted.first;
    expect(back['__READ_ONLY_ACTION'], 'BACK');
    expect(back['__ASYNCPOST'], 'true');
    expect(back['__VIEWSTATE'], 'ENTRY_VIEWSTATE_1');
    expect(back[r'ctl00$ContentPlaceHolder1$txtdate'], date);
    expect(back[r'ctl00$ContentPlaceHolder1$ddlClass'], ['0']);
    expect(back.containsKey('unchecked'), false);
    expect(back.containsKey('unselected'), false);
    expect(portal.saves, 0);
  });

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
