import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/core/direct/coordinator.dart' show Probe;
import '../../lib/services/portals/rajsims/direct/auth_manager.dart';
import '../../lib/services/portals/rajsims/direct/http_context.dart';
import 'rajsims_gateway_test.dart' show MemoryTransport, reply;

int? bodyStatus(Object? data) {
  if (data is! Map) return null;
  final value = data['Status'];
  if (value is bool) return null;
  final code = value is int
      ? value
      : value is String && RegExp(r'^[0-9]+$').hasMatch(value.trim())
      ? int.tryParse(value.trim())
      : null;
  return code != null && code >= 100 && code <= 599 ? code : null;
}

RajsimsAuthManager manager(
  RajsimsHttpContext? Function() current, {
  RajsimsLoginImplementation? login,
  Future<void> Function(RajsimsHttpContext)? save,
  Future<void> Function(String)? saveUser,
  void Function()? clearCache,
}) => RajsimsAuthManager(
  currentContext: current,
  loginImplementation: login ?? (_, _, _) async => {'success': false},
  bodyStatusCode: bodyStatus,
  persistState: save ?? (_) async {},
  persistUsername: saveUser ?? (_) async {},
  clearUserInfoCache: clearCache ?? () {},
);

void main() {
  final fixture = jsonDecode(
    File('test/direct/fixtures/python_rajsims_auth.json').readAsStringSync(),
  ) as Map;
  tearDown(RajsimsHttpContext.closeAll);
  for (final entry in fixture['profiles'] as List) {
    test('actual Python profile: ${entry['name']}', () {
      final current = RajsimsHttpContext(MemoryTransport());
      final auth = manager(() => current)..bindContext(current, 'id', 'key');
      if ((entry['initial'] as Map).isNotEmpty) {
        expect(auth.mergeProfile({'OfficeId': 11, 'OrgId': 13}, current), true);
      }
      final target = entry['stale'] == true
          ? RajsimsHttpContext(MemoryTransport())
          : current;
      expect(auth.mergeProfile(entry['data'], target), entry['success']);
      expect(auth.getUserInfo(), entry['user']);
    });
  }
  for (final entry in fixture['ocr'] as List) {
    test('actual Python OCR normalization: ${jsonEncode(entry['input'])}', () {
      expect(extractSixDigits(entry['input'] as String), entry['output']);
    });
  }
  for (final spec in <(String, int, Object?, Probe)>[
    (
      'verified',
      200,
      {'IsSuccess': true, 'OfficeId': 11, 'OrgId': 13},
      Probe.alive,
    ),
    ('http401', 401, {'Message': 'Native expiry'}, Probe.dead),
    ('body401', 200, {'Status': '401'}, Probe.dead),
    ('http403', 403, {'Message': 'Native denial'}, Probe.unknown),
    ('body403', 200, {'Status': 403}, Probe.unknown),
    ('rate_limit', 200, {'Status': 429}, Probe.unknown),
    ('server_error', 503, {}, Probe.unknown),
    (
      'native_false',
      200,
      {'IsSuccess': false, 'OfficeId': 11, 'OrgId': 13},
      Probe.unknown,
    ),
    (
      'ambiguous_identity',
      200,
      [
        {'OfficeId': 11, 'OrgId': 13},
      ],
      Probe.unknown,
    ),
    ('invalid_json', 200, null, Probe.unknown),
  ]) {
    test(
      'token probe ${spec.$1} through original HTTPX bootstrap contract',
      () async {
        final transport = MemoryTransport();
        final current = RajsimsHttpContext(transport);
        final auth = manager(() => current)..bindContext(current, 'id', 'key');
        transport.handle = (call) async => reply(
          Uri.parse(call['url'] as String),
          status: spec.$2,
          data: spec.$3,
          constText: '<html>no JSON</html>',
        );
        expect(await auth.probe(current), spec.$4);
        expect(transport.calls.length, 1);
        final call = transport.calls.single;
        expect(call['url'], rajsimsBootstrap);
        expect(call['payload'], {
          'ApiKey': 'ValidateTokenAndGetUserDetail',
          'ApiParams': {'AuthId': 'id', 'AuthKey': 'key'},
          'OrgId': 0,
        });
        expect(call['timeout'], const Duration(seconds: 8));
        expect((call['headers'] as Map).containsKey('authkey'), false);
      },
    );
  }
  test(
    'response arriving after account switch cannot merge old profile',
    () async {
      final client = MemoryTransport();
      var current = RajsimsHttpContext(client);
      final old = current;
      final auth = manager(() => current)..bindContext(old, 'old', 'old');
      final pending = Completer<void>();
      client.handle = (call) async {
        await pending.future;
        return reply(
          Uri.parse(call['url'] as String),
          data: {'OfficeId': 11, 'OrgId': 13},
        );
      };
      final probing = auth.probe(old);
      current = RajsimsHttpContext(MemoryTransport());
      pending.complete();
      expect(await probing, Probe.unknown);
      expect(auth.getUserInfo(), isEmpty);
      expect(auth.getAuth(old), (null, null));
    },
  );
  test(
    'missing auth sends no probe; clear resets identity and worker cache',
    () async {
      final client = MemoryTransport();
      final current = RajsimsHttpContext(client);
      var clears = 0;
      final auth = manager(
        () => current,
        clearCache: () {
          clears++;
        },
      );
      expect(await auth.probe(current), Probe.unknown);
      expect(client.calls, isEmpty);
      auth.bindContext(current, ' id ', ' key ');
      expect(auth.getAuth(), ('id', 'key'));
      auth.mergeProfile({'OfficeId': 11, 'OrgId': 13}, current);
      final copy = auth.getUserInfo()..['office_id'] = 99;
      expect(copy['office_id'], 99);
      expect(auth.getUserInfo()['office_id'], 11);
      auth.clearAuth();
      expect(auth.getUserInfo(), isEmpty);
      expect(clears, 1);
    },
  );
  test('public login serializes calls and preserves native response and forceFresh', () async {
    final current = RajsimsHttpContext(MemoryTransport());
    final first = Completer<void>();
    final calls = <Object>[];
    final saved = <Object>[];
    final native = {'success': true, 'message': 'मूल पोर्टल संदेश'};
    late RajsimsAuthManager auth;
    auth = manager(
      () => current,
      login: (u, p, fresh) async {
        calls.add((u, p, fresh));
        if (calls.length == 1) await first.future;
        auth.bindContext(current, 'id', 'key');
        return native;
      },
      save: (_) async {
        saved.add('state');
      },
      saveUser: (user) async {
        saved.add(user);
      },
    );
    final a = auth.executeLogin(' user ', 'password');
    final b = auth.executeLogin('user', 'password', forceFresh: true);
    await Future<void>.delayed(Duration.zero);
    expect(calls.length, 1);
    first.complete();
    expect(await a, same(native));
    expect(await b, same(native));
    expect(calls, [(' user ', 'password', false), ('user', 'password', true)]);
    expect(saved, ['state', 'user', 'state', 'user']);
  });
  test('invalid credentials do not invoke login or persistence', () async {
    var calls = 0;
    final auth = manager(
      () => null,
      login: (_, _, _) async {
        calls++;
        return {};
      },
    );
    expect((await auth.executeLogin(' ', 'p'))['code'], 'NO_CREDENTIALS');
    expect((await auth.executeLogin('u', ''))['code'], 'NO_CREDENTIALS');
    expect(calls, 0);
  });
  test(
    'failed login does not save state or replay; next explicit login can run',
    () async {
      var calls = 0, saves = 0;
      final native = {
        'success': false,
        'code': 'PORTAL_LAUNCH_UNCONFIRMED',
        'message': 'native',
      };
      final auth = manager(
        () => null,
        login: (_, _, _) async {
          calls++;
          return native;
        },
        save: (_) async {
          saves++;
        },
        saveUser: (_) async {
          saves++;
        },
      );
      expect(await auth.executeLogin('u', 'p'), same(native));
      expect(calls, 1);
      expect(saves, 0);
      await auth.executeLogin('u', 'p');
      expect(calls, 2);
    },
  );
  test(
    'persistence I/O failure does not convert successful login into failure',
    () async {
      final current = RajsimsHttpContext(MemoryTransport());
      final auth = manager(
        () => current,
        login: (_, _, _) async => {'success': true},
        save: (_) async => throw const FileSystemException('offline'),
        saveUser: (_) async => throw const FileSystemException('offline'),
      )..bindContext(current, 'id', 'key');
      expect((await auth.executeLogin('u', 'p'))['success'], true);
    },
  );
  test('thrown login releases lock for the next explicit request', () async {
    var calls = 0;
    final auth = manager(
      () => null,
      login: (_, _, _) async {
        if (++calls == 1) throw StateError('offline failure');
        return {'success': false, 'message': 'native'};
      },
    );
    await expectLater(auth.executeLogin('u', 'p'), throwsStateError);
    expect((await auth.executeLogin('u', 'p'))['message'], 'native');
    expect(calls, 2);
  });
}
