import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shaladarpan/experiments/attendance_webforms.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('Offline WebForms contract', () {
    test('Show payload preserves tokens and omits mutation controls', () {
      final doc = html.parse(fixture('attendance_page.html'));
      final button = doc.getElementById(AttendanceWebForms.showId)!;
      final payload = AttendanceWebForms.navigation(button, 'SHOW');
      expect(payload['__VIEWSTATE'], 'SYNTHETIC_VIEWSTATE');
      expect(payload['__EVENTVALIDATION'], 'SYNTHETIC_EVENTVALIDATION');
      expect(payload['__EVENTTARGET'], '');
      expect(payload['__ASYNCPOST'], isNull);
      expect(payload['checkedBox'], 'Y');
      expect(payload.containsKey('uncheckedBox'), false);
      expect(payload.containsKey('disabledField'), false);
      expect(payload['exampleClass'], '2');
      expect(payload['ctl00\$ContentPlaceHolder1\$btn_Show'], 'Show');
      expect(payload.containsKey('ctl00\$ContentPlaceHolder1\$btnsubmit'), false);
      expect(payload['__READ_ONLY_ACTION'], 'SHOW');
    });

    test('Only approved Show control may invoke SHOW', () {
      final doc = html.parse(fixture('attendance_page.html'));
      final save = doc.getElementById('ContentPlaceHolder1_btnsubmit')!;
      expect(() => AttendanceWebForms.navigation(save, 'SHOW'), throwsStateError);
      expect(() => AttendanceWebForms.navigation(save, 'SAVE'), throwsStateError);
    });

    test('Class entries use a WebForms postback target with fresh tokens', () {
      final doc = html.parse(fixture('attendance_summary.html'));
      expect(AttendanceWebForms.classRowCount(doc), 2);
      final entries = AttendanceWebForms.classEntries(doc);
      expect(entries.length, 2);
      expect(entries.first.text.trim(), '1A');
      final payload = AttendanceWebForms.navigation(entries.first, 'CLASS_ENTRY');
      expect(payload['__VIEWSTATE'], 'SYNTHETIC_NEXT_VIEWSTATE');
      expect(payload['__EVENTTARGET'], 'ctl00\$ContentPlaceHolder1\$grd_Student\$ctl02\$btn_Entry');
      expect(payload['__READ_ONLY_ACTION'], 'CLASS_ENTRY');
    });

    test('Student row count ignores nested popup table', () {
      final doc = html.parse(fixture('student_rows.html'));
      expect(AttendanceWebForms.studentRowCount(doc), 3);
    });

    test('Login redirect and login form are recognized as expired session', () {
      final doc = html.parse('<input id="bodyContent_txtUName">');
      expect(AttendanceWebForms.sessionExpired(
        Uri.https('rajshaladarpan.rajasthan.gov.in', '/SD1/Home/School/Home_New.aspx'), doc), true);
      expect(AttendanceWebForms.sessionExpired(
        Uri.https('rajshaladarpan.rajasthan.gov.in', '/SD1/Home/Public2/OfficeLoginNew.aspx'),
        html.parse('<div></div>')), true);
      expect(AttendanceWebForms.sessionExpired(
        Uri.https('rajshaladarpan.rajasthan.gov.in', '/SD1/Home/School/Home_New.aspx'),
        html.parse('<div></div>')), false);
    });
  });
}
