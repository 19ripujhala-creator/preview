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
  static String? get summary => _latest['all_ready'] == true ? null : _latest['message']?.toString();

  static bool portalReady(String name) {
    final portals = _latest['portals'];
    final portal = portals is Map ? portals[name] : null;
    return portal is Map && portal['state'] == 'ready' && portal['stale'] != true && portal['live'] != false;
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
    if (detail is Map && detail['message'] != null) return detail['message'].toString();
    return data['message']?.toString() ?? 'Backend error (HTTP $status).';
  }

  static Future<void> refreshStatus() async {
    final epoch = _epoch;
    try {
      final response = await http.get(BackendConfig.uri('/api/ecosystem/status')).timeout(const Duration(seconds: 5));
      final result = decode(response);
      if (epoch == _epoch && response.statusCode == 200 && result['portals'] is Map) {
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

  static Future<Map<String, dynamic>> initialize(Map<String, String> credentials, {void Function(double, String)? onProgress}) {
    final school = credentials['school_id']?.trim() ?? '';
    if (_initializing != null) {
      if (_initializingSchool == school && _initializingCredentials == jsonEncode(credentials)) return _initializing!;
      return Future.value({
        'success': false,
        'code': 'LOGIN_BUSY',
        'message': 'Another account login is still running.',
      });
    }
    for (final key in ['school_id', 'school_password', 'staff_id', 'staff_password', 'sso_id', 'sso_password']) {
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
    final task = _initialize(Map<String, String>.from(credentials), _epoch, onProgress);
    _initializing = task;
    return task;
  }

  static Future<Map<String, dynamic>> _initialize(Map<String, String> credentials, int epoch, void Function(double, String)? onProgress) async {
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
          final response = await messageClient.get(BackendConfig.uri('/api/shaladarpan/status')).timeout(const Duration(seconds: 2));
          final status = decode(response);
          if (messagesActive && epoch == _epoch && response.statusCode == 200 && status['message'] is String) {
            onProgress(0.0, status['message'].toString());
          }
        } catch (_) {} finally { pollingMessage = false; }
      });
    }
    Map<String, dynamic> result = {};
    try {
      try {
        final response = await client
            .post(
              BackendConfig.uri('/api/ecosystem/init-all'),
              headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
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
        if (epoch != _epoch) return {'success': false, 'code': 'LOGIN_CANCELLED', 'message': 'Login was cancelled.'};
        _latest = result;
        final readyCount = ['shaladarpan', 'staff_login', 'rajsims'].where(portalReady).length;
        onProgress?.call(readyCount / 3, result['message']?.toString() ?? 'Connecting portals ($readyCount/3 ready)…');
        if (portalReady('shaladarpan')) break;
        final portals = result['portals'];
        final loading = portals is Map && portals.values.any((p) => p is Map && p['state'] == 'loading');
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
      if (epoch != _epoch) return {'success': false, 'code': 'LOGIN_CANCELLED', 'message': 'Login was cancelled.'};
      _latest = result;
      _schoolReady = portalReady('shaladarpan');
      result['success'] = _schoolReady;
      result['all_ready'] = ['shaladarpan', 'staff_login', 'rajsims'].every(portalReady);
      if (result['all_ready'] == true) {
        result['message'] = 'All portals ready.';
      } else {
        final unavailable = ['shaladarpan', 'staff_login', 'rajsims'].where((p) => !portalReady(p)).join(', ');
        result['message'] = _schoolReady
            ? 'School ready. Other portals need attention: $unavailable'
            : result['message'] ?? 'School login did not complete. Please check portal status.';
      }
      return result;
    } catch (_) {
      if (epoch == _epoch) reset();
      return {
        'success': false,
        'code': 'CONNECTION_ERROR',
        'message': 'Could not complete backend login. Check the backend and retry.',
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
}
