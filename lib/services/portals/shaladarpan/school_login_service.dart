/// Restores the selected School transport using the existing Python-converted
/// authentication lifecycle. Direct mode never initializes the backend ecosystem.
import '../../../experiments/direct_portal_auth.dart';
import '../../../experiments/direct_school_session.dart';
import '../../core/secure_storage_service.dart';
import 'student_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

typedef SchoolLoginOperation =
    Future<({DirectPortalAuth? auth, DirectLoginResult result})> Function({
      required String user,
      required String password,
    });

class SchoolLoginService {
  SchoolLoginService({
    Future<String?> Function()? readMode,
    Future<bool> Function()? signedOut,
    Future<Map<String, String>> Function()? credentials,
    SchoolLoginOperation? authenticate,
  }) : _readMode = readMode ?? _savedMode,
       _signedOut = signedOut ?? _savedSignedOut,
       _credentials = credentials ?? SecureStorageService.getShaladarpanCreds,
       _authenticate = authenticate ?? DirectPortalAuth.automaticLogin;

  static const modeKey = 'school_connection_mode';
  static final instance = SchoolLoginService();
  final Future<String?> Function() _readMode;
  final Future<bool> Function() _signedOut;
  final Future<Map<String, String>> Function() _credentials;
  final SchoolLoginOperation _authenticate;
  bool _restoring = false;

  static Future<String?> _savedMode() async =>
      (await SharedPreferences.getInstance()).getString(modeKey);
  static Future<bool> _savedSignedOut() async =>
      (await SharedPreferences.getInstance()).getBool('user_signed_out') ==
      true;

  static Future<void> rememberMode({required bool direct}) async {
    final saved = await SharedPreferences.getInstance();
    if (!await saved.setString(modeKey, direct ? 'direct' : 'backend')) {
      throw StateError('School connection mode could not be saved.');
    }
  }

  static Map<String, dynamic> _failure(String code, String message) => {
    'success': false,
    'code': code,
    'message': message,
  };

  /// The root UI supplies its epoch/mounted guard. Saved credentials alone do
  /// not establish readiness: auth probes the saved portal session or logs in
  /// through its existing source algorithm before ownership is transferred.
  Future<Map<String, dynamic>> restore({
    required bool Function() isCurrent,
  }) async {
    if (_restoring) {
      return _failure('LOGIN_BUSY', 'School session restoration is running.');
    }
    _restoring = true;
    DirectPortalAuth? owned;
    try {
      if (!isCurrent()) {
        return _failure('LOGIN_CANCELLED', 'Login was cancelled.');
      }
      if (await _readMode() != 'direct') {
        return _failure(
          'DIRECT_MODE_NOT_SELECTED',
          'Direct School login is not selected.',
        );
      }
      if (await _signedOut()) {
        return _failure('SIGNED_OUT', 'Please sign in.');
      }
      final saved = await _credentials();
      final user = saved['id']?.trim() ?? '';
      final password = saved['pass'] ?? '';
      if (user.isEmpty || password.isEmpty) {
        return _failure(
          'NO_CREDENTIALS',
          'School ID aur password required hain.',
        );
      }
      if (!isCurrent()) {
        return _failure('LOGIN_CANCELLED', 'Login was cancelled.');
      }
      final outcome = await _authenticate(user: user, password: password);
      owned = outcome.auth;
      final current = await _credentials();
      if (!isCurrent() || await _signedOut()) {
        return _failure('LOGIN_CANCELLED', 'Login was cancelled.');
      }
      if (await _readMode() != 'direct') {
        return _failure(
          'MODE_CHANGED',
          'School connection mode changed during login.',
        );
      }
      if (current['id']?.trim() != user || current['pass'] != password) {
        return _failure('ACCOUNT_CHANGED', 'Account changed during login.');
      }
      if (!isCurrent()) {
        return _failure('LOGIN_CANCELLED', 'Login was cancelled.');
      }
      final source = Map<String, dynamic>.from(outcome.result.response);
      if (!outcome.result.success) {
        return {
          ...source,
          'success': false,
          'message':
              source['portal_message'] ??
              source['message'] ??
              outcome.result.message,
        };
      }
      if (owned?.isVerified != true || owned!.authenticatedSchoolId != user) {
        return _failure(
          'SESSION_EXPIRED',
          'A verified School portal session is required.',
        );
      }
      DirectSchoolSession.attach(owned, user);
      StudentService.directAttendanceEnabled = true;
      owned = null;
      return {...source, 'success': true, 'school_id': user};
    } catch (_) {
      return _failure(
        'DIRECT_LOGIN_ERROR',
        'Direct School session could not be restored. Please sign in.',
      );
    } finally {
      owned?.close();
      _restoring = false;
    }
  }
}
