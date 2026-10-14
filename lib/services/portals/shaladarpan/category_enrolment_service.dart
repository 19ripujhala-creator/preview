import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../experiments/direct_school_session.dart';
import '../../core/backend_config.dart';
import '../../core/ecosystem_service.dart';
import '../../core/secure_storage_service.dart';
import 'student_service.dart';
import 'direct/category_enrolment_worker.dart';

/// The existing category-wise API response, also available to future MPR callers.
class CategoryEnrolmentService {
  static Future<Map<String, dynamic>> fetch({
    String? schoolId,
    String? session,
    bool mprBundle = false,
  }) async {
    final direct = StudentService.directAttendanceEnabled;
    final portal = DirectSchoolSession.categoryEnrolment;
    try {
      final account =
          (await SecureStorageService.getShaladarpanCreds())['id']?.trim() ??
          '';
      final school = (schoolId ?? account).trim();
      if (account.isEmpty)
        return CategoryEnrolmentWorker.failure(
          'SESSION_EXPIRED',
          'School portal session expired.',
        );
      if (school != account)
        return CategoryEnrolmentWorker.failure(
          'ACCOUNT_MISMATCH',
          'Requested school differs from the logged-in school.',
        );
      Map<String, dynamic> result;
      if (direct) {
        if (portal == null || DirectSchoolSession.schoolId != school) {
          return CategoryEnrolmentWorker.failure(
            'SESSION_EXPIRED',
            'Direct School login is required.',
          );
        }
        result = await portal.fetch(
          schoolId: school,
          session: session,
          mprBundle: mprBundle,
        );
      } else {
        final uri =
            BackendConfig.uri(
              '/api/shaladarpan/enrolment/category-wise',
            ).replace(
              queryParameters: {
                'school_id': school,
                if (session != null && session.isNotEmpty) 'session': session,
              },
            );
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 80));
        result = EcosystemService.decode(response);
        if (result['detail'] is Map)
          result.addAll(Map<String, dynamic>.from(result['detail']));
        if (response.statusCode != 200) {
          result['success'] = false;
          result['complete'] = false;
        }
      }
      final current = (await SecureStorageService.getShaladarpanCreds())['id']
          ?.trim();
      if (current != account ||
          StudentService.directAttendanceEnabled != direct ||
          (direct &&
              (!identical(portal, DirectSchoolSession.categoryEnrolment) ||
                  DirectSchoolSession.schoolId != school))) {
        return CategoryEnrolmentWorker.failure(
          'ACCOUNT_CHANGED',
          'School account changed while fetching the report.',
        );
      }
      return result;
    } on TimeoutException {
      return CategoryEnrolmentWorker.failure(
        'PORTAL_SLOW',
        'Enrolment report request timed out.',
      );
    } catch (_) {
      return CategoryEnrolmentWorker.failure(
        'NETWORK_ERROR',
        'Could not connect to the enrolment report.',
      );
    }
  }
}
