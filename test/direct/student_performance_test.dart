import 'dart:async';
import 'dart:convert';

import 'package:shaladarpan/experiments/direct_school_session.dart';

import 'student_worker_test.dart' show FakeAuth, FakePortal, students, date;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/auth_manager.dart';
import 'package:shaladarpan/services/portals/shaladarpan/student_service.dart';

class SaveAuth extends FakeAuth {
  SaveAuth(super.portal);
  String identity = 'fixture-session';
  @override
  String get authenticatedSchoolId => '123';
  @override
  String get schoolSessionIdentity => identity;
}

class RecordingStorage implements SchoolAuthStorage {
  final values = <String, String>{};
  final writes = <String>[];
  bool fail = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    writes.add(value);
    if (fail) throw StateError('synthetic write failure');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final binding =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var records = <String, String>{};
  var reads = 0;
  Completer<void>? readGate, writeGate;
  String record(String id) => jsonEncode({
    'shala_id': id,
    'shala_pass': 'fixture',
    'staff_id': 'staff',
    'staff_pass': 'fixture',
    'rajsims_id': 'sso',
    'rajsims_pass': 'fixture',
  });
  setUp(() {
    DirectSchoolSession.reset();
    StudentService.directAttendanceEnabled = false;
    SecureStorageService.invalidateSchoolIdentity();
    SharedPreferences.setMockInitialValues({});
    records = {'portal_credentials_v2': record('123')};
    reads = 0;
    readGate = null;
    writeGate = null;
    binding.setMockMethodCallHandler(channel, (call) async {
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      final key = args['key'] as String;
      if (call.method == 'read') {
        reads++;
        final value = records[key];
        if (readGate != null) await readGate!.future;
        return value;
      }
      if (call.method == 'write') {
        if (writeGate != null) await writeGate!.future;
        records[key] = args['value'] as String;
        return null;
      }
      if (call.method == 'delete') {
        records.remove(key);
        return null;
      }
      throw StateError('Unexpected method ${call.method}');
    });
  });
  tearDown(() {
    DirectSchoolSession.reset();
    StudentService.directAttendanceEnabled = false;
    binding.setMockMethodCallHandler(channel, null);
    SecureStorageService.invalidateSchoolIdentity();
  });
  Future<void> save(String id) => SecureStorageService.saveAllPortals(
    shalaId: id,
    shalaPass: 'fixture',
    staffId: 'staff',
    staffPass: 'fixture',
    rajsimsId: 'sso',
    rajsimsPass: 'fixture',
  );
  Map<String, dynamic> payload() => {
    'class_id': '1',
    'section': '1A',
    'date': date,
    'students': students,
  };
  test('review: class-only Save cannot bypass a section-specific unresolved hold', () async {
    final p = FakePortal();
    DirectSchoolSession.attach(SaveAuth(p), '123');
    StudentService.directAttendanceEnabled = true;
    final prefs = await SharedPreferences.getInstance();
    final key = 'student_submission_hold/123/$date/1a';
    await prefs.setString(key, jsonEncode({'created_at': 1, 'expected': students}));
    final request = payload()..remove('section');
    final result = await StudentService.saveAttendance(request);
    expect(p.saves, 0, reason: 'Previous uncertain Save must block another POST. Section hold remains: ${prefs.containsKey(key)}. $result');
    expect(result['submission_on_hold'], true);
    expect(prefs.containsKey(key), true);
  });
  test('review: section-qualified read and reconciliation recognize class-only hold', () async {
    final p = FakePortal();
    DirectSchoolSession.attach(SaveAuth(p), '123');
    StudentService.directAttendanceEnabled = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('student_submission_hold/123/$date/1', jsonEncode({'created_at': 1, 'expected': students}));
    final result = await StudentService.fetchAttendance(classId: '1A', date: date, section: '1A');
    expect(result['success'], true, reason: '$result');
    expect(result['submission_on_hold'], true, reason: 'Changing class spelling must retain the hold');
    final checked = await StudentService.checkPreviousSubmission(classId: '1A', date: date, section: '1A');
    expect(checked['resolved'], isNot('not_held'));
    expect(p.saves, 0);
  });
  test('review: checking section alias cannot claim a class-only hold is absent', () async {
    final p = FakePortal();
    DirectSchoolSession.attach(SaveAuth(p), '123');
    StudentService.directAttendanceEnabled = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('student_submission_hold/123/$date/1', jsonEncode({'created_at': 1, 'expected': students}));
    final checked = await StudentService.checkPreviousSubmission(classId: '1A', date: date, section: '1A');
    expect(checked['resolved'], isNot('not_held'), reason: '$checked');
    expect(p.saves, 0);
  });
  test('uncertain class-only Save remains held for its explicit section', () async {
    final p = FakePortal()..timeoutSave=true;
    DirectSchoolSession.attach(SaveAuth(p),'123'); StudentService.directAttendanceEnabled=true;
    final result=await StudentService.saveAttendance(payload()..remove('section'));
    expect(result['submission_on_hold'],true); expect(p.saves,1);
    final read=await StudentService.fetchAttendance(classId:'1A',date:date,section:'1_A');
    expect(read['submission_on_hold'],true);
    final again=await StudentService.saveAttendance(payload());
    expect(again['submission_on_hold'],true); expect(p.saves,1);
  });
  test('verified Save of A leaves an independent B hold intact', () async {
    final p=FakePortal(); DirectSchoolSession.attach(SaveAuth(p),'123'); StudentService.directAttendanceEnabled=true;
    final prefs=await SharedPreferences.getInstance();
    final key='student_submission_hold/123/$date/1b';
    final metadata=jsonEncode({'created_at':1,'expected':students}); await prefs.setString(key,metadata);
    final read=await StudentService.fetchAttendance(classId:'1A',date:date,section:'1A');
    expect(read['submission_on_hold'],false);
    final result=await StudentService.saveAttendance(payload());
    expect(result['success'],true,reason:'$result'); expect(p.saves,1);
    expect(prefs.getString(key),metadata);
  });
  test('reconciliation clears only matching aliases after two verified reads', () async {
    final p=FakePortal(marked:true); DirectSchoolSession.attach(SaveAuth(p),'123'); StudentService.directAttendanceEnabled=true;
    final prefs=await SharedPreferences.getInstance();
    for(final suffix in ['1','1a','1b']) {await prefs.setString('student_submission_hold/123/$date/$suffix',jsonEncode({'created_at':1,'expected':students}));}
    final before=await StudentService.captureReadScope();
    final checked=await StudentService.checkPreviousSubmission(classId:'1A',date:date,section:'1A');
    expect(checked['resolved'],'applied',reason:'$checked'); expect(p.saves,0);
    expect(prefs.containsKey('student_submission_hold/123/$date/1'),false);
    expect(prefs.containsKey('student_submission_hold/123/$date/1a'),false);
    expect(prefs.containsKey('student_submission_hold/123/$date/1b'),true);
    expect(await StudentService.captureReadScope(),isNot(before));
  });
  test('manual review cannot release a class-only hold against another roster', () async {
    final p=FakePortal(marked:true); DirectSchoolSession.attach(SaveAuth(p),'123'); StudentService.directAttendanceEnabled=true;
    final prefs=await SharedPreferences.getInstance(); final key='student_submission_hold/123/$date/1';
    final other=students.map((s)=>{...s,'srNo':'other-${s['srNo']}'}).toList();
    await prefs.setString(key,jsonEncode({'created_at':1,'expected':other}));
    final checked=await StudentService.checkPreviousSubmission(classId:'1A',date:date,section:'1A',acknowledgeManualRetry:true);
    expect(checked['success'],false); expect(checked['manual_retry_allowed'],false);
    expect(prefs.containsKey(key),true); expect(p.saves,0);
  });
  test('one canceled caller cannot cancel or poison another identical read', () async {
    final p=FakePortal(); DirectSchoolSession.attach(SaveAuth(p),'123'); StudentService.directAttendanceEnabled=true;
    final results=await Future.wait([
      StudentService.fetchAttendance(classId:'1A',date:date,section:'1A',shouldContinue:()=>false),
      StudentService.fetchAttendance(classId:'1A',date:date,section:'1A'),
    ]);
    expect(results[0]['code'],'STALE_ATTENDANCE_READ'); expect(results[1]['success'],true);
    expect(p.requests.length,3); expect(p.saves,0);
  });
  test('background read admission waits for every attendance owner', () async {
    StudentService.directAttendanceEnabled = true;
    DirectSchoolSession.attach(SaveAuth(FakePortal()), '123');
    final service = DirectSchoolSession.attendance!;
    final a = service.acquireForeground(), b = service.acquireForeground();
    var done = false;
    final waiting = StudentService.waitForAttendanceIdle('123').then((v) { done = true; return v; });
    await Future<void>.delayed(Duration.zero); expect(done, false);
    a(); await Future<void>.delayed(Duration.zero); expect(done, false);
    b(); expect(await waiting, true);
  });
  test('background admission rejects account/session changes while deferred', () async {
    StudentService.directAttendanceEnabled = true;
    final auth = SaveAuth(FakePortal()); DirectSchoolSession.attach(auth, '123');
    final release = DirectSchoolSession.attendance!.acquireForeground();
    final waiting = StudentService.waitForAttendanceIdle('123');
    auth.identity = 'new-session'; release();
    expect(await waiting, false);
  });
  test('background admission rejects a replaced attendance service', () async {
    StudentService.directAttendanceEnabled = true;
    DirectSchoolSession.attach(SaveAuth(FakePortal()), '123');
    final release = DirectSchoolSession.attendance!.acquireForeground();
    final waiting = StudentService.waitForAttendanceIdle('123');
    DirectSchoolSession.attach(SaveAuth(FakePortal()), '123'); release();
    expect(await waiting, false);
  });
  test('concurrent valid scope saves dispatch only once', () async {
    final portal = FakePortal();
    final auth = SaveAuth(portal);
    DirectSchoolSession.attach(auth, '123');
    StudentService.directAttendanceEnabled = true;
    final scope = await StudentService.captureReadScope();
    final results = await Future.wait([
      StudentService.saveAttendance(payload(), expectedScope: scope),
      StudentService.saveAttendance(payload(), expectedScope: scope),
    ]);
    expect(portal.saves, 1);
    expect(results.where((r) => r['success'] == true), hasLength(1));
  });
  test(
    'uncertain submit keeps its hold and a new scope cannot replay Save',
    () async {
      final portal = FakePortal()..timeoutSave = true;
      final auth = SaveAuth(portal);
      DirectSchoolSession.attach(auth, '123');
      StudentService.directAttendanceEnabled = true;
      final scope = await StudentService.captureReadScope();
      final result = await StudentService.saveAttendance(
        payload(),
        expectedScope: scope,
      );
      expect(result['success'], false);
      expect(result['submission_on_hold'], true);
      expect(portal.saves, 1);
      final next = await StudentService.captureReadScope();
      final again = await StudentService.saveAttendance(
        payload(),
        expectedScope: next,
      );
      expect(again['submission_on_hold'], true);
      expect(portal.saves, 1);
    },
  );
  test(
    'captured direct scope reaches single Save and verified readback',
    () async {
      final portal = FakePortal();
      final auth = SaveAuth(portal);
      DirectSchoolSession.attach(auth, '123');
      StudentService.directAttendanceEnabled = true;
      final loaded = await StudentService.fetchAttendance(
        classId: '1',
        date: date,
        section: '1A',
      );
      expect(loaded['success'], true);
      final scope = await StudentService.captureReadScope();
      expect(scope, isNotNull);
      final result = await StudentService.saveAttendance(
        payload(),
        expectedScope: scope,
      );
      expect(result['success'], true, reason: '$result');
      expect(result['attendance_verified'], true);
      expect(result['submission_on_hold'], false);
      expect(portal.saves, 1);
    },
  );
  test('backend scope passes identity checks and rejects invalid data before dispatch', () async {
    final scope = await StudentService.captureReadScope();
    expect(scope, isNotNull);
    final result = await StudentService.saveAttendance(
      {},
      expectedScope: scope,
    );
    expect(result['code'], 'INVALID_PAYLOAD');
    expect(result['submission_attempted'], false);
  });
  test(
    'real session replacement remains blocked before Save dispatch',
    () async {
      final portal = FakePortal();
      final auth = SaveAuth(portal);
      DirectSchoolSession.attach(auth, '123');
      StudentService.directAttendanceEnabled = true;
      final scope = await StudentService.captureReadScope();
      auth.identity = 'replacement-session';
      final result = await StudentService.saveAttendance(
        payload(),
        expectedScope: scope,
      );
      expect(result['code'], 'ACCOUNT_CHANGED');
      expect(portal.saves, 0);
      expect(result['submission_attempted'], false);
    },
  );
  test(
    'credential revision change remains blocked before Save dispatch',
    () async {
      final portal = FakePortal();
      final auth = SaveAuth(portal);
      DirectSchoolSession.attach(auth, '123');
      StudentService.directAttendanceEnabled = true;
      final scope = await StudentService.captureReadScope();
      await save('123');
      final result = await StudentService.saveAttendance(
        payload(),
        expectedScope: scope,
      );
      expect(result['code'], 'ACCOUNT_CHANGED');
      expect(portal.saves, 0);
    },
  );
  test('six sequential school guards use one encrypted record read', () async {
    for (var i = 0; i < 6; i++)
      expect(await SecureStorageService.getShaladarpanIdentity(), '123');
    expect(reads, 1);
  });
  test('simultaneous cold guards coalesce to one encrypted read', () async {
    readGate = Completer<void>();
    final a = SecureStorageService.getShaladarpanIdentity();
    final b = SecureStorageService.getShaladarpanIdentity();
    await Future<void>.delayed(Duration.zero);
    readGate!.complete();
    expect(await a, '123');
    expect(await b, '123');
    expect(reads, 1);
  });
  test(
    'credential update blocks synchronous identity and changes revision',
    () async {
      expect(await SecureStorageService.getShaladarpanIdentity(), '123');
      final revision = SecureStorageService.schoolIdentityRevision;
      writeGate = Completer<void>();
      final saving = save('456');
      expect(SecureStorageService.schoolIdentityNow, isNull);
      expect(await SecureStorageService.getShaladarpanIdentity(), '');
      writeGate!.complete();
      await saving;
      expect(await SecureStorageService.getShaladarpanIdentity(), '456');
      expect(
        SecureStorageService.schoolIdentityRevision,
        greaterThan(revision),
      );
    },
  );
  test(
    'same-school credential update invalidates old attendance scope',
    () async {
      StudentService.directAttendanceEnabled = false;
      final old = await StudentService.captureReadScope();
      await save('123');
      final current = await StudentService.captureReadScope();
      expect(current, isNotNull);
      expect(current, isNot(old));
    },
  );
  test(
    'logout invalidates identity immediately and removes saved account',
    () async {
      await SecureStorageService.getShaladarpanIdentity();
      final clearing = SecureStorageService.clearAll();
      expect(SecureStorageService.schoolIdentityNow, isNull);
      await clearing;
      expect(await SecureStorageService.getShaladarpanIdentity(), '');
    },
  );
  test('an old pending read cannot restore identity after logout', () async {
    readGate = Completer<void>();
    final reading = SecureStorageService.getShaladarpanIdentity();
    await Future<void>.delayed(Duration.zero);
    await SecureStorageService.clearAll();
    readGate!.complete();
    expect(await reading, '');
    expect(SecureStorageService.schoolIdentityNow, isNull);
  });
  test(
    'empty identity read is retryable after storage becomes available',
    () async {
      records = {};
      expect(await SecureStorageService.getShaladarpanIdentity(), '');
      records['portal_credentials_v2'] = record('456');
      expect(await SecureStorageService.getShaladarpanIdentity(), '456');
    },
  );
  test(
    'same cookies and reordered cookie keys avoid duplicate writes',
    () async {
      final store = RecordingStorage();
      final auth = SchoolAuthManager(
        storage: store,
        solveCaptcha: (_) async => '',
      );
      await auth.saveSessionCookies({'a': 'one', 'b': 'two'});
      await auth.saveSessionCookies({'b': 'two', 'a': 'one'});
      expect(store.writes, hasLength(1));
      await auth.saveSessionCookies({'a': 'changed', 'b': 'two'});
      expect(store.writes, hasLength(2));
      await auth.closeAuthenticatedClients();
    },
  );
  test(
    'failed persistence does not suppress a later retry of same cookies',
    () async {
      final store = RecordingStorage()..fail = true;
      final auth = SchoolAuthManager(
        storage: store,
        solveCaptcha: (_) async => '',
      );
      await auth.saveSessionCookies({'a': 'one'});
      store.fail = false;
      await auth.saveSessionCookies({'a': 'one'});
      expect(store.writes, hasLength(2));
      expect(store.values, isNotEmpty);
      await auth.closeAuthenticatedClients();
    },
  );
  test('queued A to B to A writes preserve final cookie state', () async {
    final store = RecordingStorage();
    final auth = SchoolAuthManager(
      storage: store,
      solveCaptcha: (_) async => '',
    );
    await Future.wait([
      auth.saveSessionCookies({'a': 'one'}),
      auth.saveSessionCookies({'a': 'two'}),
      auth.saveSessionCookies({'a': 'one'}),
    ]);
    expect(store.writes.map((value) => jsonDecode(value)['a']), [
      'one',
      'two',
      'one',
    ]);
    await auth.closeAuthenticatedClients();
  });
  test('forget then identical cookies persists again instead of trusting deleted record', () async {
    final store = RecordingStorage();
    final auth = SchoolAuthManager(
      storage: store,
      solveCaptcha: (_) async => '',
    );
    await auth.saveSessionCookies({'a': 'one'});
    await auth.forgetSavedSession();
    await auth.saveSessionCookies({'a': 'one'});
    expect(store.writes, hasLength(2));
    expect(store.values, isNotEmpty);
    await auth.closeAuthenticatedClients();
  });
}
