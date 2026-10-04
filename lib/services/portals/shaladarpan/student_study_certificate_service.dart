import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shaladarpan/services/core/backend_config.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';

class StudyCertificateFile {
  final Uint8List bytes;
  final String filename;
  const StudyCertificateFile(this.bytes, this.filename);
}

class StudentStudyCertificateService {
  static String get _base => '${BackendConfig.baseUrl}/api/student/study-certificate';

  static Future<String> _school() async {
    final creds = await SecureStorageService.getShaladarpanCreds();
    final school = creds['id']?.trim() ?? '';
    if (school.isEmpty) throw const FormatException('Sign in to the school portal first.');
    return school;
  }

  static Map<String, dynamic> _json(String value) {
    final result = jsonDecode(value);
    if (result is! Map) throw const FormatException('Invalid certificate response.');
    return Map<String, dynamic>.from(result);
  }

  static String _message(Map<String, dynamic> data) {
    final detail = data['detail'];
    if (detail is Map && detail['message'] != null) return '${detail['message']}';
    if (detail is String && detail.isNotEmpty) return detail;
    return '${data['message'] ?? 'The certificate response could not be downloaded.'}';
  }

  static Future<void> _sameSchool(String school, Map<String, dynamic> data) async {
    if (await _school() != school || '${data['school_id']}' != school) {
      throw const FormatException('School account changed. Open the Study Certificate again.');
    }
  }

  static Future<StudyCertificateFile> download({required String srNo, required String expectedSchool, required void Function(double) onProgress}) async {
    final school = await _school();
    if (school != expectedSchool) throw const FormatException('School account changed. Open the Study Certificate again.');
    final client = http.Client();
    try {
      final data = await _download(client, school, srNo, onProgress).timeout(const Duration(minutes: 3));
      await _sameSchool(school, data);
      if ('${data['sr_no']}' != srNo) throw const FormatException('Certificate response does not match the requested SR number.');
      if (data['success'] != true || data['pdf_base64'] is! String) throw FormatException(_message(data));
      final bytes = base64Decode(data['pdf_base64'] as String);
      if (bytes.length < 5 || ascii.decode(bytes.sublist(0, 5), allowInvalid: true) != '%PDF-') {
        throw const FormatException('The server did not return a valid PDF.');
      }
      onProgress(1);
      return StudyCertificateFile(bytes, '${data['filename'] ?? 'Student_Study_Certificate.pdf'}');
    } finally { client.close(); }
  }

  static Future<Map<String, dynamic>> _download(http.Client client, String school, String srNo,
      void Function(double) onProgress) async {
    final request = http.Request('POST', Uri.parse('$_base/pdf'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'school_id': school, 'sr_no': srNo});
    final response = await client.send(request);
    if (response.statusCode != 200) throw FormatException(_message(_json(await response.stream.bytesToString())));
    if (!(response.headers['content-type'] ?? '').contains('application/x-ndjson')) {
      throw const FormatException('The backend Study Certificate module must be updated before downloading.');
    }
    await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final event = _json(line);
      if (event['type'] == 'progress') {
        final completed = event['completed'], total = event['total'];
        if (completed is int && total is int && total > 0 && completed >= 0 && completed <= total) {
          onProgress(.1 + .75 * completed / total);
        }
      } else if (event['type'] == 'result') {
        if (event['data'] is! Map) throw const FormatException('Invalid certificate response.');
        return Map<String, dynamic>.from(event['data'] as Map);
      } else if (event['type'] == 'error') {
        throw FormatException(_message(event));
      }
    }
    throw const FormatException('The connection ended before the certificate PDF was ready.');
  }
}
