import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_service.dart';
import 'secure_storage_service.dart';

/// Profile identity is scoped to both school and Staff Login, not table position.
class AccountIdentity {
  static String _key(String school, String staff) => 'account_identity_v1/$school/$staff';
  static String _text(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return ['', '--', 'unknown', 'staff user'].contains(text.toLowerCase()) ? '' : text;
  }

  static Future<void> remember(String school, String staff, Map profile) async {
    try {
      if (school.isEmpty || staff.isEmpty || _text(profile['staffLoginId']) != staff) return;
      final current = await SecureStorageService.getAllPortalCreds();
      if (current['school_id'] != school || current['staff_id'] != staff) return;
      final name = _text(profile['name']);
      final nic = _text(profile['nicId']);
      if (name.isEmpty || nic.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(school, staff), jsonEncode({
        'school': school, 'staff': staff, 'name': name, 'nic': nic,
      }));
    } catch (_) { /* Optional cache must not interrupt profile or session display. */ }
  }

  static Future<Map<String, String>> load(String school) async {
    const unavailable = {'name': 'Account', 'nic': '—'};
    try {
      final credentials = await SecureStorageService.getAllPortalCreds();
      final staff = credentials['staff_id']?.trim() ?? '';
      if (credentials['school_id'] != school || staff.isEmpty) return unavailable;
      final prefs = await SharedPreferences.getInstance();
      Map<String, String>? cached;
      final saved = prefs.getString(_key(school, staff));
      if (saved != null) {
        try {
          final data = jsonDecode(saved);
          if (data is Map && data['school'] == school && data['staff'] == staff &&
              _text(data['name']).isNotEmpty && _text(data['nic']).isNotEmpty) {
            cached = {'name': _text(data['name']), 'nic': _text(data['nic'])};
          }
        } catch (_) { /* Ignore malformed cache and use the portal profile. */ }
      }
      // Legacy NIC cache can identify the login only when the IDs actually match.
      if (cached == null && prefs.getString('staff_nic_id')?.trim() == staff &&
          _text(prefs.getString('staff_name')).isNotEmpty) {
        cached = {'name': _text(prefs.getString('staff_name')), 'nic': staff};
      }
      if (cached != null) {
        final current = await SecureStorageService.getAllPortalCreds();
        return current['school_id'] == school && current['staff_id'] == staff ? cached : unavailable;
      }
      final response = await AccountService.profile();
      final current = await SecureStorageService.getAllPortalCreds();
      if (current['school_id'] != school || current['staff_id'] != staff) return unavailable;
      final profile = response['profile'];
      if (response['success'] != true || profile is! Map || _text(profile['staffLoginId']) != staff) return unavailable;
      await remember(school, staff, profile);
      final after = await SecureStorageService.getAllPortalCreds();
      if (after['school_id'] != school || after['staff_id'] != staff) return unavailable;
      return {'name': _text(profile['name']).isEmpty ? 'Account' : _text(profile['name']),
        'nic': _text(profile['nicId']).isEmpty ? '—' : _text(profile['nicId'])};
    } catch (_) {
      return unavailable;
    }
  }
}
