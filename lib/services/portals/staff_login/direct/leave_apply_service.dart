/// Existing Staff coordinator/registry integration; never independently logs in.
import '../../../core/direct/async_primitives.dart';
import '../../../core/direct/coordinator.dart';
import '../../../core/direct/errors.dart';
import 'http_auth.dart';
import 'http_login.dart' show staffLower;
import 'leave_apply_worker.dart';
import 'leave_payload.dart';
import 'staff_read_service.dart';

class StaffLeaveApplyService {
  StaffLeaveApplyService({
    required this.registry,
    required this.coordinator,
    required this.reads,
  });
  final StaffHttpAuth registry;
  final PortalCoordinator coordinator;
  final StaffReadService reads;
  bool _owned(String user) =>
      user.isNotEmpty &&
      staffLower(registry.current()?.user ?? '') == staffLower(user);
  Map<String, dynamic> _failure(String code, String message) => {
    'success': false,
    'code': code,
    'message': message,
    'submission_attempted': false,
  };
  Future<Map<String, dynamic>> apply(
    String user,
    Map<String, dynamic> input,
  ) async {
    Map<String, dynamic> data;
    try {
      data = prepareStaffLeavePayload(input);
    } on StaffLeavePayloadError catch (e) {
      return _failure(e.code, e.message);
    }
    if (user.isEmpty || (registry.current() != null && !_owned(user)))
      return _failure('ACCOUNT_CHANGED', 'Staff login changed.');
    final confirmed = data['confirmed'] == true;
    if (confirmed) reads.invalidateHistory();
    try {
      if (!confirmed) {
        await coordinator.ensureReady(Kind.read);
        if (!_owned(user))
          return _failure('ACCOUNT_CHANGED', 'Staff login changed.');
        return staffLeaveConfirmation(data);
      }
      return await coordinator.run(
        resource: 'staff.leave.apply',
        kind: Kind.mutation,
        timeout: 60,
        label: 'leave_apply',
        maxAttempts: 1,
        preMutationCodes: const {
          'BAD_DATE',
          'BAD_DURATION',
          'INVALID_PAYLOAD',
          'EDIT_NOT_READY',
          'PORTAL_RESPONSE_ERROR',
          'PORTAL_MESSAGE',
        },
        worker: (_) async {
          final session = registry.current(),
              generation = coordinator.generation;
          if (!_owned(user) ||
              session == null ||
              !session.authenticated ||
              session.base == null)
            return _failure('SESSION_EXPIRED', 'Staff session expired.');
          void check() {
            OperationCancellation.current?.check();
            if (!identical(registry.current(), session) ||
                !_owned(user) ||
                generation != coordinator.generation)
              throw const StaffLeavePayloadError(
                'ACCOUNT_CHANGED',
                'Staff login changed.',
              );
          }

          return session.exclusive(() async {
            check();
            return StaffLeaveApplyWorker(session, check: check).apply(data);
          });
        },
      );
    } on CoordinatorError catch (e) {
      final upstream = e.extra['upstream_response'];
      return {
        ...e.asDetail(),
        if (upstream is Map && upstream['message_source'] == 'portal')
          'message_source': 'portal',
      };
    } finally {
      if (confirmed) reads.invalidateHistory();
    }
  }
}
