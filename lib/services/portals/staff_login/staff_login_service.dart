import 'package:shaladarpan/services/core/backend_config.dart';

// lib/services/portals/staff_login/staff_login_service.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class StaffLoginService {
  // PC testing: Flutter Web/Desktop + FastAPI same machine par hone ke liye 127.0.0.1
  static String get _baseUrl => '${BackendConfig.baseUrl}/api/staff';

  static const Map<String, String> _headers = {'Content-Type': 'application/json', 'Accept': 'application/json'};

  // ═════════════════════════════════════════════════════════════════════
  // RESPONSE HELPERS
  // ═════════════════════════════════════════════════════════════════════

  static dynamic _decodeJson(http.Response response) {
    if (response.body.trim().isEmpty) {
      return null;
    }

    try {
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('⚠️ [StaffService] Invalid JSON response: $e');
      return null;
    }
  }

  static String _extractErrorMessage(dynamic data, int statusCode, {String fallback = 'Server returned an error.'}) {
    if (data is Map) {
      final detail = data['detail'];

      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }

      if (detail is Map) {
        final message = detail['message'];
        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString().trim();
        }

        final detailMessage = detail['detail'];
        if (detailMessage != null && detailMessage.toString().trim().isNotEmpty) {
          return detailMessage.toString().trim();
        }
      }

      final message = data['message'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString().trim();
      }

      final error = data['error'];
      if (error != null && error.toString().trim().isNotEmpty) {
        return error.toString().trim();
      }
    }

    return '$fallback (HTTP $statusCode)';
  }

  static Map<String, dynamic> _safeMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return <String, dynamic>{};
  }

  // ═════════════════════════════════════════════════════════════════════
  // 1. PROFILE
  // ═════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> fetchProfile() async {
    final uri = Uri.parse('$_baseUrl/profile');

    try {
      debugPrint('📡 [StaffService] Fetching dynamic profile from: $uri');

      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));

      final data = _decodeJson(response);

      if (response.statusCode == 200) {
        final map = _safeMap(data);
        debugPrint('✅ [StaffService] Live profile received: $map');

        return {
          'success': map['success'] ?? false,
          'profile': map['profile'],
          'message':
              map['message'] ??
              (map['success'] == true ? 'Profile fetched successfully.' : 'Unable to fetch staff profile.'),
        };
      }

      final errorMsg = _extractErrorMessage(data, response.statusCode, fallback: 'Failed to load live staff profile.');

      debugPrint('⚠️ [StaffService] Profile error: $errorMsg');

      return {'success': false, 'profile': null, 'message': errorMsg};
    } on FormatException catch (e) {
      debugPrint('❌ [StaffService] Profile JSON exception: $e');
      return {'success': false, 'profile': null, 'message': 'Invalid response received from Staff backend.'};
    } catch (e) {
      debugPrint('❌ [StaffService] Profile network exception: $e');
      return {'success': false, 'profile': null, 'message': 'Network error while connecting to Staff profile: $e'};
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  // 2. LEAVE APPLY
  // ═════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> applyLeave(Map<String, dynamic> payload) async {
    final uri = Uri.parse('$_baseUrl/leave/apply');

    try {
      debugPrint('📤 [StaffService] Sending leave application payload: ${jsonEncode(payload)}');

      final response = await http
          .post(uri, headers: _headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 90));

      final data = _decodeJson(response);

      if (response.statusCode == 200) {
        final map = _safeMap(data);
        debugPrint('✅ [StaffService] Leave applied response: $map');

        return {
          'success': map['success'] ?? false,
          'message': map['message'] ?? 'Leave request processed.',
          'data': map,
        };
      }

      final errorMsg = _extractErrorMessage(data, response.statusCode, fallback: 'Leave request failed.');

      debugPrint('❌ [StaffService] Leave server error: $errorMsg');

      return {'success': false, 'message': errorMsg, 'data': data};
    } on FormatException catch (e) {
      debugPrint('❌ [StaffService] Leave JSON exception: $e');
      return {'success': false, 'message': 'Invalid response received from Staff backend.'};
    } catch (e) {
      debugPrint('❌ [StaffService] Leave network exception: $e');
      return {'success': false, 'message': 'Failed to connect to Staff Portal backend: $e'};
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  // 3. LEAVE HISTORY (🚀 All records returned when page/pageSize omitted)
  // ═════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> fetchLeaveHistory({
    String filter = 'all',
    int? page,
    int? pageSize,
    bool refresh = false,
  }) async {
    final normalizedFilter = filter.trim().toLowerCase();
    final safeFilter = normalizedFilter == 'pending' ? 'pending' : 'all';

    final queryParams = <String, String>{'filter': safeFilter, 'refresh': '$refresh'};

    if (page != null && page >= 1) {
      queryParams['page'] = '$page';
    }
    if (pageSize != null && pageSize >= 1) {
      queryParams['page_size'] = '$pageSize';
    }

    final uri = Uri.parse('$_baseUrl/leave/history').replace(queryParameters: queryParams);

    try {
      debugPrint('📡 [StaffService] Fetching leave history from: $uri');

      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 45));

      final data = _decodeJson(response);

      if (response.statusCode == 200) {
        final map = _safeMap(data);

        final records = map['records'] is List ? List<dynamic>.from(map['records']) : <dynamic>[];

        final total = map['total'] is num ? map['total'] : records.length;
        final bool hasMore = map['has_more'] is bool
            ? map['has_more'] as bool
            : (pageSize != null && records.length >= pageSize);

        return {
          'success': map['success'] ?? false,
          'records': records,
          'total': total,
          'hasMore': hasMore,
          'page': page ?? 1,
          'message': map['message'] ?? '',
        };
      }

      final errorMsg = _extractErrorMessage(data, response.statusCode, fallback: 'Failed to fetch leave history.');

      debugPrint('❌ [StaffService] Leave history error: $errorMsg');

      return {
        'success': false,
        'records': <dynamic>[],
        'total': 0,
        'hasMore': false,
        'page': page ?? 1,
        'message': errorMsg,
      };
    } on FormatException catch (e) {
      debugPrint('❌ [StaffService] History JSON exception: $e');
      return {
        'success': false,
        'records': <dynamic>[],
        'total': 0,
        'hasMore': false,
        'page': page ?? 1,
        'message': 'Invalid response received from Staff backend.',
      };
    } catch (e) {
      debugPrint('❌ [StaffService] Leave history network exception: $e');
      return {
        'success': false,
        'records': <dynamic>[],
        'total': 0,
        'hasMore': false,
        'page': page ?? 1,
        'message': 'Connection error: $e',
      };
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  // 4. DOWNLOAD LEAVE PDF (🚀 Instant 0.3s GFAR 64 PDF Stream)
  // ═════════════════════════════════════════════════════════════════════

  static Future<Uint8List?> downloadLeavePdf({
    String? sNo,
    String? printUrl,
    String? name,
    String? designation,
    String? school,
    String? leaveType,
    String? fromDate,
    String? toDate,
    String? days,
    String? reason,
    String? remark,
  }) async {
    final queryParams = <String, String>{};
    if (sNo != null && sNo.isNotEmpty) queryParams['s_no'] = sNo;
    if (printUrl != null && printUrl.isNotEmpty) queryParams['print_url'] = printUrl;
    if (name != null && name.isNotEmpty) queryParams['name'] = name;
    if (designation != null && designation.isNotEmpty) queryParams['designation'] = designation;
    if (school != null && school.isNotEmpty) queryParams['school'] = school;
    if (leaveType != null && leaveType.isNotEmpty) queryParams['leave_type'] = leaveType;
    if (fromDate != null && fromDate.isNotEmpty) queryParams['from_date'] = fromDate;
    if (toDate != null && toDate.isNotEmpty) queryParams['to_date'] = toDate;
    if (days != null && days.isNotEmpty) queryParams['days'] = days;
    if (reason != null && reason.isNotEmpty) queryParams['reason'] = reason;
    if (remark != null && remark.isNotEmpty) queryParams['remark'] = remark;

    final uri = Uri.parse('$_baseUrl/leave/pdf').replace(queryParameters: queryParams);

    try {
      debugPrint('📡 [StaffService] Downloading GFAR 64 PDF from: $uri');
      final response = await http.get(uri).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
      debugPrint('❌ [StaffService] PDF download failed with HTTP ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('❌ [StaffService] PDF download exception: $e');
      return null;
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  // 5. DOWNLOAD FORMAT-10 PDF
  // ═════════════════════════════════════════════════════════════════════

  static Future<Uint8List?> downloadFormat10Pdf({String? nicId}) async {
    final queryParams = <String, String>{};
    if (nicId != null && nicId.isNotEmpty) {
      queryParams['nic_id'] = nicId;
    }

    final uri = Uri.parse('$_baseUrl/format10/pdf').replace(queryParameters: queryParams);

    try {
      debugPrint('📡 [StaffService] Fetching Format-10 PDF from: $uri');
      final response = await http.get(uri).timeout(const Duration(seconds: 40));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
      debugPrint('❌ [StaffService] Format-10 PDF failed: HTTP ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('❌ [StaffService] Format-10 PDF exception: $e');
      return null;
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  // 6. LOGIN
  // ═════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final uri = Uri.parse('$_baseUrl/login');

    final cleanUsername = username.trim();
    final cleanPassword = password.trim();

    if (cleanUsername.isEmpty) {
      return {'success': false, 'message': 'Staff username is required.'};
    }

    if (cleanPassword.isEmpty) {
      return {'success': false, 'message': 'Staff password is required.'};
    }

    final payload = {'username': cleanUsername, 'password': cleanPassword};

    try {
      debugPrint('🔐 [StaffService] Initiating login for: $cleanUsername');

      final response = await http
          .post(uri, headers: _headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 60));

      final data = _decodeJson(response);

      if (response.statusCode == 200) {
        final map = _safeMap(data);
        debugPrint('✅ [StaffService] Login response received.');

        return {
          'success': map['success'] ?? false,
          'already_logged_in': map['already_logged_in'] ?? false,
          'message': map['message'] ?? 'Staff portal login successful.',
          'url': map['url'],
        };
      }

      final errorMsg = _extractErrorMessage(data, response.statusCode, fallback: 'Authentication failed.');

      debugPrint('❌ [StaffService] Login error: $errorMsg');

      return {'success': false, 'message': errorMsg};
    } on FormatException catch (e) {
      debugPrint('❌ [StaffService] Login JSON exception: $e');
      return {'success': false, 'message': 'Invalid response received from Staff backend.'};
    } catch (e) {
      debugPrint('❌ [StaffService] Login network exception: $e');
      return {'success': false, 'message': 'Login connection failed: $e'};
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  // 7. STATUS
  // ═════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> checkStatus() async {
    final uri = Uri.parse('$_baseUrl/status');

    try {
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));

      final data = _decodeJson(response);

      if (response.statusCode == 200) {
        final map = _safeMap(data);

        return {
          'success': map['success'] ?? false,
          'connected': map['connected'] ?? false,
          'authenticated': map['authenticated'] ?? false,
          'url': map['url'],
          if (map['error'] != null) 'error': map['error'],
        };
      }

      return {
        'success': false,
        'connected': false,
        'authenticated': false,
        'error': _extractErrorMessage(data, response.statusCode, fallback: 'Status request failed.'),
      };
    } catch (e) {
      return {'success': false, 'connected': false, 'authenticated': false, 'error': '$e'};
    }
  }
}
