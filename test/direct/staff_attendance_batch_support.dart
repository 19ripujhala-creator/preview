import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shaladarpan/services/portals/shaladarpan/shaladarpan_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/student_service.dart';

String attendanceDate([DateTime? time]) {
  final d = (time ?? DateTime.now()).toUtc().add(
    const Duration(hours: 5, minutes: 30),
  );
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

List<Map<String, dynamic>> attendanceRows() => [
  {
    'staffId': '101',
    'sno': '1',
    'name': 'Employee One',
    'status_code': '2',
    'status': 'Present',
    'original_status': 'Present',
    'editable': true,
    'options': [
      {'code': '2', 'label': 'Present'},
      {'code': '9', 'label': 'Not Present'},
    ],
  },
  {
    'staffId': '102',
    'sno': '2',
    'name': 'Employee Two',
    'status_code': null,
    'status': 'CL',
    'original_status': 'CL',
    'editable': false,
    'options': [],
    'appliedLeave': 'CL',
    'isApprovedLeave': true,
  },
];
Map<String, dynamic> attendanceDocument({
  bool marked = false,
  String school = '123456',
  String? date,
}) => {
  'success': true,
  'school_id': school,
  'date': date ?? attendanceDate(),
  'is_already_marked': marked,
  'attendance_verified': marked,
  'attendance_status': marked ? 'marked' : 'pending',
  'portal_marking_text': '',
  'marked_at': null,
  'staff': attendanceRows(),
};
Map<String, dynamic> attendanceSuccess([Map<String, dynamic>? doc]) => {
  'success': true,
  'attendance_verified': true,
  'is_already_marked': true,
  'submission_attempted': true,
  'message': 'Native attendance accepted.',
  'portal_message': 'Native attendance accepted.',
  'message_source': 'portal',
  'data': doc ?? attendanceDocument(marked: true),
};
http.Response attendanceResponse(Map<String, dynamic> data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json'},
);

class AttendanceStore extends InMemorySharedPreferencesStore {
  AttendanceStore() : super.empty();
  bool failHold = false, failDraft = false;
  @override
  Future<bool> setValue(String type, String key, Object value) {
    if ((failHold &&
            key.contains('attendance_submission_hold_') &&
            value == true) ||
        (failDraft && key.endsWith('offline_attendance_queue_payload')))
      return Future.value(false);
    return super.setValue(type, key, value);
  }
}

class AttendanceFixture {
  final credentials = <String, String>{
    'shala_id': '123456',
    'shala_pass': 'password',
  };
  final requests = <http.Request>[];
  final store = AttendanceStore();
  late Future<http.Response> Function(http.Request) respond;
  Future<void> setup() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'saved_school_id': '123456'});
    final prefs = await SharedPreferences.getInstance();
    SharedPreferencesStorePlatform.instance = store;
    await prefs.setString('saved_school_id', '123456');
    StudentService.directAttendanceEnabled = false;
    ShaladarpanService.invalidateStaffSnapshot();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args = call.arguments as Map;
            if (call.method == 'read' && args['key'] == 'portal_credentials_v2')
              return jsonEncode(credentials);
            return null;
          },
        );
    respond = (request) async => attendanceResponse(
      request.url.path.endsWith('/submit')
          ? attendanceSuccess()
          : {'success': true, 'data': attendanceDocument()},
    );
  }

  Future<T> run<T>(Future<T> Function() body) => http.runWithClient(
    body,
    () => MockClient((request) async {
      requests.add(request);
      return respond(request);
    }),
  );
  Future<void> close() async {
    ShaladarpanService.invalidateStaffSnapshot();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  }

  String get hold => 'attendance_submission_hold_123456_${attendanceDate()}';
  Future<Map<String, dynamic>> submit() =>
      ShaladarpanService.submitStaffAttendance(
        attendanceRows(),
        schoolId: '123456',
      );
}
