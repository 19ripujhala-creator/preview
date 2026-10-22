import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/experiments/direct_portal_auth.dart';
import 'package:shaladarpan/experiments/direct_class_mapping_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/class_mapping_worker.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

String fixture(String name) =>
    File('test/direct/fixtures/$name').readAsStringSync();
dynamic golden(String name) => jsonDecode(fixture(name));
const base = 'https://rajshaladarpan.rajasthan.gov.in/SD1/';
List<Map<String, dynamic>> updates() => [
  {'index': 0, 'teacher_id': '102'},
];

class MappingPortal {
  String pending = fixture('mapping_page.html'),
      confirmed = fixture('mapping_saved.html');
  String key = 'session-1', school = '123456', baseUrl = base;
  bool saved = false,
      timeoutSave = false,
      redirect = false,
      changeKeyOnRead = false;
  Object? readError;
  Uri? responseUrl;
  int gets = 0, posts = 0;
  double time = 0;
  Map<String, Object?>? payload;
  String? control;
  late final worker = ClassMappingWorker(
    request: request,
    baseUrl: () => Uri.parse(baseUrl),
    schoolId: () => school,
    sessionKey: () => key,
    clock: () => time,
  );
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? saveControl,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    expect(url.path, '/SD1/Home/School/TeacherClassMapping.aspx');
    if (fields == null) {
      gets++;
      expect(timeout, const Duration(seconds: 25));
      if (readError != null) throw readError!;
      if (changeKeyOnRead) key = 'rotated';
      return (
        url: responseUrl ?? url,
        status: 200,
        html: saved ? confirmed : pending,
      );
    }
    posts++;
    payload = Map.from(fields);
    control = saveControl;
    expect(referer, url);
    expect(timeout, const Duration(seconds: 30));
    saved = true;
    if (timeoutSave) throw TimeoutException('lost Save response');
    return (url: url, status: redirect ? 302 : 200, html: 'OK');
  }
}

class MappingAuth extends DirectPortalAuth {
  MappingAuth(this.portal) : super(node: 'SD1');
  final MappingPortal portal;
  @override
  bool get isVerified => true;
  @override
  String? get authenticatedSchoolId => '123456';
  @override
  String get verifiedNode => 'SD1';
  @override
  String get schoolSessionIdentity => portal.key;
  @override
  Future<AttendanceHttpReply> classMappingRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? saveControl,
    Duration timeout = const Duration(seconds: 25),
    bool userConfirmed = false,
  }) {
    if (fields != null) expect(userConfirmed, true);
    return portal.request(
      url,
      fields: fields,
      referer: referer,
      saveControl: saveControl,
      timeout: timeout,
    );
  }
}

class GateAuth extends DirectPortalAuth {
  GateAuth() : super(node: 'SD1');
  @override
  bool get isVerified => true;
}

void main() {
  for (final mode in ['pending', 'empty']) {
    test('$mode READ exactly matches original Python', () async {
      final p = MappingPortal();
      if (mode == 'empty') p.pending = fixture('mapping_empty.html');
      expect(await p.worker.fetch(), golden('python_mapping_$mode.json'));
      expect(p.posts, 0);
    });
  }
  for (final mode in ['save', 'image', 'timeout', 'mismatch']) {
    test('$mode response and complete payload equal Python', () async {
      final p = MappingPortal()..timeoutSave = mode == 'timeout';
      if (mode == 'image') p.pending = fixture('mapping_image.html');
      if (mode == 'mismatch') p.confirmed = p.pending;
      await p.worker.fetch();
      expect(
        await p.worker.save(updates(), userConfirmed: true),
        golden('python_mapping_$mode.json'),
      );
      expect(p.payload, golden('python_mapping_${mode}_payload.json'));
      expect(p.posts, 1);
      expect(p.payload!.containsKey('ctl00\$ScriptManager1'), false);
      expect(p.payload!['duplicate'], ['a', 'b']);
    });
  }
  test('no reviewed snapshot blocks all requests', () async {
    final p = MappingPortal();
    expect(
      (await p.worker.save(updates(), userConfirmed: true))['code'],
      'STALE_FORM',
    );
    expect(p.gets, 0);
    expect(p.posts, 0);
  });
  test('user confirmation is required before requests', () async {
    final p = MappingPortal();
    expect(
      (await p.worker.save(updates(), userConfirmed: false))['code'],
      'CONFIRMATION_REQUIRED',
    );
    expect(p.gets, 0);
  });
  test('invalid indices and teacher IDs cannot dispatch', () async {
    for (final bad in [
      <Map<String, dynamic>>[],
      [
        {'index': true, 'teacher_id': '102'},
      ],
      [
        {'index': '0', 'teacher_id': '102'},
      ],
      [
        {'index': -1, 'teacher_id': '102'},
      ],
      [
        {'index': 0, 'teacher_id': ''},
      ],
      [updates().first, updates().first],
    ]) {
      final p = MappingPortal();
      expect(
        (await p.worker.save(bad, userConfirmed: true))['code'],
        'INVALID_PAYLOAD',
      );
      expect(p.gets, 0);
      expect(p.posts, 0);
    }
  });
  for (final kind in ['cookie', 'expiry', 'identity', 'selected']) {
    test('$kind change invalidates reviewed rows before commit', () async {
      final p = MappingPortal();
      await p.worker.fetch();
      if (kind == 'cookie') p.key = 'new-cookie';
      if (kind == 'expiry') p.time = 181;
      if (kind == 'identity')
        p.pending = p.pending.replaceFirst('value="10"', 'value="99"');
      if (kind == 'selected')
        p.pending = p.pending
            .replaceFirst('value="101" selected', 'value="101"')
            .replaceFirst('value="102"', 'value="102" selected');
      expect(
        (await p.worker.save(updates(), userConfirmed: true))['code'],
        'STALE_FORM',
      );
      expect(p.posts, 0);
    });
  }
  for (final kind in [
    'disabled',
    'name',
    'offered',
    'postback',
    'tokens',
    'button',
    'destination',
  ]) {
    test('$kind form blocks commit', () async {
      final p = MappingPortal();
      await p.worker.fetch();
      if (kind == 'disabled')
        p.pending = p.pending.replaceFirst('<select ', '<select disabled ');
      if (kind == 'name')
        p.pending = p.pending.replaceFirst(
          'name="ctl00\$ContentPlaceHolder1\$grdList\$ctl02\$ddlClassTeacher"',
          '',
        );
      if (kind == 'offered')
        p.pending = p.pending.replaceFirst(
          'value="102"',
          'value="102" disabled',
        );
      if (kind == 'postback')
        p.pending = p.pending.replaceFirst(
          '<select ',
          '<select onchange="dependent()" ',
        );
      if (kind == 'tokens')
        p.pending = p.pending.replaceAll('value="MAPPING_STATE"', 'value=""');
      if (kind == 'button')
        p.pending = p.pending
            .replaceAll('btnSave', 'other')
            .replaceAll('value="Save"', 'value="Other"');
      if (kind == 'destination')
        p.pending = p.pending.replaceAll(
          'action="TeacherClassMapping.aspx"',
          'action="https://example.org/"',
        );
      final r = await p.worker.save(updates(), userConfirmed: true);
      expect(r['success'], false);
      expect(r['submission_attempted'], false);
      expect(p.posts, 0);
    });
  }
  test('duplicate index and missing identity cannot be displayed', () async {
    for (final s in [
      fixture('mapping_page.html').replaceAll('_1"', '_0"'),
      fixture('mapping_page.html').replaceAll('hdnClassSectionId_0', 'other_0'),
      '<table id="ContentPlaceHolder1_grdList"></table>',
    ]) {
      final p = MappingPortal()..pending = s;
      expect((await p.worker.fetch())['success'], false);
    }
  });
  test(
    'unexpected READ URL is never accepted as authenticated mapping',
    () async {
      final p = MappingPortal()
        ..responseUrl = Uri.parse(
          'https://rajshaladarpan.rajasthan.gov.in/SD2/Home/School/TeacherClassMapping.aspx',
        );
      expect((await p.worker.fetch())['code'], 'PAGE_NOT_READY');
      expect(p.posts, 0);
    },
  );
  test('session rotation during GET invalidates result', () async {
    final p = MappingPortal()..changeKeyOnRead = true;
    expect((await p.worker.fetch())['code'], 'ACCOUNT_CHANGED');
  });
  test('GET timeout and transport error match Python codes', () async {
    for (final pair in [
      (TimeoutException('slow'), 'PORTAL_SLOW'),
      (const SocketException('offline'), 'NETWORK_ERROR'),
    ]) {
      final p = MappingPortal()..readError = pair.$1;
      expect((await p.worker.fetch())['code'], pair.$2);
    }
  });
  test(
    'redirect after commit stays unconfirmed and is never replayed',
    () async {
      final p = MappingPortal()..redirect = true;
      await p.worker.fetch();
      expect(
        (await p.worker.save(updates(), userConfirmed: true))['code'],
        'SAVE_UNCONFIRMED',
      );
      expect(p.posts, 1);
      expect(p.gets, 2);
      expect(
        (await p.worker.save(updates(), userConfirmed: true))['code'],
        'STALE_FORM',
      );
      expect(p.posts, 1);
    },
  );
  test('readback validates unrelated rows as well as selected row', () async {
    final p = MappingPortal();
    await p.worker.fetch();
    p.confirmed = p.confirmed.replaceFirst('value="11"', 'value="99"');
    expect(
      (await p.worker.save(updates(), userConfirmed: true))['code'],
      'SAVE_UNCONFIRMED',
    );
    expect(p.posts, 1);
  });
  test('fresh readback failure after Save stays unconfirmed', () async {
    final p = MappingPortal();
    await p.worker.fetch();
    p.confirmed = '<html>Missing grid</html>';
    expect(
      (await p.worker.save(updates(), userConfirmed: true))['code'],
      'SAVE_UNCONFIRMED',
    );
    expect(p.posts, 1);
  });
  test(
    'successful readback renews the review for later explicit save',
    () async {
      final p = MappingPortal();
      await p.worker.fetch();
      expect(
        (await p.worker.save(updates(), userConfirmed: true))['verified'],
        true,
      );
      expect(
        (await p.worker.save(updates(), userConfirmed: true))['verified'],
        true,
      );
      expect(p.posts, 2);
    },
  );
  test(
    'native gate blocks unconfirmed or missing control and foreign URLs',
    () async {
      final a = GateAuth();
      addTearDown(a.close);
      final u = Uri.parse('${base}Home/School/TeacherClassMapping.aspx');
      await expectLater(
        a.classMappingRequest(
          u,
          fields: {'btnSave': 'Save'},
          referer: u,
          saveControl: 'btnSave',
        ),
        throwsStateError,
      );
      await expectLater(
        a.classMappingRequest(
          u,
          fields: {'other': 'x'},
          referer: u,
          saveControl: 'btnSave',
          userConfirmed: true,
        ),
        throwsStateError,
      );
      await expectLater(
        a.classMappingRequest(
          Uri.parse('https://example.org/TeacherClassMapping.aspx'),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'facade reuses one auth and review; cookie change blocks Save',
    () async {
      final p = MappingPortal(), a = MappingAuth(MappingPortal());
      a.close();
      final auth = MappingAuth(p);
      addTearDown(auth.close);
      final service = DirectClassMappingService(auth);
      expect(await service.fetch(), golden('python_mapping_pending.json'));
      expect(
        await service.save(updates(), userConfirmed: true),
        golden('python_mapping_save.json'),
      );
      p.key = 'different';
      expect(
        (await service.save(updates(), userConfirmed: true))['code'],
        'STALE_FORM',
      );
      expect(p.posts, 1);
    },
  );
}
