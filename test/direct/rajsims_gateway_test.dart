import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/shaladarpan/direct/school_http.dart';
import '../../lib/services/portals/rajsims/direct/http_context.dart';
import '../../lib/services/portals/rajsims/direct/rajsims_httpx.dart';

SchoolHttpReply reply(
  Uri url, {
  int status = 200,
  Object? data,
  constText = '',
  Map<String, List<String>> headers = const {},
}) => SchoolHttpReply(
  url,
  status,
  Uint8List.fromList(
    utf8.encode(data == null ? constText as String : jsonEncode(data)),
  ),
  headers,
);

class MemoryTransport implements RajsimsHttpTransport {
  @override
  final jar = SchoolCookieJar();
  final calls = <Map<String, dynamic>>[];
  int closes = 0;
  Future<SchoolHttpReply> Function(Map<String, dynamic>)? handle;
  @override
  Future<SchoolHttpReply> request(
    String method,
    Uri url, {
    String? content,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) async {
    final call = <String, dynamic>{
      'method': method,
      'url': url.toString(),
      'payload': content == null ? null : jsonDecode(content),
      'headers': {
        for (final e in headers.entries) e.key.toLowerCase(): e.value,
      },
      'cookies': {for (final c in jar.matching(url)) c.name: c.value},
      'timeout': timeout,
    };
    calls.add(call);
    return handle == null
        ? reply(url, data: {'IsSuccess': true})
        : await handle!(call);
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

const read = {
  'ApiKey': 'GetAllChartData',
  'ApiParams': <String, dynamic>{},
  'OrgId': 123,
};
const write = {
  'ApiKey': 'SaveEditBeneficiaryDistribution',
  'ApiParams': {'NoOfBeneficiary': 5},
  'OrgId': 123,
};
Future<RajsimsHttpContext> context(MemoryTransport client) async {
  final ctx = RajsimsHttpContext(client);
  await ctx.addCookies([
    {
      'name': 'session',
      'value': 'offline-cookie',
      'domain': 'rajsims-mdm.rajasthan.gov.in',
      'path': '/',
    },
  ]);
  return ctx;
}

RajsimsGatewayAdapter adapter(
  RajsimsHttpContext ctx,
  MemoryTransport client, {
  RajsimsWriteMode mode = RajsimsWriteMode.enabled,
}) => RajsimsGatewayAdapter(
  currentContext: () => ctx,
  waitForAuth: (_) async => ('offline-id', 'offline-key'),
  bodyStatusCode: (data) => data is Map ? data['Status'] as int? : null,
  responseErrorMessage: (_, data) => data is Map
      ? (data['Message'] ?? 'Gateway error').toString()
      : 'Gateway error',
  apiUrl: rajsimsGateway,
  apiTimeout: const Duration(seconds: 1),
  readRetries: 1,
  readRetryBackoff: Duration.zero,
  writeMode: mode,
  clientFactory: () => client,
);

void main() {
  tearDown(RajsimsHttpContext.closeAll);
  final cases = jsonDecode(
    File('test/direct/fixtures/python_rajsims_gateway.json').readAsStringSync(),
  ) as List;
  for (final raw in cases) {
    final sample = Map<String, dynamic>.from(raw as Map);
    test('actual Python Gateway parity: ${sample['name']}', () async {
      final authClient = MemoryTransport(), client = MemoryTransport();
      final ctx = await context(authClient);
      final responses = List<Map>.from(sample['responses'] as List);
      client.handle = (call) async {
        final value = responses.removeAt(0);
        if (value['timeout'] == true) throw TimeoutException('Offline timeout');
        return reply(
          Uri.parse(call['url'] as String),
          status: value['status'] as int,
          data: value['data'],
          constText: value['text'] ?? '',
        );
      };
      final gateway = adapter(
        ctx,
        client,
        mode: sample['mode'] == 'disabled'
            ? RajsimsWriteMode.disabled
            : RajsimsWriteMode.enabled,
      );
      final result = await gateway.request(
        ctx,
        Map<String, dynamic>.from(sample['payload'] as Map),
        safeToRetry: sample['safe'] as bool,
      );
      expect([
        result.success,
        result.data,
        result.status,
        result.message,
      ], sample['expected']);
      expect([
        for (final call in client.calls)
          {
            'url': call['url'],
            'payload': call['payload'],
            'headers': call['headers'],
          },
      ], sample['requests']);
      if (client.calls.isNotEmpty)
        expect(client.calls.first['cookies'], {'session': 'offline-cookie'});
      await gateway.closeAll();
    });
  }
  test('in-flight identical final write sends only once', () async {
    final client = MemoryTransport(), ctx = await context(MemoryTransport());
    final entered = Completer<void>(), release = Completer<void>();
    client.handle = (call) async {
      entered.complete();
      await release.future;
      return reply(
        Uri.parse(call['url']),
        data: {'IsSuccess': true, 'Message': 'Native saved'},
      );
    };
    final transport = RajsimsGatewayTransport(
      ctx,
      () => ctx,
      rajsimsGateway,
      client: client,
    );
    final first = transport.postWrite(write, 'id', 'key');
    await entered.future;
    expect((await transport.postWrite(write, 'id', 'key')).status, 409);
    expect(client.calls.length, 1);
    release.complete();
    expect((await first).ok, true);
    await transport.close();
  });
  test('uncertain timeout receipt prevents another matching POST', () async {
    final client = MemoryTransport(), ctx = await context(MemoryTransport());
    client.handle = (call) async => throw TimeoutException('Offline timeout');
    final transport = RajsimsGatewayTransport(
      ctx,
      () => ctx,
      rajsimsGateway,
      client: client,
    );
    await expectLater(
      transport.postWrite(write, 'id', 'key'),
      throwsA(isA<TimeoutException>()),
    );
    expect((await transport.postWrite(write, 'id', 'key')).status, 409);
    expect(client.calls.length, 1);
    await transport.close();
  });
  test(
    'confirmed receipt lasts 10 seconds; key ordering does not duplicate',
    () async {
      final client = MemoryTransport(), ctx = await context(MemoryTransport());
      var now = 100.0;
      final transport = RajsimsGatewayTransport(
        ctx,
        () => ctx,
        rajsimsGateway,
        client: client,
        monotonic: () => now,
      );
      final first = await transport.postWrite(write, 'id', 'key');
      final reordered = <String, dynamic>{
        'OrgId': 123,
        'ApiParams': {'NoOfBeneficiary': 5},
        'ApiKey': 'SaveEditBeneficiaryDistribution',
      };
      expect(
        identical(await transport.postWrite(reordered, 'id', 'key'), first),
        true,
      );
      expect(client.calls.length, 1);
      now += 11;
      await transport.postWrite(write, 'id', 'key');
      expect(client.calls.length, 2);
      await transport.close();
    },
  );
  test(
    'definitive native rejection clears receipt for later deliberate attempt',
    () async {
      final client = MemoryTransport(), ctx = await context(MemoryTransport());
      client.handle = (call) async => reply(
        Uri.parse(call['url']),
        data: {'IsSuccess': false, 'Message': 'Native rejection'},
      );
      final transport = RajsimsGatewayTransport(
        ctx,
        () => ctx,
        rajsimsGateway,
        client: client,
      );
      await transport.postWrite(write, 'id', 'key');
      await transport.postWrite(write, 'id', 'key');
      expect(client.calls.length, 2);
      await transport.close();
    },
  );
  test(
    'session switch withholds in-flight response and cookie rotations',
    () async {
      final client = MemoryTransport(), ctx = await context(MemoryTransport());
      RajsimsHttpContext? active = ctx;
      client.handle = (call) async {
        active = null;
        return reply(
          Uri.parse(call['url']),
          data: {'IsSuccess': true},
          headers: {
            'set-cookie': ['rotated=value; Path=/'],
          },
        );
      };
      final transport = RajsimsGatewayTransport(
        ctx,
        () => active,
        rajsimsGateway,
        client: client,
      );
      await expectLater(
        transport.postRead(read, 'id', 'key'),
        throwsA(isA<RajsimsSessionChanged>()),
      );
      expect((await ctx.cookies()).any((c) => c['name'] == 'rotated'), false);
      await transport.close();
    },
  );
  test('profile token mismatch stops before sending any request', () async {
    final client = MemoryTransport(), ctx = await context(MemoryTransport());
    final transport = RajsimsGatewayTransport(
      ctx,
      () => ctx,
      rajsimsGateway,
      client: client,
    );
    await expectLater(
      transport.postRead(
        {
          'ApiKey': 'ValidateTokenAndGetUserDetail',
          'ApiParams': {'AuthId': 'other', 'AuthKey': 'key'},
        },
        'id',
        'key',
      ),
      throwsArgumentError,
    );
    expect(client.calls, isEmpty);
    await transport.close();
  });
  test('original token probe redirects to exact native bootstrap with matched payload', () async {
    final client = MemoryTransport(), ctx = await context(client);
    final payload = {
      'ApiKey': 'ValidateTokenAndGetUserDetail',
      'OrgId': 0,
      'ApiParams': {'AuthId': 'id', 'AuthKey': 'key'},
    };
    await ctx.request.post(
      rajsimsGateway,
      headers: {'Authid': 'id', 'Authkey': 'key'},
      data: jsonEncode(payload),
      timeout: 5000,
    );
    expect(client.calls.single['url'], rajsimsBootstrap);
    expect(client.calls.single['payload'], payload);
    expect(
      (client.calls.single['headers'] as Map).containsKey('authid'),
      false,
    );
    await expectLater(
      ctx.request.post(
        rajsimsGateway,
        headers: {'Authid': 'other', 'Authkey': 'key'},
        data: payload,
        timeout: 5000,
      ),
      throwsArgumentError,
    );
    expect(client.calls.length, 1);
  });
  test(
    'context cookie paths/domains are isolated; storage is page-free',
    () async {
      final client = MemoryTransport(), ctx = await context(client);
      await ctx.addCookies([
        {
          'name': 'parent',
          'value': 'p',
          'domain': '.rajasthan.gov.in',
          'path': '/',
          'secure': true,
        },
        {
          'name': 'sso',
          'value': 's',
          'domain': 'sso.rajasthan.gov.in',
          'path': '/signin',
        },
        {
          'name': 'expired',
          'value': 'x',
          'domain': 'sso.rajasthan.gov.in',
          'expires': 1,
        },
      ]);
      expect(
        (await ctx.cookies([
          Uri.parse('https://rajsims-mdm.rajasthan.gov.in/'),
        ])).map((e) => e['name']).toSet(),
        {'session', 'parent'},
      );
      expect(
        (await ctx.cookies([Uri.parse('https://sso.rajasthan.gov.in/sso')]))
            .map((e) => e['name'])
            .toSet(),
        {'parent'},
      );
      expect((await ctx.storageState())['origins'], isEmpty);
      expect(ctx.pages, isEmpty);
      await ctx.close();
      expect(client.closes, 1);
      await ctx.close();
      expect(client.closes, 1);
    },
  );
  test(
    'rotated cookie returns to context authority and cannot leak to School jar',
    () async {
      final client = MemoryTransport(), ctx = await context(MemoryTransport());
      final school = SchoolCookieJar();
      client.handle = (call) async => reply(
        Uri.parse(call['url']),
        data: {'IsSuccess': true},
        headers: {
          'set-cookie': ['session=new-value; Path=/; HttpOnly; Secure'],
        },
      );
      final transport = RajsimsGatewayTransport(
        ctx,
        () => ctx,
        rajsimsGateway,
        client: client,
      );
      await transport.postRead(read, 'id', 'key');
      expect((await ctx.cookies()).single['value'], 'new-value');
      expect(school.records(), isEmpty);
      await transport.close();
    },
  );
  test(
    'close callback retires Gateway connection and prohibits later operations',
    () async {
      final client = MemoryTransport(),
          ctx = await context(MemoryTransport()),
          gateway = adapter(ctx, client);
      await gateway.request(ctx, read);
      await ctx.close();
      expect(client.closes, 1);
      expect((await gateway.request(ctx, read)).success, false);
      expect(client.calls.length, 1);
      await gateway.closeAll();
    },
  );
}
