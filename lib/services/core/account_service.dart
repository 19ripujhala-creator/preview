import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'backend_config.dart';
import 'ecosystem_service.dart';
import 'secure_storage_service.dart';
import '../portals/staff_login/staff_login_service.dart';
import '../portals/shaladarpan/student_service.dart';

/// Read-only account data using the app's existing direct portal sessions.
class AccountService {
  static Future<Map<String, dynamic>>? _profileFlight;
  static String? _profileScope;
  // Only a digest is kept in memory; raw passwords never sit in a static field.
  static String _scope(Map<String, String> c) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            for (final key in [
              'school_id',
              'school_password',
              'staff_id',
              'staff_password',
              'sso_id',
              'sso_password',
            ])
              c[key],
          ]),
        ),
      )
      .toString();

  static Future<Map<String, dynamic>> _get(String path, int seconds) async {
    final client = http.Client();
    try {
      final response = await client
          .get(BackendConfig.uri(path))
          .timeout(Duration(seconds: seconds));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return {'success': false};
      final result = Map<String, dynamic>.from(decoded);
      if (response.statusCode != 200) result['success'] = false;
      return result;
    } catch (_) {
      return {'success': false};
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> connections() async {
    if (kIsWeb) return _get('/api/ecosystem/status', 8);
    final credentials = await SecureStorageService.getAllPortalCreds();
    return EcosystemService.statusSnapshot(credentials: credentials);
  }

  static Future<Map<String, dynamic>> profile() async {
    if (kIsWeb) return _get('/api/staff/profile', 30);
    if (!StudentService.directAttendanceEnabled)
      return {
        'success': false,
        'code': 'DIRECT_MODE_NOT_SELECTED',
        'message': 'Direct portal session is not available.',
      };
    final before = await SecureStorageService.getAllPortalCreds();
    final scope = _scope(before);
    if (_profileFlight != null && _profileScope == scope)
      return _profileFlight!;
    final task = _nativeProfile(scope);
    _profileScope = scope;
    _profileFlight = task;
    unawaited(
      task.then<void>(
        (_) {
          if (identical(_profileFlight, task)) {
            _profileFlight = null;
            _profileScope = null;
          }
        },
        onError: (Object _, StackTrace __) {
          if (identical(_profileFlight, task)) {
            _profileFlight = null;
            _profileScope = null;
          }
        },
      ),
    );
    return task;
  }

  static Future<Map<String, dynamic>> _nativeProfile(String scope) async {
    final result = await StaffLoginService.fetchProfile();
    final after = await SecureStorageService.getAllPortalCreds();
    if (!StudentService.directAttendanceEnabled || _scope(after) != scope)
      return {
        'success': false,
        'code': 'ACCOUNT_CHANGED',
        'message': 'Account changed during profile loading.',
      };
    return result;
  }
}
