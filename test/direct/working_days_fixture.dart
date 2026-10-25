import 'dart:async';
import 'dart:io';

import 'package:html/parser.dart' as html;
import 'package:shaladarpan/experiments/direct_portal_auth.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/ranking_http.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

const workingHead = r'ctl00$ContentPlaceHolder1$ctl00$';
String fieldName(String month) =>
    '${workingHead}grdMonthlySession\$ctl02\$txt$month';

class WorkingDaysFixture extends DirectPortalAuth {
  final values = <String, String>{};
  final submissions = <Map<String, Object?>>[];
  bool ambiguous = false,
      failAfterSave = false,
      locked = false,
      wrongSession = false;
  String identity = 'fixture-1';
  Completer<void>? submitGate;
  @override
  bool get isVerified => true;
  @override
  String get authenticatedSchoolId => 'school-1';
  @override
  String get verifiedNode => 'SD1';
  @override
  String get schoolSessionIdentity => identity;
  @override
  void close() {}
  String initial() =>
      File('test/fixtures/working_days/initial.html').readAsStringSync();
  String delta({bool saved = false}) {
    final raw = File(
      'test/fixtures/working_days/${saved ? 'saved' : 'show'}.delta',
    ).readAsStringSync();
    return RankingHttp.parseDelta(raw).map((r) {
      var value = r.$3;
      if (r.$1 == 'updatePanel' &&
          r.$2 == 'ContentPlaceHolder1_ctl00_UpdPanel') {
        final doc = html.parseFragment(value);
        for (final input in doc.querySelectorAll('input[name][type="text"]')) {
          input.attributes['value'] = values[input.attributes['name']] ?? '0';
          if (locked && input.attributes['name'] == fieldName('Oct'))
            input.attributes['disabled'] = 'disabled';
        }
        if (wrongSession) {
          for (final o in doc.querySelectorAll('option')) {
            o.attributes.remove('selected');
          }
          doc.querySelector('option[value="2025-26"]')!.attributes['selected'] =
              'selected';
        }
        value = doc.outerHtml;
      }
      return '${value.length}|${r.$1}|${r.$2}|$value|';
    }).join();
  }

  @override
  Future<AttendanceHttpReply> workingDaysRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (failAfterSave && submissions.isNotEmpty && !mutation)
      throw const SocketException('Read-back unavailable');
    if (mutation) {
      submissions.add(Map.of(fields!));
      await submitGate?.future;
      if (ambiguous) throw const SocketException('Lost Submit response');
      for (final e in fields.entries) {
        if (e.key.contains('grdMonthlySession') && e.key.contains('txt'))
          values[e.key] = '${e.value}';
      }
      return (url: url, status: 200, html: delta(saved: true));
    }
    return (url: url, status: 200, html: fields == null ? initial() : delta());
  }
}
