import 'dart:convert';
import 'package:http/http.dart' as http;
import 'backend_config.dart';

/// Read-only account data. Does not log in, submit tasks or retry portal writes.
class AccountService {
  static Future<Map<String, dynamic>> _get(String path, int seconds) async {
    final client = http.Client();
    try {
      final response = await client.get(BackendConfig.uri(path)).timeout(Duration(seconds: seconds));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return {'success': false};
      final result = Map<String, dynamic>.from(decoded);
      if (response.statusCode != 200) result['success'] = false;
      return result;
    } catch (_) {
      return {'success': false};
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> connections() => _get('/api/ecosystem/status', 8);
  static Future<Map<String, dynamic>> profile() => _get('/api/staff/profile', 30);
}
