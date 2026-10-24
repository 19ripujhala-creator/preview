/// Conversion of student/gender_master.py; device JSON storage is injected.
import 'dart:async';
import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../../../core/direct/async_primitives.dart';
import '../../../../experiments/student_attendance_parity.dart';
import 'student_attendance_worker.dart';

/// Each source JSON file keeps its data and modification time on the device.
/// Keys include the school ID, matching Python's separate files per school.
class SchoolReportCache {
  const SchoolReportCache({required this.read, required this.write});
  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;

  Future<({Map<String, dynamic> data, DateTime? modified})> load(
    String key,
  ) async {
    try {
      final raw = await read(key);
      if (raw != null) {
        final envelope = jsonDecode(raw) as Map;
        return (
          data: Map<String, dynamic>.from(envelope['data'] as Map),
          modified: DateTime.fromMillisecondsSinceEpoch(
            envelope['modified'] as int,
          ),
        );
      }
    } catch (_) {
      /* Corrupt or unavailable cache is a cache miss. */
    }
    return (data: <String, dynamic>{}, modified: null);
  }

  Future<void> save(String key, Map<String, dynamic> data, DateTime now) =>
      write(
        key,
        jsonEncode({'data': data, 'modified': now.millisecondsSinceEpoch}),
      );
}

class GenderMaster {
  GenderMaster({
    required this.request,
    required this.baseUrl,
    required this.schoolId,
    required this.cache,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final AttendanceHttpRequest request;
  final Uri Function() baseUrl;
  final String Function() schoolId;
  final SchoolReportCache cache;
  final DateTime Function() now;
  final Map<String, Map<String, String>> _memory = {};
  final Map<String, DateTime> _lastSync = {};
  final Map<String, AsyncMutex> _locks = {};
  static const gridId = 'ContentPlaceHolder1_grdStudentSection';
  static const ttl = Duration(hours: 24);
  static const missCooldown = Duration(minutes: 10);

  static String normSr(Object? value) =>
      StudentAttendanceParity.normalizeSr(value);

  static String genderCode(String raw) {
    final g = raw.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (g.isEmpty) return '';
    if (['f', 'g'].contains(g) ||
        g.startsWith('female') ||
        g.startsWith('girl') ||
        ['बालिका', 'लड़की', 'महिला'].any(g.contains))
      return 'G';
    if (['m', 'b'].contains(g) ||
        g.startsWith('male') ||
        g.startsWith('boy') ||
        ['बालक', 'लड़का', 'पुरुष'].any(g.contains))
      return 'B';
    return '';
  }

  Future<Map<String, String>> fetchMaster({Uri? base}) async {
    Future<AttendanceHttpReply> send(
      Uri url, {
      Map<String, Object?>? fields,
      Uri? referer,
    }) async {
      OperationCancellation.current?.check();
      final reply = await request(
        url,
        fields: fields,
        referer: referer,
        mutation: false,
      );
      OperationCancellation.current?.check();
      if (reply.status < 200 || reply.status >= 300) {
        throw AttendanceWorkerError('PORTAL_HTTP', 'HTTP ${reply.status}');
      }
      if (StudentAttendanceWorker.isLoginRedirect(reply.url) ||
          html
                  .parse(reply.html)
                  .querySelector('#bodyContent_txtUName, #txtUserId') !=
              null) {
        throw const AttendanceWorkerError('SESSION_EXPIRED', 'SESSION_EXPIRED');
      }
      return reply;
    }

    final targetBase = Uri.parse(
      '${(base ?? baseUrl()).toString().replaceFirst(RegExp(r'/+$'), '')}/',
    );
    final initial = await send(
      targetBase.resolve('Home/School/StudentDetails.aspx'),
    );
    final doc = html.parse(initial.html);
    final button = doc.getElementById('ContentPlaceHolder1_btnShow');
    if (button == null) throw StateError('GENDER_SHOW_BUTTON_NOT_FOUND');
    final form = AttendanceForm.enclosing(button);
    if (form == null) throw StateError('GENDER_FORM_NOT_FOUND');
    final action = initial.url.resolve(
      form.attributes['action'] ?? initial.url.toString(),
    );
    if (action.scheme != initial.url.scheme ||
        action.authority != initial.url.authority) {
      throw StateError('GENDER_FORM_ORIGIN_MISMATCH');
    }
    final payload = AttendanceForm.payload(form, button)
      ..['__READ_ONLY_ACTION'] = 'GENDER_SHOW';
    final shown = await send(action, fields: payload, referer: initial.url);
    final grid = html.parse(shown.html).getElementById(gridId);
    if (grid == null) throw StateError('GENDER_GRID_NOT_FOUND');
    final result = <String, String>{};
    for (final row in grid.querySelectorAll('tr')) {
      final sr = row.querySelector('span[id*="lblSRNO"]');
      final gender = row.querySelector('span[id*="lblgender"]');
      if (sr == null || gender == null) continue;
      final key = normSr(sr.text.trim());
      final code = genderCode(gender.text.trim());
      if (key.isNotEmpty && code.isNotEmpty) result[key] = code;
    }
    return result;
  }

  Future<Map<String, String>> _fetchWithDeadline(Uri? base) async {
    final parent = OperationCancellation.current;
    final cancellation = OperationCancellation();
    final detach = parent?.listen(cancellation.cancel);
    final operation = runZoned(
      () => fetchMaster(base: base),
      zoneValues: {OperationCancellation.zoneKey: cancellation},
    );
    try {
      return await operation.timeout(const Duration(seconds: 40));
    } on TimeoutException {
      cancellation.cancel();
      // Wait for transport cancellation to settle before releasing the lease.
      try {
        await operation;
      } catch (_) {}
      rethrow;
    } finally {
      detach?.call();
    }
  }

  Future<Map<String, String>> getGenderMap({
    Uri? base,
    String? school,
    Iterable<Object?>? neededSr,
    bool force = false,
  }) async {
    final sid = school != null && school.isNotEmpty
        ? school
        : (schoolId().isEmpty ? 'default' : schoolId());
    final lock = _locks.putIfAbsent(sid, AsyncMutex.new);
    return lock.protect(() async {
      OperationCancellation.current?.check();
      final file = 'gender_master_$sid.json';
      final stored = await cache.load(file);
      var existing = _memory[sid] ?? <String, String>{};
      if (existing.isEmpty) {
        existing = stored.data.map((k, v) => MapEntry(k, v.toString()));
      }
      _memory[sid] = existing;
      final current = now();
      var age = current.difference(
        _lastSync[sid] ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
      if (age > ttl && stored.modified != null)
        age = current.difference(stored.modified!);
      final needed = (neededSr ?? const <Object?>[])
          .map(normSr)
          .where((s) => s.isNotEmpty)
          .toSet();
      final missing = needed.difference(existing.keys.toSet()).isNotEmpty;
      final sinceSync = current.difference(
        _lastSync[sid] ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
      final stale = existing.isEmpty || age.isNegative || age > ttl;
      final missRefresh =
          missing && (sinceSync.isNegative || sinceSync > missCooldown);
      if (!(force || stale || missRefresh))
        return Map<String, String>.from(existing);
      _lastSync[sid] = current;
      try {
        final fresh = await _fetchWithDeadline(base);
        if (fresh.isNotEmpty) {
          _memory[sid] = fresh;
          await cache.save(file, fresh, now());
          return Map<String, String>.from(fresh);
        }
      } catch (_) {
        /* Source returns the previous cache if refresh fails. */
      }
      OperationCancellation.current?.check();
      return Map<String, String>.from(existing);
    });
  }
}
