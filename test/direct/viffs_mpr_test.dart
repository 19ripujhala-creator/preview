import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import '../../lib/services/portals/shaladarpan/direct/monthly_tasks_worker.dart';
import '../../lib/services/portals/shaladarpan/direct/viffs_mpr_worker.dart';
import '../../lib/services/portals/shaladarpan/direct/viffs_mpr_http.dart';
import '../../lib/services/portals/shaladarpan/direct/school_http.dart';
import '../../lib/experiments/direct_monthly_task_service.dart';
import '../../lib/experiments/direct_portal_auth.dart';

const p = MonthlyTasksWorker.prefix;
final base = Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/');
String fixture(String name) =>
    File('test/direct/fixtures/$name').readAsStringSync();
MonthlyReply reply(Uri url, String text) => (
  url: url,
  status: 200,
  html: text,
  cookies: SchoolCookieJar({'ASP.NET_SessionId': 'offline'}),
);
ViffsMprHttp worker(
  MonthlyRequest request, {
  Uri? node,
  String Function()? key,
}) => ViffsMprHttp(
  request: request,
  baseUrl: () => node ?? base,
  schoolId: () => '123456',
  sessionKey: key ?? () => 'school/1/cookie',
);

class SummaryAuth extends DirectPortalAuth {
  int requests = 0;
  @override
  bool get isVerified => true;
  @override
  String get verifiedNode => 'SD1';
  @override
  String? get authenticatedSchoolId => '123456';
  @override
  String get schoolSessionIdentity => 'mpr/session';
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
    requests++;
    return reply(url, fixture('monthly_viffs_locked.html'));
  }
}

void main() {
  final cases = jsonDecode(fixture('python_viffs_mpr_summary.json')) as List;
  for (final c in cases) {
    test('original Python locked summary ${c['name']}', () {
      final form = Map<String, dynamic>.from(c['form']);
      final selection = Map<String, String>.from(c['selection']);
      if ((c['expected'] as Map).containsKey('code')) {
        expect(
          () =>
              ViffsMprWorker.summarizeLockedForm(form, c['school'], selection),
          throwsA(
            isA<MonthlyError>()
                .having((e) => e.code, 'code', c['expected']['code'])
                .having((e) => e.message, 'message', c['expected']['message']),
          ),
        );
      } else {
        expect(
          ViffsMprWorker.summarizeLockedForm(form, c['school'], selection),
          c['expected'],
        );
      }
    });
  }

  test('HTTP native chain exactly matches original Python payloads', () async {
    final golden = jsonDecode(fixture('python_viffs_read_chain.json')) as List;
    var posts = 0;
    String page(bool locked) {
      final soup = html.parse(
        fixture(
          locked ? 'monthly_viffs_locked.html' : 'monthly_viffs_open.html',
        ),
      );
      if (!locked) soup.getElementById('${p}grd_Add')!.remove();
      if (posts > 0) {
        soup.querySelector('input[name="__VIEWSTATE"]')!.attributes['value'] =
            'VS${posts + 1}';
        soup
                .querySelector('input[name="__EVENTVALIDATION"]')!
                .attributes['value'] =
            'EV${posts + 1}';
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
      if (body == null) {
        expect(followRedirects, true);
        return reply(url, page(false));
      }
      expect(
        Uri.splitQueryString(body),
        Uri.splitQueryString(golden[posts]['body']),
      );
      expect(timeout, const Duration(seconds: 25));
      expect(followRedirects, false);
      expect(referer, url);
      posts++;
      return reply(url, page(posts == 4));
    });
    final result = await w.fetchSummary(
      school: '123456',
      year: 2026,
      month: 9,
      timeoutMs: 25000,
    );
    expect(result['success'], true, reason: result.toString());
    expect(result['entry_available'], true);
    expect(result['status'], 'locked');
    expect(result['transport'], 'http');
    expect(posts, 4);
  });

  for (final tablet in ['P', 'B']) {
    test(
      'HTTP $tablet chain picks month from refreshed tablet response',
      () async {
        var posts = 0;
        final selected = <String, String>{
          'ddlStudentType': '2026-27',
          'ddlClass': '0',
          'ddlmonth': '0',
        };
        String page() {
          final soup = html.parse(fixture('monthly_viffs_locked.html'));
          for (final e in selected.entries) {
            final node = soup.getElementById(p + e.key)!;
            if (e.key == 'ddlmonth') {
              node.innerHtml = posts >= 2
                  ? '<option value="0">Select</option><option value="09">September</option>'
                  : '<option value="0">Select</option>';
            }
            for (final o in node.querySelectorAll('option')) {
              o.attributes.remove('selected');
              if (o.attributes['value'] == e.value)
                o.attributes['selected'] = '';
            }
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
          if (body != null) {
            final data = Uri.splitQueryString(body);
            posts++;
            for (final k in selected.keys) {
              final v = data['ctl00\$ContentPlaceHolder1\$$k'];
              if (v != null) selected[k] = v;
            }
            expect(
              data.keys.any(
                (k) =>
                    k.contains('Unlock') ||
                    k.contains('btnSubmit') ||
                    k.endsWith(r'$Lock'),
              ),
              false,
            );
          }
          return reply(url, page());
        });
        final result = await w.fetchSummary(
          school: '123456',
          year: 2026,
          month: 9,
          tablet: tablet,
        );
        expect(result['success'], true);
        expect(result['tablet'], tablet);
        expect(result['selection']['${p}ddlmonth'], '09');
        expect(posts, 4);
      },
    );
  }

  for (final record in [
    (year: true, month: 9, tablet: 'P', code: 'INVALID_SELECTION'),
    (year: 2026, month: 0, tablet: 'P', code: 'INVALID_SELECTION'),
    (year: 2026, month: 13, tablet: 'P', code: 'INVALID_SELECTION'),
    (year: 2026, month: 9, tablet: 'X', code: 'INVALID_SELECTION'),
    (year: '2026x', month: 9, tablet: 'P', code: 'INVALID_SELECTION'),
  ]) {
    test('invalid report period rejected before network $record', () async {
      final w = worker(
        (
          url, {
          body,
          referer,
          headers = const {},
          timeout = const Duration(seconds: 30),
          followRedirects = true,
          cookies,
        }) async => throw StateError('must not request'),
      );
      final result = await w.fetchSummary(
        school: '123456',
        year: record.year,
        month: record.month,
        tablet: record.tablet,
      );
      expect(result['code'], record.code);
      expect(result['complete'], false);
    });
  }
  for (final time in [0, -1, double.nan, double.infinity]) {
    test('invalid timeout $time rejected before network', () async {
      final w = worker(
        (
          url, {
          body,
          referer,
          headers = const {},
          timeout = const Duration(seconds: 30),
          followRedirects = true,
          cookies,
        }) async => throw StateError('must not request'),
      );
      expect(
        (await w.fetchSummary(
          school: '123456',
          year: 2026,
          month: 9,
          timeoutMs: time,
        ))['code'],
        'INVALID_SELECTION',
      );
    });
  }
  test('session replacement stops after first request', () async {
    var key = 'old', calls = 0;
    final w = worker((
      url, {
      body,
      referer,
      headers = const {},
      timeout = const Duration(seconds: 30),
      followRedirects = true,
      cookies,
    }) async {
      calls++;
      key = 'new';
      return reply(url, fixture('monthly_viffs_locked.html'));
    }, key: () => key);
    expect(
      (await w.fetchSummary(school: '123456', year: 2026, month: 9))['code'],
      'SESSION_CHANGED',
    );
    expect(calls, 1);
  });
  for (final e in [
    TimeoutException('offline'),
    const SocketException('offline'),
  ]) {
    test('source network classification ${e.runtimeType}', () async {
      final w = worker(
        (
          url, {
          body,
          referer,
          headers = const {},
          timeout = const Duration(seconds: 30),
          followRedirects = true,
          cookies,
        }) async => throw e,
      );
      expect(
        (await w.fetchSummary(school: '123456', year: 2026, month: 9))['code'],
        e is TimeoutException ? 'PORTAL_SLOW' : 'NETWORK_ERROR',
      );
    });
  }
  test('actual deadline alert preserved in HTTP report', () async {
    var posts = 0;
    final soup = html.parse(fixture('monthly_viffs_open.html'));
    soup.getElementById('${p}grd_Add')!.remove();
    final initial = soup.outerHtml;
    soup.body!.append(
      html.parseFragment(fixture('viffs_live_deadline_script.html')),
    );
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
      return reply(url, posts == 4 ? soup.outerHtml : initial);
    });
    final result = await w.fetchSummary(school: '123456', year: 2026, month: 9);
    expect(result['code'], 'PORTAL_MESSAGE');
    expect(result['message'], contains('अनलॉक बटन पर क्लिक करें'));
    expect(result['complete'], false);
    expect(posts, 4);
  });
  test(
    'router adapter uses existing authenticated monthly transport',
    () async {
      final auth = SummaryAuth();
      final result = await DirectMonthlyTaskService(auth)
          .fetchViffsSummary(school: '123456', year: 2026, month: 9);
      expect(result['success'], true);
      expect(auth.requests, 5);
    },
  );
  test('router invalid year rejects before request', () async {
    final auth = SummaryAuth();
    final result = await DirectMonthlyTaskService(auth)
        .fetchViffsSummary(school: '123456', year: 1999, month: 9);
    expect(result['code'], 'INVALID_SELECTION');
    expect(auth.requests, 0);
  });
  test(
    'legacy worker retains May academic start and metric contract',
    () async {
      final original = Map<String, dynamic>.from(cases.first['form']);
      final calls = <Map<String, String>>[];
      final result = await ViffsMprWorker.fetchSummary(
        (selection, school) async {
          calls.add(selection);
          return original;
        },
        '123456',
        2026,
        9,
      );
      expect(result['success'], true);
      expect(calls, hasLength(2));
      expect(result['metric'], 'children_four_or_more_tablets');
      expect(result.containsKey('transport'), false);
    },
  );
  test('academic session rolls before May and accepts full/en dash years', () {
    expect(ViffsMprWorker.sessionPattern(2025).hasMatch('2025–2026'), true);
    expect(ViffsMprWorker.sessionPattern(2025).hasMatch('2025-26'), true);
    expect(ViffsMprWorker.sessionPattern(2025).hasMatch('2026-27'), false);
  });
}
