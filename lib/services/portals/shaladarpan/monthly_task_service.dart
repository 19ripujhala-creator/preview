import 'ranking_status_service.dart';
import 'viffs_status_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shaladarpan/services/core/backend_config.dart';

class MonthlyTaskException implements Exception {
  final String message;
  final bool submissionUnknown;
  final Map<String, dynamic>? savedForm;
  final Map<String, String> fieldErrors;
  const MonthlyTaskException(this.message, {this.submissionUnknown = false, this.savedForm, this.fieldErrors = const {}});
  @override
  String toString() => message;
}

class MonthlyTaskService {
  static final Map<String, Map<String, dynamic>> _viffsSelectors = {};
  static Map<String, dynamic>? cachedViffsSelectors(String school) {
    final value = _viffsSelectors[school];
    return value == null ? null : Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));
  }

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
        final savedForm = error['submission_rejected'] == true && error['data'] is Map
          ? Map<String, dynamic>.from(error['data']) : null;
        if (savedForm != null && body['school_id'] != null) {
          await RankingStatusService.storeForm(body['school_id'].toString(), {'data': savedForm});
        }
        throw MonthlyTaskException((error['message'] ?? (detail is String ? detail : 'Monthly task request failed.')).toString(),
          submissionUnknown: mutation && savedForm == null && error['submission_attempted'] != false, savedForm: savedForm, fieldErrors: error['field_errors'] is Map
            ? Map<String, dynamic>.from(error['field_errors']).map((key, value) => MapEntry(key, value.toString())) : const {});
      }
      if (data['data'] is! Map) throw MonthlyTaskException('Monthly form data is missing.', submissionUnknown: mutation);
      final school = body['school_id']?.toString();
      if (school != null) {
        await RankingStatusService.storeForm(school, data);
        await ViffsStatusService.storeForm(school, data, saved: mutation);
        final form = data['data'];
        if (form is Map && form['task'] == 'viffs' && form['school_id']?.toString() == school && form['selectors'] is List && form['selection'] is Map) {
          _viffsSelectors[school] = Map<String, dynamic>.from(jsonDecode(jsonEncode({'selectors': form['selectors'], 'selection': form['selection']})));
        }
      }
      return data;
    } on TimeoutException {
      if (mutation && body['task'] == 'viffs') await ViffsStatusService.invalidate(body['school_id'].toString(), Map<String, dynamic>.from(body['selection'] as Map));
      throw MonthlyTaskException(mutation ? 'Submission is taking longer than expected. Check the portal before retrying.' : 'The portal is taking longer than expected. Please refresh.', submissionUnknown: mutation);
    } on MonthlyTaskException catch (e) {
      if (e.submissionUnknown && body['task'] == 'viffs') await ViffsStatusService.invalidate(body['school_id'].toString(), Map<String, dynamic>.from(body['selection'] as Map));
      rethrow;
    }
    catch (_) {
      if (mutation && body['task'] == 'viffs') await ViffsStatusService.invalidate(body['school_id'].toString(), Map<String, dynamic>.from(body['selection'] as Map));
      throw MonthlyTaskException('Unable to reach the backend.', submissionUnknown: mutation);
    }
  }
  static Future<Map<String, dynamic>> fetch(String school, String task, Map<String, String> selection, {bool refresh = false}) =>
    _request('form', {'school_id': school, 'task': task, 'selection': selection, 'refresh': refresh});
  static Future<Map<String, dynamic>> submit(String school, String task, Map<String, String> selection,
    String snapshot, Map<String, String> values, {bool editing = false}) => _request('submit', {
      'school_id': school, 'task': task, 'selection': selection, 'snapshot': snapshot,
      'values': values, 'confirmed': true, 'editing': editing,
    }, mutation: true);
  static Future<Map<String, dynamic>> rankingAction(String school, String action,
    Map<String, String> selection, String snapshot) {
    if (action != 'edit' && action != 'delete') throw const MonthlyTaskException('Unsupported ranking action.');
    return _request('ranking/$action', {'school_id': school, 'task': 'ranking',
      'selection': selection, 'snapshot': snapshot, 'confirmed': true}, mutation: true);
  }
  static Future<Map<String, dynamic>> lock(String school, Map<String, String> selection,
    String snapshot) => _request('lock', {
      'school_id': school, 'task': 'viffs', 'selection': selection,
      'snapshot': snapshot, 'confirmed': true,
    }, mutation: true);
}
