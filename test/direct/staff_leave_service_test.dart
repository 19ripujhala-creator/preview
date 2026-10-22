import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/staff_login/direct/http_auth.dart';
import '../../lib/services/portals/staff_login/direct/leave_apply_service.dart';
import '../../lib/services/portals/staff_login/direct/staff_read_service.dart';
import '../../lib/services/portals/staff_login/direct/staff_runtime.dart';
import 'staff_auth_test.dart' show StaffMemoryStorage;
import 'staff_read_test.dart' show ReadBackend;
import 'staff_leave_apply_test.dart' show LeavePortal, payload;

class CountingReads extends StaffReadService {
  CountingReads({required super.registry, required super.coordinator});
  int invalidations = 0;
  @override
  void invalidateHistory() {
    invalidations++;
    super.invalidateHistory();
  }
}

void main() {
  late StaffHttpAuth registry;
  late StaffCoordinator coordinator;
  late CountingReads reads;
  late StaffLeaveApplyService service;
  late LeavePortal portal;
  Future<void> install(LeavePortal value) async {
    portal = value;
    if (registry.current() == null) {
      await registry.install(portal.session);
    } else {
      (registry.current()!.client as dynamic).handler = portal.respond;
    }
  }

  setUp(() async {
    registry = StaffHttpAuth(storage: StaffMemoryStorage());
    await install(LeavePortal());
    coordinator = StaffCoordinator(backend: ReadBackend(registry));
    coordinator.rememberCredentials('99', 'offline-password');
    reads = CountingReads(registry: registry, coordinator: coordinator);
    service = StaffLeaveApplyService(
      registry: registry,
      coordinator: coordinator,
      reads: reads,
    );
  });
  tearDown(() async {
    await coordinator.shutdown();
    await registry.closeSession();
  });
  test('confirmed direct service uses existing session and invalidates history twice', () async {
    final result = await service.apply('99', payload());
    expect(result['success'], true, reason: result.toString());
    expect(reads.invalidations, 2);
    expect(portal.applies, 1);
  });
  test(
    'unconfirmed preview requires ready account but never opens form',
    () async {
      final result = await service.apply('99', {
        ...payload(),
        'confirmed': false,
      });
      expect(result['confirmation_required'], true);
      expect(portal.client.requests, isEmpty);
      expect(reads.invalidations, 0);
    },
  );
  test('changed account cannot send any portal request', () async {
    final result = await service.apply('another-user', payload());
    expect(result['code'], 'ACCOUNT_CHANGED');
    expect(portal.client.requests, isEmpty);
  });
  test('portal validation survives coordinator unchanged', () async {
    await install(
      LeavePortal(
        nextMessage: 'यह आवेदन स्वीकार नहीं किया जा सकता।',
        delta: true,
      ),
    );
    final result = await service.apply('99', payload());
    expect(result['message'], 'यह आवेदन स्वीकार नहीं किया जा सकता।');
    expect(result['message_source'], 'portal');
    expect(portal.applies, 0);
    expect(reads.invalidations, 2);
  });
  test(
    'uncertain service submission does not automatically replay Apply',
    () async {
      await install(LeavePortal(uncertain: true));
      final result = await service.apply('99', payload());
      expect(result['success'], false);
      expect(portal.applies, 1);
      expect(reads.invalidations, 2);
    },
  );
  test(
    'unknown portal message is retained through ambiguous coordinator response',
    () async {
      await install(LeavePortal(finalMessage: 'अवकाश सूची में स्थिति देखें।'));
      final result = await service.apply('99', payload());
      expect(result['success'], false);
      expect(result['message'], 'अवकाश सूची में स्थिति देखें।');
      expect(result['message_source'], 'portal');
      expect(portal.applies, 1);
    },
  );
}
