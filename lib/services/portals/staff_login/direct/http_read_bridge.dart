/// Complete http_read_bridge.py: shared registry and final account fence.
import 'http_auth.dart';
import 'http_session.dart';
import 'http_profile.dart';
import 'http_history.dart';

class StaffHttpReadBridge {
  StaffHttpReadBridge(this.registry);
  final StaffHttpAuth registry;
  Map<String, dynamic> rejected(String code, String message) => {
    'success': false,
    'code': code,
    'message': message,
    'records': <dynamic>[],
  };
  Future<Map<String, dynamic>> run(
    Future<Map<String, dynamic>> Function(StaffHttpSession) operation,
  ) async {
    final session = registry.current();
    if (session == null || !session.authenticated || session.base == null)
      return rejected('SESSION_EXPIRED', 'Staff session expired.');
    Map<String, dynamic> result;
    try {
      result = await operation(session);
    } on StaffHttpError catch (e) {
      return rejected(e.code, e.message);
    }
    if (!identical(registry.current(), session))
      return rejected('ACCOUNT_CHANGED', 'Staff login changed.');
    return result;
  }

  Future<Map<String, dynamic>> fetchProfile() => run(fetchStaffHttpProfile);
  Future<Map<String, dynamic>> fetchHistory([String filter = 'all']) =>
      run((s) => fetchStaffHttpHistory(s, filter));
  Future<Map<String, dynamic>> fetchPendingLeaves() => fetchHistory('pending');
}
