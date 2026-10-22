import 'dart:convert';
import 'dart:async';

import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/services/core/direct/coordinator.dart';
import 'package:shaladarpan/experiments/direct_student_attendance_service.dart';

import 'student_worker_test.dart' show FakeAuth, FakePortal, students, date;

class _Backend implements PortalBackend {
  final context = Object();
  @override
  Object? currentContext() => context;
  @override
  Future<Probe> probe(Object context) async => Probe.alive;
  @override
  Future<Map<String, dynamic>> authenticate(
    String user,
    String password,
    bool forceFresh,
  ) async => {'success': true};
}

class _Auth extends FakeAuth {
  _Auth(super.portal, this.co);
  final PortalCoordinator co;
  @override
  PortalCoordinator? get coordinator => co;
}

class _PreflightTimeoutPortal extends FakePortal {
  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    if (!mutation) throw TimeoutException('synthetic preflight timeout');
    return super.request(
      url,
      fields: fields,
      referer: referer,
      mutation: mutation,
    );
  }
}

void main() {
  test('real coordinator retains proven preflight timeout as unsent, not ambiguous', () async {
    final portal = _PreflightTimeoutPortal();
    final co = PortalCoordinator(name: 'sd', backend: _Backend());
    final auth = _Auth(portal, co);
    try {
      await co.authenticate('offline-school', 'password');
      final result = await DirectStudentAttendanceService(auth).save(
        classId: '1',
        date: date,
        section: '1A',
        students: students,
        userConfirmed: true,
      );
      expect(result.success, false);
      expect(result.submissionAttempted, false);
      expect(result.code, 'PORTAL_SLOW');
      expect(result.response['submission_attempted'], false);
      expect(portal.saves, 0);
    } finally {
      await co.shutdown();
      auth.close();
    }
  });
  test(
    'real coordinator retains portal SAVE failure details and never replays',
    () async {
      final portal = FakePortal()..rejectSave = true;
      final co = PortalCoordinator(name: 'sd', backend: _Backend());
      final auth = _Auth(portal, co);
      try {
        await co.authenticate('offline-school', 'password');
        final result = await DirectStudentAttendanceService(auth).save(
          classId: '1',
          date: date,
          section: '1A',
          students: students,
          userConfirmed: true,
        );
        expect(result.success, false);
        expect(result.submissionAttempted, true);
        expect(result.response['failure_code'], 'PORTAL_RESPONSE_ERROR');
        expect(
          result.response['portal_message'],
          'Server Error in application',
        );
        expect(result.response['attendance_verified'], false);
        expect(() => jsonEncode(result.response), returnsNormally);
        expect(portal.saves, 1);
      } finally {
        await co.shutdown();
        auth.close();
      }
    },
  );
}
