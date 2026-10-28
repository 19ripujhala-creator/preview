import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();

  // Cache only school identity, never the credential/password record.
  static String? _schoolIdentity;
  static int _schoolRevision = 0, _identityWriters = 0;
  static Future<String>? _identityRead;
  static int get schoolIdentityRevision => _schoolRevision;
  static String? get schoolIdentityNow =>
      _identityWriters == 0 ? _schoolIdentity : null;

  static void invalidateSchoolIdentity() {
    _schoolRevision++;
    _schoolIdentity = null;
    _identityRead = null;
  }

  static Future<String> getShaladarpanIdentity() async {
    if (_identityWriters != 0) return '';
    final cached = _schoolIdentity;
    if (cached != null) return cached;
    final active = _identityRead;
    if (active != null) return active;
    final revision = _schoolRevision;
    final read = getShaladarpanCreds().then(
      (credentials) => revision == _schoolRevision && _identityWriters == 0
          ? credentials['id']?.trim() ?? ''
          : '',
    );
    _identityRead = read;
    try {
      return await read;
    } finally {
      if (identical(_identityRead, read)) _identityRead = null;
    }
  }

  static Future<Map<String, String>> _readPair(
    String idKey,
    String passKey,
    List<String> legacyIds,
    String legacyPass,
  ) async {
    try {
      final record = await _storage.read(key: 'portal_credentials_v2');
      if (record != null) {
        final saved = jsonDecode(record);
        if (saved is Map)
          return {
            'id': saved[idKey]?.toString() ?? '',
            'pass': saved[passKey]?.toString() ?? '',
          };
      }
      if (await _storage.read(key: 'is_app_configured') == 'false')
        return {'id': '', 'pass': ''};
      final id = await _storage.read(key: idKey) ?? '';
      final pass = await _storage.read(key: passKey) ?? '';
      if (id.isNotEmpty && pass.isNotEmpty) return {'id': id, 'pass': pass};
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    String id = '';
    for (final key in legacyIds) {
      final value = prefs.getString(key) ?? '';
      if (value.isNotEmpty) {
        id = value;
        break;
      }
    }
    return {'id': id, 'pass': prefs.getString(legacyPass) ?? ''};
  }

  static Future<bool> isAppConfigured() async {
    final credentials = await getAllPortalCreds();
    return credentials.values.every((value) => value.isNotEmpty);
  }

  static Future<Map<String, String>> getShaladarpanCreds() async {
    final revision = _schoolRevision;
    final credentials = await _readPair('shala_id', 'shala_pass', [
      'saved_shala_id',
      'saved_school_id',
      'school_id',
    ], 'saved_shala_pass');
    if (revision == _schoolRevision && _identityWriters == 0) {
      final school = credentials['id']?.trim() ?? '';
      // Failed/empty reads must remain retryable, not become a permanent cache.
      if (school.isNotEmpty) _schoolIdentity = school;
    }
    return credentials;
  }

  static Future<Map<String, String>> getStaffCreds() => _readPair(
    'staff_id',
    'staff_pass',
    ['saved_staff_id'],
    'saved_staff_pass',
  );
  static Future<Map<String, String>> getRajSimsCreds() => _readPair(
    'rajsims_id',
    'rajsims_pass',
    ['saved_sso_id'],
    'saved_sso_pass',
  );

  static Future<Map<String, String>> getAllPortalCreds() async {
    final shala = await getShaladarpanCreds();
    final staff = await getStaffCreds();
    final sso = await getRajSimsCreds();
    return {
      'school_id': shala['id']!.trim(),
      'school_password': shala['pass']!,
      'staff_id': staff['id']!.trim(),
      'staff_password': staff['pass']!,
      'sso_id': sso['id']!.trim(),
      'sso_password': sso['pass']!,
    };
  }

  static Future<void> saveAllPortals({
    required String shalaId,
    required String shalaPass,
    required String staffId,
    required String staffPass,
    required String rajsimsId,
    required String rajsimsPass,
  }) async {
    invalidateSchoolIdentity();
    _identityWriters++;
    try {
      final previous = await getShaladarpanCreds();
      final values = {
        'shala_id': shalaId.trim(),
        'shala_pass': shalaPass,
        'staff_id': staffId.trim(),
        'staff_pass': staffPass,
        'rajsims_id': rajsimsId.trim(),
        'rajsims_pass': rajsimsPass,
      };
      await _storage.write(key: 'is_app_configured', value: 'false');
      for (final entry in values.entries) {
        await _storage.write(key: entry.key, value: entry.value);
      }
      await _storage.write(
        key: 'portal_credentials_v2',
        value: jsonEncode(values),
      );
      await _storage.write(key: 'is_app_configured', value: 'true');
      final prefs = await SharedPreferences.getInstance();
      if (previous['id']?.trim() != shalaId.trim()) {
        for (final key in [
          'cached_student_kpi',
          'cached_staff_attendance',
          'cached_pending_leaves',
          'attendance_verified_date',
          'attendance_already_marked',
          'dashboard_cache_school_id',
          'dashboard_cache_date',
        ]) {
          await prefs.remove(key);
        }
      }
      await prefs.setString('saved_shala_id', shalaId.trim());
      await prefs.setString('saved_school_id', shalaId.trim());
      await prefs.setString('school_id', shalaId.trim());
      await prefs.setString('saved_staff_id', staffId.trim());
      await prefs.setString('saved_sso_id', rajsimsId.trim());
      for (final key in [
        'saved_shala_pass',
        'saved_staff_pass',
        'saved_sso_pass',
      ]) {
        await prefs.remove(key);
      }
    } finally {
      _identityWriters--;
      invalidateSchoolIdentity();
    }
  }

  static Future<void> clearAll() async {
    invalidateSchoolIdentity();
    _identityWriters++;
    try {
      for (final key in [
        'portal_credentials_v2',
        'is_app_configured',
        'shala_id',
        'shala_pass',
        'staff_id',
        'staff_pass',
        'rajsims_id',
        'rajsims_pass',
      ]) {
        await _storage.delete(key: key);
      }
      final prefs = await SharedPreferences.getInstance();
      for (final key in [
        'saved_shala_id',
        'saved_school_id',
        'school_id',
        'saved_staff_id',
        'saved_sso_id',
        'saved_shala_pass',
        'saved_staff_pass',
        'saved_sso_pass',
      ]) {
        await prefs.remove(key);
      }
    } finally {
      _identityWriters--;
      invalidateSchoolIdentity();
    }
  }
}
