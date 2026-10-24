import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../lib/services/portals/shaladarpan/direct/staff_attendance.dart';
import '../../lib/services/portals/shaladarpan/direct/student_attendance_worker.dart';
import '../../lib/services/portals/shaladarpan/staff_attendance_status.dart';

void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

String _fixture(String name) =>
    File('test/direct/fixtures/$name').readAsStringSync();
List<Map<String, dynamic>> _payload() => [
  {
    'staffId': '101',
    'sno': '1',
    'status_code': '2',
    'original_status': 'Present',
  },
  {'staffId': '102', 'sno': '2', 'status_code': '3', 'original_status': 'CL'},
];

class _Portal {
  bool marked = false, markAfterFinal = true, failReadback = false;
  String? initialDocument;
  bool mismatchReadback = false, timeoutFinal = false;
  String finalNotice = '', saveNotice = '';
  final posts = <String>[];
  int gets = 0;
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? action,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (fields == null) {
      gets++;
      if (posts.contains('FINAL') && failReadback)
        throw const SocketException('offline');
      var source =
          initialDocument ??
          _fixture(marked ? 'staff_marked.html' : 'staff_pending.html');
      if (posts.contains('FINAL') && mismatchReadback)
        source = source.replaceAll('>Absent<', '>Present<');
      return (url: url, status: 200, html: source);
    }
    _check(mutation, 'SAVE/FINAL must remain mutations');
    posts.add(action!);
    if (action == 'SAVE') {
      return (
        url: url,
        status: 200,
        html: _fixture('staff_confirmation.html') + saveNotice,
      );
    }
    if (action == 'FINAL') {
      if (timeoutFinal) throw TimeoutException('lost response');
      marked = markAfterFinal;
      return (
        url: url,
        status: 200,
        html:
            _fixture(marked ? 'staff_marked.html' : 'staff_pending.html') +
            finalNotice,
      );
    }
    throw StateError('Unexpected mutation $action');
  }

  StaffAttendanceWorker worker() => StaffAttendanceWorker(
    request: request,
    baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
    schoolId: () => '123456',
    now: () => DateTime.utc(2026, 10, 10, 3, 30),
  );
  Future<Map<String, dynamic>> submit() =>
      worker().submit(_payload(), userConfirmed: true);
}

Map<String, Future<void> Function()> staffFinalRegressionCases() => {
  'pending and marked fetch contracts still match Python fixtures': () async {
    final p = _Portal();
    _check(
      jsonEncode(await p.worker().fetch()) ==
          jsonEncode(jsonDecode(_fixture('python_staff_pending.json'))),
      'Pending contract changed',
    );
    p.marked = true;
    _check(
      jsonEncode(await p.worker().fetch()) ==
          jsonEncode(jsonDecode(_fixture('python_staff_marked.json'))),
      'Marked contract changed',
    );
  },
  'no-message submit result still matches Python fixture': () async {
    final p = _Portal();
    final result = await p.submit();
    _check(
      jsonEncode(result) ==
          jsonEncode(jsonDecode(_fixture('python_staff_save.json'))),
      'No-message contract changed: $result',
    );
    _check(
      p.posts.join(',') == 'SAVE,FINAL' && p.gets == 2,
      'Submission/readback sequence changed',
    );
  },
  'FINAL error survives pending readback without claiming success': () async {
    final p = _Portal()
      ..markAfterFinal = false
      ..finalNotice = '<div id="msgDiv">Attendance cannot be finalized.</div>';
    final r = await p.submit();
    _check(
      r['message'] == 'Attendance cannot be finalized.' &&
          r['message_source'] == 'portal',
      '$r',
    );
    _check(
      r['success'] == false &&
          r['code'] == 'SAVE_UNCONFIRMED' &&
          r['submission_attempted'] == true,
      '$r',
    );
    _check(
      r['backend_message'] is String && p.posts.join(',') == 'SAVE,FINAL',
      'No replay / backend detail missing',
    );
  },
  'FINAL success text survives verified matching readback': () async {
    final p = _Portal()
      ..finalNotice =
          '<span id="ContentPlaceHolder1_lblMessage">Attendance finalized successfully.</span>';
    final r = await p.submit();
    _check(r['success'] == true && r['attendance_verified'] == true, '$r');
    _check(
      r['message'] == 'Attendance finalized successfully.' &&
          r['portal_message'] == r['message'] &&
          r['message_source'] == 'portal',
      '$r',
    );
    _check((r['portalMessages'] as List).single == r['message'], '$r');
  },
  'success wording cannot replace verified locked readback': () async {
    final p = _Portal()
      ..markAfterFinal = false
      ..finalNotice = '<div id="msgDiv">Saved successfully</div>';
    final r = await p.submit();
    _check(
      r['success'] == false &&
          r['attendance_verified'] == false &&
          r['code'] == 'SAVE_UNCONFIRMED',
      '$r',
    );
    _check(
      r['message'] == 'Saved successfully' && r['backend_message'] is String,
      '$r',
    );
  },
  'FINAL message survives network failure during verification': () async {
    final p = _Portal()
      ..failReadback = true
      ..finalNotice = '<div id="msgDiv">Final request received.</div>';
    final r = await p.submit();
    _check(
      r['success'] == false &&
          r['requires_verification'] == true &&
          r['submission_attempted'] == true,
      '$r',
    );
    _check(
      r['message'] == 'Final request received.' &&
          r['message_source'] == 'portal' &&
          r['backend_message'] is String,
      '$r',
    );
    _check(p.posts.join(',') == 'SAVE,FINAL', 'Mutation replayed');
  },
  'hidden FINAL messages and hidden ancestors are ignored': () async {
    final p = _Portal()
      ..finalNotice =
          '<section hidden><div id="msgDiv">stale rejection</div></section><span id="ContentPlaceHolder1_lblMessage" style="display:none">hidden</span>';
    final r = await p.submit();
    _check(
      r['success'] == true &&
          r['message_source'] == 'backend_verified' &&
          (r['portalMessages'] as List).isEmpty,
      '$r',
    );
  },
  'multiple FINAL fields retain text and decode entities': () async {
    final p = _Portal()
      ..finalNotice =
          '<div id="msgDiv">Saved &amp; locked</div><span id="ContentPlaceHolder1_lblMsg">Check report</span><span id="ContentPlaceHolder1_lblMessage">Check report</span>';
    final r = await p.submit();
    _check(r['message'] == 'Saved & locked\nCheck report', '$r');
    _check((r['portalMessages'] as List).length == 2, '$r');
  },
  'mismatched locked readback retains portal text but never succeeds':
      () async {
        final p = _Portal()
          ..mismatchReadback = true
          ..finalNotice = '<div id="msgDiv">Final received</div>';
        final r = await p.submit();
        _check(
          r['success'] == false &&
              r['code'] == 'SAVE_UNCONFIRMED' &&
              r['message'] == 'Final received',
          '$r',
        );
      },
  'FINAL timeout remains ambiguous and is never replayed': () async {
    final p = _Portal()..timeoutFinal = true;
    final r = await p.submit();
    _check(
      r['success'] == false &&
          r['requires_verification'] == true &&
          p.posts.join(',') == 'SAVE,FINAL',
      '$r',
    );
  },
  'SAVE validation still blocks FINAL and retains portal error': () async {
    final p = _Portal()
      ..saveNotice = '<div id="msgDiv">Please check attendance</div>';
    final r = await p.submit();
    _check(
      r['success'] == false &&
          r['message'] == 'Please check attendance' &&
          r['message_source'] == 'portal',
      '$r',
    );
    _check(p.posts.join(',') == 'SAVE', 'FINAL followed rejected SAVE');
  },
  'unconfirmed user request cannot mutate': () async {
    final p = _Portal();
    final r = await p.worker().submit(_payload(), userConfirmed: false);
    _check(r['success'] == false && p.posts.isEmpty && p.gets == 0, '$r');
  },
  'worker categorizes Not Present without changing native label or code':
      () async {
        final source = _fixture('staff_pending.html')
            .replaceAll('selected>Present<', 'selected>Not Present<');
        final row = StaffAttendanceWorker.parseStaffAttendance(source).first;
        _check(
          row['category'] == 'absent' &&
              row['status_code'] == '1' &&
              row['original_status'] == 'Not Present',
          '$row',
        );
      },
  'Select rows are counted as pending instead of Other': () async {
    final source = _fixture('staff_pending.html')
        .replaceAll('value="1" selected', 'value="1"')
        .replaceAll(
          '<option value="">Choose</option>',
          '<option value="" selected>Select</option>',
        );
    final p = _Portal()..initialDocument = source;
    final result = await p.worker().fetch();
    final stats = result['stats'] as Map;
    final row = (result['staff'] as List).first as Map;
    _check(
      stats['pending'] == 1 &&
          stats['pending_staff'] == 1 &&
          stats['other'] == 0 &&
          stats['present'] == 0,
      '$result',
    );
    _check(
      row['category'] == 'pending' &&
          row['status_code'] == '' &&
          row['original_status'] == 'Select',
      '$row',
    );
    final selected = source
        .replaceAll('value="" selected', 'value=""')
        .replaceAll('value="1"', 'value="1" selected');
    final selectedRow = StaffAttendanceWorker.parseStaffAttendance(selected)
        .first;
    _check(selectedRow['category'] == 'present', '$selectedRow');
  },
  'all Select rows leave every attendance tile count at zero': () async {
    var source = _fixture('staff_pending.html')
        .replaceAll('value="1" selected', 'value="1"')
        .replaceAll(
          '<option value="">Choose</option>',
          '<option value="" selected>Select</option>',
        );
    source = source.replaceAll(
      '<span id="g_Lbl_Leave_1">CL</span>',
      '<select id="g_DDLLeave_1" name="g' + r'$DDLLeave$1' + '"><option value="" selected>Select</option><option value="1">Present</option></select>',
    );
    final result = await (_Portal()..initialDocument = source).worker().fetch();
    final stats = result['stats'] as Map;
    _check(stats['pending'] == 2 && stats['total'] == 2, '$result');
    for (final key in ['present', 'absent', 'leave', 'other']) {
      _check(stats[key] == 0, '$key must be zero: $stats');
    }
  },
  'placeholder and invalid selection stay separate from actual Other':
      () async {
        for (final label in [
          'Select',
          'Choose',
          'Please Select',
          '-- Select --',
          'Select Status',
          'चयन करें',
        ]) {
          _check(staffAttendanceCategory(label) == 'pending', label);
        }
        _check(
          staffAttendanceCategory('Other') == 'other',
          'Real Other was lost',
        );
        _check(
          staffAttendanceCategory('Present', selectionPending: true) ==
              'pending',
          'Invalid selection fell back to stale portal label',
        );
      },
  'shared classification handles negative labels and partial words': () async {
    final expected = {
      'Present': 'present',
      ' present ': 'present',
      'PRESENT (School)': 'present',
      'Not Present': 'absent',
      'NOT   PRESENT': 'absent',
      'not-present': 'absent',
      'Absent': 'absent',
      'उपस्थित': 'present',
      'अनुपस्थित': 'absent',
      'CL': 'leave',
      'HCL': 'leave',
      'On Leave': 'leave',
      'अवकाश': 'leave',
      'Presentation': 'other',
      'Presently': 'other',
      'Unknown': 'other',
      '': 'pending',
    };
    for (final item in expected.entries) {
      _check(
        staffAttendanceCategory(item.key) == item.value,
        '${item.key}: expected ${item.value}',
      );
    }
    _check(
      staffAttendanceCategory('Special', approvedLeave: true) == 'leave',
      'Approved leave lost',
    );
  },
};
