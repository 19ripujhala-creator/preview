import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;
import 'package:shaladarpan/services/portals/shaladarpan/direct/ranking_http.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

import 'working_days_fixture.dart';

const monthlyHead = r'ctl00$ContentPlaceHolder1$footer2$';
String monthlyField(int index) =>
    '${monthlyHead}gvattendence\$ctl${(index + 2).toString().padLeft(2, '0')}\$txtatt';
String monthlyId(int index) => '${10001 + index}/${20001 + index}';

class MonthlyAttendanceFixture extends WorkingDaysFixture {
  final attendance = <String, String>{};
  final attendanceSubmissions = <Map<String, Object?>>[];
  int reads = 0;
  bool renewOnPost = false, renewWorkingGet = false;
  bool noPersist = false,
      changedRoster = false,
      zeroDays = false,
      renewOnGet = false,
      switchSchoolOnGet = false,
      badDestination = false,
      badForm = false,
      pendingConfirmation = false;
  String owner = 'school-1', popup = '';
  @override
  String get authenticatedSchoolId => owner;
  String monthlyInitial() =>
      File('test/fixtures/monthly_attendance/initial.html').readAsStringSync();
  String monthlyDelta(Map<String, Object?> fields) =>
      RankingHttp.parseDelta(
        File('test/fixtures/monthly_attendance/show.delta').readAsStringSync(),
      ).map((r) {
        var value = r.$3;
        if (r.$1 == 'updatePanel' &&
            r.$2 == 'ContentPlaceHolder1_footer2_UpdPanel') {
          final doc = html.parseFragment(value);
          for (final select in doc.querySelectorAll('select')) {
            for (final option in select.querySelectorAll('option')) {
              option.attributes.remove('selected');
              if (option.attributes['value'] ==
                  ((fields[select.attributes['name']] as List?)?.firstOrNull)) {
                option.attributes['selected'] = 'selected';
              }
            }
          }
          var index = 0;
          for (final row in doc.querySelectorAll('tr').skip(1)) {
            final input = row.querySelector('input[type="text"]')!;
            input.attributes['value'] =
                attendance[input.attributes['name']] ?? '0';
            if (locked) input.attributes['readonly'] = 'readonly';
            if (zeroDays) row.querySelector('[id*="_lblmaxatt_"]')!.text = '0';
            if (changedRoster && index == 0) {
              row
                      .querySelector('input[id*="_hdnstudentprofileid_"]')!
                      .attributes['value'] =
                  '99999';
            }
            index++;
          }
          if (wrongSession) {
            doc
                .querySelector('option[value="2026-27"]')
                ?.attributes
                .remove('selected');
          }
          value = doc.outerHtml;
        }
        if (r.$1 == 'formAction' && badForm) {
          value = 'https://example.invalid/StudentAttendence.aspx';
        }
        return '${value.length}|${r.$1}|${r.$2}|$value|';
      }).join();
  @override
  Future<AttendanceHttpReply> workingDaysRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final reply = await super.workingDaysRequest(
      url,
      fields: fields,
      referer: referer,
      mutation: mutation,
      timeout: timeout,
    );
    if (renewWorkingGet && fields == null) identity = 'working-renewed';
    return reply;
  }

  @override
  Future<AttendanceHttpReply> monthlyAttendanceRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    reads++;
    if (failAfterSave && attendanceSubmissions.isNotEmpty && !mutation) {
      throw const SocketException('Read-back unavailable');
    }
    if (fields == null) {
      if (renewOnGet) {
        identity = 'renewed-$reads';
      }
      if (switchSchoolOnGet) owner = 'school-2';
      return (
        url: badDestination ? Uri.https('example.invalid', '/') : url,
        status: 200,
        html: monthlyInitial(),
      );
    }
    if (mutation) {
      attendanceSubmissions.add(Map.of(fields));
      await submitGate?.future;
      if (ambiguous) throw const SocketException('Lost Save response');
      if (!noPersist && !pendingConfirmation) {
        for (final e in fields.entries) {
          if (e.key.endsWith(r'$txtatt'))
            attendance[e.key] = (int.tryParse('${e.value}') ?? e.value)
                .toString();
        }
      }
    }
    if (renewOnPost) identity = 'post-renewed';
    var body = monthlyDelta(fields);
    if (mutation && popup.isNotEmpty) {
      final script = 'alert(${jsonEncode(popup)});';
      body +=
          '${script.length}|scriptStartupBlock|ScriptContentNoTags|$script|';
    }
    return (url: url, status: 200, html: body);
  }
}
