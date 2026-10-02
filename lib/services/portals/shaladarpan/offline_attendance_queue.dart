import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';
import 'package:shaladarpan/services/core/ecosystem_service.dart';

import 'shaladarpan_service.dart';

class OfflineAttendanceQueue {
  static const String _queueKey = 'offline_attendance_queue_payload';
  static Future<Map<String, dynamic>>? _sync;
  static Future<void> _storageTail = Future<void>.value();
  static String get _todayStr {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _storageTail = _storageTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (e, stack) {
        result.completeError(e, stack);
      }
    });
    return result.future;
  }

  static Future<void> saveToQueue({required String schoolId, required List<Map<String, dynamic>> staffList}) =>
      _serialized(() async {
        final id = schoolId.trim();
        if (id.isEmpty || staffList.isEmpty) throw ArgumentError('School ID and staff list are required.');
        final normalized = <Map<String, dynamic>>[];
        for (final item in staffList) {
          final staffId = item['staffId']?.toString().trim() ?? '';
          final status = (item['status_code'] ?? item['attendanceCode'])?.toString();
          if (staffId.isEmpty || ((status == null || status.isEmpty) && (item['original_status']?.toString().isEmpty ?? true))) {
            throw ArgumentError('Each queued row needs Staff ID and attendance status.');
          }
          normalized.add({...item, 'staffId': staffId, 'status_code': status == null || status.isEmpty ? null : status});
        }
        final prefs = await SharedPreferences.getInstance();
        final oldRaw = prefs.getString(_queueKey);
        if (oldRaw != null && oldRaw.isNotEmpty) {
          final old = jsonDecode(oldRaw);
          if (old is Map &&
              (old['date'] != _todayStr ||
                  old['school_id'] != id ||
                  old['sync_state'] == 'uncertain' ||
                  _sync != null)) {
            throw StateError('Resolve the existing queued attendance before replacing it.');
          }
        }
        await prefs.setString(
          _queueKey,
          jsonEncode({
            'date': _todayStr,
            'school_id': id,
            'timestamp': DateTime.now().microsecondsSinceEpoch,
            'sync_state': 'pending',
            'staff_list': normalized,
          }),
        );
      });

  static Future<Map<String, dynamic>?> getQueuedAttendance() => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid attendance queue.');
    // Preserve expired/uncertain data for review; never silently erase it.
    return Map<String, dynamic>.from(decoded);
  });

  static Future<bool> hasPendingQueue() async => await getQueuedAttendance() != null;
  static Future<void> clearQueue() => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey);
  });

  static Future<void> _settle(Map queued, bool success, {bool uncertain = false}) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null) return;
    final current = jsonDecode(raw);
    if (current is! Map || current['timestamp'] != queued['timestamp'] || current['school_id'] != queued['school_id'])
      return;
    if (success) {
      await prefs.remove(_queueKey);
    } else if (uncertain) {
      await prefs.setString(_queueKey, jsonEncode({...current, 'sync_state': 'uncertain'}));
    }
  });

  static Future<Map<String, dynamic>> syncNow({bool reviewed = false}) async {
    if (!reviewed) return {'success': false, 'code': 'REVIEW_REQUIRED',
      'message': 'Review current portal attendance before submitting a stored draft.'};
    final existing = _sync;
    if (existing != null) return existing;
    final task = _syncQueued();
    _sync = task;
    try {
      return await task;
    } finally {
      if (identical(_sync, task)) _sync = null;
    }
  }

  static Future<Map<String, dynamic>> _syncQueued() async {
    try {
      final queued = await getQueuedAttendance();
      if (queued == null) return {'success': false, 'message': 'No pending attendance.'};
      if (queued['date'] != _todayStr) {
        return {
          'success': false,
          'code': 'STALE_QUEUE',
          'message': 'Queued attendance belongs to an earlier date. Review it before clearing.',
        };
      }
      if (queued['sync_state'] == 'uncertain') {
        return {
          'success': false,
          'code': 'MUTATION_AMBIGUOUS',
          'message': 'Verify the previous submission on the portal before retrying.',
        };
      }
      final credentials = await SecureStorageService.getShaladarpanCreds();
      final school = queued['school_id']?.toString() ?? '';
      if (!EcosystemService.isSchoolReady || school.isEmpty || credentials['id']?.trim() != school) {
        return {
          'success': false,
          'code': 'ACCOUNT_NOT_READY',
          'message': 'Log in to the school that owns this queued attendance.',
        };
      }
      final raw = queued['staff_list'];
      if (raw is! List || raw.isEmpty)
        return {'success': false, 'code': 'BAD_QUEUE', 'message': 'Queued staff list is invalid.'};
      final staff = raw.map((row) => Map<String, dynamic>.from(row as Map)).toList();
      if (staff.any((row) => (row['staffId']?.toString() ?? '').isEmpty ||
          (row['status_code'] == null && (row['original_status']?.toString().isEmpty ?? true)))) {
        return {'success': false, 'code': 'BAD_QUEUE', 'message': 'Queued rows need Staff IDs and attendance status.'};
      }
      // Persist uncertainty BEFORE dispatch, including app termination during POST.
      await _settle(queued, false, uncertain: true);
      final result = await ShaladarpanService.submitStaffAttendance(staff, schoolId: school);
      final success = ShaladarpanService.isSubmissionConfirmed(result);
      await _settle(queued, success);
      // Failures remain held for manual portal verification; no blind automatic replay.
      return result;
    } catch (_) {
      return {
        'success': false,
        'code': 'QUEUE_ERROR',
        'message': 'Queued data was retained. Review it before retrying.',
      };
    }
  }
}
