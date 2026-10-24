import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/experiments/direct_portal_auth.dart';
import '../../lib/experiments/direct_school_session.dart';
import '../../lib/services/core/ecosystem_service.dart';
import '../../lib/services/portals/shaladarpan/direct/school_runtime.dart';
import '../../lib/services/portals/shaladarpan/student_service.dart';
import '../../lib/services/portals/staff_login/direct/staff_runtime.dart';
import '../../lib/services/portals/rajsims/direct/rajsims_runtime.dart';

void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

const _school = 'school-A', _password = 'password-A';
Map<String, String> _credentials() => {
  'school_id': _school,
  'school_password': _password,
  'staff_id': 'staff-A',
  'staff_password': 'staff-password-A',
  'sso_id': 'sso-A',
  'sso_password': 'sso-password-A',
};

class _BlockedHttpClient implements HttpClient {
  _BlockedHttpClient(this.onRequest);
  final void Function(Uri) onRequest;
  @override
  Duration? connectionTimeout;
  @override
  bool autoUncompress = true;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    onRequest(url);
    throw const SocketException('Offline test blocks outgoing requests');
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected HTTP client method ${invocation.memberName}',
  );
}

class _Fixture {
  _Fixture(this.runtime);
  final SchoolDirectRuntime runtime;
  final progressDone = Completer<void>();
  int progressCalls = 0, httpClientAttempts = 0;
  final requests = <Uri>[];
  Future<Map<String, dynamic>> login(
    Map<String, String> credentials, {
    bool valid = true,
  }) async {
    final result = await HttpOverrides.runZoned(
      () => EcosystemService.initialize(
        credentials,
        onProgress: (_, message) {
          progressCalls++;
          if (progressCalls == 3) progressDone.complete();
        },
      ),
      createHttpClient: (_) {
        httpClientAttempts++;
        return _BlockedHttpClient(requests.add);
      },
    );
    if (valid) await progressDone.future.timeout(const Duration(seconds: 5));
    return result;
  }
}

Future<void> _with(Future<void> Function(_Fixture) body) =>
    HttpOverrides.runZoned(
      () => _withOffline(body),
      createHttpClient: (_) => _BlockedHttpClient((_) {}),
    );
Future<void> _withOffline(Future<void> Function(_Fixture) body) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  EcosystemService.reset();
  DirectSchoolSession.reset();
  StudentService.directAttendanceEnabled = false;
  final memory = <String, String>{
    'rajshala.direct.sd.session_v2': jsonEncode({
      'version': 2,
      'active': {
        'user': _school,
        'session_id': 'verified-session-A',
        'server_base': 'https://rajshaladarpan.rajasthan.gov.in/SD1',
      },
      'cookies': {'ASP.NET_SessionId': 'cookie-A'},
    }),
  };
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    final args = call.arguments as Map, key = args['key'] as String;
    switch (call.method) {
      case 'read':
        return memory[key];
      case 'write':
        memory[key] = args['value'] as String;
        return null;
      case 'delete':
        memory.remove(key);
        return null;
      default:
        throw StateError('Unexpected storage call');
    }
  });
  SchoolDirectRuntime? runtime;
  DirectPortalAuth? original;
  try {
    runtime = await SchoolDirectRuntime.get();
    runtime.coordinator.rememberCredentials(_school, _password);
    runtime.coordinator.markAlive(runtime.coordinator.generation);
    final initial = await DirectPortalAuth.automaticLogin(
      user: _school,
      password: _password,
    );
    original = initial.auth;
    _check(
      initial.result.success && original != null,
      'Could not seed verified existing session',
    );
    DirectSchoolSession.attach(original!, _school);
    StudentService.directAttendanceEnabled = true;
    await body(_Fixture(runtime));
  } finally {
    EcosystemService.reset();
    DirectSchoolSession.reset();
    StudentService.directAttendanceEnabled = false;
    if (runtime != null) await runtime.close();
    await StaffDirectRuntime.reset();
    await RajsimsDirectRuntime.reset();
    original?.close();
    messenger.setMockMethodCallHandler(channel, null);
  }
}

Map<String, Future<void> Function()> schoolReuseCases() => {
  'ecosystem changed School password cannot bypass authentication via retained ID':
      () => _with((f) async {
        final credentials = _credentials()
          ..['school_password'] = 'changed-password';
        final result = await f.login(credentials);
        _check(
          result['success'] == false,
          'Changed School password was ignored and dashboard admitted',
        );
        final school = (result['portals'] as Map)['shaladarpan'] as Map;
        _check(
          school['success'] == false && school['state'] == 'failed',
          'Changed password reported School ready',
        );
        _check(
          f.runtime.auth.sessionIdentity == null,
          'Changed password never reached fresh School authentication',
        );
        _check(
          f.requests.isNotEmpty,
          'Changed password never reached the offline transport boundary',
        );
      }),
  'ecosystem closed School coordinator cannot be retained as ready': () =>
      _with((f) async {
        await f.runtime.coordinator.shutdown(timeout: 1);
        _check(
          DirectSchoolSession.ready,
          'Test requires the existing adapter view to remain attached',
        );
        final result = await f.login(_credentials());
        _check(
          result['success'] == false,
          'Closed School runtime opened dashboard through ready shortcut',
        );
        _check(
          (result['portals'] as Map)['shaladarpan']['success'] == false,
          'Closed runtime reported School live',
        );
      }),
  'ecosystem unchanged School credentials reuse live coordinator without School requests':
      () => _with((f) async {
        final generation = f.runtime.coordinator.generation;
        final result = await f.login(_credentials());
        _check(
          result['success'] == true,
          'Healthy same-account session was discarded',
        );
        _check(
          f.runtime.coordinator.generation == generation,
          'Healthy session was re-authenticated',
        );
        _check(
          f.runtime.auth.loadSessionCookies()['ASP.NET_SessionId'] ==
              'cookie-A',
          'Healthy cookies changed',
        );
        _check(
          DirectSchoolSession.ready && StudentService.directAttendanceEnabled,
          'Healthy session was not attached',
        );
        // Any School client attempt would fail this offline login; Staff/SSO run independently.
      }),
  'ecosystem Staff-only password change preserves unchanged School session':
      () => _with((f) async {
        final credentials = _credentials()
          ..['staff_password'] = 'changed-staff-password';
        final generation = f.runtime.coordinator.generation;
        final result = await f.login(credentials);
        _check(
          result['success'] == true &&
              f.runtime.coordinator.generation == generation,
          'Staff-only password edit re-authenticated or rejected School',
        );
      }),
  'ecosystem School ID whitespace remains normalized by shared authentication':
      () => _with((f) async {
        final result = await f.login(
          _credentials()..['school_id'] = '  school-A  ',
        );
        _check(
          result['success'] == true && DirectSchoolSession.schoolId == _school,
          'School ID trim compatibility changed',
        );
      }),
  'ecosystem missing password rejects before touching live School session':
      () => _with((f) async {
        final generation = f.runtime.coordinator.generation;
        final result = await f.login(
          _credentials()..['school_password'] = '',
          valid: false,
        );
        _check(
          result['success'] == false && result['code'] == 'EMPTY_CREDENTIALS',
          'Missing password was accepted',
        );
        _check(
          f.runtime.coordinator.generation == generation &&
              DirectSchoolSession.ready,
          'Invalid input disturbed live session',
        );
        _check(
          f.progressCalls == 0 && f.httpClientAttempts == 0,
          'Invalid input started authentication',
        );
      }),
};
