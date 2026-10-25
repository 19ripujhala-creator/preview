import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/services/core/direct/coordinator.dart';
import '../../lib/services/portals/shaladarpan/student_service.dart';
import '../../lib/services/portals/staff_login/staff_login_service.dart';
import '../../lib/services/portals/staff_login/direct/http_auth.dart';
import '../../lib/services/portals/staff_login/direct/native_print_service.dart';
import '../../lib/services/portals/staff_login/direct/staff_read_service.dart';
import '../../lib/services/portals/staff_login/direct/staff_runtime.dart';
import 'staff_auth_test.dart' show StaffFakeTransport, StaffMemoryStorage;
import 'staff_read_test.dart' show authenticated;

class RecoveryBackend implements PortalBackend {
  RecoveryBackend(this.registry, {this.dead = true});
  final StaffHttpAuth registry;
  bool dead;
  int logins = 0;
  (String, String)? supplied;
  @override
  Object? currentContext() => registry.current();
  @override
  Future<Probe> probe(Object context) async => dead ? Probe.dead : Probe.alive;
  @override
  Future<Map<String, dynamic>> authenticate(
    String user,
    String password,
    bool forceFresh,
  ) async {
    logins++;
    supplied = (user, password);
    await registry.install(authenticated(StaffFakeTransport()));
    dead = false;
    return {'success': true};
  }
}

class RecoveryReads extends StaffReadService {
  RecoveryReads({required super.registry, required super.coordinator});
  @override
  Future<Map<String, dynamic>> fetchProfile(String user) async {
    await coordinator.ensureReady(Kind.read);
    return {'success': true};
  }
}

class RecoveryPrints extends StaffNativePrintService {
  RecoveryPrints({required super.registry, required super.coordinator});
  @override
  Future<Map<String, dynamic>> format10Pdf(String user, {String? nicId}) async {
    await coordinator.ensureReady(Kind.read);
    return {
      'success': true,
      'pdf_bytes': Uint8List.fromList('%PDF-test'.codeUnits),
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late StaffHttpAuth registry;
  late StaffCoordinator coordinator;
  late RecoveryBackend backend;
  var user = '99';

  setUp(() async {
    user = '99';
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, (call) async {
          if (call.method == 'read' &&
              (call.arguments as Map)['key'] == 'portal_credentials_v2') {
            return jsonEncode({'staff_id': user, 'staff_pass': 'saved-secret'});
          }
          return null;
        });
    StudentService.directAttendanceEnabled = true;
    registry = StaffHttpAuth(storage: StaffMemoryStorage());
    await registry.install(authenticated(StaffFakeTransport()));
    backend = RecoveryBackend(registry);
    coordinator = StaffCoordinator(backend: backend);
    StaffLoginService.directReadProvider = () async =>
        RecoveryReads(registry: registry, coordinator: coordinator);
    StaffLoginService.directPrintProvider = () async =>
        RecoveryPrints(registry: registry, coordinator: coordinator);
  });

  tearDown(() async {
    StaffLoginService.directReadProvider = null;
    StaffLoginService.directPrintProvider = null;
    StudentService.directAttendanceEnabled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, null);
    await coordinator.shutdown();
    await registry.closeSession();
  });

  test(
    'Restored expired Staff session recovers once with saved credentials',
    () async {
      expect(coordinator.status()['has_credentials'], false);
      final result = await StaffLoginService.fetchProfile();
      expect(result['success'], true);
      expect(backend.logins, 1);
      expect(backend.supplied, ('99', 'saved-secret'));
    },
  );

  test(
    'Healthy restored Staff session is reused without another login',
    () async {
      backend.dead = false;
      expect((await StaffLoginService.fetchProfile())['success'], true);
      expect(backend.logins, 0);
    },
  );

  test(
    'Direct PDF entry also binds recovery credentials after restart',
    () async {
      expect(await StaffLoginService.downloadFormat10Pdf(), isNotNull);
      expect(backend.logins, 1);
      expect(backend.supplied, ('99', 'saved-secret'));
    },
  );

  test(
    'Different saved account cannot bind or recover the restored session',
    () async {
      user = '100';
      expect(
        (await StaffLoginService.fetchProfile())['code'],
        'ACCOUNT_CHANGED',
      );
      expect(coordinator.status()['has_credentials'], false);
      expect(backend.logins, 0);
    },
  );
}
