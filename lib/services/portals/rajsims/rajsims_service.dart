import 'package:shaladarpan/services/core/backend_config.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/dashboard_bootstrap.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class RajsimsService {
  // ============================================================
  // BASE URL
  // ============================================================
  //
  // Windows/Desktop Flutter:
  //    127.0.0.1:7860
  //
  // Android Emulator:
  //    10.0.2.2:7860
  //
  // Physical Android device:
  //    PC ka LAN IP, e.g. 192.168.1.100:7860
  //
  static String get baseUrl => '${BackendConfig.baseUrl}/api/rajsims';

  // ============================================================
  // TIMEOUTS
  // ============================================================

  static const Duration _stockTimeout = Duration(seconds: 15);
  static const Duration _fetchTimeout = Duration(seconds: 45);
  static const Duration _listTimeout = Duration(seconds: 60);
  static const Duration _submitTimeout = Duration(seconds: 45);
  static const Duration _entryTimeout = Duration(seconds: 45);
  static const Duration _updateTimeout = Duration(seconds: 45);

  // ============================================================
  // COMMON HEADERS
  // ============================================================

  static const Map<String, String> _jsonHeaders = {'Content-Type': 'application/json', 'Accept': 'application/json'};

  static const Map<String, String> _acceptHeaders = {'Accept': 'application/json'};

  // ============================================================
  // RESPONSE HELPERS
  // ============================================================

  /// Backend response ko safely Map<String, dynamic> mein convert karta hai.
  static Map<String, dynamic> _parseResponse(http.Response response) {
    final statusCode = response.statusCode;
    final body = response.body.trim();

    Map<String, dynamic>? decoded;

    if (body.isNotEmpty) {
      try {
        final dynamic json = jsonDecode(body);

        if (json is Map) {
          decoded = Map<String, dynamic>.from(json);
        }
      } catch (e) {
        debugPrint('RajSIMS JSON Parse Error (HTTP $statusCode): $e');
      }
    }

    // ------------------------------------------------------------
    // Successful HTTP response
    // ------------------------------------------------------------
    if (statusCode >= 200 && statusCode < 300) {
      if (decoded != null) {
        return decoded;
      }

      return {
        'success': false,
        'code': 'INVALID_RESPONSE',
        'message': 'Backend returned no valid JSON response.',
        'status_code': statusCode,
      };
    }

    // ------------------------------------------------------------
    // Backend ne JSON error diya hai
    // ------------------------------------------------------------
    if (decoded != null) {
      final result = Map<String, dynamic>.from(decoded);

      result['success'] = false;
      result['status_code'] = statusCode;

      if (!_hasUsableValue(result['message']) && _hasUsableValue(result['detail'])) {
        result['message'] = _extractDetail(result['detail']);
      }

      if (!_hasUsableValue(result['message'])) {
        result['message'] = 'Server error: HTTP $statusCode';
      }

      return result;
    }

    // ------------------------------------------------------------
    // Non-JSON server error
    // ------------------------------------------------------------
    return {'success': false, 'status_code': statusCode, 'message': _serverErrorMessage(statusCode)};
  }

  /// Generic request exception ko user-friendly response mein convert karta hai.
  static Map<String, dynamic> _handleException(Object error, String operation) {
    debugPrint('$operation Error: $error');

    if (error is TimeoutException) {
      return {'success': false, 'error_type': 'timeout', 'message': '$operation timed out. Server response nahi mila.'};
    }

    if (error is http.ClientException) {
      return {
        'success': false,
        'error_type': 'network',
        'message': 'Server se connection nahi ho pa raha. Backend/API running hai ya nahi check karein.',
      };
    }

    return {'success': false, 'error_type': 'unknown', 'message': '$operation failed: $error'};
  }

  static bool _hasUsableValue(dynamic value) {
    if (value == null) return false;

    if (value is String) {
      return value.trim().isNotEmpty;
    }

    return true;
  }

  static String _extractDetail(dynamic detail) {
    if (detail is String) {
      return detail;
    }

    if (detail is Map) {
      final map = Map<String, dynamic>.from(detail);

      final message = map['message'];
      if (_hasUsableValue(message)) {
        return message.toString();
      }

      final error = map['error'];
      if (_hasUsableValue(error)) {
        return error.toString();
      }
    }

    if (detail is List) {
      return detail.map((item) => item.toString()).join(', ');
    }

    return detail.toString();
  }

  static String _serverErrorMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Invalid request.';
      case 401:
        return 'RajSIMS authentication required.';
      case 403:
        return 'RajSIMS access denied.';
      case 404:
        return 'RajSIMS API endpoint not found.';
      case 408:
        return 'Request timeout.';
      case 409:
        return 'Request conflict.';
      case 422:
        return 'Invalid data submitted.';
      case 429:
        return 'Too many requests. Please try again later.';
      case 500:
        return 'Backend server error.';
      case 502:
        return 'Backend gateway error.';
      case 503:
        return 'RajSIMS service is temporarily unavailable.';
      case 504:
        return 'Backend gateway timed out.';
      default:
        return 'Server error: HTTP $statusCode';
    }
  }

  // ============================================================
  // 1. STOCK
  // ============================================================

  /// FAST API: Sirf Dashboard ka stock instantly lane ke liye.
  static Future<Map<String, dynamic>> fetchStockData() async {
    try {
      final uri = Uri.parse('$baseUrl/mdm/stock');

      final response = await http.get(uri, headers: _acceptHeaders).timeout(_stockTimeout);

      return _parseResponse(response);
    } catch (e) {
      return _handleException(e, 'Stock Fetch');
    }
  }

  // ============================================================
  // 2. COMBINED MDM DATA
  // ============================================================

  /// Stock + Status lane ke liye.
  static Future<Map<String, dynamic>> fetchMdmData({bool force = false}) async {
    try {
      final school = (await SecureStorageService.getShaladarpanCreds())['id']?.trim() ?? '';
      if (school.isEmpty) return {'success': false, 'message': 'School login is required.'};
      return await DashboardBootstrap.loadMdm(school, fresh: force);
    } catch (e) {
      return _handleException(e, 'MDM Fetch');
    }
  }

  // ============================================================
  // 3. DISTRIBUTION LIST
  // ============================================================

  /// Normal ya Legacy distribution list fetch karne ke liye.
  static Future<Map<String, dynamic>> fetchMdmList({bool isLegacy = false, bool force = false}) async {
    try {
      final Map<String, String> queryParameters = {'legacy': isLegacy.toString()};

      if (force) {
        queryParameters['force'] = 'true';
      }

      final uri = Uri.parse('$baseUrl/mdm/list').replace(queryParameters: queryParameters);

      final response = await http.get(uri, headers: _acceptHeaders).timeout(_listTimeout);

      final result = _parseResponse(response);

      if (result['success'] != true && !result.containsKey('records')) {
        result['records'] = <dynamic>[];
      }

      return result;
    } catch (e) {
      return {..._handleException(e, 'List Fetch'), 'records': <dynamic>[]};
    }
  }

  // ============================================================
  // 4. SUBMIT DISTRIBUTION (AUTO LEGACY DETECTION)
  // ============================================================

  /// Nayi distribution entry submit karne ke liye (Normal & Legacy).
  static Future<Map<String, dynamic>> submitDistribution(Map<String, dynamic> payload) async {
    try {
      final finalPayload = Map<String, dynamic>.from(payload);

      // Agar legacy_date maujood hai aur khali nahi hai, to automatically 'legacy: true' set karein
      if (finalPayload.containsKey('legacy_date') &&
          finalPayload['legacy_date'] != null &&
          finalPayload['legacy_date'].toString().trim().isNotEmpty) {
        finalPayload['legacy'] = true;
      }

      final response = await http
          .post(Uri.parse('$baseUrl/mdm/submit'), headers: _jsonHeaders, body: jsonEncode(finalPayload))
          .timeout(_submitTimeout);

      return _parseResponse(response);
    } catch (e) {
      return _handleException(e, 'Distribution Submit');
    } finally {
      DashboardBootstrap.invalidateMdm();
    }
  }

  /// Explicit Legacy Submit Helper
  static Future<Map<String, dynamic>> submitLegacyDistribution(Map<String, dynamic> payload) async {
    final legacyPayload = Map<String, dynamic>.from(payload);
    legacyPayload['legacy'] = true;
    return submitDistribution(legacyPayload);
  }

  // ============================================================
  // 5. ENTRY DETAILS
  // ============================================================

  /// Kisi existing distribution entry ki details fetch karta hai.
  static Future<Map<String, dynamic>> fetchEntryDetails(String distNo, {bool isLegacy = false}) async {
    try {
      final cleanedDistNo = distNo.trim();

      if (cleanedDistNo.isEmpty) {
        return {'success': false, 'error_type': 'validation', 'message': 'Distribution number is required.'};
      }

      final uri = Uri.parse('$baseUrl/mdm/entry')
          .replace(queryParameters: {'dist_no': cleanedDistNo, 'legacy': isLegacy.toString()});

      final response = await http.get(uri, headers: _acceptHeaders).timeout(_entryTimeout);

      return _parseResponse(response);
    } catch (e) {
      return _handleException(e, 'Entry Fetch');
    }
  }

  // ============================================================
  // 6. UPDATE DISTRIBUTION
  // ============================================================

  /// Existing distribution entry update karta hai.
  static Future<Map<String, dynamic>> updateDistribution(Map<String, dynamic> payload) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/mdm/update'), headers: _jsonHeaders, body: jsonEncode(payload))
          .timeout(_updateTimeout);

      return _parseResponse(response);
    } catch (e) {
      return _handleException(e, 'Distribution Update');
    } finally {
      DashboardBootstrap.invalidateMdm();
    }
  }
}
