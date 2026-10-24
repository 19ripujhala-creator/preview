import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/services/portals/shaladarpan/student_service.dart';
import '../../lib/services/portals/staff_login/staff_login_service.dart';
import '../../lib/services/portals/staff_login/direct/http_auth.dart';
import '../../lib/services/portals/staff_login/direct/leave_apply_service.dart';
import '../../lib/services/portals/staff_login/direct/leave_payload.dart';
import '../../lib/services/portals/staff_login/direct/leave_result.dart';
import '../../lib/services/portals/staff_login/direct/native_print_service.dart';
import '../../lib/services/portals/staff_login/direct/staff_read_service.dart';
import '../../lib/services/portals/staff_login/direct/staff_runtime.dart';
import 'staff_auth_test.dart' show StaffMemoryStorage;
import 'staff_leave_apply_test.dart' show LeavePortal, payload;
import 'staff_saved_session_recovery_test.dart' show RecoveryBackend;

void _check(bool value, String description) {
  if (!value) throw StateError(description);
}

class _Scenario {
  _Scenario(this.portal);
  final LeavePortal portal;
  String user = '99', password = 'saved-secret';
  late final registry = StaffHttpAuth(storage: StaffMemoryStorage());
  late final backend = RecoveryBackend(registry, dead: false);
  late final coordinator = StaffCoordinator(backend: backend);
  late final reads = StaffReadService(
    registry: registry,
    coordinator: coordinator,
  );
  late final leaves = StaffLeaveApplyService(
    registry: registry,
    coordinator: coordinator,
    reads: reads,
  );
}

Future<void> _withStaff(
  Future<void> Function(_Scenario) body, {
  LeavePortal? portal,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final s = _Scenario(portal ?? LeavePortal());
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  SharedPreferences.setMockInitialValues({});
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'read' &&
        (call.arguments as Map)['key'] == 'portal_credentials_v2') {
      return jsonEncode({'staff_id': s.user, 'staff_pass': s.password});
    }
    return null;
  });
  StudentService.directAttendanceEnabled = true;
  await s.registry.install(s.portal.session);
  StaffLoginService.directLeaveProvider = () async => s.leaves;
  try {
    await body(s);
  } finally {
    StaffLoginService.directLeaveProvider = null;
    StaffLoginService.directReadProvider = null;
    StaffLoginService.directPrintProvider = null;
    StudentService.directAttendanceEnabled = false;
    messenger.setMockMethodCallHandler(channel, null);
    await s.coordinator.shutdown();
    await s.registry.closeSession();
  }
}

Map<String, Future<void> Function()> staffLeaveGuardCases() => {
  for (final half in [false, true])
    for (final delta in [false, true])
      'native ${half ? 'half' : 'full'} day flow retains ${delta ? 'delta' : 'HTML'} submission': () async {
        final portal = LeavePortal(delta: delta);
        final result = await portal.run(payload(half: half));
        _check(result['success'] == true && result['submitted'] == true, '$result');
        _check(result['message'] == portal.finalMessage && portal.applies == 1, '$result');
        portal.session.close();
      },
  'edit retains portal identity and submits exactly once': () async {
    final portal = LeavePortal(edit: true);
    final result = await portal.run({...payload(), 'record_id': '7', 'sNo': '7', 'original_from_date': '13/10/2026', 'original_to_date': '13/10/2026'});
    _check(result['success'] == true && portal.applies == 1 && portal.editTarget != null, '$result');
    portal.session.close();
  },
  'unknown FINAL wording stays unconfirmed without replay': () async {
    final portal = LeavePortal(finalMessage: 'Please check leave status');
    final result = await portal.run(payload());
    _check(result['success'] == false && result['code'] == 'SAVE_UNCONFIRMED' && result['submitted'] == null, '$result');
    _check(result['message'] == portal.finalMessage && portal.applies == 1, '$result');
    portal.session.close();
  },

  for (final changePassword in [false, true])
    'leave blocks credential change during runtime wait (password=$changePassword)':
        () => _withStaff((s) async {
          StaffLoginService.directLeaveProvider = () async {
            if (changePassword) {
              s.password = 'new-secret';
            } else {
              s.user = '100';
            }
            return s.leaves;
          };
          final result = await StaffLoginService.applyLeave(payload());
          _check(result['code'] == 'ACCOUNT_CHANGED', '$result');
          _check(
            result['submission_attempted'] == false &&
                result['submitted'] == false,
            '$result',
          );
          _check(
            s.portal.client.requests.isEmpty,
            'Stale account made a portal request',
          );
          _check(
            s.coordinator.status()['has_credentials'] == false,
            'Stale credentials were remembered',
          );
        }),
  'profile blocks changed account before binding recovery credentials': () =>
      _withStaff((s) async {
        StaffLoginService.directReadProvider = () async {
          s.user = '100';
          return s.reads;
        };
        final result = await StaffLoginService.fetchProfile();
        _check(result['code'] == 'ACCOUNT_CHANGED', '$result');
        _check(
          s.portal.client.requests.isEmpty &&
              s.coordinator.status()['has_credentials'] == false,
          'Profile used stale credentials',
        );
      }),
  'PDF blocks changed password before binding recovery credentials': () =>
      _withStaff((s) async {
        StaffLoginService.directPrintProvider = () async {
          s.password = 'new-secret';
          return StaffNativePrintService(
            registry: s.registry,
            coordinator: s.coordinator,
          );
        };
        var rejected = false;
        try {
          await StaffLoginService.downloadFormat10Pdf();
        } catch (e) {
          rejected = e.toString().contains('Staff login changed');
        }
        _check(rejected, 'Changed PDF account was allowed');
        _check(
          s.portal.client.requests.isEmpty &&
              s.coordinator.status()['has_credentials'] == false,
          'PDF used stale credentials',
        );
      }),
  'unchanged account still applies once with original portal result': () =>
      _withStaff((s) async {
        final result = await StaffLoginService.applyLeave(payload());
        _check(
          result['success'] == true && result['submitted'] == true,
          '$result',
        );
        _check(
          result['message'] == s.portal.finalMessage &&
              result['message_source'] == 'portal',
          '$result',
        );
        _check(
          (result['data'] as Map)['message'] == s.portal.finalMessage,
          'Response contract changed',
        );
        _check(
          s.portal.applies == 1 && s.backend.logins == 0,
          'Submission replayed or relogged in',
        );
      }),
  'unconfirmed preview still makes no portal request': () =>
      _withStaff((s) async {
        final result = await StaffLoginService.applyLeave({
          ...payload(),
          'confirmed': false,
        });
        _check(
          result['confirmation_required'] == true && result['success'] == false,
          '$result',
        );
        _check(s.portal.client.requests.isEmpty, 'Preview submitted a form');
      }),
  for (final uncertain in [false, true])
    'account change after Apply preserves attempted result (uncertain=$uncertain)':
        () => _withStaff((s) async {
          s.portal.client.handler = (request) async {
            try {
              return await s.portal.respond(request);
            } finally {
              if (s.portal.applies > 0) s.user = '100';
            }
          };
          final result = await StaffLoginService.applyLeave(payload());
          _check(
            result['success'] == false && result['code'] == 'SAVE_UNCONFIRMED',
            '$result',
          );
          _check(
            result['submission_attempted'] == true,
            'Submission attempt was lost: $result',
          );
          _check(s.portal.applies == 1, 'Apply was replayed');
          if (!uncertain) {
            _check(
              result['message'] == s.portal.finalMessage &&
                  result['message_source'] == 'portal',
              'Original portal message was lost: $result',
            );
            _check(
              result['submitted'] == true,
              'Acknowledged submission was lost',
            );
            _check(
              staffLeaveDisplayMessage(result)
                  .contains('\nApp: Staff login changed.'),
              'Account guard is not labelled separately',
            );
          } else {
            _check(
              result['submitted'] == null &&
                  (result['upstream_response'] as Map)['code'] ==
                      'MUTATION_AMBIGUOUS',
              '$result',
            );
          }
        }, portal: LeavePortal(uncertain: uncertain)),
  for (final message in [
    'Leave Request has not been applied successfully',
    'Leave Request has not yet been updated',
    'Leave Request was never applied',
  ])
    'negative FINAL message remains failure: $message': () async {
      _check(
        classifyStaffLeaveMessage(message) == false,
        'Negation classified as success',
      );
      final portal = LeavePortal(finalMessage: message);
      final result = await portal.run(payload());
      _check(
        result['success'] == false && result['submitted'] != true,
        '$result',
      );
      _check(
        result['message'] == message && result['message_source'] == 'portal',
        'Portal message replaced',
      );
      _check(portal.applies == 1, 'Negative response caused a replay');
      portal.session.close();
    },
  'portal and local display messages remain separate': () async {
    _check(
      staffLeaveDisplayMessage({
            'message_source': 'portal',
            'message': 'Exact portal wording',
          }) ==
          'Exact portal wording',
      'Portal wording changed',
    );
    _check(
      staffLeaveDisplayMessage({'message': 'Network unavailable'}) ==
          'App: Network unavailable',
      'Local error is not labelled',
    );
    final result = staffLeaveAccountChanged({
      'success': false,
      'submission_attempted': false,
      'message': 'Form unavailable',
    });
    _check(
      result['code'] == 'ACCOUNT_CHANGED' && result['submitted'] == false,
      '$result',
    );
  },
};
