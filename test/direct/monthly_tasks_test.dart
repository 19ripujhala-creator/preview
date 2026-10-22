import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import '../../lib/services/portals/shaladarpan/direct/monthly_tasks_worker.dart';
import '../../lib/services/portals/shaladarpan/direct/ranking_http.dart';
import '../../lib/services/portals/shaladarpan/direct/ranking_status_cache.dart';
import '../../lib/services/portals/shaladarpan/direct/school_http.dart';
import '../../lib/experiments/direct_portal_auth.dart';
import '../../lib/experiments/direct_monthly_task_service.dart';

const p = MonthlyTasksWorker.prefix;
final base = Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/');
const period = {'${p}ddlMonth1': '9', '${p}ddlyear': '2026'};
const vperiod = {
  '${p}ddlStudentType': '2026-27',
  '${p}ddlClass': 'P',
  '${p}ddlmonth': '9',
};
String fixture(String name) =>
    File('test/direct/fixtures/$name').readAsStringSync();
dynamic golden(String name) => jsonDecode(fixture(name));
final cache = RankingStatusCache(
  read: (_) async => null,
  write: (_, _) async {},
  remove: (_) async {},
);
MonthlyTasksWorker worker(
  MonthlyRequest request, {
  String Function()? session,
  double Function()? clock,
}) => MonthlyTasksWorker(
  request: request,
  baseUrl: () => base,
  schoolId: () => '123456',
  sessionKey: session ?? () => '123456/1/cookie',
  clock: clock,
  statusCache: cache,
  secret: List.filled(32, 7),
);
Map<String, String> values(Map<String, dynamic> form) => {
  for (final s in form['sections'])
    for (final f in s['fields'])
      if (f['readonly'] != true) f['id']: f['value'],
};
String delta(String source, {String? message, bool tokens = true}) {
  final soup = html.parse(source);
  if (message != null) soup.getElementById('${p}lblerrmsg')!.text = message;
  final content = soup.getElementById('${p}upPnl')!.innerHtml;
  final records = [
    ('updatePanel', '${p}upPnl', content),
    if (tokens) ('hiddenField', '__VIEWSTATE', 'VS2'),
    if (tokens) ('hiddenField', '__EVENTVALIDATION', 'EV2'),
  ];
  return records.map((r) => '${r.$3.length}|${r.$1}|${r.$2}|${r.$3}|').join();
}

MonthlyReply reply(Uri url, String source) => (
  url: url,
  status: 200,
  html: source,
  cookies: SchoolCookieJar({'ASP.NET_SessionId': 'test'}),
);

class MonthlyPolicyAuth extends DirectPortalAuth {
  int gets = 0;
  @override
  bool get isVerified => true;
  @override
  String get verifiedNode => 'SD1';
  @override
  String? get authenticatedSchoolId => '123456';
  @override
  String get schoolSessionIdentity => 'policy';
  @override
  Future<MonthlyReply> monthlyRequest(
    Uri url, {
    String? body,
    Uri? referer,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 30),
    bool followRedirects = true,
    SchoolCookieJar? cookies,
  }) async {
    gets++;
    return reply(url, fixture('monthly_ranking_pending.html'));
  }
}

void main() {
  const liveDeadlineMessage =
      '10 तारीख के बाद एंट्री उपलब्‍ध नहीं है| अनलॉक बटन पर क्लिक करें';
  test('actual VIFFS ASP.NET startup script preserves exact Unicode alert', () {
    final soup = html.parse(fixture('viffs_live_deadline_script.html'));
    expect(MonthlyTasksWorker.portalRejection(soup), liveDeadlineMessage);
  });
  test(
    'actual VIFFS startup alert reaches READ error without any mutation',
    () async {
      final soup = html.parse(fixture('monthly_viffs_open.html'));
      soup.getElementById('${p}grd_Add')!.remove();
      final initial = soup.outerHtml;
      soup.body!.append(
        html.parseFragment(fixture('viffs_live_deadline_script.html')),
      );
      var posts = 0;
      final w = worker((
        url, {
        body,
        referer,
        headers = const {},
        timeout = const Duration(seconds: 30),
        followRedirects = true,
        cookies,
      }) async {
        if (body == null) return reply(url, initial);
        posts++;
        final fields = Uri.splitQueryString(body);
        expect(
          fields.keys.any(
            (k) =>
                k.contains('Unlock') ||
                k.contains('btnSubmit') ||
                k.endsWith(r'$Lock'),
          ),
          false,
        );
        expect(posts, lessThanOrEqualTo(4));
        return reply(url, posts == 4 ? soup.outerHtml : initial);
      });
      await expectLater(
        w.readForm('viffs', vperiod, '123456'),
        throwsA(
          isA<MonthlyError>()
              .having(
                (e) => e.message,
                'actual original text',
                liveDeadlineMessage,
              )
              .having((e) => e.code, 'code', 'PORTAL_MESSAGE')
              .having((e) => e.attempted, 'mutation attempted', false),
        ),
      );
      expect(posts, 4);
    },
  );
  test('CDATA support ignores dormant commented and function alerts', () {
    final soup = html.parse('''<script>//<![CDATA[
      // alert('commented message');
      function dormant() { alert('dormant message'); }
      //]]></script>''');
    expect(MonthlyTasksWorker.portalRejection(soup), '');
  });
  const deadlineMessage =
      '10 तारीख के बाद एंट्री उपलब्ध नहीं है। अनलॉक बटन पर क्लिक करें';
  for (final call in ['alert', 'window.alert']) {
    test('VIFFS missing grid preserves native $call deadline message', () {
      final soup = html.parse(fixture('monthly_viffs_open.html'));
      soup.getElementById('${p}grd_Add')!.remove();
      soup.body!.append(
        html.parseFragment(
          '<script>$call(${jsonEncode(deadlineMessage)});</script>',
        ),
      );
      expect(
        () => MonthlyTasksWorker.parseForm(
          soup.outerHtml,
          'viffs',
          selection: vperiod,
        ),
        throwsA(
          isA<MonthlyError>()
              .having(
                (e) => e.message,
                'original portal message',
                deadlineMessage,
              )
              .having((e) => e.code, 'code', 'PORTAL_MESSAGE')
              .having((e) => e.attempted, 'mutation attempted', false),
        ),
      );
    });
  }
  test(
    'VIFFS deadline Show stops with portal message and never Unlocks',
    () async {
      var posts = 0;
      final soup = html.parse(fixture('monthly_viffs_open.html'));
      soup.getElementById('${p}grd_Add')!.remove();
      final initial = soup.outerHtml;
      soup.body!.append(
        html.parseFragment(
          '<script>alert(${jsonEncode(deadlineMessage)});</script>',
        ),
      );
      final blocked = soup.outerHtml;
      final w = worker((
        url, {
        body,
        referer,
        headers = const {},
        timeout = const Duration(seconds: 30),
        followRedirects = true,
        cookies,
      }) async {
        if (body == null) return reply(url, initial);
        posts++;
        final fields = Uri.splitQueryString(body);
        expect(
          fields.keys.any(
            (k) =>
                k.contains('Unlock') ||
                k.contains('btnSubmit') ||
                k.endsWith(r'$Lock'),
          ),
          false,
        );
        expect(posts, lessThanOrEqualTo(4));
        return reply(url, posts == 4 ? blocked : initial);
      });
      await expectLater(
        w.readForm('viffs', vperiod, '123456'),
        throwsA(
          isA<MonthlyError>()
              .having((e) => e.message, 'portal message', deadlineMessage)
              .having((e) => e.code, 'code', 'PORTAL_MESSAGE'),
        ),
      );
      expect(posts, 4);
    },
  );
  test('VIFFS missing grid without portal message remains unavailable', () {
    final soup = html.parse(fixture('monthly_viffs_open.html'));
    soup.getElementById('${p}grd_Add')!.remove();
    expect(
      () => MonthlyTasksWorker.parseForm(
        soup.outerHtml,
        'viffs',
        selection: vperiod,
      ),
      throwsA(
        isA<MonthlyError>().having(
          (e) => e.code,
          'code',
          'MONTHLY_UNAVAILABLE',
        ),
      ),
    );
  });
  test('VIFFS source MPR chain initializes server even when selectors already match', () async {
    final expected = golden('python_viffs_read_chain.json') as List;
    var steps = 0;
    final full = fixture('monthly_viffs_open.html');
    String page({bool grid = false}) {
      final soup = html.parse(full);
      if (!grid) soup.getElementById('${p}grd_Add')?.remove();
      if (steps > 0) {
        soup.querySelector('input[name="__VIEWSTATE"]')!.attributes['value'] =
            'VS${steps + 1}';
        soup
                .querySelector('input[name="__EVENTVALIDATION"]')!
                .attributes['value'] =
            'EV${steps + 1}';
      }
      return soup.outerHtml;
    }

    final w = worker((
      url, {
      body,
      referer,
      headers = const {},
      timeout = const Duration(seconds: 30),
      followRedirects = true,
      cookies,
    }) async {
      if (body == null) return reply(url, page());
      expect(steps, lessThan(4));
      final source = expected[steps];
      // Map comparison ignores ordinary control order; all values and tokens match.
      expect(Uri.splitQueryString(body), Uri.splitQueryString(source['body']));
      expect(timeout.inMilliseconds, source['timeout_ms']);
      expect(followRedirects, false);
      steps++;
      return reply(url, page(grid: steps == 4));
    });
    final result = await w.readForm('viffs', vperiod, '123456');
    expect(result['sections'], hasLength(2));
    expect(steps, 4);
  });

  test('ranking login policy after fifth day does not open portal', () async {
    final auth = MonthlyPolicyAuth();
    final service = DirectMonthlyTaskService(auth);
    final result = await service.collectRankingStatus(
      '123456',
      indiaDate: DateTime.utc(2026, 10, 11),
    );
    expect(result['ranking_status']['auto_check_enabled'], false);
    expect(auth.gets, 0);
  });
  test(
    'ranking login policy first five days coalesces concurrent read',
    () async {
      final auth = MonthlyPolicyAuth();
      final actual = DirectMonthlyTaskService(auth);
      final results = await Future.wait([
        actual.collectRankingStatus(
          '123456',
          indiaDate: DateTime.utc(2026, 10, 2),
        ),
        actual.collectRankingStatus(
          '123456',
          indiaDate: DateTime.utc(2026, 10, 2),
        ),
      ]);
      expect(
        results.every((r) => r['ranking_status']['auto_check_enabled'] == true),
        true,
      );
      expect(auth.gets, 1);
    },
  );
  test(
    'cookie snapshots preserve scope and cannot alter live outgoing cookies',
    () {
      final original = SchoolCookieJar();
      original.receive([Cookie('sid', 'first')..path = '/SD1/'], base);
      final snapshot = original.copy();
      original.receive([Cookie('sid', 'second')..path = '/SD1/'], base);
      expect(snapshot.matching(base).single.value, 'first');
      expect(original.matching(base).single.value, 'second');
      expect(
        snapshot.matching(
          Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD2/'),
        ),
        isEmpty,
      );
      snapshot.receive([Cookie('sid', 'third')..path = '/SD1/'], base);
      expect(original.matching(base).single.value, 'second');
    },
  );
  test(
    'ranking request cookie override isolated from parallel shared request',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
          seen = <String, String>{};
      final local = Uri.parse('http://127.0.0.1:${server.port}/');
      final client = SchoolHttpClient(
        baseUrl: local,
        cookies: {'sid': 'live'},
        allowUrl: (u) => u.host == '127.0.0.1' && u.port == server.port,
      );
      final sub = server.listen((req) async {
        seen[req.uri.path] = req.cookies.single.value;
        await req.drain<void>();
        req.response.write('ok');
        await req.response.close();
      });
      try {
        await Future.wait([
          client.request(
            'POST',
            local.resolve('ranking'),
            body: [1],
            cookieJar: SchoolCookieJar({'sid': 'reviewed'}),
            followRedirects: false,
          ),
          client.request('GET', local.resolve('student')),
        ]);
        expect(seen, {'/ranking': 'reviewed', '/student': 'live'});
        expect(client.jar.snapshot()['sid'], 'live');
      } finally {
        client.retire();
        await sub.cancel();
        await server.close(force: true);
      }
    },
  );
  test(
    'VIFFS dependent selector postback uses current tokens before Show',
    () async {
      final original = fixture('monthly_viffs_open.html').replaceAll(
        '<select id="${p}ddlmonth"',
        '<select onchange="__doPostBack(this.name,\'\')" id="${p}ddlmonth"',
      );
      final calls = <Map<String, String>>[];
      final w = worker((
        url, {
        body,
        referer,
        headers = const {},
        timeout = const Duration(seconds: 30),
        followRedirects = true,
        cookies,
      }) async {
        if (body == null) return reply(url, original);
        final f = Uri.splitQueryString(body);
        calls.add(f);
        expect(followRedirects, false);
        if (f['__EVENTTARGET'] == r'ctl00$ContentPlaceHolder1$ddlmonth')
          return reply(
            url,
            original
                .replaceAll('value="9" selected', 'value="9"')
                .replaceAll('value="8"', 'value="8" selected')
                .replaceAll('value="vs1"', 'value="fresh-vs"'),
          );
        return reply(
          url,
          original
              .replaceAll('value="9" selected', 'value="9"')
              .replaceAll('value="8"', 'value="8" selected'),
        );
      });
      await w.readForm('viffs', {...vperiod, '${p}ddlmonth': '8'}, '123456');
      expect(calls, hasLength(4));
      expect(calls.every((f) => !f.containsKey('_selector_only')), true);
      expect(calls[3]['__VIEWSTATE'], 'fresh-vs');
    },
  );

  test('Python canonical JSON and HMAC review token parity', () {
    final c = golden('python_monthly_signature.json');
    final w = worker(
      (
        url, {
        body,
        referer,
        headers = const {},
        timeout = const Duration(seconds: 30),
        followRedirects = true,
        cookies,
      }) async => reply(url, ''),
    );
    expect(
      w.signature(Map<String, dynamic>.from(c['form']), c['school']),
      c['snapshot'],
    );
  });
  for (final c in golden('python_monthly_ranking_posts.json'))
    test('exact source ${c['action']} body and AJAX policies', () async {
      String? sent;
      Map<String, String>? sentHeaders;
      Duration? sentTimeout;
      bool? redirected;
      final w = worker((
        url, {
        body,
        referer,
        headers = const {},
        timeout = const Duration(seconds: 30),
        followRedirects = true,
        cookies,
      }) async {
        sent = body;
        sentHeaders = {...headers, 'Referer': referer.toString()};
        sentTimeout = timeout;
        redirected = followRedirects;
        return reply(url, delta(fixture('monthly_ranking_saved.html')));
      });
      final state = RankingState(
        soup: html.parse(
          fixture(
            c['action'] == 'Submit'
                ? 'monthly_ranking_pending.html'
                : 'monthly_ranking_saved.html',
          ),
        ),
        url: base.resolve(MonthlyTasksWorker.paths['ranking']!),
        school: '123456',
        key: w.ranking.stateKey('123456'),
        at: 0,
        cookies: SchoolCookieJar({'ASP.NET_SessionId': 'test'}),
      );
      await w.ranking.post(
        state,
        c['action'] == 'Submit'
            ? r'ctl00$ContentPlaceHolder1$sub_btn'
            : r'ctl00$ContentPlaceHolder1$grd_Add$ctl02$btn' + c['action'],
        image: c['action'] != 'Submit',
      );
      expect(sent, c['request']['content']);
      expect(sentHeaders, c['request']['headers']);
      expect(sentTimeout, const Duration(seconds: 60));
      expect(redirected, c['request']['follow_redirects']);
    });

  for (final task in ['ranking', 'viffs'])
    for (final mode
        in task == 'ranking'
            ? ['pending', 'saved', 'edit', 'paged', 'missing', 'duplicate']
            : ['open', 'locked', 'bad_lock', 'absent']) {
      test('$task $mode exact Python form and reviewed fields', () {
        final expected = golden('python_monthly_${task}_$mode.json');
        final form = MonthlyTasksWorker.parseForm(
          fixture('monthly_${task}_$mode.html'),
          task,
          selection: task == 'viffs' ? {'${p}ddlClass': 'P'} : null,
          editing: mode == 'edit',
        );
        expect(form, expected['data']);
        expect(MonthlyTasksWorker.reviewData(form), expected['review']);
      });
    }
  test('duplicate successful controls retain order and defaults', () {
    expect(
      RankingHttp.controls(html.parse(fixture('monthly_ranking_controls.html')))
          .map((r) => [r.$1, r.$2])
          .toList(),
      golden('python_monthly_ranking_controls.json'),
    );
  });
  test('UTF16 delta Hindi emoji and embedded pipes', () {
    expect(
      RankingHttp.parseDelta(fixture('monthly_ranking_delta.txt'))
          .map((r) => [r.$1, r.$2, r.$3])
          .toList(),
      golden('python_monthly_ranking_delta.json'),
    );
  });
  for (final malformed in ['x|a|b|c|', '-1|a|b||', '4|a|b|x|', '1|a|b|😀|']) {
    test('malformed delta $malformed', () {
      expect(() => RankingHttp.parseDelta(malformed), throwsFormatException);
    });
  }
  for (final c in golden('python_monthly_confirmations.json')) {
    test('literal native confirm ${c['source']}', () {
      expect(MonthlyTasksWorker.literalConfirmation(c['source']), c['message']);
    });
  }
  for (final c in golden('python_monthly_values.json')) {
    test('values ${c['mode']} Python validation', () {
      Map<String, dynamic> result;
      try {
        MonthlyTasksWorker.validateValues(
          Map<String, dynamic>.from(c['form']),
          Map<String, String>.from(c['values']),
          today: DateTime.utc(2026, 10, 11),
        );
        result = {'success': true};
      } on MonthlyError catch (e) {
        result = {
          'success': false,
          'code': e.code,
          'message': e.message,
          'field_errors': e.fieldErrors,
        };
      }
      expect(result, c['result']);
    });
  }
  test('review signature ignores ranking row IDs and labels, guards business changes', () {
    final w = worker(
      (
        url, {
        body,
        referer,
        headers = const {},
        timeout = const Duration(seconds: 30),
        followRedirects = true,
        cookies,
      }) async => reply(url, ''),
    );
    final a = MonthlyTasksWorker.parseForm(
      fixture('monthly_ranking_saved.html'),
      'ranking',
    );
    final token = w.signature(a, '123456');
    final b = monthlyCopy(a);
    b['history'][0]['actions']['Edit'] = 'changed_row';
    b['sections'][0]['fields'][0]['label'] = 'different label';
    expect(w.signature(b, '123456'), token);
    b['history'][0]['values'][0] = '999';
    expect(w.signature(b, '123456'), isNot(token));
    expect(
      () => w.requireReview(
        token,
        {'snapshot': w.signature(b, '123456')},
        '123456',
        'submit',
      ),
      throwsA(isA<MonthlyError>().having((e) => e.code, 'code', 'STALE_FORM')),
    );
  });
  test(
    'retained ranking period changes do not repeat GET; refresh does',
    () async {
      var gets = 0;
      final w = worker((
        url, {
        body,
        referer,
        headers = const {},
        timeout = const Duration(seconds: 30),
        followRedirects = true,
        cookies,
      }) async {
        gets++;
        expect(body, isNull);
        return reply(url, fixture('monthly_ranking_pending.html'));
      });
      final form = await w.readForm('ranking', period, '123456');
      expect(values(form).values, everyElement(''));
      await w.readForm('ranking', {...period, '${p}ddlMonth1': '8'}, '123456');
      expect(gets, 1);
      await w.readForm('ranking', period, '123456', refresh: true);
      expect(gets, 2);
    },
  );
  test(
    'ranking submit exact payload and verified response, no duplicate POST',
    () async {
      var posts = 0;
      String? sent;
      final w = worker((
        url, {
        body,
        referer,
        headers = const {},
        timeout = const Duration(seconds: 30),
        followRedirects = true,
        cookies,
      }) async {
        if (body == null)
          return reply(url, fixture('monthly_ranking_pending.html'));
        posts++;
        sent = body;
        expect(followRedirects, false);
        expect(timeout, const Duration(seconds: 60));
        expect(headers['X-MicrosoftAjax'], 'Delta=true');
        expect(cookies, isNotNull);
        return reply(url, delta(fixture('monthly_ranking_saved.html')));
      });
      final form = await w.readForm('ranking', period, '123456'),
          val = {
            '${p}txtaward': '1',
            '${p}txtlibbooks': '2',
            '${p}txtsports': '3',
            '${p}TextBox1': '01-09-2026',
          };
      final result = await w.submitForm(
        'ranking',
        period,
        '123456',
        form['snapshot'],
        val,
      );
      expect(result['verified'], true);
      expect(result['data']['completed'], true);
      expect(posts, 1);
      final payload = Uri.splitQueryString(sent!);
      expect(
        payload[r'ctl00$ScriptManager1'],
        r'ctl00$ContentPlaceHolder1$upPnl|ctl00$ContentPlaceHolder1$sub_btn',
      );
      expect(payload['__ASYNCPOST'], 'true');
      expect(payload[r'ctl00$ContentPlaceHolder1$txtaward'], '1');
    },
  );
  for (final mode in [
    'timeout',
    'malformed',
    'missing_tokens',
    'wrong_values',
    'redirect',
  ])
    test('ranking $mode discards tokens and never replays', () async {
      var posts = 0, gets = 0;
      final w = worker((
        url, {
        body,
        referer,
        headers = const {},
        timeout = const Duration(seconds: 30),
        followRedirects = true,
        cookies,
      }) async {
        if (body == null) {
          gets++;
          return reply(url, fixture('monthly_ranking_pending.html'));
        }
        posts++;
        if (mode == 'timeout') throw TimeoutException('mock');
        if (mode == 'malformed') return reply(url, 'not-delta');
        if (mode == 'redirect')
          return (url: url, status: 302, html: '', cookies: null);
        return reply(
          url,
          delta(
            fixture(
              mode == 'wrong_values'
                  ? 'monthly_ranking_pending.html'
                  : 'monthly_ranking_saved.html',
            ),
            tokens: mode != 'missing_tokens',
          ),
        );
      });
      final form = await w.readForm('ranking', period, '123456');
      await expectLater(
        () => w.submitForm('ranking', period, '123456', form['snapshot'], {
          '${p}txtaward': '1',
          '${p}txtlibbooks': '2',
          '${p}txtsports': '3',
          '${p}TextBox1': '01-09-2026',
        }),
        throwsA(
          isA<MonthlyError>().having((e) => e.attempted, 'attempted', true),
        ),
      );
      await w.readForm('ranking', period, '123456');
      expect(posts, 1);
      expect(gets, 2);
    });
  test(
    'authentic validation rejection retains draft and original field warning',
    () async {
      final w = worker(
        (
          url, {
          body,
          referer,
          headers = const {},
          timeout = const Duration(seconds: 30),
          followRedirects = true,
          cookies,
        }) async => reply(
          url,
          body == null
              ? fixture('monthly_ranking_pending.html')
              : delta(
                  fixture('monthly_ranking_pending.html'),
                  message: 'award value invalid',
                ),
        ),
      );
      final form = await w.readForm('ranking', period, '123456');
      try {
        await w.submitForm('ranking', period, '123456', form['snapshot'], {
          '${p}txtaward': '1',
          '${p}txtlibbooks': '2',
          '${p}txtsports': '3',
          '${p}TextBox1': '01-09-2026',
        });
        fail('expected rejection');
      } on MonthlyError catch (e) {
        expect(e.rejected, true);
        expect(e.data, isNotNull);
        expect(e.fieldErrors, {'${p}txtaward': 'award value invalid'});
        expect(e.message, 'award value invalid');
      }
    },
  );
  test('native ranking Edit verifies values and image coordinates', () async {
    var posts = 0;
    final w = worker((
      url, {
      body,
      referer,
      headers = const {},
      timeout = const Duration(seconds: 30),
      followRedirects = true,
      cookies,
    }) async {
      if (body != null) {
        posts++;
        final payload = Uri.splitQueryString(body);
        expect(
          payload[r'ctl00$ContentPlaceHolder1$grd_Add$ctl02$btnEdit.x'],
          '4',
        );
        expect(
          payload[r'ctl00$ContentPlaceHolder1$grd_Add$ctl02$btnEdit.y'],
          '11',
        );
      }
      return reply(
        url,
        body == null
            ? fixture('monthly_ranking_saved.html')
            : delta(fixture('monthly_ranking_edit.html')),
      );
    });
    final form = await w.readForm('ranking', period, '123456'),
        result = await w.editRanking(period, '123456', form['snapshot']);
    expect(result['data']['editing'], true);
    expect(result['submission_attempted'], false);
    expect(posts, 1);
    await expectLater(
      () => w.submitForm(
        'ranking',
        period,
        '123456',
        result['data']['snapshot'],
        {
          '${p}txtaward': '1',
          '${p}txtlibbooks': '2',
          '${p}txtsports': '3',
          '${p}TextBox1': '01-09-2026',
        },
        editing: true,
      ),
      throwsA(isA<MonthlyError>().having((e) => e.code, 'code', 'NO_CHANGES')),
    );
    expect(posts, 1);
  });
  test(
    'native Delete verified history removal; duplicate target is blocked',
    () async {
      var posts = 0;
      final w = worker((
        url, {
        body,
        referer,
        headers = const {},
        timeout = const Duration(seconds: 30),
        followRedirects = true,
        cookies,
      }) async {
        if (body != null) posts++;
        return reply(
          url,
          body == null
              ? fixture('monthly_ranking_saved.html')
              : delta(fixture('monthly_ranking_pending.html')),
        );
      });
      final form = await w.readForm('ranking', period, '123456');
      final result = await w.deleteRanking(period, '123456', form['snapshot']);
      expect(result['verified'], true);
      expect(result['data']['completed'], false);
      expect(posts, 1);
      expect(
        () => MonthlyTasksWorker.rankingRecord(
          MonthlyTasksWorker.parseForm(
            fixture('monthly_ranking_duplicate.html'),
            'ranking',
          ),
          period,
        ),
        throwsA(isA<MonthlyError>()),
      );
    },
  );
  test('ranking session and 180 second TTL guard retained editing', () async {
    var key = 'one', at = 0.0, gets = 0;
    final w = worker(
      (
        url, {
        body,
        referer,
        headers = const {},
        timeout = const Duration(seconds: 30),
        followRedirects = true,
        cookies,
      }) async {
        gets++;
        return reply(url, fixture('monthly_ranking_pending.html'));
      },
      session: () => key,
      clock: () => at,
    );
    await w.readForm('ranking', period, '123456');
    at = 181;
    await w.readForm('ranking', period, '123456');
    expect(gets, 2);
    key = 'two';
    await w.readForm('ranking', period, '123456');
    expect(gets, 3);
  });
  test('VIFFS read GET then Show native payload', () async {
    final calls = <String>[];
    final w = worker((
      url, {
      body,
      referer,
      headers = const {},
      timeout = const Duration(seconds: 30),
      followRedirects = true,
      cookies,
    }) async {
      calls.add(body == null ? 'GET' : 'POST');
      if (body != null) {
        expect(followRedirects, false);
        final payload = Uri.splitQueryString(body);
        if (payload['__EVENTTARGET'] == '')
          expect(payload[r'ctl00$ContentPlaceHolder1$Button1'], 'Show');
      }
      return reply(url, fixture('monthly_viffs_open.html'));
    });
    final form = await w.readForm('viffs', vperiod, '123456');
    expect(calls, ['GET', 'POST', 'POST', 'POST', 'POST']);
    expect(form['sections'], hasLength(2));
    expect(form['snapshot'], isNotEmpty);
  });
  for (final mode in ['verified', 'timeout', 'identity', 'value', 'reject'])
    test('VIFFS submit $mode fresh full readback one commit', () async {
      var commits = 0, saved = false;
      final original = fixture('monthly_viffs_open.html');
      final freshSoup = html.parse(original);
      for (final n in freshSoup.querySelectorAll('input')) {
        if (n.id.contains('_Tablet_')) n.attributes['value'] = '5';
        if (n.id.contains('_TabletLessThen4_')) n.attributes['value'] = '3';
      }
      final fresh = freshSoup.outerHtml;
      final w = worker((
        url, {
        body,
        referer,
        headers = const {},
        timeout = const Duration(seconds: 30),
        followRedirects = true,
        cookies,
      }) async {
        if (body != null &&
            Uri.splitQueryString(body)
                .containsKey(r'ctl00$ContentPlaceHolder1$btnSubmit')) {
          commits++;
          saved = true;
          if (mode == 'timeout') throw TimeoutException('commit unknown');
          if (mode == 'reject')
            return reply(
              url,
              original.replaceFirst(
                '</form>',
                '<span id="${p}lblerrmsg">मूल पोर्टल त्रुटि</span></form>',
              ),
            );
        }
        if (saved && mode == 'identity')
          return reply(url, fresh.replaceAll('value="1"', 'value="99"'));
        return reply(url, saved && mode != 'value' ? fresh : original);
      });
      final form = await w.readForm('viffs', vperiod, '123456');
      final val = values(form);
      val.updateAll(
        (k, v) => k.contains('_Tablet_')
            ? '5'
            : k.contains('_TabletLessThen4_')
            ? '3'
            : v,
      );
      if (mode == 'verified') {
        final result = await w.submitForm(
          'viffs',
          vperiod,
          '123456',
          form['snapshot'],
          val,
        );
        expect(result['verified'], true);
      } else {
        await expectLater(
          () => w.submitForm('viffs', vperiod, '123456', form['snapshot'], val),
          throwsA(
            isA<MonthlyError>().having((e) => e.attempted, 'attempted', true),
          ),
        );
      }
      expect(commits, 1);
    });
  test('VIFFS expired review prevents commit', () async {
    var at = 0.0, posts = 0;
    final w = worker((
      url, {
      body,
      referer,
      headers = const {},
      timeout = const Duration(seconds: 30),
      followRedirects = true,
      cookies,
    }) async {
      if (body != null) posts++;
      return reply(url, fixture('monthly_viffs_open.html'));
    }, clock: () => at);
    final form = await w.readForm('viffs', vperiod, '123456');
    at = 181;
    await expectLater(
      () => w.submitForm(
        'viffs',
        vperiod,
        '123456',
        form['snapshot'],
        values(form),
      ),
      throwsA(isA<MonthlyError>().having((e) => e.code, 'code', 'STALE_FORM')),
    );
    expect(posts, 4);
  });
  for (final mode in ['verified', 'warning', 'changed', 'timeout', 'unlocked'])
    test('VIFFS Lock $mode exact confirmation and verification', () async {
      var first = 0, finals = 0, locked = false;
      final original = fixture('monthly_viffs_open.html');
      const warning =
          'कृपया सूचना को लॉक करने से पूर्व एक बार चेक कर ले अन्यथा लॉक करने के बाद बदलाव संभव नहीं होगा';
      final w = worker((
        url, {
        body,
        referer,
        headers = const {},
        timeout = const Duration(seconds: 30),
        followRedirects = true,
        cookies,
      }) async {
        final fields = body == null ? {} : Uri.splitQueryString(body);
        if (fields.containsKey(r'ctl00$ContentPlaceHolder1$Lock')) {
          first++;
          if (mode == 'timeout') throw TimeoutException('lock');
          var modal = original.replaceFirst(
            '</form>',
            '<div id="${p}div1">${mode == 'warning' ? 'Unexpected' : warning}</div><input type="submit" id="${p}btn_ok" name="ctl00\$ContentPlaceHolder1\$btn_ok" value="OK"></form>',
          );
          if (mode == 'changed')
            modal = modal.replaceAll('value="6"', 'value="7"');
          return reply(url, modal);
        }
        if (fields.containsKey(r'ctl00$ContentPlaceHolder1$btn_ok')) {
          finals++;
          locked = true;
        }
        return reply(
          url,
          locked && mode != 'unlocked'
              ? fixture('monthly_viffs_locked.html')
              : original,
        );
      });
      final form = await w.readForm('viffs', vperiod, '123456');
      if (mode == 'verified') {
        final result = await w.lockForm(
          'viffs',
          vperiod,
          '123456',
          form['snapshot'],
        );
        expect(result['verified'], true);
        expect(result['data']['locked'], true);
        expect(finals, 1);
      } else {
        await expectLater(
          () => w.lockForm('viffs', vperiod, '123456', form['snapshot']),
          throwsA(
            isA<MonthlyError>().having((e) => e.attempted, 'attempted', true),
          ),
        );
        expect(finals, mode == 'unlocked' ? 1 : 0);
      }
      expect(first, 1);
    });
  test('already locked is verified without commit', () async {
    var commits = 0;
    final w = worker((
      url, {
      body,
      referer,
      headers = const {},
      timeout = const Duration(seconds: 30),
      followRedirects = true,
      cookies,
    }) async {
      if (body != null &&
          (Uri.splitQueryString(body)
                  .containsKey(r'ctl00$ContentPlaceHolder1$Lock') ||
              Uri.splitQueryString(body)
                  .containsKey(r'ctl00$ContentPlaceHolder1$btn_ok')))
        commits++;
      return reply(url, fixture('monthly_viffs_locked.html'));
    });
    final form = await w.readForm('viffs', vperiod, '123456');
    final result = await w.lockForm(
      'viffs',
      vperiod,
      '123456',
      form['snapshot'],
    );
    expect(result['submission_attempted'], false);
    expect(commits, 0);
  });
}
