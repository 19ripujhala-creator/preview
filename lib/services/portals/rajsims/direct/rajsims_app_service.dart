/// Existing Flutter API contracts backed by the shared native RajSIMS runtime.
library;

import '../../../core/secure_storage_service.dart';
import '../../shaladarpan/student_service.dart';
import '../../shaladarpan/category_enrolment_service.dart';
import 'rajsims_runtime.dart';
import 'rajsims_mdm_service.dart';

class RajsimsAppService {
  static Future<RajsimsMdmService> Function()? directProvider;
  static Future<Map<String, dynamic>> call(
    Future<Map<String, dynamic>> Function(RajsimsMdmService, String) operation,
  ) async {
    final credentials = await SecureStorageService.getRajSimsCreds(),
        u = credentials['id']?.trim() ?? '',
        p = credentials['pass'] ?? '';
    if (u.isEmpty || p.isEmpty)
      return {
        'success': false,
        'code': 'NO_CREDENTIALS',
        'message': 'RajSIMS SSO ID and password are required.',
      };
    if (!StudentService.directAttendanceEnabled)
      return {
        'success': false,
        'code': 'MODE_CHANGED',
        'message': 'Direct portal mode changed.',
      };
    try {
      final service =
          await (directProvider?.call() ??
              RajsimsDirectRuntime.get().then((runtime) => runtime.mdm));
      if (service.registry.current() != null && service.registry.username != u)
        return {
          'success': false,
          'code': 'ACCOUNT_CHANGED',
          'message': 'RajSIMS login changed.',
        };
      service.coordinator.rememberCredentials(u, p);
      if (service.registry.current() == null) {
        final login = await service.coordinator.authenticate(u, p);
        if (login['success'] != true) return login;
      }
      final school = await SecureStorageService.getShaladarpanCreds();
      final result = await operation(service, u),
          after = await SecureStorageService.getRajSimsCreds();
      final schoolAfter = await SecureStorageService.getShaladarpanCreds();
      if (schoolAfter['id']?.trim() != school['id']?.trim() ||
          !StudentService.directAttendanceEnabled ||
          after['id']?.trim() != u ||
          after['pass'] != p ||
          service.registry.username != u)
        return {
          'success': false,
          'code': 'ACCOUNT_CHANGED',
          'message': 'RajSIMS login changed.',
        };
      return result;
    } catch (e) {
      return {
        'success': false,
        'code': 'DIRECT_RAJ_SIM_ERROR',
        'message': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> stock({bool force = false}) =>
      call((s, u) => s.stock(u, force: force));
  static Future<Map<String, dynamic>> status({bool force = false}) =>
      call((s, u) => s.status(u, force: force));
  static Future<Map<String, dynamic>> history({
    bool legacy = false,
    bool force = false,
  }) => call((s, u) => s.history(u, legacy: legacy, force: force));
  static Future<Map<String, dynamic>> submit(Map<String, dynamic> p) =>
      call((s, u) => s.submit(u, p));
  static Future<Map<String, dynamic>> entry(String no, {bool legacy = false}) =>
      call((s, u) => s.entry(u, no, legacy: legacy));
  static Future<Map<String, dynamic>> update(Map<String, dynamic> p) =>
      call((s, u) => s.update(u, p));
  static Future<Map<String, dynamic>> mpr(String path) async {
    final uri = Uri.parse(path),
        q = uri.queryParameters,
        y = int.tryParse(q['year'] ?? ''),
        m = int.tryParse(q['month'] ?? '');
    if (uri.path.endsWith('/mpr-profile')) return call((s, u) => s.profile(u));
    if (y == null || m == null || y < 2000 || y > 2100 || m < 1 || m > 12)
      return {
        'success': false,
        'code': 'INVALID_PAYLOAD',
        'message': 'Report month is invalid.',
      };
    if (uri.path.endsWith('/monthly-summary'))
      return call((s, u) => s.monthly(u, y, m));
    if (uri.path.endsWith('/mpr-bundle'))
      return call(
        (s, u) => s.bundle(
          u,
          y,
          m,
          () => CategoryEnrolmentService.fetch(mprBundle: true),
        ),
      );
    return {
      'success': false,
      'code': 'INVALID_PAYLOAD',
      'message': 'Unsupported monthly report operation.',
    };
  }
}
