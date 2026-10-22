import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/services/portals/shaladarpan/student_service.dart';
import '../../lib/services/portals/staff_login/staff_login_service.dart';
import '../../lib/services/portals/staff_login/direct/http_auth.dart';
import '../../lib/services/portals/staff_login/direct/leave_apply_service.dart';
import '../../lib/services/portals/staff_login/direct/staff_read_service.dart';
import '../../lib/services/portals/staff_login/direct/staff_runtime.dart';
import 'staff_auth_test.dart' show StaffFakeTransport, StaffMemoryStorage;
import 'staff_read_test.dart' show ReadBackend, authenticated;

class LeaveFacade extends StaffLeaveApplyService {
  LeaveFacade({
    required super.registry,
    required super.coordinator,
    required super.reads,
  });
  int calls = 0;
  Map<String, dynamic>? received;
  void Function()? after;
  Map<String, dynamic> result = {
    'success': false,
    'code': 'PORTAL_MESSAGE',
    'message': 'अवकाश आवेदन पहले से मौजूद है।',
    'message_source': 'portal',
  };
  @override
  Future<Map<String, dynamic>> apply(
    String user,
    Map<String, dynamic> input,
  ) async {
    calls++;
    received = Map.of(input);
    after?.call();
    return Map.of(result);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  var user = '99';
  late StaffHttpAuth registry;
  late StaffCoordinator coordinator;
  late LeaveFacade leaves;
  setUp(() async {
    user = '99';
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, (call) async {
          if (call.method == 'read' &&
              (call.arguments as Map)['key'] == 'portal_credentials_v2')
            return jsonEncode({'staff_id': user, 'staff_pass': 'saved-secret'});
          return null;
        });
    StudentService.directAttendanceEnabled = true;
    registry = StaffHttpAuth(storage: StaffMemoryStorage());
    await registry.install(authenticated(StaffFakeTransport()));
    coordinator = StaffCoordinator(backend: ReadBackend(registry));
    leaves = LeaveFacade(
      registry: registry,
      coordinator: coordinator,
      reads: StaffReadService(registry: registry, coordinator: coordinator),
    );
    StaffLoginService.directLeaveProvider = () async => leaves;
  });
  tearDown(() async {
    StaffLoginService.directLeaveProvider = null;
    StudentService.directAttendanceEnabled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, null);
    await coordinator.shutdown();
    await registry.closeSession();
  });
  test(
    'existing applyLeave signature forwards payload and exact portal message',
    () async {
      final payload = <String, dynamic>{
        'confirmed': true,
        'sNo': '7',
        'original_from_date': '13/10/2026',
      };
      final response = await StaffLoginService.applyLeave(payload);
      expect(leaves.received, payload);
      expect(response['message'], leaves.result['message']);
      expect(response['message_source'], 'portal');
      expect(response['data'], leaves.result);
    },
  );
  test(
    'same-account stored credentials are bound for coordinator recovery',
    () async {
      await StaffLoginService.applyLeave({'confirmed': false});
      expect(coordinator.status()['has_credentials'], true);
      expect(leaves.calls, 1);
    },
  );
  test('missing saved account cannot call direct worker or backend', () async {
    user = '';
    final response = await StaffLoginService.applyLeave({'confirmed': true});
    expect(response['code'], 'SESSION_EXPIRED');
    expect(leaves.calls, 0);
  });
  test('account change during operation discards old result', () async {
    leaves.after = () => user = 'another';
    final response = await StaffLoginService.applyLeave({'confirmed': true});
    expect(response['code'], 'ACCOUNT_CHANGED');
    expect(leaves.calls, 1);
  });
}
