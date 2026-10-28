import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/core/direct/mutation_dispatch.dart';
import '../../lib/services/portals/shaladarpan/direct/school_http.dart';
import 'student_worker_test.dart' show FakePortal, date, students;

class InvalidActionPortal extends FakePortal {
  @override
  String entry() => super.entry().replaceFirst(
    'action="StudentdailyAttendanceStatus_Web_NewVersion.aspx"',
    'action="https://invalid.example/blocked"',
  );
}

void main() {
  for (final code in [307, 308, 302, 303]) {
    test('SAVE redirect $code never produces a second POST', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final client = SchoolHttpClient(
        baseUrl: base,
        allowUrl: (u) => u.host == '127.0.0.1' && u.port == server.port,
      );
      final seen = <String>[];
      final sub = server.listen((r) async {
        seen.add('${r.method} ${r.uri.path}');
        await r.drain<void>();
        if (r.uri.path == '/save') {
          r.response.statusCode = code;
          r.response.headers.set('location', '/next');
        } else {
          r.response.write('ok');
        }
        await r.response.close();
      });
      try {
        final response = await client.request(
          'POST',
          base.resolve('/save'),
          allowPostRedirects: false,
          body: [1],
        );
        expect(
          seen,
          code >= 307 ? ['POST /save'] : ['POST /save', 'GET /next'],
        );
        expect(response.statusCode, code >= 307 ? code : 200);
      } finally {
        client.retire();
        await sub.cancel();
        await server.close(force: true);
      }
    });
  }
  test('response-body timeout releases native client ownership for a later read', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = SchoolHttpClient(baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      timeout: const Duration(milliseconds: 150), allowUrl: (u) => u.host == '127.0.0.1' && u.port == server.port);
    final release = Completer<void>();
    final subscription = server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path == '/slow') {
        request.response.write('partial'); await request.response.flush();
        await release.future;
      } else { request.response.write('ready'); }
      try { await request.response.close(); } catch (_) {}
    });
    try {
      await expectLater(client.get('/slow'), throwsA(isA<TimeoutException>()));
      expect(client.idleActivityStamp, isNotNull);
      final reply = await client.get('/ready', timeout: const Duration(seconds: 2));
      expect(reply.statusCode, 200); expect(reply.text, 'ready');
    } finally {
      release.complete(); client.retire(); await subscription.cancel(); await server.close(force: true);
    }
  });
  test(
    'READ navigation still supports original 307 redirect behavior',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = SchoolHttpClient(
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        allowUrl: (u) => u.port == server.port && u.host == '127.0.0.1',
      );
      final seen = <String>[];
      final sub = server.listen((r) async {
        seen.add(r.method);
        await r.drain<void>();
        if (seen.length == 1) {
          r.response.statusCode = 307;
          r.response.headers.set('location', '/next');
        }
        await r.response.close();
      });
      try {
        await client.post('/start', data: {'show': '1'});
        expect(seen, ['POST', 'POST']);
      } finally {
        client.retire();
        await sub.cancel();
        await server.close(force: true);
      }
    },
  );
  test('preflight Show POST does not count as attendance dispatch', () async {
    final tracker = MutationDispatch();
    tracker.observeNativeTransport();
    tracker.startDispatch();
    expect(tracker.mayHaveStarted, false);
    tracker.enterRequest();
    tracker.startDispatch();
    expect(tracker.mayHaveStarted, true);
  });
  test(
    'local invalid form action sends zero SAVE calls and is not ambiguous',
    () async {
      final portal = InvalidActionPortal();
      final result = await portal.worker.saveStudentAttendance(
        classId: '1',
        attendanceDate: date,
        section: '1A',
        students: students,
        userConfirmed: true,
      );
      expect(portal.saves, 0);
      expect(result['submission_attempted'], false);
      expect(result['code'], 'PORTAL_RESPONSE_ERROR');
    },
  );
  test('blocked native URL is rejected before dispatch', () async {
    final tracker = MutationDispatch();
    final client = SchoolHttpClient(
      baseUrl: Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1'),
    );
    try {
      await expectLater(
        tracker.run(() async {
          tracker.enterRequest();
          await client.post(
            'https://invalid.example/save',
            data: {'synthetic': 'one'},
          );
        }),
        throwsStateError,
      );
      expect(tracker.mayHaveStarted, false);
    } finally {
      client.retire();
    }
  });
  test(
    'network timeout after dispatch remains uncertain with only one POST',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = SchoolHttpClient(
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        allowUrl: (u) => u.host == '127.0.0.1' && u.port == server.port,
      );
      var posts = 0;
      final sub = server.listen((r) async {
        posts++;
        await r.drain<void>();
      });
      final tracker = MutationDispatch();
      try {
        await expectLater(
          tracker.run(() async {
            tracker.enterRequest();
            await client.request(
              'POST',
              client.resolve('/save'),
              allowPostRedirects: false,
              body: [1],
              timeout: const Duration(milliseconds: 100),
            );
          }),
          throwsA(isA<TimeoutException>()),
        );
        expect(tracker.mayHaveStarted, true);
        expect(posts, 1);
      } finally {
        client.retire();
        await sub.cancel();
        await server.close(force: true);
      }
    },
  );
}
