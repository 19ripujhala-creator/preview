import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/services/core/direct/coordinator.dart';
import '../../lib/services/portals/shaladarpan/student_service.dart';
import '../../lib/services/portals/staff_login/staff_login_service.dart';
import '../../lib/services/portals/staff_login/direct/auth_manager.dart';
import '../../lib/services/portals/staff_login/direct/http_auth.dart';
import '../../lib/services/portals/staff_login/direct/leave_apply_service.dart';
import '../../lib/services/portals/staff_login/direct/leave_apply_worker.dart';
import '../../lib/services/portals/staff_login/direct/leave_pdf_worker.dart';
import '../../lib/services/portals/staff_login/direct/portal_state.dart';
import '../../lib/services/portals/staff_login/direct/staff_read_service.dart';
import '../../lib/services/portals/staff_login/direct/staff_runtime.dart';
import 'staff_auth_test.dart' show StaffMemoryStorage, staffReply;
import 'staff_leave_apply_test.dart' show LeavePortal, payload, fixture;
import 'staff_native_print_test.dart' show StaffFakePrintBrowser;
import 'staff_read_test.dart' show goldens;

class BatchCleanupBrowser extends StaffFakePrintBrowser {
  bool closeFails = false, dismissFails = false;
  @override
  Future<void> closePopup() async {
    await super.closePopup();
    if (closeFails)
      throw const StaffPortalError('PAGE_NOT_READY', 'Popup cleanup failed.');
  }

  @override
  Future<Object?> evaluate(String e, {bool popup = false}) async {
    if (dismissFails && popupClosed && e.contains("'#MsgPopup button'"))
      throw const StaffPortalError('PAGE_NOT_READY', 'Modal cleanup failed.');
    return super.evaluate(e, popup: popup);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late LeavePortal portal;
  late StaffHttpAuth registry;
  late StaffCoordinator co;
  late StaffReadService reads;
  late StaffLeaveApplyService leaves;
  var now = DateTime.utc(2026, 10, 24, 5);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, (c) async {
          if (c.method == 'read' &&
              (c.arguments as Map)['key'] == 'portal_credentials_v2')
            return jsonEncode({'staff_id': '99', 'staff_pass': 'secret'});
          return null;
        });
    StudentService.directAttendanceEnabled = true;
    portal = LeavePortal();
    registry = StaffHttpAuth(storage: StaffMemoryStorage());
    final auth = StaffAuthManager(
      registry: registry,
      solveCaptcha: (_) => '1234',
    );
    await auth.initialize();
    portal.client.handler = (r) async {
      if ((r['url'] as String).endsWith('/StaffHome.aspx'))
        return staffReply(r['url'] as String, '<a id="lnkLogout">Logout</a>');
      return portal.respond(r);
    };
    portal.client.jar.receive([
      Cookie('ASP.NET_SessionId', 'saved')..path = '/',
    ], Uri.parse(portal.session.base!));
    await registry.install(portal.session);
    co = StaffCoordinator(backend: StaffHttpBackend(auth));
    co.rememberCredentials('99', 'secret');
    await co.ensureReady(Kind.read);
    now = DateTime.utc(2026, 10, 24, 5);
    reads = StaffReadService(
      registry: registry,
      coordinator: co,
      now: () => now,
    );
    leaves = StaffLeaveApplyService(
      registry: registry,
      coordinator: co,
      reads: reads,
    );
    StaffLoginService.directLeaveProvider = () async => leaves;
  });
  tearDown(() async {
    StaffLoginService.directLeaveProvider = null;
    StudentService.directAttendanceEnabled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, null);
    await co.shutdown();
    await registry.closeSession();
  });
  test(
    'public apply freezes the confirmed payload before provider await',
    () async {
      final provider = Completer<StaffLeaveApplyService>();
      StaffLoginService.directLeaveProvider = () => provider.future;
      final data = payload();
      final saving = StaffLoginService.applyLeave(data);
      data['reason_id'] = 'bad';
      data['confirmed'] = false;
      provider.complete(leaves);
      final r = await saving;
      expect(r['success'], true, reason: '$r');
      expect(portal.applies, 1);
    },
  );
  test(
    'concurrent service calls cannot queue two native Apply submissions',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final handler = portal.client.handler!;
      portal.client.handler = (r) async {
        if (r['method'] == 'GET' &&
            (r['url'] as String).contains('Staff_LeaveApplication.aspx')) {
          if (!entered.isCompleted) {
            entered.complete();
            await release.future;
          } else if (portal.applies > 0) {
            portal.state = html.parse(fixture());
          }
        }
        return handler(r);
      };
      final one = leaves.apply('99', payload());
      await entered.future;
      final two = leaves.apply('99', payload());
      release.complete();
      final result = await Future.wait([one, two]);
      expect(result.first['success'], true);
      expect(result.last['success'], false);
      expect(result.last['submission_attempted'], false);
      expect(portal.applies, 1);
    },
  );
  for (final status in [200, 409]) {
    test(
      'legacy HTTP $status preserves portal provenance and submission details',
      () async {
        StudentService.directAttendanceEnabled = false;
        final r = await http.runWithClient(
          () => StaffLoginService.applyLeave(payload()),
          () => MockClient(
            (_) async => http.Response(
              jsonEncode({
                'success': status == 200,
                'code': status == 200 ? 'OK' : 'DUPLICATE',
                'message': 'Exact original portal notice.',
                'message_source': 'portal',
                'submission_attempted': true,
                'submitted': status == 200,
              }),
              status,
            ),
          ),
        );
        expect(r['message'], 'Exact original portal notice.');
        expect(r['message_source'], 'portal');
        expect(r['submission_attempted'], true);
        expect(r['code'], status == 200 ? 'OK' : 'DUPLICATE');
      },
    );
  }
  for (final finalApply in [false, true]) {
    test(
      'native HTTP 500 heading retains portal provenance after finalApply=$finalApply',
      () async {
        final handler = portal.client.handler!;
        portal.client.handler = (r) async {
          final body = r['content'] as String? ?? '';
          if ((!finalApply && r['method'] == 'GET') ||
              (finalApply && body.contains('btnApply=')))
            return staffReply(
              r['url'] as String,
              '<h2>Exact native server error.</h2><p>Server Error in Application</p>',
              status: 500,
            );
          return handler(r);
        };
        final result = await StaffLeaveApplyWorker(portal.session)
            .apply(payload());
        expect(result['success'], false);
        expect(result['message'], 'Exact native server error.');
        expect(result['message_source'], 'portal');
        expect(result['submission_attempted'], finalApply);
        expect(portal.applies, 0);
      },
    );
  }
  for (final cleanup in ['close', 'dismiss']) {
    test('valid native leave PDF survives $cleanup cleanup failure', () async {
      final b = BatchCleanupBrowser()
        ..closeFails = cleanup == 'close'
        ..dismissFails = cleanup == 'dismiss';
      final result = await LeavePdfWorker(
        browser: b,
        check: () {},
      ).generate(sNo: '3', fromDate: '01/10/2026', toDate: '03/10/2026');
      expect(result['success'], true);
      expect(b.renders, 1);
      expect(b.viewClicks, 1);
      expect(b.popupClosed, true);
    });
  }
  test('popup cleanup cannot replace original wrong-row PDF error', () async {
    final b = BatchCleanupBrowser()
      ..closeFails = true
      ..wrongPopupDate = true;
    await expectLater(
      LeavePdfWorker(
        browser: b,
        check: () {},
      ).generate(sNo: '3', fromDate: '01/10/2026', toDate: '03/10/2026'),
      throwsA(
        isA<StaffPortalError>().having(
          (e) => e.message,
          'message',
          contains('selected From date'),
        ),
      ),
    );
    expect(b.renders, 0);
    expect(b.popupClosed, true);
  });
  test(
    'backward clock expires history cache instead of extending it',
    () async {
      final c = (goldens['cases'] as List).first as Map;
      var index = 0;
      portal.client.handler = (r) async {
        final responses = c['responses'] as List;
        final row = responses[index++ % responses.length] as Map;
        return staffReply(
          r['url'] as String,
          row['text'] as String,
          status: row['status'] as int,
        );
      };
      expect((await reads.fetchHistory('99'))['success'], true);
      final before = index;
      now = now.subtract(const Duration(seconds: 1));
      expect((await reads.fetchHistory('99'))['success'], true);
      expect(index, greaterThan(before));
    },
  );
  test('successful same-session Apply uses original portal notice and no extra login', () async {
    final r = await StaffLoginService.applyLeave(payload(half: true));
    expect(r['success'], true, reason: '$r');
    expect(r['message'], 'Leave Request Applied Successfully');
    expect(r['message_source'], 'portal');
    expect(portal.applies, 1);
    expect(
      portal.client.requests.where(
        (r) => (r['url'] as String).contains('captcha'),
      ),
      isEmpty,
    );
  });
  test('unconfirmed preview never sends native Apply', () async {
    final r = await leaves.apply('99', {...payload(), 'confirmed': false});
    expect(r['confirmation_required'], true);
    expect(portal.applies, 0);
    expect(portal.nexts, 0);
  });
  test(
    'native server-error provenance survives the public coordinator path',
    () async {
      final handler = portal.client.handler!;
      portal.client.handler = (r) async {
        if ((r['content'] as String? ?? '').contains('btnApply='))
          return staffReply(
            r['url'] as String,
            '<h2>Original native Apply failure.</h2><p>Server Error in Application</p>',
            status: 500,
          );
        return handler(r);
      };
      final result = await StaffLoginService.applyLeave(payload());
      expect(result['success'], false);
      expect(result['message'], 'Original native Apply failure.');
      expect(result['message_source'], 'portal');
      expect(result['submission_attempted'], true);
      expect(
        portal.client.requests
            .where((r) => (r['content'] as String? ?? '').contains('btnApply='))
            .length,
        1,
      );
    },
  );
}
