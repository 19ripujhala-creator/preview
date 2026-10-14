import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../experiments/direct_school_session.dart';
import '../../core/backend_config.dart';
import '../../core/ecosystem_service.dart';
import '../../core/secure_storage_service.dart';
import 'student_service.dart';

class InchargeService {
  static Map<String, dynamic> _error(
    String code,
    String message, {
    bool attempted = false,
  }) => {
    'success': false,
    'code': code,
    'message': message,
    'message_source': 'backend',
    'portal_message': null,
    'verified': false,
    'submission_attempted': attempted,
  };
  static Future<Map<String, dynamic>> _request({
    String? schoolId,
    String? type,
    String roleId = '',
    String teacherId = '',
    String buttonId = '',
    bool confirmed = false,
  }) async {
    final direct = StudentService.directAttendanceEnabled,
        session = DirectSchoolSession.incharge;
    final mutation = type != null;
    var dispatched = false;
    try {
      final account =
              (await SecureStorageService.getShaladarpanCreds())['id']
                  ?.trim() ??
              '',
          school = (schoolId ?? account).trim();
      if (account.isEmpty)
        return _error('SESSION_EXPIRED', 'School is not logged in.');
      if (school != account)
        return _error(
          'ACCOUNT_MISMATCH',
          'Requested school differs from login.',
        );
      if (mutation && !confirmed)
        return _error(
          'CONFIRMATION_REQUIRED',
          'Confirm the incharge change before submitting.',
        );
      if (StudentService.directAttendanceEnabled != direct ||
          (direct && !identical(session, DirectSchoolSession.incharge)))
        return _error(
          'ACCOUNT_CHANGED',
          'School login changed; refresh first.',
        );
      late Map<String, dynamic> result;
      if (direct) {
        if (session == null || DirectSchoolSession.schoolId != school)
          return _error('SESSION_EXPIRED', 'Direct School login is required.');
        if (session.auth.authenticatedSchoolId != school)
          return _error(
            'ACCOUNT_CHANGED',
            'School login changed; refresh first.',
          );
        result = mutation
            ? await session.execute(
                type,
                roleId: roleId,
                teacherId: teacherId,
                buttonId: buttonId,
                userConfirmed: confirmed,
              )
            : await session.fetch();
        dispatched = result['submission_attempted'] == true;
      } else {
        dispatched = mutation;
        final response = await http
            .post(
              BackendConfig.uri(
                '/api/shaladarpan/incharge/${mutation ? 'action' : 'fetch'}',
              ),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'school_id': school,
                if (mutation) ...{
                  'action_type': type,
                  'role_id': roleId,
                  'teacher_id': teacherId,
                  'button_id': buttonId,
                },
              }),
            )
            .timeout(Duration(seconds: mutation ? 35 : 30));
        result = EcosystemService.decode(response);
        final detail = result['detail'];
        if (detail is Map) {
          result.addAll(Map<String, dynamic>.from(detail));
        } else if (detail is String && detail.trim().isNotEmpty) {
          result.putIfAbsent('message', () => detail);
        }
        if (response.statusCode != 200) result['success'] = false;
      }
      if (StudentService.directAttendanceEnabled != direct ||
          (direct && !identical(session, DirectSchoolSession.incharge)) ||
          (await SecureStorageService.getShaladarpanCreds())['id']?.trim() !=
              account)
        return _error(
          dispatched ? 'SAVE_UNCONFIRMED' : 'ACCOUNT_CHANGED',
          'School login changed. Refresh before further changes.',
          attempted: dispatched,
        );
      return result;
    } on TimeoutException {
      return _error(
        dispatched ? 'SAVE_UNCONFIRMED' : 'NETWORK_TIMEOUT',
        dispatched
            ? 'Portal result could not be verified. Refresh before further changes.'
            : 'Portal request timed out.',
        attempted: dispatched,
      );
    } catch (_) {
      return _error(
        dispatched ? 'SAVE_UNCONFIRMED' : 'NETWORK_ERROR',
        dispatched
            ? 'Portal result could not be verified. Refresh before further changes.'
            : 'Portal connection failed.',
        attempted: dispatched,
      );
    }
  }

  static Future<Map<String, dynamic>> fetch({String? schoolId}) =>
      _request(schoolId: schoolId);
  static Future<Map<String, dynamic>> action({
    String? schoolId,
    required String type,
    String roleId = '',
    String teacherId = '',
    String buttonId = '',
    required bool confirmed,
  }) => _request(
    schoolId: schoolId,
    type: type,
    roleId: roleId,
    teacherId: teacherId,
    buttonId: buttonId,
    confirmed: confirmed,
  );
}
