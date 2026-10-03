import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shaladarpan/services/core/backend_config.dart';

class MonthlyTaskException implements Exception {
  final String message;
  final bool submissionUnknown;
  const MonthlyTaskException(this.message, {this.submissionUnknown = false});
  @override
  String toString() => message;
}

class MonthlyTaskService {
  static Future<Map<String, dynamic>> _request(String path, Map<String, dynamic> body, {bool mutation = false}) async {
    try {
      final response = await http.post(BackendConfig.uri('/api/shaladarpan/monthly/$path'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(Duration(seconds: mutation ? 210 : 150));
      dynamic decoded;
      try { decoded = jsonDecode(utf8.decode(response.bodyBytes)); }
      catch (_) { throw MonthlyTaskException('The server returned an unreadable response.', submissionUnknown: mutation); }
      if (decoded is! Map) throw MonthlyTaskException('The server returned an invalid response.', submissionUnknown: mutation);
      final data = Map<String, dynamic>.from(decoded);
      if (response.statusCode != 200 || data['success'] != true) {
        final detail = data['detail'];
        final error = detail is Map ? detail : data;
        throw MonthlyTaskException((error['message'] ?? (detail is String ? detail : 'Monthly task request failed.')).toString(),
          submissionUnknown: mutation && error['submission_attempted'] != false);
      }
      if (data['data'] is! Map) throw MonthlyTaskException('Monthly form data is missing.', submissionUnknown: mutation);
      return data;
    } on TimeoutException {
      throw MonthlyTaskException(mutation ? 'Submission is taking longer than expected. Check the portal before retrying.' : 'The portal is taking longer than expected. Please refresh.', submissionUnknown: mutation);
    } on MonthlyTaskException { rethrow; }
    catch (_) { throw MonthlyTaskException('Unable to reach the backend.', submissionUnknown: mutation); }
  }
  static Future<Map<String, dynamic>> fetch(String school, String task, Map<String, String> selection) =>
    _request('form', {'school_id': school, 'task': task, 'selection': selection});
  static Future<Map<String, dynamic>> submit(String school, String task, Map<String, String> selection,
    String snapshot, Map<String, String> values) => _request('submit', {
      'school_id': school, 'task': task, 'selection': selection, 'snapshot': snapshot,
      'values': values, 'confirmed': true,
    }, mutation: true);
  static Future<Map<String, dynamic>> lock(String school, Map<String, String> selection,
    String snapshot) => _request('lock', {
      'school_id': school, 'task': 'viffs', 'selection': selection,
      'snapshot': snapshot, 'confirmed': true,
    }, mutation: true);
}
