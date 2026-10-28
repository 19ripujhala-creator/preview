import '../../lib/services/core/direct/async_primitives.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/core/direct/portal_diagnostics.dart';

void main() {
  test('student view telemetry reports cache decisions with monotonic times and no identities', () {
    PortalDiagnostics.clear();
    PortalDiagnostics.recordStudentView(
      startedMs: PortalDiagnostics.monotonicMilliseconds,
      cache: 'expired',
      outcome: 'rendered',
      viewOnly: true,
    );
    final event =
        (jsonDecode(PortalDiagnostics.export())['events'] as List).single;
    expect(event['phase'], 'studentView');
    expect(event['cache'], 'expired');
    expect(event['view_only'], true);
    expect(event['started_ms'], greaterThanOrEqualTo(0));
    expect(event['ended_ms'], greaterThanOrEqualTo(event['started_ms']));
  });
  test(
    'student view telemetry cannot export arbitrary cache or outcome text',
    () {
      PortalDiagnostics.clear();
      PortalDiagnostics.recordStudentView(
        startedMs: 0,
        cache: 'private-class',
        outcome: 'private-student',
      );
      final output = PortalDiagnostics.export();
      expect(output.contains('private-'), false);
      final event = (jsonDecode(output)['events'] as List).single;
      expect(event['cache'], 'other');
      expect(event['outcome'], 'other');
    },
  );

  setUp(PortalDiagnostics.clear);
  test(
    'only fixed failure codes and success flags are included from results',
    () async {
      await PortalDiagnostics.measure(
        PortalPhase.studentReadOperation,
        () async => {
          'success': false,
          'code': 'PORTAL_SLOW',
          'message': 'private-name',
        },
      );
      await PortalDiagnostics.measure(
        PortalPhase.studentReadOperation,
        () async => {'success': false, 'code': 'secret-code'},
      );
      final output = PortalDiagnostics.export();
      final rows = jsonDecode(output)['events'] as List;
      expect(rows.first['success'], false);
      expect(rows.first['result_code'], 'PORTAL_SLOW');
      expect(rows.last.containsKey('result_code'), false);
      expect(output, isNot(contains('private-name')));
      expect(output, isNot(contains('secret-code')));
    },
  );
  test('request deadline and cancellation have distinct outcomes without exception details', () async {
    await expectLater(
      PortalDiagnostics.measure(
        PortalPhase.httpRequest,
        () async => throw TimeoutException('private-timeout-text'),
        deadlineMs: 25000,
      ),
      throwsA(isA<TimeoutException>()),
    );
    await expectLater(
      PortalDiagnostics.measure(
        PortalPhase.httpRequest,
        () async => throw const OperationCancelled(),
      ),
      throwsA(isA<OperationCancelled>()),
    );
    final output = PortalDiagnostics.export();
    final events = jsonDecode(output)['events'] as List;
    expect(events[0]['outcome'], 'timeout');
    expect(events[0]['deadline_ms'], 25000);
    expect(events[1]['outcome'], 'cancelled');
    expect(output, isNot(contains('private-timeout-text')));
  });
  test('nested timings retain parents and monotonic boundaries', () async {
    await PortalDiagnostics.measure(
      PortalPhase.studentSaveOperation,
      () => PortalDiagnostics.withAction(
        'SUBMIT',
        () => PortalDiagnostics.measure(
          PortalPhase.httpRequest,
          () async => 200,
          method: 'POST',
          source: 'school',
          path: '/SD1/Home/School/StudentdailyAttendanceStatus_Web_NewVersion.aspx',
          status: (v) => v,
        ),
      ),
    );
    final rows = jsonDecode(PortalDiagnostics.export())['events'] as List;
    final child = rows.first, parent = rows.last;
    expect(child['parent_sequence'], parent['sequence']);
    expect(child['action'], 'SUBMIT');
    expect(child['source'], 'school');
    expect(child['started_ms'], greaterThanOrEqualTo(parent['started_ms']));
    expect(parent['ended_ms'], greaterThanOrEqualTo(child['ended_ms']));
  });
  test(
    'new attribution fields never export unknown host/source/action strings',
    () async {
      await PortalDiagnostics.withAction(
        'private-token',
        () => PortalDiagnostics.measure(
          PortalPhase.httpRequest,
          () async => 200,
          source: 'private-cookie',
          path: '/hidden-token',
        ),
      );
      final output = PortalDiagnostics.export();
      expect(output, isNot(contains('private')));
      expect(output, isNot(contains('hidden')));
      expect(
        PortalDiagnostics.sourceForHost('rajsims-mdm.rajasthan.gov.in'),
        'rajsims',
      );
      expect(PortalDiagnostics.sourceForHost('sso.rajasthan.gov.in'), 'sso');
      expect(PortalDiagnostics.sourceForHost('secret.example'), 'other');
    },
  );
  test('clearing logs excludes completions from an earlier capture', () async {
    final gate = Completer<void>();
    final pending = PortalDiagnostics.measure(
      PortalPhase.studentRead,
      () => gate.future,
    );
    PortalDiagnostics.clear();
    gate.complete();
    await pending;
    expect(jsonDecode(PortalDiagnostics.export())['events'], isEmpty);
  });
  test(
    'timings whitelist page and method and never contain secret path/query',
    () async {
      final result = await PortalDiagnostics.measure(
        PortalPhase.httpRequest,
        () async => 200,
        method: 'POST',
        path: '/private-account/AuthKey-secret?password=hidden',
        status: (value) => value,
      );
      expect(result, 200);
      final output = PortalDiagnostics.export();
      expect(output.contains('private-account'), false);
      expect(output.contains('secret'), false);
      expect(output.contains('hidden'), false);
      final event = (jsonDecode(output)['events'] as List).single;
      expect(event['page'], 'other');
      expect(event['method'], 'POST');
      expect(event['status'], 200);
    },
  );
  test(
    'failed operation is rethrown without serializing exception contents',
    () async {
      final error = StateError('private-cookie-secret');
      await expectLater(
        PortalDiagnostics.measure(
          PortalPhase.studentSubmit,
          () async => throw error,
        ),
        throwsA(same(error)),
      );
      expect(
        PortalDiagnostics.export().contains('private-cookie-secret'),
        false,
      );
      final event =
          (jsonDecode(PortalDiagnostics.export())['events'] as List).single;
      expect(event['outcome'], 'exception');
    },
  );
  test('ring buffer stays bounded across many requests', () async {
    for (var i = 0; i < PortalDiagnostics.capacity + 30; i++) {
      await PortalDiagnostics.measure(
        PortalPhase.httpRequest,
        () async => 500,
        method: 'GET',
        path: '/SD1/Home/School/Home_New.aspx',
        status: (value) => value,
      );
    }
    final events = jsonDecode(PortalDiagnostics.export())['events'] as List;
    expect(events.length, PortalDiagnostics.capacity);
    expect(events.last['page'], 'home_new.aspx');
    expect(events.last['outcome'], 'http_error');
  });
}
