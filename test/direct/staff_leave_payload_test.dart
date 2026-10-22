import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/staff_login/direct/leave_payload.dart';

void main() {
  test(
    'message extraction matches uploaded Python, preserving original text',
    () {
      final messages = jsonDecode(
        File('test/direct/fixtures/python_staff_leave_messages.json')
            .readAsStringSync(),
      ) as List;
      for (final sample in messages) {
        expect(
          extractStaffLeaveMessage(sample['html'] as String),
          sample['expected'],
        );
      }
    },
  );
  final goldens = jsonDecode(
    File('test/direct/fixtures/python_staff_leave_preview.json')
        .readAsStringSync(),
  ) as List;
  test('preview equals uploaded Python worker across endpoint/date matrix', () {
    for (var i = 0; i < goldens.length; i++) {
      final sample = goldens[i] as Map;
      expect(
        previewStaffLeave(Map<String, dynamic>.from(sample['input'] as Map)),
        sample['expected'],
        reason: 'Python case $i: ${sample['input']}',
      );
    }
  });
  test('confirmation preserves nested preview and distinguishes edit/new', () {
    final data = <String, dynamic>{
      'from_date': '13/10/2026',
      'to_date': '13/10/2026',
      'sNo': '7',
    };
    expect(staffLeaveConfirmation(data), {
      'success': false,
      'confirmation_required': true,
      'message': 'User confirmation required before final submission.',
      'preview': previewStaffLeave(data),
      'mode': 'edit',
    });
    expect(
      staffLeaveConfirmation({...data, 'record_id': 'LR-7'})['mode'],
      'new',
    );
  });
  String row(String serial, String id, {String from = '13/10/2026'}) =>
      '<tr><td>$serial</td><td>$from</td><td>14/10/2026</td><td><input type="image" id="$id"></td></tr>';
  String grid(String rows) =>
      '<table id="ContentPlaceHolder1_grdLeaveDetails">$rows</table>';
  test('edit requires exact serial AND original date range', () {
    final text = grid(row('7', 'a_btnEdit_7') + row('8', 'a_btnEdit_8'));
    expect(findStaffLeaveEditTarget(text, '2026-10-13', '2026-10-14'), isNull);
    expect(
      findStaffLeaveEditTarget(
        text,
        '2026-10-13',
        '2026-10-14',
        serialNumber: '8',
      ),
      {'button_id': 'a_btnEdit_8', 's_no': '8'},
    );
    expect(
      findStaffLeaveEditTarget(
        text,
        '2026-10-12',
        '2026-10-14',
        serialNumber: '8',
      ),
      isNull,
    );
    expect(
      findStaffLeaveEditTarget(
        text,
        '2026-10-13',
        '2026-10-14',
        serialNumber: '9',
      ),
      isNull,
    );
  });
  test('duplicate identical edit matches fail closed', () {
    final text = grid(row('7', 'a_btnEdit_7') + row('7', 'b_btnEdit_7'));
    expect(
      findStaffLeaveEditTarget(
        text,
        '13-10-2026',
        '14-10-2026',
        serialNumber: '7',
      ),
      isNull,
    );
  });
  test('wrong edit button, missing grid and pager cannot select leave', () {
    expect(
      findStaffLeaveEditTarget(
        grid(row('7', 'a_btnView_7')),
        '13-10-2026',
        '14-10-2026',
      ),
      isNull,
    );
    expect(
      findStaffLeaveEditTarget('<html></html>', '13-10-2026', '14-10-2026'),
      isNull,
    );
    expect(
      findStaffLeaveEditTarget(
        grid(row('Page 7', 'a_btnEdit_7')),
        '13-10-2026',
        '14-10-2026',
      ),
      isNull,
    );
  });
  test('portal failure takes precedence over success words', () {
    expect(
      classifyStaffLeaveMessage('Leave Request Applied successfully'),
      true,
    );
    expect(
      classifyStaffLeaveMessage('Leave Request not applied successfully'),
      false,
    );
    expect(classifyStaffLeaveMessage('Already applied'), false);
    expect(classifyStaffLeaveMessage('Please check history'), isNull);
  });
}
