import '../rajsims/direct/rajsims_app_service.dart';
import '../../../experiments/direct_school_session.dart';
import 'student_service.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'shaladarpan_service.dart';

import 'package:http/http.dart' as http;
import 'package:shaladarpan/services/core/backend_config.dart';
import 'package:shaladarpan/services/core/ecosystem_service.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';

class DashboardBootstrap {
  static final ValueNotifier<Map<String, dynamic>?> mdmStatus = ValueNotifier(
    null,
  );
  static final ValueNotifier<int> mdmRevision = ValueNotifier(0);
  static void invalidateMdm() {
    _mdmPending = null;
    _mdmStarted = null;
    _mdmRunning = false;
    mdmRevision.value++;
  }

  static bool _mdmRunning = false;
  static bool _mdmFresh = false;
  static String? _mdmKey;
  static DateTime? _mdmStarted;
  static Future<Map<String, dynamic>>? _mdmPending;
  static Future<Map<String, dynamic>> loadMdm(
    String schoolId, {
    bool fresh = false,
  }) {
    final now = DateTime.now();
    final mode = StudentService.directAttendanceEnabled ? 'direct' : 'backend';
    final key = '$mode/$schoolId/${now.year}-${now.month}-${now.day}';
    if (key == _mdmKey &&
        _mdmRunning &&
        _mdmPending != null &&
        (!fresh || _mdmFresh))
      return _mdmPending!;
    if (!fresh &&
        key == _mdmKey &&
        _mdmPending != null &&
        _mdmStarted != null &&
        now.difference(_mdmStarted!) < const Duration(seconds: 30))
      return _mdmPending!;
    _mdmKey = key;
    _mdmStarted = now;
    _mdmFresh = fresh;
    final revision = mdmRevision.value;
    late Future<Map<String, dynamic>> task;
    task = _readMdm(schoolId, fresh).then((result) {
      if (revision != mdmRevision.value || !identical(_mdmPending, task)) {
        return {'success': false, 'code': 'STALE_MDM_READ'};
      }
      if (identical(_mdmPending, task)) {
        mdmStatus.value = {
          'school_id': schoolId,
          'day_key': key,
          'result': result,
        };
      }
      return result;
    });
    _mdmPending = task;
    _mdmRunning = true;
    unawaited(
      task.whenComplete(() {
        if (identical(_mdmPending, task)) {
          _mdmRunning = false;
          if (mdmStatus.value?['result'] is Map &&
              mdmStatus.value!['result']['success'] == true) {
            _mdmStarted = DateTime.now();
          } else {
            _mdmPending = null;
            _mdmStarted = null;
          }
        }
      }),
    );
    return task;
  }

  static Future<Map<String, dynamic>> _readMdm(
    String school,
    bool fresh,
  ) async {
    try {
      final before = await SecureStorageService.getShaladarpanCreds();
      if (before['id']?.trim() != school)
        return {'success': false, 'code': 'ACCOUNT_CHANGED'};
      if (StudentService.directAttendanceEnabled) {
        final result = await RajsimsAppService.status(force: fresh);
        final current = await SecureStorageService.getShaladarpanCreds();
        if (!StudentService.directAttendanceEnabled ||
            current['id']?.trim() != school)
          return {'success': false, 'code': 'ACCOUNT_CHANGED'};
        return result;
      }
      final uri = BackendConfig.uri('/api/rajsims/mdm/fetch')
          .replace(queryParameters: {if (fresh) 'force': 'true'});
      final response = await http.get(uri).timeout(const Duration(seconds: 60));
      final after = await SecureStorageService.getShaladarpanCreds();
      if (after['id']?.trim() != school)
        return {'success': false, 'code': 'ACCOUNT_CHANGED'};
      final decoded = EcosystemService.decode(response);
      if (response.statusCode != 200) return decoded;
      if (decoded['data'] is Map) {
        final payload = Map<String, dynamic>.from(decoded['data']);
        return {
          ...payload,
          'success': decoded['success'] == true && payload['success'] != false,
        };
      }
      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'MDM data could not be loaded.'};
    }
  }

  static String? _key;
  static Future<Map<String, dynamic>>? _pending;
  static DateTime? _started;

  /// Test seam; production always uses [ShaladarpanService].
  @visibleForTesting
  static DashboardLoader? dashboardLoader;

  @visibleForTesting
  static void resetForTest() {
    _key = null;
    _pending = null;
    _started = null;
    dashboardLoader = null;
  }

  static Future<Map<String, dynamic>> load(
    String schoolId, {
    bool fresh = false,
    void Function(double, String)? onProgress,
  }) {
    final now = DateTime.now();
    final mode = StudentService.directAttendanceEnabled
        ? 'direct/${identityHashCode(DirectSchoolSession.studentKpi)}'
        : 'backend';
    final key = '$mode/$schoolId/${now.year}-${now.month}-${now.day}';
    if (!fresh &&
        _key == key &&
        _pending != null &&
        _started != null &&
        now.difference(_started!) < const Duration(minutes: 2))
      return _pending!;
    _key = key;
    _started = now;
    final DashboardLoader loader =
        dashboardLoader ?? ShaladarpanService.loginAndSyncDashboard;
    final task = Future<Map<String, dynamic>>.sync(
      () => loader(forceRefresh: fresh, onProgress: onProgress),
    );
    _pending = task;
    // Share only a usable result. A failed or thrown load is dropped so the
    // next call retries instead of replaying the same failure for two minutes.
    // (Registered before the caller's own await, so it runs first.)
    task.then<void>(
      (result) {
        if (identical(_pending, task) && result['success'] != true) {
          _pending = null;
          _started = null;
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_pending, task)) {
          _pending = null;
          _started = null;
        }
      },
    );
    return task;
  }
}

typedef DashboardLoader = Future<Map<String, dynamic>> Function({
  bool forceRefresh,
  void Function(double, String)? onProgress,
});
