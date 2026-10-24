import 'package:flutter/foundation.dart';

import '../../experiments/direct_portal_auth.dart';
import '../../experiments/direct_school_session.dart';
import '../portals/shaladarpan/student_service.dart';
import '../portals/shaladarpan/school_login_service.dart';
import '../portals/staff_login/direct/staff_runtime.dart';
import '../portals/rajsims/direct/rajsims_runtime.dart';
import 'direct/coordinator.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend_config.dart';
import 'secure_storage_service.dart';

class EcosystemService {
  static Future<Map<String, dynamic>>? _initializing;
  static String? _initializingSchool;
  static String? _initializingCredentials;
  static Map<String, dynamic> _latest = {};
  static bool _schoolReady = false;
  static int _epoch = 0;
  static bool get isSchoolReady => _schoolReady;
  static String? get summary =>
      _latest['all_ready'] == true ? null : _latest['message']?.toString();

  /// Only structural diagnostics are exposed; credentials, URLs and HTML
  /// never become part of the technical details shown in the UI.
  static Map<String, dynamic> safeLoginDiagnostics(Object? value) {
    if (value is! Map) return {};
    final safe = <String, dynamic>{};
    const textValues = {
      'phase': {'rajsims_sso_bridge'},
      'stage': {'bridge_envelope', 'bridge_input'},
      'page': {'signin', 'dashboard', 'other'},
    };
    for (final entry in textValues.entries) {
      if (entry.value.contains(value[entry.key])) {
        safe[entry.key] = value[entry.key];
      }
    }
    for (final key in const [
      'attempt',
      'http_status',
      'html_bytes',
      'form_count',
      'error_nodes',
      'nonempty_error_nodes',
      'tile_count',
    ]) {
      if (value[key] is int) safe[key] = value[key];
    }
    for (final key in const [
      'user_control',
      'password_control',
      'captcha_control',
      'logout_control',
      'javascript_alert_call',
      'javascript_redirect',
      'meta_refresh',
    ]) {
      if (value[key] is bool) safe[key] = value[key];
    }
    final checks = value['checks'];
    if (checks is Map) {
      final safeChecks = <String, bool>{};
      for (final key in const [
        'source_is_sso',
        'source_is_rajsims',
        'source_is_mdm',
        'action_query_empty',
        'action_fragment_empty',
        'method_is_post',
        'single_form',
        'single_named_input',
        'input_is_userdetails',
        'input_enabled',
        'input_hidden',
        'input_nonempty',
      ]) {
        if (checks[key] is bool) safeChecks[key] = checks[key] as bool;
      }
      if (safeChecks.isNotEmpty) safe['checks'] = safeChecks;
    }
    return safe;
  }

  static Map<String, dynamic> describeLoginResult(
    Map<String, dynamic> result, {
    required double durationSeconds,
  }) {
    final success = result['success'] == true;
    final diagnostics = success
        ? <String, dynamic>{}
        : safeLoginDiagnostics(result['diagnostics']);
    return {
      'state': success ? 'ready' : 'failed',
      'success': success,
      'live': success,
      'stale': false,
      'code': result['code'],
      'message': result['message'] ?? '',
      'duration_s': durationSeconds,
      if (result['message_source'] != null)
        'message_source': result['message_source'],
      if (diagnostics.isNotEmpty) 'diagnostics': diagnostics,
    };
  }

  static bool portalReady(String name) {
    final portals = _latest['portals'];
    final portal = portals is Map ? portals[name] : null;
    return portal is Map &&
        portal['state'] == 'ready' &&
        portal['stale'] != true &&
        portal['live'] != false;
  }

  static void reset() {
    _epoch++;
    _schoolReady = false;
    _latest = {};
  }

  static Map<String, dynamic> decode(http.Response response) {
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is Map) {
        final result = Map<String, dynamic>.from(data);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          result['success'] = false;
          result['message'] ??= errorMessage(result, response.statusCode);
        }
        return result;
      }
    } catch (_) {}
    return {
      'success': false,
      'code': 'INVALID_RESPONSE',
      'message': 'Invalid backend response (HTTP ${response.statusCode}).',
    };
  }

  static String errorMessage(Map data, int status) {
    final detail = data['detail'];
    if (detail is String) return detail;
    if (detail is Map && detail['message'] != null)
      return detail['message'].toString();
    return data['message']?.toString() ?? 'Backend error (HTTP $status).';
  }

  static Future<void> refreshStatus() async {
    if (!kIsWeb) {
      _refreshNativeStates();
      return;
    }
    final epoch = _epoch;
    try {
      final response = await http
          .get(BackendConfig.uri('/api/ecosystem/status'))
          .timeout(const Duration(seconds: 5));
      final result = decode(response);
      if (epoch == _epoch &&
          response.statusCode == 200 &&
          result['portals'] is Map) {
        _latest = result;
        _schoolReady = portalReady('shaladarpan');
      }
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> initializeSaved() async {
    try {
      return await initialize(await SecureStorageService.getAllPortalCreds());
    } catch (_) {
      return {
        'success': false,
        'code': 'CREDENTIAL_STORAGE_ERROR',
        'message': 'Saved credentials could not be loaded. Please sign in.',
      };
    }
  }

  static Future<Map<String, dynamic>> initialize(
    Map<String, String> credentials, {
    void Function(double, String)? onProgress,
  }) {
    final school = credentials['school_id']?.trim() ?? '';
    if (_initializing != null) {
      if (_initializingSchool == school &&
          _initializingCredentials == jsonEncode(credentials))
        return _initializing!;
      return Future.value({
        'success': false,
        'code': 'LOGIN_BUSY',
        'message': 'Another account login is still running.',
      });
    }
    for (final key in [
      'school_id',
      'school_password',
      'staff_id',
      'staff_password',
      'sso_id',
      'sso_password',
    ]) {
      if ((credentials[key] ?? '').isEmpty) {
        return Future.value({
          'success': false,
          'code': 'EMPTY_CREDENTIALS',
          'message': 'Enter credentials for all three portals.',
        });
      }
    }
    if (school == credentials['staff_id']?.trim()) {
      return Future.value({
        'success': false,
        'code': 'BAD_STAFF_ID',
        'message': 'Staff ID and School ID must be different.',
      });
    }
    _initializingSchool = school;
    _initializingCredentials = jsonEncode(credentials);
    reset();
    final task = _initialize(
      Map<String, String>.from(credentials),
      _epoch,
      onProgress,
    );
    _initializing = task;
    return task;
  }

  static Future<Map<String, dynamic>> _initialize(
    Map<String, String> credentials,
    int epoch,
    void Function(double, String)? onProgress,
  ) async {
    if (!kIsWeb) {
      try {
        return await _initializeNative(credentials, epoch, onProgress);
      } finally {
        _initializing = null;
        _initializingSchool = null;
        _initializingCredentials = null;
      }
    }
    final client = http.Client();
    final watch = Stopwatch()..start();
    Timer? messageTimer;
    bool pollingMessage = false;
    bool messagesActive = true;
    final messageClient = http.Client();
    if (onProgress != null) {
      messageTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!messagesActive || pollingMessage || epoch != _epoch) return;
        pollingMessage = true;
        try {
          final response = await messageClient
              .get(BackendConfig.uri('/api/shaladarpan/status'))
              .timeout(const Duration(seconds: 2));
          final status = decode(response);
          if (messagesActive &&
              epoch == _epoch &&
              response.statusCode == 200 &&
              status['message'] is String) {
            onProgress(0.0, status['message'].toString());
          }
        } catch (_) {
        } finally {
          pollingMessage = false;
        }
      });
    }
    Map<String, dynamic> result = {};
    try {
      try {
        final response = await client
            .post(
              BackendConfig.uri('/api/ecosystem/init-all'),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({...credentials, 'wait_all': false}),
            )
            .timeout(const Duration(seconds: 75));
        result = decode(response);
        if (response.statusCode != 200) return result;
      } on TimeoutException {
        // The backend may still be authenticating. Observe it; never replay POST.
        result = {
          'pending': ['shaladarpan', 'staff_login', 'rajsims'],
        };
      }
      while (watch.elapsed < const Duration(seconds: 190)) {
        if (epoch != _epoch)
          return {
            'success': false,
            'code': 'LOGIN_CANCELLED',
            'message': 'Login was cancelled.',
          };
        _latest = result;
        final readyCount = [
          'shaladarpan',
          'staff_login',
          'rajsims',
        ].where(portalReady).length;
        onProgress?.call(
          readyCount / 3,
          result['message']?.toString() ??
              'Connecting portals ($readyCount/3 ready)…',
        );
        if (portalReady('shaladarpan')) break;
        final portals = result['portals'];
        final loading =
            portals is Map &&
            portals.values.any((p) => p is Map && p['state'] == 'loading');
        final pending = result['pending'];
        if (!loading && !(pending is List && pending.isNotEmpty)) break;
        await Future<void>.delayed(const Duration(seconds: 2));
        final response = await client
            .get(BackendConfig.uri('/api/ecosystem/status'))
            .timeout(const Duration(seconds: 5));
        result = decode(response);
        if (response.statusCode != 200) break;
        final states = result['portals'];
        if (states is! Map) break;
        result['pending'] = states.entries
            .where((e) => e.value is Map && e.value['state'] == 'loading')
            .map((e) => e.key)
            .toList();
        result['failed'] = states.entries
            .where((e) => e.value is Map && e.value['state'] == 'failed')
            .map((e) => e.key)
            .toList();
      }
      if (epoch != _epoch)
        return {
          'success': false,
          'code': 'LOGIN_CANCELLED',
          'message': 'Login was cancelled.',
        };
      _latest = result;
      _schoolReady = portalReady('shaladarpan');
      result['success'] = _schoolReady;
      result['all_ready'] = [
        'shaladarpan',
        'staff_login',
        'rajsims',
      ].every(portalReady);
      if (result['all_ready'] == true) {
        result['message'] = 'All portals ready.';
      } else {
        final unavailable = [
          'shaladarpan',
          'staff_login',
          'rajsims',
        ].where((p) => !portalReady(p)).join(', ');
        result['message'] = _schoolReady
            ? 'School ready. Other portals need attention: $unavailable'
            : result['message'] ??
                  'School login did not complete. Please check portal status.';
      }
      return result;
    } catch (_) {
      if (epoch == _epoch) reset();
      return {
        'success': false,
        'code': 'CONNECTION_ERROR',
        'message':
            'Could not complete backend login. Check the backend and retry.',
      };
    } finally {
      messagesActive = false;
      messageTimer?.cancel();
      messageClient.close();
      client.close();
      _initializing = null;
      _initializingSchool = null;
      _initializingCredentials = null;
    }
  }

  /// Local metadata only. Reading status never probes, logs in, or submits.
  static Map<String, dynamic> describeNativePortal(PortalCoordinator? co) {
    if (co == null)
      return {
        'state': 'idle',
        'success': null,
        'live': false,
        'stale': false,
        'coordinator_health': 'IDLE',
        'transport': 'http',
      };
    final status = co.status();
    final health = status['closed'] == true
        ? 'IDLE'
        : status['health'] as String;
    final live = health == 'READY' && status['context_current'] == true;
    final loading = health == 'AUTHENTICATING' || health == 'RECOVERING';
    return {
      'state': live
          ? 'ready'
          : loading
          ? 'loading'
          : health == 'UNKNOWN'
          ? 'unknown'
          : health == 'IDLE'
          ? 'idle'
          : 'failed',
      'success': live
          ? true
          : loading
          ? null
          : false,
      'live': live,
      'stale': !live && status['context_current'] == true,
      'coordinator_health': health,
      'generation': status['generation'],
      'last_ok_age_s': status['last_ok_age_s'],
      'active_operations': status['active_operations'],
      'transport': 'http',
    };
  }

  static Map<String, dynamic> statusSnapshot({
    Map<String, String>? credentials,
  }) {
    if (kIsWeb) return jsonDecode(jsonEncode(_latest)) as Map<String, dynamic>;
    final staff = StaffDirectRuntime.current,
        rajsims = RajsimsDirectRuntime.current;
    final coordinators = {
      'shaladarpan': DirectSchoolSession.coordinator,
      'staff_login': staff?.coordinator,
      'rajsims': rajsims?.coordinator,
    };
    final owners = {
      'shaladarpan': DirectSchoolSession.schoolId,
      'staff_login': staff?.registry.current()?.user ?? '',
      'rajsims': rajsims?.registry.username ?? '',
    };
    final keys = {
      'shaladarpan': 'school_id',
      'staff_login': 'staff_id',
      'rajsims': 'sso_id',
    };
    final previous = _latest['portals'];
    final portals = <String, dynamic>{};
    for (final entry in coordinators.entries) {
      final row = describeNativePortal(entry.value);
      if (entry.key == 'shaladarpan' &&
          row['live'] == true &&
          !DirectSchoolSession.ready) {
        row['state'] = 'unknown';
        row['live'] = false;
        row['success'] = false;
        row['coordinator_health'] = 'UNKNOWN';
        row['code'] = 'SESSION_CHANGED';
      }
      final prior = previous is Map ? previous[entry.key] : null;
      if (entry.value == null && prior is Map && prior['state'] == 'loading') {
        row['state'] = 'loading';
        row['coordinator_health'] = 'AUTHENTICATING';
      }
      if (credentials != null &&
          row['live'] == true &&
          owners[entry.key]!.trim().toLowerCase() !=
              (credentials[keys[entry.key]] ?? '').trim().toLowerCase()) {
        row['state'] = 'unknown';
        row['live'] = false;
        row['success'] = false;
        row['coordinator_health'] = 'UNKNOWN';
        row['code'] = 'ACCOUNT_CHANGED';
      }
      if (prior is Map && prior['message'] != null)
        row['message'] = prior['message'];
      if (prior is Map &&
          prior['state'] == 'failed' &&
          row['state'] == 'failed' &&
          row['generation'] == prior['generation']) {
        if (prior['code'] != null) row['code'] = prior['code'];
        if (prior['message_source'] != null)
          row['message_source'] = prior['message_source'];
        final diagnostics = safeLoginDiagnostics(prior['diagnostics']);
        if (diagnostics.isNotEmpty) row['diagnostics'] = diagnostics;
      }
      portals[entry.key] = row;
    }
    return {
      'success': true,
      'all_ready': portals.values.every((p) => p['live'] == true),
      'portals': portals,
      'transport': 'http',
    };
  }

  static void _refreshNativeStates() {
    final snapshot = statusSnapshot();
    _latest = {..._latest, ...snapshot};
    _schoolReady = portalReady('shaladarpan');
  }

  static Future<Map<String, dynamic>> _initializeNative(
    Map<String, String> credentials,
    int epoch,
    void Function(double, String)? progress,
  ) async {
    final portals = <String, dynamic>{
      for (final name in ['shaladarpan', 'staff_login', 'rajsims'])
        name: {
          'state': 'loading',
          'success': null,
          'live': false,
          'stale': false,
          'message': 'Login in progress...',
        },
    };
    _latest = {'portals': portals};
    final tasks = <Future<Map<String, dynamic>>>[];
    Future<Map<String, dynamic>> login(
      String name,
      Future<Map<String, dynamic>> Function() action,
      int delay,
    ) async {
      if (delay > 0) await Future<void>.delayed(Duration(milliseconds: delay));
      final watch = Stopwatch()..start();
      Map<String, dynamic> r;
      try {
        r = await action();
      } catch (e) {
        r = {
          'success': false,
          'code': 'DIRECT_LOGIN_ERROR',
          'message': e.toString(),
        };
      }
      if (epoch != _epoch)
        return {
          'success': false,
          'code': 'LOGIN_CANCELLED',
          'message': 'Login was cancelled.',
        };
      portals[name] = describeLoginResult(
        r,
        durationSeconds: watch.elapsedMilliseconds / 1000,
      );
      // Tie failure details to this session generation so a later recovery
      // cannot display the earlier login failure as the new result.
      final coordinator = name == 'rajsims'
          ? RajsimsDirectRuntime.current?.coordinator
          : name == 'staff_login'
          ? StaffDirectRuntime.current?.coordinator
          : DirectSchoolSession.coordinator;
      if (coordinator != null) {
        portals[name]['generation'] = coordinator.status()['generation'];
      }
      final count = portals.values.where((p) => p['state'] == 'ready').length;
      progress?.call(count / 3, r['message']?.toString() ?? '');
      return r;
    }

    tasks.add(
      login('shaladarpan', () async {
        final user = credentials['school_id']!,
            password = credentials['school_password']!;
        // The coordinator checks credentials and lifecycle before reusing a
        // session; matching School ID alone cannot establish readiness.
        final outcome = await DirectPortalAuth.automaticLogin(
              user: user,
              password: password,
            ),
            auth = outcome.auth;
        if (epoch != _epoch) {
          auth?.close();
          return {
            'success': false,
            'code': 'LOGIN_CANCELLED',
            'message': 'Login was cancelled.',
          };
        }
        if (!outcome.result.success || auth?.isVerified != true) {
          auth?.close();
          return {
            ...outcome.result.response,
            'success': false,
            'message':
                outcome.result.response['portal_message'] ??
                outcome.result.response['message'] ??
                outcome.result.message,
          };
        }
        DirectSchoolSession.attach(auth!, user);
        StudentService.directAttendanceEnabled = true;
        await SchoolLoginService.rememberMode(direct: true);
        return {...outcome.result.response, 'success': true};
      }, 0),
    );
    tasks.add(
      login('staff_login', () async {
        final runtime = await StaffDirectRuntime.get();
        if (epoch != _epoch)
          return {'success': false, 'code': 'LOGIN_CANCELLED'};
        return runtime.coordinator.authenticate(
          credentials['staff_id']!,
          credentials['staff_password']!,
        );
      }, 150),
    );
    tasks.add(
      login('rajsims', () async {
        final runtime = await RajsimsDirectRuntime.get();
        if (epoch != _epoch)
          return {'success': false, 'code': 'LOGIN_CANCELLED'};
        return runtime.coordinator.authenticate(
          credentials['sso_id']!,
          credentials['sso_password']!,
        );
      }, 300),
    );
    // Same source wait_all=false behavior: School gates navigation; other
    // authenticated sessions continue independently with their own coordinators.
    final school = await tasks.first;
    final remaining = Future.wait(tasks.skip(1));
    unawaited(
      remaining.then<void>((_) {
        if (epoch == _epoch) {
          _latest['all_ready'] = portals.values.every(
            (p) => p['state'] == 'ready',
          );
          _refreshNativeStates();
        }
      }, onError: (Object _, StackTrace __) {}),
    );
    if (epoch != _epoch)
      return {
        'success': false,
        'code': 'LOGIN_CANCELLED',
        'message': 'Login was cancelled.',
      };
    _schoolReady = school['success'] == true && DirectSchoolSession.ready;
    _latest = {
      'success': _schoolReady,
      'all_ready': portals.values.every((p) => p['state'] == 'ready'),
      'portals': portals,
      'message': school['message'] ?? '',
      if (school['message_source'] != null)
        'message_source': school['message_source'],
      'transport': 'http',
    };
    return Map<String, dynamic>.from(_latest);
  }
}
