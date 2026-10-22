import 'dart:async';

import 'package:shaladarpan/services/core/direct/coordinator.dart';
import 'package:shaladarpan/services/core/direct/errors.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:shaladarpan/experiments/direct_student_attendance_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

import 'student_worker_test.dart' show FakePortal, FakeAuth, students, date;

class InterruptedPortal extends FakePortal {
  InterruptedPortal({this.applied = true, this.failRecheck = false});
  final bool applied, failRecheck;
  bool interrupted = false;
  int rechecks = 0;
  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    if (mutation) {
      saves++;
      marked = applied;
      interrupted = true;
      throw TimeoutException('synthetic response loss');
    }
    if (interrupted && fields == null) {
      rechecks++;
      if (failRecheck) throw TimeoutException('synthetic READ loss');
    }
    return super.request(
      url,
      fields: fields,
      referer: referer,
      mutation: mutation,
    );
  }
}

class _IdleBackend implements PortalBackend {
  @override
  Object? currentContext() => null;
  @override
  Future<Probe> probe(Object context) async => Probe.unknown;
  @override
  Future<Map<String, dynamic>> authenticate(
    String user,
    String password,
    bool forceFresh,
  ) async => {'success': false};
}

class _PendingCoordinator extends PortalCoordinator {
  _PendingCoordinator() : super(name: 'sd', backend: _IdleBackend());
  int calls = 0;
  @override
  Future<Map<String, dynamic>> run({
    required String resource,
    required Kind kind,
    required Future<Map<String, dynamic>> Function(Object?) worker,
    double? timeout,
    double? wait,
    Set<String> preMutationCodes = const {},
    Future<bool?> Function(Object?)? verify,
    String label = '',
    int? maxAttempts,
  }) async {
    calls++;
    throw CoordinatorError(
      ErrorKind.mutationAmbiguous,
      'Original owner is pending.',
      {'pending': true},
    );
  }
}

class _PendingAuth extends FakeAuth {
  _PendingAuth(super.portal, this.co);
  final PortalCoordinator co;
  @override
  PortalCoordinator? get coordinator => co;
}

void main() {
  test(
    'pending mutation owner prevents independent READ reconciliation',
    () async {
      final p = FakePortal(), co = _PendingCoordinator();
      final auth = _PendingAuth(p, co);
      try {
        final r = await DirectStudentAttendanceService(auth).save(
          classId: '1',
          date: date,
          section: '1A',
          students: students,
          userConfirmed: true,
        );
        expect(r.success, false);
        expect(r.response['pending'], true);
        expect(co.calls, 1);
        expect(p.requests, isEmpty);
      } finally {
        auth.close();
        await co.shutdown();
      }
    },
  );
  test(
    'lost response after committed SAVE is confirmed by one independent READ',
    () async {
      final p = InterruptedPortal();
      final actual = FakeAuth(p);
      try {
        final r = await DirectStudentAttendanceService(actual).save(
          classId: '1',
          date: date,
          section: '1A',
          students: students,
          userConfirmed: true,
        );
        expect(r.success, true);
        expect(r.verified, true);
        expect(r.code, 'VERIFIED_AFTER_RECHECK');
        expect(p.saves, 1);
        expect(p.rechecks, 1);
      } finally {
        actual.close();
      }
    },
  );
  test('unapplied SAVE stays uncertain and is never replayed', () async {
    final p = InterruptedPortal(applied: false);
    final actual = FakeAuth(p);
    try {
      final r = await DirectStudentAttendanceService(actual).save(
        classId: '1',
        date: date,
        section: '1A',
        students: students,
        userConfirmed: true,
      );
      expect(r.success, false);
      expect(r.submissionAttempted, true);
      expect(p.saves, 1);
      expect(p.rechecks, 1);
    } finally {
      actual.close();
    }
  });
  test('failed independent READ retains original uncertain result', () async {
    final p = InterruptedPortal(failRecheck: true);
    final auth = FakeAuth(p);
    try {
      final r = await DirectStudentAttendanceService(auth).save(
        classId: '1',
        date: date,
        section: '1A',
        students: students,
        userConfirmed: true,
      );
      expect(r.success, false);
      expect(r.submissionAttempted, true);
      expect(p.saves, 1);
      expect(p.rechecks, 1);
    } finally {
      auth.close();
    }
  });
  test(
    'native error message is retained without a silent replacement',
    () async {
      final p = FakePortal()..rejectSave = true;
      final auth = FakeAuth(p);
      try {
        final r = await DirectStudentAttendanceService(auth).save(
          classId: '1',
          date: date,
          section: '1A',
          students: students,
          userConfirmed: true,
        );
        expect(r.success, false);
        expect(r.response['portal_message'], 'Server Error in application');
        expect(p.saves, 1);
        expect(p.gets, 1);
      } finally {
        auth.close();
      }
    },
  );
}
