import '../../../experiments/direct_school_session.dart';
import 'student_service.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shaladarpan/services/core/backend_config.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';

class NicSheetFile {
  final Uint8List bytes;
  final String filename;
  const NicSheetFile(this.bytes, this.filename);
}

class StudentNicService {
  static String get _base => '${BackendConfig.baseUrl}/api/student/nic';

  static Future<String> _school() async {
    final creds = await SecureStorageService.getShaladarpanCreds();
    final school = creds['id']?.trim() ?? '';
    if (school.isEmpty)
      throw const FormatException('Sign in to the school portal first.');
    return school;
  }

  static Map<String, dynamic> _json(String value) {
    final result = jsonDecode(value);
    if (result is! Map)
      throw const FormatException('Invalid NIC report response.');
    return Map<String, dynamic>.from(result);
  }

  static String _message(Map<String, dynamic> data) {
    final detail = data['detail'];
    if (detail is Map && detail['message'] != null)
      return '${detail['message']}';
    if (detail is String && detail.isNotEmpty) return detail;
    return '${data['message'] ?? 'The NIC report could not be downloaded.'}';
  }

  static Future<void> _sameSchool(
    String school,
    Map<String, dynamic> data,
  ) async {
    if (await _school() != school || '${data['school_id']}' != school) {
      throw const FormatException(
        'School account changed. Open the NIC directory again.',
      );
    }
  }

  static Future<Map<String, dynamic>> catalog() async {
    final school = await _school();
    if (StudentService.directAttendanceEnabled) {
      final service = DirectSchoolSession.nicCatalog;
      if (service == null || DirectSchoolSession.schoolId != school)
        throw const FormatException('Direct School login is required.');
      final data = await service.catalog(school);
      if (!StudentService.directAttendanceEnabled ||
          !identical(service, DirectSchoolSession.nicCatalog))
        throw const FormatException(
          'School account changed. Open the NIC directory again.',
        );
      if (data['success'] != true) throw FormatException(_message(data));
      await _sameSchool(school, data);
      return data;
    }
    final client = http.Client();
    try {
      final response = await client
          .get(
            Uri.parse('$_base/catalog')
                .replace(queryParameters: {'school_id': school}),
          )
          .timeout(const Duration(seconds: 70));
      final data = _json(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || data['success'] != true)
        throw FormatException(_message(data));
      await _sameSchool(school, data);
      if (data['classes'] is! List || (data['classes'] as List).isEmpty) {
        throw const FormatException(
          'No classes were returned by the school portal.',
        );
      }
      return data;
    } finally {
      client.close();
    }
  }

  static Future<NicSheetFile> download({
    String? classId,
    required String expectedSchool,
    required void Function(double) onProgress,
  }) async {
    final school = await _school();
    if (school != expectedSchool)
      throw const FormatException(
        'School account changed. Open the NIC directory again.',
      );
    if (StudentService.directAttendanceEnabled) {
      final service = DirectSchoolSession.nativePrint;
      if (service == null || DirectSchoolSession.schoolId != school)
        throw const FormatException('Direct School login is required.');
      final data = await service.nicPdf(
        school,
        classId: classId,
        progress: (completed, total) {
          if (total > 0) onProgress(.1 + .75 * completed / total);
        },
      );
      if (!StudentService.directAttendanceEnabled ||
          !identical(service, DirectSchoolSession.nativePrint))
        throw const FormatException(
          'School account changed. Open the NIC directory again.',
        );
      if (data['success'] != true || data['pdf_base64'] is! String)
        throw FormatException(_message(data));
      await _sameSchool(school, data);
      final bytes = base64Decode(data['pdf_base64'] as String);
      if (bytes.length < 5 ||
          ascii.decode(bytes.sublist(0, 5), allowInvalid: true) != '%PDF-')
        throw const FormatException('Portal print did not return a valid PDF.');
      onProgress(1);
      return NicSheetFile(bytes, '${data['filename']}');
    }
    final client = http.Client();
    try {
      final data = await _download(
        client,
        school,
        classId,
        onProgress,
      ).timeout(const Duration(minutes: 11));
      await _sameSchool(school, data);
      if (data['success'] != true || data['pdf_base64'] is! String)
        throw FormatException(_message(data));
      final bytes = base64Decode(data['pdf_base64'] as String);
      if (bytes.length < 5 ||
          ascii.decode(bytes.sublist(0, 5), allowInvalid: true) != '%PDF-') {
        throw const FormatException('The server did not return a valid PDF.');
      }
      onProgress(1);
      return NicSheetFile(
        bytes,
        '${data['filename'] ?? 'Student_NIC_Sheet.pdf'}',
      );
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> _download(
    http.Client client,
    String school,
    String? classId,
    void Function(double) onProgress,
  ) async {
    final request = http.Request('POST', Uri.parse('$_base/pdf'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'school_id': school,
        if (classId != null) 'class_id': classId,
      });
    final response = await client.send(request);
    if (response.statusCode != 200)
      throw FormatException(
        _message(_json(await response.stream.bytesToString())),
      );
    if (!(response.headers['content-type'] ?? '').contains(
      'application/x-ndjson',
    )) {
      throw const FormatException(
        'The backend NIC module must be updated before downloading.',
      );
    }
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final event = _json(line);
      if (event['type'] == 'progress') {
        final completed = event['completed'], total = event['total'];
        if (completed is int &&
            total is int &&
            total > 0 &&
            completed >= 0 &&
            completed <= total) {
          onProgress(.1 + .75 * completed / total);
        }
      } else if (event['type'] == 'result') {
        if (event['data'] is! Map)
          throw const FormatException('Invalid NIC report response.');
        return Map<String, dynamic>.from(event['data'] as Map);
      } else if (event['type'] == 'error') {
        throw FormatException(_message(event));
      }
    }
    throw const FormatException(
      'The connection ended before the NIC PDF was ready.',
    );
  }
}
