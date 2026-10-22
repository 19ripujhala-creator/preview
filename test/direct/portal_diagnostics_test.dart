import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/core/direct/portal_diagnostics.dart';

void main() {
  setUp(PortalDiagnostics.clear);
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
