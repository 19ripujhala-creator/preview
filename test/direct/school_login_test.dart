import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/experiments/direct_portal_auth.dart';
import '../../lib/experiments/direct_school_session.dart';
import '../../lib/services/portals/shaladarpan/school_login_service.dart';
import '../../lib/services/portals/shaladarpan/student_service.dart';

class RestoredSchoolAuth extends DirectPortalAuth {
  RestoredSchoolAuth({this.school = '123456', this.verified = true});
  final String school;
  final bool verified;
  bool closed = false;
  @override
  bool get isVerified => verified && !closed;
  @override
  String? get authenticatedSchoolId => school;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String? mode;
  late bool signedOut, current;
  late Map<String, String> credentials;
  late RestoredSchoolAuth auth;
  late Completer<void>? gate;
  late Map<String, dynamic> source;
  late bool loginSuccess;
  late int calls;
  late SchoolLoginService service;
  late String sentUser, sentPassword;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DirectSchoolSession.reset();
    StudentService.directAttendanceEnabled = false;
    mode = 'direct';
    signedOut = false;
    current = true;
    credentials = {'id': ' 123456 ', 'pass': ' school password '};
    auth = RestoredSchoolAuth();
    gate = null;
    calls = 0;
    sentUser = sentPassword = '';
    loginSuccess = true;
    source = {
      'success': true,
      'cached': true,
      'server_name': 'SD3',
      'message': 'Saved session reused.',
    };
    service = SchoolLoginService(
      readMode: () async => mode,
      signedOut: () async => signedOut,
      credentials: () async => Map.of(credentials),
      authenticate: ({required user, required password}) async {
        calls++;
        sentUser = user;
        sentPassword = password;
        await gate?.future;
        return (
          auth: auth,
          result: DirectLoginResult(
            loginSuccess,
            'diagnostic fallback',
            'SD3',
            5,
            response: source,
          ),
        );
      },
    );
  });

  tearDown(() {
    DirectSchoolSession.reset();
    auth.close();
    StudentService.directAttendanceEnabled = false;
  });

  Future<Map<String, dynamic>> restore() =>
      service.restore(isCurrent: () => current);

  Future<void> beginPending() async {
    while (calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'direct selection persists and explicit backend selection replaces it',
    () async {
      await SchoolLoginService.rememberMode(direct: true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SchoolLoginService.modeKey), 'direct');
      await SchoolLoginService.rememberMode(direct: false);
      expect(prefs.getString(SchoolLoginService.modeKey), 'backend');
    },
  );

  test(
    'cold start transfers one verified saved session to every School module',
    () async {
      expect(await restore(), {...source, 'school_id': '123456'});
      expect(calls, 1);
      expect(sentUser, '123456');
      expect(sentPassword, ' school password ');
      expect(StudentService.directAttendanceEnabled, isTrue);
      expect(DirectSchoolSession.schoolId, '123456');
      expect(DirectSchoolSession.attendance, isNotNull);
      expect(DirectSchoolSession.staffAttendance, isNotNull);
      expect(DirectSchoolSession.leaveApprovals, isNotNull);
      expect(DirectSchoolSession.nativePrint, isNotNull);
      expect(auth.closed, isFalse);
    },
  );

  for (final selection in <String?>[null, 'backend']) {
    test('non-direct selection $selection does not authenticate', () async {
      mode = selection;
      expect((await restore())['code'], 'DIRECT_MODE_NOT_SELECTED');
      expect(calls, 0);
      expect(DirectSchoolSession.ready, isFalse);
    });
  }

  test('explicit logout prevents saved authentication', () async {
    signedOut = true;
    expect((await restore())['code'], 'SIGNED_OUT');
    expect(calls, 0);
  });

  for (final key in ['id', 'pass']) {
    test(
      'missing School $key does not authenticate or require other portals',
      () async {
        credentials[key] = '';
        expect((await restore())['code'], 'NO_CREDENTIALS');
        expect(calls, 0);
      },
    );
  }

  test('invalid root epoch prevents authentication', () async {
    current = false;
    expect((await restore())['code'], 'LOGIN_CANCELLED');
    expect(calls, 0);
  });

  test(
    'portal login failure retains exact code, text and provenance',
    () async {
      loginSuccess = false;
      source = {
        'success': false,
        'code': 'INVALID_CREDENTIALS',
        'portal_message': 'यूजर नाम अथवा पासवर्ड गलत है।',
        'message': 'source backend text',
        'message_source': 'portal',
      };
      expect(await restore(), {...source, 'message': source['portal_message']});
      expect(DirectSchoolSession.ready, isFalse);
      expect(auth.closed, isTrue);
    },
  );

  for (final change in ['id', 'pass', 'mode', 'logout', 'epoch']) {
    test('pending login discards result after $change changes', () async {
      gate = Completer<void>();
      final task = restore();
      await beginPending();
      switch (change) {
        case 'id':
          credentials['id'] = '654321';
        case 'pass':
          credentials['pass'] = 'new password';
        case 'mode':
          mode = 'backend';
        case 'logout':
          signedOut = true;
        case 'epoch':
          current = false;
      }
      gate!.complete();
      final result = await task;
      expect(
        result['code'],
        change == 'mode'
            ? 'MODE_CHANGED'
            : ['id', 'pass'].contains(change)
            ? 'ACCOUNT_CHANGED'
            : 'LOGIN_CANCELLED',
      );
      expect(DirectSchoolSession.ready, isFalse);
      expect(StudentService.directAttendanceEnabled, isFalse);
      expect(auth.closed, isTrue);
    });
  }

  test(
    'success flag without verified session does not open dashboard',
    () async {
      auth.close();
      auth = RestoredSchoolAuth(verified: false);
      expect((await restore())['code'], 'SESSION_EXPIRED');
      expect(DirectSchoolSession.ready, isFalse);
    },
  );

  test('verified session for another School is rejected', () async {
    auth.close();
    auth = RestoredSchoolAuth(school: '654321');
    expect((await restore())['code'], 'SESSION_EXPIRED');
    expect(DirectSchoolSession.ready, isFalse);
  });

  test(
    'second startup cannot start a duplicate login while the first is pending',
    () async {
      gate = Completer<void>();
      final task = restore();
      await beginPending();
      expect((await restore())['code'], 'LOGIN_BUSY');
      expect(calls, 1);
      gate!.complete();
      expect((await task)['success'], isTrue);
    },
  );

  test(
    'local runtime failure stays a direct error and releases startup guard',
    () async {
      int attempts = 0;
      final failing = SchoolLoginService(
        readMode: () async => 'direct',
        signedOut: () async => false,
        credentials: () async => credentials,
        authenticate: ({required user, required password}) async {
          attempts++;
          throw StateError('offline device failure');
        },
      );
      expect(
        (await failing.restore(isCurrent: () => true))['code'],
        'DIRECT_LOGIN_ERROR',
      );
      expect(
        (await failing.restore(isCurrent: () => true))['code'],
        'DIRECT_LOGIN_ERROR',
      );
      expect(attempts, 2);
      expect(StudentService.directAttendanceEnabled, isFalse);
    },
  );
}
