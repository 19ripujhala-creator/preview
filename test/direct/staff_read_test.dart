import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/core/direct/coordinator.dart';
import '../../lib/services/portals/staff_login/direct/http_session.dart';
import '../../lib/services/portals/staff_login/direct/http_auth.dart';
import '../../lib/services/portals/staff_login/direct/http_profile.dart';
import '../../lib/services/portals/staff_login/direct/http_history.dart';
import '../../lib/services/portals/staff_login/direct/http_read_bridge.dart';
import '../../lib/services/portals/staff_login/direct/staff_read_service.dart';
import '../../lib/services/portals/staff_login/direct/staff_runtime.dart'
    show StaffCoordinator;
import '../../lib/services/portals/staff_login/direct/webforms_delta.dart';
import 'staff_auth_test.dart'
    show StaffFakeTransport, StaffMemoryStorage, staffReply, staffTestBase;

class ReadBackend implements PortalBackend {
  ReadBackend(this.registry);
  final StaffHttpAuth registry;
  @override
  Object? currentContext() => registry.current();
  @override
  Future<Probe> probe(Object context) async => Probe.alive;
  @override
  Future<Map<String, dynamic>> authenticate(
    String user,
    String password,
    bool forceFresh,
  ) => throw StateError('Reads must not independently login');
}

Map<String, dynamic> get goldens => jsonDecode(
  File('test/direct/fixtures/python_staff_read.json').readAsStringSync(),
) as Map<String, dynamic>;
StaffFakeTransport scripted(Map c) => StaffFakeTransport([
  for (final r in c['responses'] as List)
    staffReply(
      staffHistoryPath,
      r['text'] as String,
      status: r['status'] as int,
      headers: {
        for (final e in (r['headers'] as Map).entries)
          e.key.toString(): [e.value.toString()],
      },
    ),
]);
StaffHttpSession authenticated(StaffFakeTransport client) =>
    StaffHttpSession(client: client)
      ..authenticated = true
      ..base = staffTestBase
      ..user = '99';
const profileHome =
    '<form><a id="logout"></a><div class="widget-heading">Test Person</div><div class="widget-subheading">Teacher</div></form>';
String framed(String kind, String id, String text) =>
    '${text.length}|$kind|$id|$text|';
void main() {
  for (final c in goldens['cases'] as List) {
    test('Python complete history golden: ${c['name']}', () async {
      final transport = scripted(c);
      final result = await fetchStaffHttpHistory(
        authenticated(transport),
        c['filter'] as String,
      );
      expect(result, c['expected']);
      final expected = c['requests'] as List;
      expect(transport.requests.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        final actual = transport.requests[i], want = expected[i] as Map;
        expect(actual['method'], want['method']);
        expect(actual['url'], want['url']);
        expect(actual['followRedirects'], false);
        if (want.containsKey('content'))
          expect(actual['content'], want['content']);
        if (want.containsKey('headers'))
          expect(actual['headers'], want['headers']);
      }
    });
  }
  for (final c in goldens['profiles'] as List) {
    test('Python profile field golden ${c['html']}', () {
      final expected = c['expected'] as Map;
      if (expected.containsKey('code')) {
        expect(
          () => staffProfileFields(c['html'] as String, c['user'] as String),
          throwsA(
            isA<StaffHttpError>()
                .having((e) => e.code, 'code', expected['code'])
                .having((e) => e.message, 'message', expected['message']),
          ),
        );
      } else {
        expect(
          staffProfileFields(c['html'] as String, c['user'] as String),
          expected,
        );
      }
    });
  }
  for (final c in goldens['p10'] as List) {
    test(
      'Python P10 golden ${c['html']}',
      () => expect(staffP10Fields(c['html'] as String), c['expected']),
    );
  }
  test(
    'delta framing retains emoji and embedded pipes',
    () => expect(parseStaffDelta(framed('updatePanel', 'x', '😀|हिंदी')), [
      ('updatePanel', 'x', '😀|हिंदी'),
    ]),
  );
  for (final bad in [
    '3|updatePanel|x|a|',
    'x|updatePanel|x|a|',
    '1|x',
    '1|x|y|a',
  ]) {
    test(
      'reject malformed AJAX frame $bad',
      () => expect(() => parseStaffDelta(bad), throwsFormatException),
    );
  }
  test(
    'profile uses Home then P10 on same already authenticated transport',
    () async {
      final client = StaffFakeTransport([
        staffReply(staffHomePath, profileHome),
        staffReply(staffP10Path, '<span id="spn_StatusPercen">100%</span>'),
      ]);
      final result = await fetchStaffHttpProfile(authenticated(client));
      expect(result['success'], true);
      expect((result['profile'] as Map)['p10StatusKnown'], 'true');
      expect(client.requests.map((r) => r['url']), [
        '$staffTestBase$staffHomePath',
        '$staffTestBase$staffP10Path',
      ]);
    },
  );
  for (final failure in ['HTTP', 'login', 'redirect', 'server']) {
    test('profile retains authoritative P10 $failure error', () async {
      final p10 = failure == 'HTTP'
          ? staffReply(staffP10Path, 'error', status: 503)
          : failure == 'login'
          ? staffReply(staffP10Path, '<input id="txt_Username">')
          : failure == 'redirect'
          ? staffReply(
              'https://rajshaladarpan.rajasthan.gov.in/SD1$staffP10Path',
              'other',
            )
          : staffReply(staffP10Path, 'Server Error in /');
      await expectLater(
        fetchStaffHttpProfile(
          authenticated(
            StaffFakeTransport([staffReply(staffHomePath, profileHome), p10]),
          ),
        ),
        throwsA(isA<StaffHttpError>()),
      );
    });
  }
  test(
    'P10 transport outage retains verified Home but marks status unknown',
    () async {
      final client = StaffFakeTransport()
        ..handler = (r) async {
          if ((r['url'] as String).endsWith(staffP10Path))
            throw const SocketException('offline');
          return staffReply(staffHomePath, profileHome);
        };
      final result = await fetchStaffHttpProfile(authenticated(client));
      expect((result['profile'] as Map)['p10StatusKnown'], 'false');
    },
  );
  test('unverified Home blocks profile and P10 request', () async {
    final client = StaffFakeTransport([
      staffReply(staffHomePath, '<form>maintenance</form>'),
    ]);
    await expectLater(
      fetchStaffHttpProfile(authenticated(client)),
      throwsA(isA<StaffHttpError>()),
    );
    expect(client.requests.length, 1);
  });
  test('invalid history filter never sends a request', () async {
    final client = StaffFakeTransport();
    expect(
      (await fetchStaffHttpHistory(authenticated(client), 'other'))['code'],
      'INVALID_PAYLOAD',
    );
    expect(client.requests, isEmpty);
  });
  test(
    'unauthenticated session never sends history or profile requests',
    () async {
      final client = StaffFakeTransport(),
          s = StaffHttpSession(client: StaffFakeTransport());
      expect((await fetchStaffHttpHistory(s))['code'], 'SESSION_EXPIRED');
      await expectLater(
        fetchStaffHttpProfile(s),
        throwsA(isA<StaffHttpError>()),
      );
      expect(client.requests, isEmpty);
    },
  );
  test('read bridge discards old account result', () async {
    final registry = StaffHttpAuth(storage: StaffMemoryStorage());
    final started = Completer<void>(), finish = Completer<void>();
    final client = StaffFakeTransport()
      ..handler = (r) async {
        if (!started.isCompleted) started.complete();
        await finish.future;
        return staffReply(
          staffHistoryPath,
          (goldens['cases'][2]['responses'][0]['text']) as String,
        );
      };
    await registry.install(authenticated(client));
    final pending = StaffHttpReadBridge(registry).fetchHistory();
    await started.future;
    // Swap ownership immediately; old close waits for its read to settle.
    final install = registry.install(authenticated(StaffFakeTransport()));
    finish.complete();
    expect((await pending)['code'], 'ACCOUNT_CHANGED');
    await install;
    await registry.closeSession();
  });
  test('source page cap returns partial failure instead of successful truncated history', () async {
    final client = scripted(goldens['cases'][0] as Map);
    final result = await StaffHistoryHttp(
      client,
      staffTestBase,
      maxPages: 1,
    ).fetch();
    expect(result['success'], false);
    expect(result['code'], 'INVALID_RESULT');
    expect(result['partial'], true);
    expect(result['failed_page'], 1);
    expect(client.requests.length, 1);
  });
  test('history refuses pager actions targeting a row mutation', () async {
    final source = goldens['cases'][0]['responses'][0]['text'] as String;
    final client = StaffFakeTransport([
      staffReply(
        staffHistoryPath,
        source.replaceAll('Page\$2', 'Delete\$2 Page\$2'),
      ),
    ]);
    final result = await fetchStaffHttpHistory(authenticated(client));
    expect(result['code'], 'PAGE_NOT_READY');
    expect(client.requests.length, 1);
  });
  test('delta unknown panel stops after one post without replay', () async {
    final client = scripted(goldens['cases'][3] as Map);
    client.replies[1] = staffReply(
      staffHistoryPath,
      framed('updatePanel', 'missing', '<p>unknown</p>'),
    );
    final result = await fetchStaffHttpHistory(authenticated(client));
    expect(result['success'], false);
    expect(result['partial'], true);
    expect(client.requests.length, 2);
  });
  test('history worker rejects unofficial or port-bearing bases', () {
    for (final base in [
      'http://rajshaladarpan.rajasthan.gov.in/SD4',
      '$staffTestBase/extra',
      'https://rajshaladarpan.rajasthan.gov.in:443/SD4',
      'https://other.example/SD4',
    ]) {
      expect(
        () => StaffHistoryHttp(StaffFakeTransport(), base),
        throwsArgumentError,
      );
    }
  });
  group('source complete-history route cache', () {
    late StaffFakeTransport client;
    late StaffHttpAuth registry;
    late StaffCoordinator coordinator;
    late StaffReadService reads;
    late DateTime clock;
    setUp(() async {
      clock = DateTime(2026, 10, 11);
      client = scripted(goldens['cases'][0] as Map);
      registry = StaffHttpAuth(storage: StaffMemoryStorage());
      await registry.install(authenticated(client));
      coordinator = StaffCoordinator(backend: ReadBackend(registry));
      reads = StaffReadService(
        registry: registry,
        coordinator: coordinator,
        now: () => clock,
      );
    });
    tearDown(() async {
      await coordinator.shutdown();
      await registry.closeSession();
    });
    test('all records and total are retained while API pagination slices complete cache', () async {
      final first = await reads.fetchHistory('99', page: 1, pageSize: 1);
      expect(first['success'], true);
      expect(first['total'], 2);
      expect(first['has_more'], true);
      expect((first['records'] as List).length, 1);
      final second = await reads.fetchHistory('99', page: 2, pageSize: 1);
      expect(second['total'], 2);
      expect(second['has_more'], false);
      expect((second['records'] as List).first['sNo'], '2');
      expect(client.requests.length, 2);
    });
    test('refresh bypasses complete cache', () async {
      await reads.fetchHistory('99');
      client.replies.addAll(scripted(goldens['cases'][0] as Map).replies);
      expect((await reads.fetchHistory('99', refresh: true))['success'], true);
      expect(client.requests.length, 4);
    });
    test('source 45-second cache expiry triggers fresh full read', () async {
      await reads.fetchHistory('99');
      clock = clock.add(const Duration(seconds: 45));
      client.replies.addAll(scripted(goldens['cases'][0] as Map).replies);
      await reads.fetchHistory('99');
      expect(client.requests.length, 4);
    });
    test('parallel callers share one complete history request', () async {
      final result = await Future.wait([
        reads.fetchHistory('99'),
        reads.fetchHistory('99'),
      ]);
      expect(result.every((r) => r['success'] == true), true);
      expect(client.requests.length, 2);
    });
    test('cache is copied before handing data to UI', () async {
      final first = await reads.fetchHistory('99');
      (first['records'] as List).clear();
      expect((await reads.fetchHistory('99'))['total'], 2);
    });
    test('account mismatch stops before HTTP', () async {
      expect((await reads.fetchHistory('other'))['code'], 'ACCOUNT_CHANGED');
      expect(client.requests, isEmpty);
    });
    test('paired paging parameters required', () async {
      expect(
        (await reads.fetchHistory('99', page: 1))['code'],
        'INVALID_PAYLOAD',
      );
      expect(client.requests, isEmpty);
    });
    test(
      'history invalidation prevents stale in-flight result publication',
      () async {
        final started = Completer<void>(), finish = Completer<void>();
        final replies = client.replies.toList();
        client.handler = (r) async {
          if (!started.isCompleted) {
            started.complete();
            await finish.future;
          }
          return replies.removeAt(0);
        };
        final task = reads.fetchHistory('99');
        await started.future;
        reads.invalidateHistory();
        finish.complete();
        expect((await task)['code'], 'CACHE_INVALIDATED');
      },
    );
    test('profile route reuses the same Staff lease and session', () async {
      client.replies.clear();
      client.replies.addAll([
        staffReply(staffHomePath, profileHome),
        staffReply(staffP10Path, ''),
      ]);
      expect((await reads.fetchProfile('99'))['success'], true);
      expect(client.requests.length, 2);
    });
  });
}
