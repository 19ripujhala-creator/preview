import 'package:shaladarpan/services/core/backend_config.dart';
// lib/tabs/student/student_service.dart

import 'dart:convert';

import 'package:http/http.dart' as http;

class StudentService {
  // FastAPI backend base URL
  static String get baseUrl => '${BackendConfig.baseUrl}/api/student';

  // Standard request timeout
  static const Duration _timeout = Duration(seconds: 45);

  // School report har section ko portal par kholta hai (+ gender sync),
  // isliye ise lamba timeout chahiye.
  static const Duration _reportTimeout = Duration(seconds: 240);

  /// 1. Fetch student attendance for a class
  static Future<Map<String, dynamic>> fetchAttendance({
    required String classId,
    required String date, // Format: DD/MM/YYYY
    String? section,
  }) async {
    try {
      final queryParams = {
        'class_id': classId,
        'date': date,
        if (section != null && section.isNotEmpty) 'section': section,
      };

      final uri = Uri.parse("$baseUrl/attendance/fetch").replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(_timeout);

      final Map<String, dynamic> data = _parseResponseBody(response.body);

      if (response.statusCode == 200) {
        return data;
      } else {
        return {
          "success": false,
          "code": data["code"] ?? response.statusCode.toString(),
          "message": _extractErrorMessage(data, response.statusCode),
        };
      }
    } catch (e) {
      return {"success": false, "message": "Connection error: $e"};
    }
  }

  /// 2. Save & Sync student attendance to Shala Darpan portal
  static Future<Map<String, dynamic>> saveAttendance(Map<String, dynamic> payload) async {
    try {
      final uri = Uri.parse("$baseUrl/attendance/save");
      final response = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
          .timeout(_timeout);

      final Map<String, dynamic> data = _parseResponseBody(response.body);

      if (response.statusCode == 200) {
        return data;
      } else {
        return {
          "success": false,
          "code": data["code"] ?? response.statusCode.toString(),
          "message": _extractErrorMessage(data, response.statusCode),
        };
      }
    } catch (e) {
      return {"success": false, "message": "Connection error: $e"};
    }
  }

  /// 3. Fetch summary of all classes for the day
  static Future<Map<String, dynamic>> fetchClassSummary({String? date}) async {
    try {
      final queryParams = <String, String>{if (date != null && date.isNotEmpty) 'date': date};

      final uri = Uri.parse("$baseUrl/summary").replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(uri).timeout(_timeout);
      final Map<String, dynamic> data = _parseResponseBody(response.body);

      if (response.statusCode == 200) {
        return data;
      } else {
        return {"success": false, "message": _extractErrorMessage(data, response.statusCode)};
      }
    } catch (e) {
      return {"success": false, "message": "Connection error: $e"};
    }
  }

  /// 4. School-wide report (class/section wise Boys, Girls, Absent, Leave, Total)
  /// Response: { success, date, schoolName, rows: [...], unknownGender, failedSections }
  static Future<Map<String, dynamic>> fetchSchoolReport({
    required String date,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (onProgress == null) {
      try {
        final uri = Uri.parse('$baseUrl/school-report').replace(queryParameters: {'date': date});
        final response = await http.get(uri).timeout(_reportTimeout);
        final data = _parseResponseBody(response.body);
        if (response.statusCode == 200) return data;
        return {'success': false, 'code': data['code'] ?? '${response.statusCode}',
          'message': _extractErrorMessage(data, response.statusCode)};
      } catch (e) {
        return {'success': false, 'message': 'Connection error: $e'};
      }
    }
    final client = http.Client();
    try {
      return await _readReportStream(client, date, onProgress).timeout(_reportTimeout);
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    } finally {
      // Closes the request on success, timeout, incomplete stream or errors.
      client.close();
    }
  }

  static Future<Map<String, dynamic>> _readReportStream(http.Client client, String date,
    void Function(int completed, int total) onProgress) async {
    final uri = Uri.parse('$baseUrl/school-report').replace(
      queryParameters: {'date': date, 'stream': 'true'});
    final response = await client.send(http.Request('GET', uri));
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      final data = _parseResponseBody(body);
      return {'success': false, 'code': '${response.statusCode}',
        'message': _extractErrorMessage(data, response.statusCode)};
    }
    if (!(response.headers['content-type'] ?? '').contains('application/x-ndjson')) {
      // Compatibility with the previous backend, which only returns final JSON.
      return _parseResponseBody(await response.stream.bytesToString());
    }
    await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final event = _parseResponseBody(line);
      switch (event['type']) {
        case 'progress':
          final completed = event['completed'];
          final total = event['total'];
          if (completed is int && total is int && total > 0 && completed >= 0 && completed <= total) {
            onProgress(completed, total);
          }
          break;
        case 'result':
          final data = event['data'];
          if (data is! Map) throw const FormatException('Invalid report response.');
          return Map<String, dynamic>.from(data);
        case 'error':
          final statusCode = event['status'] is int ? event['status'] as int : 500;
          return {'success': false, 'code': '$statusCode',
            'message': _extractErrorMessage({'detail': event['detail']}, statusCode)};
        case 'started':
        case 'heartbeat':
          break;
        default:
          throw const FormatException('Invalid report progress response.');
      }
    }
    throw const FormatException('Report connection ended before completion.');
  }

  // Helper: Safely parses JSON response
  static Map<String, dynamic> _parseResponseBody(String body) {
    try {
      if (body.isEmpty) return {};
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {"data": decoded};
    } catch (_) {
      return {"raw": body};
    }
  }

  // Helper: Extracts clean error message from FastAPI HTTPException responses
  static String _extractErrorMessage(Map<String, dynamic> data, int statusCode) {
    if (data.containsKey('detail')) {
      final detail = data['detail'];
      if (detail is Map && detail.containsKey('message')) {
        return detail['message'].toString();
      } else if (detail is String) {
        return detail;
      }
    }
    if (data.containsKey('message')) {
      return data['message'].toString();
    }
    return "Server returned error (Code: $statusCode)";
  }
}
