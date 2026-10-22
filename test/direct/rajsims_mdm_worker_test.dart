import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/rajsims/direct/rajsims_mdm_worker.dart';
import '../../lib/services/portals/rajsims/direct/auth_manager.dart';
import '../../lib/services/portals/rajsims/direct/http_context.dart';
import '../../lib/services/portals/rajsims/direct/rajsims_httpx.dart';
import 'rajsso_httpx_test.dart' show ScriptedSsoTransport, loadSsoFixture;

void main() {
  final fixture = jsonDecode(
    File('test/direct/fixtures/python_rajsims_mdm.json').readAsStringSync(),
  ) as Map;
  for (final raw in fixture['cases']) {
    final testCase = Map<String, dynamic>.from(raw);
    test(
      'Python MDM ${testCase['name']} request and response parity',
      () async {
        final context = RajsimsHttpContext(
          ScriptedSsoTransport(loadSsoFixture()),
        );
        final auth = RajsimsAuthManager(
          currentContext: () => context,
          loginImplementation: (_, __, ___) async => {},
          bodyStatusCode: (_) => null,
          persistState: (_) async {},
          persistUsername: (_) async {},
          clearUserInfoCache: () {},
        );
        auth.bindContext(context, 'id', 'key');
        expect(
          auth.mergeProfile({
            'OfficeId': 11,
            'OrgId': 13,
            'OfficeTypeId': 224,
            'GroupId': 81,
            'GroupName': 'Primary School',
            'OfficeName': 'Offline School',
            'PersonalDetails': {
              'Name': 'Offline User',
              'MobileNumber': '9876543210',
              'OfficeName': 'Offline School',
            },
          }, context),
          true,
        );
        final expectedCalls = (testCase['calls'] as List)
                .map((v) => Map<String, dynamic>.from(v))
                .toList(),
            used = <int>{};
        final worker = RajsimsMdmWorker(
          auth: auth,
          currentContext: () => context,
          nowIst: () => DateTime.utc(2026, 10, 14, 12),
          request:
              (c, p, {bool allowAuthRetry = true, bool? safeToRetry}) async {
                expect(identical(c, context), true);
                final i = expectedCalls.indexWhere(
                  (r) =>
                      !used.contains(expectedCalls.indexOf(r)) &&
                      jsonEncode(r['payload']) == jsonEncode(p),
                );
                // Compare maps independent of JSON map insertion order.
                var matched = i;
                if (matched < 0) {
                  for (var k = 0; k < expectedCalls.length; k++) {
                    if (!used.contains(k) &&
                        equals(expectedCalls[k]['payload']).matches(p, {})) {
                      matched = k;
                      break;
                    }
                  }
                }
                expect(
                  matched,
                  greaterThanOrEqualTo(0),
                  reason: 'Unexpected payload: ${jsonEncode(p)}',
                );
                final call = expectedCalls[matched];
                used.add(matched);
                expect(allowAuthRetry, call['allow_auth_retry']);
                expect(safeToRetry, call['safe_to_retry']);
                final r = call['reply'] as List;
                return RajsimsGatewayResult(
                  r[0] as bool,
                  r[1],
                  r[2] as int?,
                  r[3] as String,
                );
              },
        );
        final p = Map<String, dynamic>.from(testCase['payload'] ?? {}),
            variant = testCase['variant'];
        Map<String, dynamic> result;
        switch (testCase['operation']) {
          case 'stock':
            result = await worker.stock(context, force: true);
          case 'status':
            result = await worker.status(context, force: true);
          case 'history':
            result = await worker.history(
              context,
              isLegacy: variant == 'legacy',
            );
          case 'entry':
            result = await worker.entry('D77', context);
          case 'submit':
            result = await worker.submit(context, p);
          case 'update':
            result = await worker.update(
              'D77',
              p,
              context,
              legacy: variant == 'legacy',
            );
          case 'monthly':
            result = await worker.monthlySummary(context, 2026, 9);
          case 'profile':
            result = await worker.mprProfile(context);
          default:
            throw StateError('Unknown operation');
        }
        result.remove('timings');
        expect(result, testCase['expected']);
        expect(used.length, expectedCalls.length);
        await worker.close();
        await context.close();
      },
    );
  }
}
