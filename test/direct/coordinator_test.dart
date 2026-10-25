import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/core/direct/async_primitives.dart';
import '../../lib/services/core/direct/coordinator.dart';
import '../../lib/services/core/direct/coordinator_config.dart';
import '../../lib/services/core/direct/errors.dart';

class _Backend implements PortalBackend {
  Object? context = Object();
  int logins = 0, probes = 0;
  Probe verdict = Probe.alive;
  Completer<void>? authStarted, authRelease;
  @override
  Object? currentContext() => context;
  @override
  Future<Map<String, dynamic>> authenticate(
    String user,
    String password,
    bool forceFresh,
  ) async {
    logins++;
    authStarted?.complete();
    if (authRelease != null) await authRelease!.future;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    context = Object();
    return {'success': true};
  }

  @override
  Future<Probe> probe(Object context) async {
    probes++;
    return verdict;
  }
}

void main() {
  test(
    'recovery holds its lifecycle barrier until authentication settles',
    () async {
      final backend = _Backend()
        ..authStarted = Completer<void>()
        ..authRelease = Completer<void>();
      final co = PortalCoordinator(name: 'sd', backend: backend);
      co.rememberCredentials('school', 'password');
      var entered = false;
      try {
        final recovery = co.handleExpiry(1, 'expired', assumeDead: true);
        await backend.authStarted!.future;
        final read = co.run(
          resource: 'sd.student',
          kind: Kind.read,
          worker: (_) async {
            entered = true;
            return {'success': true};
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 15));
        expect(entered, false);
        backend.authRelease!.complete();
        expect(await recovery, Verdict.recovered);
        expect((await read)['success'], true);
      } finally {
        if (!backend.authRelease!.isCompleted) backend.authRelease!.complete();
        await co.shutdown();
      }
    },
  );

  test(
    'same-resource operations serialize; different resources can overlap',
    () async {
      final backend = _Backend();
      final co = PortalCoordinator(name: 'sd', backend: backend);
      co.markAlive(1);
      var active = 0, peak = 0;
      Future<Map<String, dynamic>> work(Object? _) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active--;
        return {'success': true};
      }

      try {
        await Future.wait([
          co.run(resource: 'sd.student', kind: Kind.read, worker: work),
          co.run(resource: 'sd.student', kind: Kind.read, worker: work),
        ]);
        expect(peak, 1);
        peak = 0;
        await Future.wait([
          co.run(resource: 'sd.student', kind: Kind.read, worker: work),
          co.run(resource: 'sd.leave', kind: Kind.read, worker: work),
        ]);
        expect(peak, 2);
        expect(backend.probes, 0);
      } finally {
        await co.shutdown();
      }
    },
  );

  test(
    'parallel expiry reports coalesce into one new login generation',
    () async {
      final backend = _Backend();
      final co = PortalCoordinator(name: 'sd', backend: backend);
      co.rememberCredentials('school', 'password');
      try {
        final results = await Future.wait([
          co.handleExpiry(1, 'first', assumeDead: true),
          co.handleExpiry(1, 'second', assumeDead: true),
        ]);
        expect(results, [Verdict.recovered, Verdict.alreadyRecovered]);
        expect(backend.logins, 1);
        expect(co.generation, 2);
      } finally {
        await co.shutdown();
      }
    },
  );

  test(
    'UNKNOWN is not evidence of logout; mutation admission remains blocked',
    () async {
      final backend = _Backend()..verdict = Probe.unknown;
      final co = PortalCoordinator(
        name: 'sd',
        backend: backend,
        config: const CoordinatorConfig(probeMaxAge: 0, mutationProbeMaxAge: 0),
      );
      co.rememberCredentials('school', 'password');
      try {
        await co.ensureReady(Kind.read);
        expect(backend.logins, 0);
        await expectLater(
          co.ensureReady(Kind.mutation),
          throwsA(
            isA<CoordinatorError>().having(
              (e) => e.kind,
              'kind',
              ErrorKind.sessionUnverified,
            ),
          ),
        );
        expect(backend.logins, 0);
      } finally {
        await co.shutdown();
      }
    },
  );

  test(
    'uncertain mutation keeps its lease and prevents replacement/replay',
    () async {
      final backend = _Backend();
      final co = PortalCoordinator(
        name: 'sd',
        backend: backend,
        config: const CoordinatorConfig(
          mutationSettleTimeout: 0.01,
          mutationDrainTimeout: 0.01,
          readCancelGrace: 0.01,
        ),
      );
      co.markAlive(1);
      final release = Completer<void>();
      var saves = 0;
      try {
        final request = co.run(
          resource: 'sd.student',
          kind: Kind.mutation,
          timeout: 0.01,
          maxAttempts: 1,
          worker: (_) async {
            saves++;
            await release.future;
            return {'success': true};
          },
        );
        await expectLater(
          request,
          throwsA(
            isA<CoordinatorError>().having(
              (e) => e.kind,
              'kind',
              ErrorKind.mutationAmbiguous,
            ),
          ),
        );
        expect(co.status()['active_mutations'], 1);
        final old = backend.context;
        final login = await co.authenticate(
          'other-school',
          'password',
          forceFresh: true,
        );
        expect(login['code'], 'BUSY');
        expect(identical(backend.context, old), true);
        expect(backend.logins, 0);
        expect(saves, 1);
      } finally {
        release.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await co.shutdown();
      }
    },
  );

  test('portal message survives ambiguous mutation classification', () async {
    final co = PortalCoordinator(name: 'sd', backend: _Backend());
    co.markAlive(1);
    try {
      await expectLater(
        co.run(
          resource: 'sd.student',
          kind: Kind.mutation,
          maxAttempts: 1,
          worker: (_) async => {
            'success': false,
            'code': 'SAVE_UNCONFIRMED',
            'submission_attempted': true,
            'message': 'Original portal message',
          },
        ),
        throwsA(
          isA<CoordinatorError>()
              .having((e) => e.message, 'message', 'Original portal message')
              .having(
                (e) => e.extra['upstream_response']['code'],
                'upstream code',
                'SAVE_UNCONFIRMED',
              ),
        ),
      );
    } finally {
      await co.shutdown();
    }
  });

  test('read timeout cooperatively aborts and releases its resource', () async {
    final co = PortalCoordinator(name: 'sd', backend: _Backend());
    co.markAlive(1);
    try {
      await expectLater(
        co.run(
          resource: 'sd.student',
          kind: Kind.read,
          timeout: 0.01,
          maxAttempts: 1,
          worker: (_) async {
            final done = Completer<Map<String, dynamic>>();
            final remove = OperationCancellation.current!.listen(
              () => done.completeError(const OperationCancelled()),
            );
            try {
              return await done.future;
            } finally {
              remove();
            }
          },
        ),
        throwsA(
          isA<CoordinatorError>().having(
            (e) => e.kind,
            'kind',
            ErrorKind.portalSlow,
          ),
        ),
      );
      expect(co.status()['active_operations'], 0);
    } finally {
      await co.shutdown();
    }
  });

  test(
    'preflight business failure is returned without submitting or replaying',
    () async {
      final co = PortalCoordinator(name: 'sd', backend: _Backend());
      co.markAlive(1);
      var calls = 0;
      try {
        final result = await co.run(
          resource: 'sd.student',
          kind: Kind.mutation,
          maxAttempts: 1,
          preMutationCodes: {'BAD_CLASS'},
          worker: (_) async {
            calls++;
            return {
              'success': false,
              'code': 'BAD_CLASS',
              'submission_attempted': false,
            };
          },
        );
        expect(result['code'], 'BAD_CLASS');
        expect(calls, 1);
      } finally {
        await co.shutdown();
      }
    },
  );
}
