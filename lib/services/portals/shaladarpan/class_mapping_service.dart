/// Preserves the existing class-mapping route response shape in both modes.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../experiments/direct_school_session.dart';
import '../../core/backend_config.dart';
import '../../core/ecosystem_service.dart';
import '../../core/secure_storage_service.dart';
import 'student_service.dart';

class ClassMappingService {
  static Map<String, dynamic> _error(
    String code,
    String message, {
    bool attempted = false,
  }) => {
    'success': false,
    'code': code,
    'message': message,
    'submission_attempted': attempted,
  };
  static Future<Map<String, dynamic>> _request(
    String school, {
    List<Map<String, dynamic>>? updates,
    bool userConfirmed = false,
  }) async {
    final direct = StudentService.directAttendanceEnabled,
        session = DirectSchoolSession.classMappings;
    final mutation = updates != null;
    try {
      if ((await SecureStorageService.getShaladarpanCreds())['id']?.trim() !=
          school.trim())
        return _error(
          'ACCOUNT_MISMATCH',
          'Requested school differs from the logged-in school.',
        );
      if (mutation && !userConfirmed)
        return _error(
          'CONFIRMATION_REQUIRED',
          'Confirm the mapping updates before saving.',
        );
      if (StudentService.directAttendanceEnabled != direct ||
          (direct && !identical(session, DirectSchoolSession.classMappings))) {
        return _error(
          'ACCOUNT_CHANGED',
          'School login changed. Refresh mappings before continuing.',
        );
      }
      late Map<String, dynamic> result;
      if (direct) {
        if (session == null || DirectSchoolSession.schoolId != school.trim())
          return _error('SESSION_EXPIRED', 'Direct School login is required.');
        if (session.auth.authenticatedSchoolId != school.trim()) {
          return _error(
            'ACCOUNT_CHANGED',
            'School login changed. Refresh mappings before continuing.',
          );
        }
        result = mutation
            ? await session.save(updates, userConfirmed: userConfirmed)
            : await session.fetch();
      } else {
        final response = mutation
            ? await http
                  .post(
                    BackendConfig.uri('/api/shaladarpan/class-mapping/save'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({'school_id': school, 'updates': updates}),
                  )
                  .timeout(const Duration(seconds: 40))
            : await http
                  .get(
                    BackendConfig.uri('/api/shaladarpan/class-mapping/fetch')
                        .replace(queryParameters: {'school_id': school}),
                  )
                  .timeout(const Duration(seconds: 35));
        result = EcosystemService.decode(response);
        if (result['detail'] is Map)
          result = {
            ...Map<String, dynamic>.from(result['detail'] as Map),
            'success': false,
          };
      }
      if (StudentService.directAttendanceEnabled != direct ||
          (direct && !identical(session, DirectSchoolSession.classMappings)) ||
          (await SecureStorageService.getShaladarpanCreds())['id']?.trim() !=
              school.trim())
        return _error(
          mutation && result['submission_attempted'] == true
              ? 'SAVE_UNCONFIRMED'
              : 'ACCOUNT_CHANGED',
          'School login changed. Refresh mappings before continuing.',
          attempted: mutation && result['submission_attempted'] == true,
        );
      return result;
    } on TimeoutException {
      return _error(
        mutation ? 'SAVE_UNCONFIRMED' : 'PORTAL_SLOW',
        mutation
            ? 'Mapping Save was submitted but not verified. Fetch mappings before submitting again.'
            : 'The portal is taking longer than expected.',
        attempted: mutation,
      );
    } catch (error) {
      return _error(
        mutation ? 'SAVE_UNCONFIRMED' : 'NETWORK_ERROR',
        mutation
            ? 'Mapping Save was submitted but not verified. Fetch mappings before submitting again.'
            : 'Could not load class mappings.',
        attempted: mutation,
      );
    }
  }

  static Future<Map<String, dynamic>> fetch(String school) => _request(school);
  static Future<Map<String, dynamic>> save(
    String school,
    List<Map<String, dynamic>> updates, {
    required bool userConfirmed,
  }) => _request(school, updates: updates, userConfirmed: userConfirmed);
}
