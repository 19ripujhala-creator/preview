import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/portal_messages.dart';

import 'attendance_form_reuse_test.dart' show FormPortal;
import 'student_worker_test.dart' show students, date;

class MessagePortal extends FormPortal {
  bool forgetSave = false;
  bool failVerification = false;
  bool oldMessage = false;
  final message = 'उपस्थिति सुरक्षित कर दी गई है।';
  @override
  String entry() =>
      super.entry() + (oldMessage ? '<script>alert("$message");</script>' : '');
  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    if (failVerification && saved && !mutation)
      throw StateError('read unavailable');
    final result = await super.request(
      url,
      fields: fields,
      referer: referer,
      mutation: mutation,
    );
    if (!mutation) return result;
    if (forgetSave) {
      saved = false;
      marked = false;
    }
    return (
      url: result.url,
      status: result.status,
      html: result.html + '<script>alert("$message");</script>',
    );
  }
}

void main() {
  Future<Map<String, dynamic>> save(MessagePortal p) =>
      StudentAttendanceWorker(
        request: p.request,
        baseUrl: () =>
            Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
        sessionIdentity: () => 'one/session',
        indiaNow: () => DateTime(2026, 10, 10),
      ).saveStudentAttendance(
        classId: '1',
        attendanceDate: date,
        section: '1A',
        students: students,
        userConfirmed: true,
      );
  test('original portal success message wins after independent roster verification', () async {
    final p = MessagePortal();
    final result = await save(p);
    expect(result['success'], true);
    expect(result['attendance_verified'], true);
    expect(result['message'], p.message);
    expect(result['portal_message'], p.message);
    expect(result['message_source'], 'portal');
    expect(result['portalMessages'], [p.message]);
    expect(p.saves, 1);
  });
  test(
    'portal success alert cannot substitute for actual saved attendance',
    () async {
      final p = MessagePortal()..forgetSave = true;
      final result = await save(p);
      expect(result['success'], false);
      expect(result['attendance_verified'], false);
      expect(result['message'], p.message);
      expect(result['verification_message'], isNotEmpty);
      expect(result['submission_attempted'], true);
      expect(p.saves, 1);
    },
  );
  test('verification exception retains original SAVE message and uncertain outcome', () async {
    final p = MessagePortal()..failVerification = true;
    final result = await save(p);
    expect(result['success'], false);
    expect(result['message'], p.message);
    expect(result['portal_message'], p.message);
    expect(result['submission_attempted'], true);
    expect(result['verification_message'], isNotEmpty);
    expect(p.saves, 1);
  });
  test(
    'unchanged pre-existing page alerts are not presented as new SAVE messages',
    () async {
      final p = MessagePortal()..oldMessage = true;
      final result = await save(p);
      expect(result['success'], true);
      expect(result['portalMessages'], isEmpty);
      expect(result['message'], isNot(p.message));
    },
  );
  test('shared source parser preserves literal text and ignores hidden/confirmation messages', () {
    final messages = SchoolPortalMessages.parse(
      '<div id="lblMsg">मूल संदेश &amp; data</div><span id="ContentPlaceHolder1_lblError" hidden>old</span><script>alert("Are you sure?"); alert("Saved\\nOK");</script>',
    );
    expect(messages, ['मूल संदेश & data', 'Saved\nOK']);
  });
}
