import '../services/core/direct/coordinator.dart';
import '../services/core/direct/errors.dart';
import '../services/portals/shaladarpan/direct/leave_approvals.dart';
import '../services/portals/shaladarpan/direct/staff_attendance.dart';
import 'direct_portal_auth.dart';

class DirectLeaveApprovalService {
  DirectLeaveApprovalService(this.auth);
  final DirectPortalAuth auth;
  LeaveApprovalsWorker? _worker;
  bool _confirmed = false;
  String get _key =>
      '${auth.authenticatedSchoolId}/${auth.coordinator?.generation}';
  LeaveApprovalsWorker get _portal => _worker ??= LeaveApprovalsWorker(
    baseUrl: () =>
        Uri.https('rajshaladarpan.rajasthan.gov.in', '/${auth.verifiedNode}/'),
    schoolId: () => auth.authenticatedSchoolId ?? '',
    sessionKey: () => _key,
    observeUrl: auth.observeAttendanceUrl,
    check: () {
      if (!auth.isVerified)
        throw const StaffAttendanceError(
          'SESSION_EXPIRED',
          'School portal session expired.',
        );
    },
    request:
        (
          url, {
          fields,
          referer,
          action,
          mutation = false,
          timeout = const Duration(seconds: 25),
        }) => auth.leaveApprovalRequest(
          url,
          fields: fields,
          referer: referer,
          action: action,
          mutation: mutation,
          timeout: timeout,
          userConfirmed: _confirmed,
        ),
  );
  Future<Map<String, dynamic>> _run(
    Future<Map<String, dynamic>> Function() operation, {
    bool mutation = false,
    bool confirmed = false,
  }) async {
    var key = _key;
    final school = auth.authenticatedSchoolId, co = auth.coordinator;
    Map<String, dynamic>? result;
    Future<Map<String, dynamic>> execute() async {
      if (!mutation && auth.authenticatedSchoolId == school) key = _key;
      if (!auth.isVerified ||
          auth.authenticatedSchoolId != school ||
          key != _key ||
          (auth.authenticatedSchoolId ?? '').isEmpty)
        return LeaveApprovalsWorker.failure(
          const StaffAttendanceError(
            'ACCOUNT_CHANGED',
            'School login session changed. Fetch leave approvals again.',
          ),
        );
      _confirmed = confirmed;
      try {
        result = await operation();
        if (key != _key || !auth.isVerified)
          return LeaveApprovalsWorker.failure(
            const StaffAttendanceError(
              'ACCOUNT_CHANGED',
              'School login session changed. Fetch leave approvals again.',
            ),
            result?['submission_attempted'] == true,
          );
        return result!;
      } finally {
        _confirmed = false;
      }
    }

    try {
      if (co == null) return await execute();
      return await co.run(
        resource: 'sd.leave',
        kind: mutation ? Kind.mutation : Kind.read,
        timeout: mutation ? 120 : 90,
        maxAttempts: mutation ? 1 : 3,
        preMutationCodes: mutation
            ? {
                'PAGE_NOT_READY',
                'NETWORK_ERROR',
                'PORTAL_SLOW',
                'SESSION_EXPIRED',
              }
            : {},
        label: mutation ? 'leave_action' : 'leave_fetch',
        worker: (_) => execute(),
      );
    } on CoordinatorError catch (error) {
      if (result?['submission_attempted'] == true) return result!;
      final ambiguous = mutation && error.kind == ErrorKind.mutationAmbiguous;
      return {
        'success': false,
        'code': ambiguous ? 'SAVE_UNCONFIRMED' : error.kind.code,
        'message': error.message,
        'submission_attempted': ambiguous,
        'verified': false,
      };
    } catch (error) {
      return LeaveApprovalsWorker.failure(error, mutation);
    }
  }

  Future<Map<String, dynamic>> fetch() => _run(() => _portal.fetch());
  Future<Map<String, dynamic>> submit(
    List<Map<String, dynamic>> actions, {
    required bool userConfirmed,
  }) => _run(
    () => _portal.submit(actions, userConfirmed: userConfirmed),
    mutation: true,
    confirmed: userConfirmed,
  );
}
