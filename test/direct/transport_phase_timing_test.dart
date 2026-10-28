import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/experiments/direct_portal_auth.dart';
import '../../lib/services/core/direct/portal_diagnostics.dart';
import '../../lib/services/portals/shaladarpan/direct/auth_manager.dart';
import '../../lib/services/portals/shaladarpan/direct/school_http.dart';

const _page =
    '/SD1/Home/School/StudentdailyAttendanceStatus_Web_NewVersion.aspx';
List<Map<String, dynamic>> _events() =>
    (jsonDecode(PortalDiagnostics.export())['events'] as List)
        .cast<Map<String, dynamic>>();

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), true);
}

class _Storage implements SchoolAuthStorage {
  final firstWrite = Completer<void>(), release = Completer<void>();
  int writes = 0;
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> delete(String key) async {}
  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (writes == 1) {
      firstWrite.complete();
      await release.future;
    }
  }
}

class _MappedClient implements HttpClient {
  _MappedClient(this.inner, this.local);
  final HttpClient inner;
  final Uri local;
  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      inner.openUrl(method, local.resolve(url.path));
  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VerifiedDirectAuth extends DirectPortalAuth {
  @override
  bool get isVerified => true;
}

void main() {
  setUp(PortalDiagnostics.clear);

  test('pooled request phases retain root, action and safe labels', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final client = SchoolHttpClient(
      baseUrl: base,
      allowUrl: (u) => u.origin == base.origin,
    );
    final subscription = server.listen((request) async {
      await request.drain<void>();
      request.response.write('private-body');
      await request.response.close();
    });
    try {
      final reply = await PortalDiagnostics.withAction(
        'CLASS_ENTRY',
        () => client.post(_page, data: {'private-student': 'private-status'}),
      );
      expect(reply.text, 'private-body');
      final all = _events();
      final root = all.singleWhere((e) => e['phase'] == 'httpRequest');
      for (final phase in [
        'httpOpen',
        'httpResponseHeaders',
        'httpResponseBody',
      ]) {
        final child = all.singleWhere((e) => e['phase'] == phase);
        expect(child['parent_sequence'], root['sequence']);
        expect(child['request_sequence'], root['sequence']);
        expect(child['action'], 'CLASS_ENTRY');
        expect(child['transport'], 'pooled');
        expect(child['hop'], 0);
        expect(child['started_ms'], greaterThanOrEqualTo(root['started_ms']));
        expect(child['ended_ms'], lessThanOrEqualTo(root['ended_ms']));
      }
      final exported = PortalDiagnostics.export();
      expect(exported, isNot(contains('private-body')));
      expect(exported, isNot(contains('private-student')));
      expect(exported, isNot(contains('private-status')));
    } finally {
      client.retire();
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test(
    'cookie storage still completes before response-body consumption',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final started = Completer<void>(), release = Completer<void>();
      final client = SchoolHttpClient(
        baseUrl: base,
        allowUrl: (u) => u.origin == base.origin,
        onCookies: (_, _) async {
          started.complete();
          await release.future;
        },
      );
      final subscription = server.listen((request) async {
        await request.drain<void>();
        request.response.cookies.add(Cookie('session', 'private-cookie'));
        request.response.write('ready');
        await request.response.close();
      });
      final pending = client.get(_page);
      try {
        await started.future.timeout(const Duration(seconds: 3));
        expect(_events().any((e) => e['phase'] == 'httpResponseHeaders'), true);
        expect(_events().any((e) => e['phase'] == 'httpResponseBody'), false);
        release.complete();
        expect((await pending).text, 'ready');
        final all = _events();
        final cookie = all.singleWhere(
          (e) => e['phase'] == 'httpCookiePersistence',
        );
        final body = all.singleWhere((e) => e['phase'] == 'httpResponseBody');
        expect(body['started_ms'], greaterThanOrEqualTo(cookie['ended_ms']));
        expect(PortalDiagnostics.export(), isNot(contains('private-cookie')));
      } finally {
        if (!release.isCompleted) release.complete();
        await pending;
        client.retire();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );

  test(
    'failed cookie write remains nonfatal and records no exception text',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final client = SchoolHttpClient(
        baseUrl: base,
        allowUrl: (u) => u.origin == base.origin,
        onCookies: (_, _) async => throw StateError('private-storage-error'),
      );
      final subscription = server.listen((request) async {
        await request.drain<void>();
        request.response.cookies.add(Cookie('session', 'one'));
        request.response.write('kept');
        await request.response.close();
      });
      try {
        expect((await client.get(_page)).text, 'kept');
        expect(
          _events().singleWhere(
            (e) => e['phase'] == 'httpCookiePersistence',
          )['outcome'],
          'exception',
        );
        expect(
          PortalDiagnostics.export(),
          isNot(contains('private-storage-error')),
        );
      } finally {
        client.retire();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );

  test('header and body waits have separate boundaries', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final headers = Completer<void>(), body = Completer<void>();
    final received = Completer<void>();
    final client = SchoolHttpClient(
      baseUrl: base,
      allowUrl: (u) => u.origin == base.origin,
    );
    final subscription = server.listen((request) async {
      await request.drain<void>();
      received.complete();
      await headers.future;
      request.response.write('part');
      await request.response.flush();
      await body.future;
      request.response.write('end');
      await request.response.close();
    });
    final pending = client.get(_page);
    try {
      await received.future.timeout(const Duration(seconds: 3));
      expect(_events().any((e) => e['phase'] == 'httpOpen'), true);
      expect(_events().any((e) => e['phase'] == 'httpResponseHeaders'), false);
      headers.complete();
      await _until(
        () => _events().any((e) => e['phase'] == 'httpResponseHeaders'),
      );
      expect(_events().any((e) => e['phase'] == 'httpResponseBody'), false);
      body.complete();
      expect((await pending).text, 'partend');
    } finally {
      if (!headers.isCompleted) headers.complete();
      if (!body.isCompleted) body.complete();
      await pending;
      client.retire();
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test(
    'redirect hops share one root and preserve GET redirect policy',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final methods = <String>[];
      final client = SchoolHttpClient(
        baseUrl: base,
        allowUrl: (u) => u.origin == base.origin,
      );
      final subscription = server.listen((request) async {
        await request.drain<void>();
        methods.add(request.method);
        if (methods.length == 1) {
          request.response.statusCode = 302;
          request.response.headers.set('location', _page);
        } else {
          request.response.write('next');
        }
        await request.response.close();
      });
      try {
        expect(
          (await client.request(
            'POST',
            base.resolve('/start'),
            body: utf8.encode('submit=one'),
            allowPostRedirects: false,
          )).text,
          'next',
        );
        expect(methods, ['POST', 'GET']);
        final all = _events(),
            root = _events().singleWhere((e) => e['phase'] == 'httpRequest');
        expect(
          all
              .where((e) => e['phase'] == 'httpResponseHeaders')
              .map((e) => e['hop']),
          [0, 1],
        );
        expect(
          all.every((e) => e['request_sequence'] == root['sequence']),
          true,
        );
      } finally {
        client.retire();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );

  test('real auth write queue is measured separately without changing ordering or dedup', () async {
    final storage = _Storage();
    final auth = SchoolAuthManager(
      storage: storage,
      solveCaptcha: (_) async => 'unused',
    );
    await auth.initialize();
    final first = PortalDiagnostics.measure(
      PortalPhase.httpRequest,
      () => auth.saveSessionCookies({'session': 'private-one'}),
      source: 'school',
      method: 'POST',
      path: _page,
    );
    await storage.firstWrite.future.timeout(const Duration(seconds: 3));
    final second = auth.saveSessionCookies({'session': 'private-two'});
    await Future<void>.delayed(Duration.zero);
    expect(storage.writes, 1);
    storage.release.complete();
    await Future.wait([first, second]);
    await auth.saveSessionCookies({'session': 'private-two'});
    expect(storage.writes, 2);
    expect(
      _events().where((e) => e['phase'] == 'httpStorageWrite'),
      hasLength(2),
    );
    expect(
      _events().where((e) => e['phase'] == 'httpStorageQueue'),
      hasLength(3),
    );
    final root = _events().singleWhere((e) => e['phase'] == 'httpRequest');
    for (final phase in ['httpStorageQueue', 'httpStorageWrite']) {
      final child = _events().firstWhere((e) => e['phase'] == phase);
      expect(child['request_sequence'], root['sequence']);
    }
    expect(PortalDiagnostics.export(), isNot(contains('private-')));
    await auth.closeAuthenticatedClients();
  });

  test(
    'direct fallback gets its own component events and retains request count',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final native = HttpClient();
      var requests = 0;
      final subscription = server.listen((request) async {
        requests++;
        await request.drain<void>();
        request.response.write('direct');
        await request.response.close();
      });
      try {
        await HttpOverrides.runZoned(() async {
          final auth = _VerifiedDirectAuth();
          try {
            final result = await PortalDiagnostics.withAction(
              'GET_PAGE',
              () => auth.attendanceRequest(
                Uri.parse('https://rajshaladarpan.rajasthan.gov.in$_page'),
              ),
            );
            expect(result.html, 'direct');
          } finally {
            auth.close();
          }
        }, createHttpClient: (_) => _MappedClient(native, base));
        expect(requests, 1);
        final all = _events(),
            root = _events().singleWhere((e) => e['phase'] == 'httpRequest');
        expect(root['transport'], 'direct');
        expect(root['source'], 'school');
        for (final phase in [
          'httpOpen',
          'httpResponseHeaders',
          'httpResponseBody',
        ]) {
          final child = all.singleWhere((e) => e['phase'] == phase);
          expect(child['request_sequence'], root['sequence']);
          expect(child['action'], 'GET_PAGE');
        }
      } finally {
        native.close(force: true);
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
