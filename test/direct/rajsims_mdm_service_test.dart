import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/core/direct/coordinator.dart';
import '../../lib/services/portals/rajsims/direct/http_auth.dart';
import '../../lib/services/portals/rajsims/direct/http_context.dart';
import '../../lib/services/portals/rajsims/direct/rajsims_sso_httpx.dart';
import '../../lib/services/portals/rajsims/direct/rajsims_mdm_worker.dart';
import '../../lib/services/portals/rajsims/direct/rajsims_mdm_service.dart';
import '../../lib/services/portals/rajsims/direct/rajsims_httpx.dart';
import 'rajsso_httpx_test.dart' show ScriptedSsoTransport, loadSsoFixture;

class MdmTestRegistry extends RajsimsHttpAuth {
  MdmTestRegistry(this.context)
    : super(
        sso: RajssoHttpx(
          solveCaptcha: (_) => '123456',
          clientFactory: () => ScriptedSsoTransport(loadSsoFixture()),
        ),
      );
  final RajsimsHttpContext context;
  @override
  RajsimsHttpContext? current() => context;
  @override
  String get username => 'offline-user';
}

class MdmTestBackend implements PortalBackend {
  MdmTestBackend(this.context);
  final RajsimsHttpContext context;
  @override
  Object? currentContext() => context;
  @override
  Future<Probe> probe(Object context) async => Probe.alive;
  @override
  Future<Map<String, dynamic>> authenticate(
    String u,
    String p,
    bool fresh,
  ) async => {'success': true};
}

Map<String, dynamic> _payload() => {
  'product_name': ' Wheat ',
  'beneficiary_count': 26,
  'atithi_mata_choice': '0',
  'atithi_mata_count': 1,
  'is_zero_consumption': false,
};
void main() {
  test('route validation retains required product, count, reason and calendar rules', () {
    final valid = _payload();
    expect(RajsimsMdmService.validate(valid), null);
    expect(valid['product_name'], 'Wheat');
    expect(
      RajsimsMdmService.validate({
        ..._payload(),
        'beneficiary_count': 0,
      })?['code'],
      'BAD_COUNT',
    );
    expect(
      RajsimsMdmService.validate({
        ..._payload(),
        'beneficiary_count': 10000,
      })?['code'],
      'INVALID_PAYLOAD',
    );
    expect(
      RajsimsMdmService.validate({
        ..._payload(),
        'atithi_mata_choice': '1',
        'atithi_mata_count': 0,
      })?['message'],
      'Atithi Mata count must be positive.',
    );
    expect(
      RajsimsMdmService.validate({
        ..._payload(),
        'is_zero_consumption': true,
      })?['code'],
      'INVALID_PAYLOAD',
    );
    expect(
      RajsimsMdmService.validate({..._payload(), 'legacy': true})?['code'],
      'BAD_DATE',
    );
    expect(
      RajsimsMdmService.validate({
        ..._payload(),
        'legacy_date': '31/02/2026',
      })?['code'],
      'BAD_DATE',
    );
    expect(
      RajsimsMdmService.validate({
        ..._payload(),
        'legacy_date': '13-Oct-2026',
      })?['code'],
      'BAD_DATE',
    );
    final legacy = {..._payload(), 'legacy': true, 'legacy_date': '2026-10-13'};
    expect(RajsimsMdmService.validate(legacy), null);
    expect(legacy['legacy_date'], '13/10/2026');
  });
  test('parallel stock callers share one request and receive separate cached copies', () async {
    final context = RajsimsHttpContext(ScriptedSsoTransport(loadSsoFixture())),
        reg = MdmTestRegistry(context),
        gate = Completer<void>();
    reg.auth.bindContext(context, 'id', 'key');
    reg.auth.mergeProfile({'OfficeId': 11, 'OrgId': 13}, context);
    var calls = 0;
    final worker = RajsimsMdmWorker(
      auth: reg.auth,
      currentContext: reg.current,
      request: (c, p, {bool allowAuthRetry = true, bool? safeToRetry}) async {
        calls++;
        await gate.future;
        return const RajsimsGatewayResult(
          true,
          {
            'CustomObject': [
              {'NAME': 'Wheat', 'TOTAL': 12},
            ],
          },
          200,
          '',
        );
      },
    );
    final a = worker.stock(context), b = worker.stock(context);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    gate.complete();
    final ra = await a, rb = await b;
    ra['stock']['wheat'] = 0;
    expect(rb['stock']['wheat'], 12);
    expect((await worker.stock(context))['stock']['wheat'], 12);
    expect(calls, 1);
    await worker.close();
    await context.close();
  });
  test(
    'invalidation prevents an older in-flight stock result repopulating cache',
    () async {
      final context = RajsimsHttpContext(
            ScriptedSsoTransport(loadSsoFixture()),
          ),
          reg = MdmTestRegistry(context),
          gate = Completer<void>();
      reg.auth.bindContext(context, 'id', 'key');
      reg.auth.mergeProfile({'OfficeId': 11, 'OrgId': 13}, context);
      var calls = 0;
      final worker = RajsimsMdmWorker(
        auth: reg.auth,
        currentContext: reg.current,
        request: (c, p, {bool allowAuthRetry = true, bool? safeToRetry}) async {
          calls++;
          if (calls == 1) await gate.future;
          return const RajsimsGatewayResult(
            true,
            {
              'CustomObject': [
                {'NAME': 'Wheat', 'TOTAL': 12},
              ],
            },
            200,
            '',
          );
        },
      );
      final stale = worker.stock(context);
      await Future<void>.delayed(Duration.zero);
      worker.invalidateResults();
      gate.complete();
      await stale;
      await worker.stock(context);
      expect(calls, 2);
      await worker.close();
      await context.close();
    },
  );
  test('account mismatch and invalid mutation stop before dispatch', () async {
    final context = RajsimsHttpContext(ScriptedSsoTransport(loadSsoFixture())),
        reg = MdmTestRegistry(context),
        co = PortalCoordinator(
          name: 'rajsims',
          backend: MdmTestBackend(context),
        );
    var calls = 0;
    final worker = RajsimsMdmWorker(
          auth: reg.auth,
          currentContext: reg.current,
          request:
              (c, p, {bool allowAuthRetry = true, bool? safeToRetry}) async {
                calls++;
                return const RajsimsGatewayResult(
                  false,
                  null,
                  500,
                  'unexpected',
                );
              },
        ),
        service = RajsimsMdmService(
          registry: reg,
          worker: worker,
          coordinator: co,
        );
    expect((await service.stock('another-user'))['code'], 'ACCOUNT_CHANGED');
    expect(
      (await service.submit('offline-user', {
        ..._payload(),
        'beneficiary_count': 0,
      }))['code'],
      'BAD_COUNT',
    );
    expect(calls, 0);
    await co.shutdown();
    await worker.close();
    await context.close();
  });
  test(
    'MPR bundle preserves source partial results and never fetches VIFFS',
    () async {
      final context = RajsimsHttpContext(
            ScriptedSsoTransport(loadSsoFixture()),
          ),
          reg = MdmTestRegistry(context),
          co = PortalCoordinator(
            name: 'rajsims',
            backend: MdmTestBackend(context),
          );
      reg.auth.bindContext(context, 'id', 'key');
      reg.auth.mergeProfile({
        'OfficeId': 11,
        'OrgId': 13,
        'PersonalDetails': {
          'Name': 'Offline User',
          'MobileNumber': '9876543210',
        },
      }, context);
      await co.authenticate('offline-user', 'password');
      final calls = <String>[];
      final worker = RajsimsMdmWorker(
            auth: reg.auth,
            currentContext: reg.current,
            request:
                (c, p, {bool allowAuthRetry = true, bool? safeToRetry}) async {
                  calls.add(p['ApiKey'] as String);
                  return const RajsimsGatewayResult(
                    false,
                    null,
                    403,
                    'मूल संदेश',
                  );
                },
          ),
          service = RajsimsMdmService(
            registry: reg,
            worker: worker,
            coordinator: co,
          );
      final r = await service.bundle(
        'offline-user',
        2026,
        9,
        () async => {'success': true, 'complete': true, 'udise': '12345678901'},
      );
      expect(r['success'], true);
      expect(r['school']['udise'], '12345678901');
      expect(r['monthly'], null);
      expect(r['profile']['incharge_name'], 'Offline User');
      expect(r['viffs_p'], null);
      expect(r['viffs_source'], 'monthly_task_status');
      expect(calls, ['GetSummaryReport']);
      await co.shutdown();
      await worker.close();
      await context.close();
    },
  );
}
