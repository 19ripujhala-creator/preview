import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/services/core/direct/coordinator.dart';
import 'package:shaladarpan/services/core/direct/coordinator_config.dart';
import 'package:shaladarpan/services/core/direct/runtime_slot.dart';

class _Backend implements PortalBackend {
  final Object context = Object();
  @override
  Object? currentContext() => context;
  @override
  Future<Map<String, dynamic>> authenticate(
    String user,
    String password,
    bool forceFresh,
  ) async => {'success': true};
  @override
  Future<Probe> probe(Object context) async => Probe.alive;
}

class _Runtime {
  _Runtime(this.id)
    : coordinator = PortalCoordinator(
        name: 'fake',
        backend: _Backend(),
        config: const CoordinatorConfig(readCancelGrace: 0.01),
      );
  final int id;
  final PortalCoordinator coordinator;
}

void main() {
  test('failed retirement keeps the barrier; once work settles the next login gets a fresh runtime', () async {
    var created = 0;
    final slot = RuntimeSlot<_Runtime>(
      create: () async => _Runtime(++created),
      close: (runtime) => runtime.coordinator.shutdown(timeout: 0.05),
    );
    final first = await slot.get();
    first.coordinator.markAlive(1);
    final started = Completer<void>(), release = Completer<void>();
    final save = first.coordinator.run(
      resource: 'sd.student',
      kind: Kind.mutation,
      maxAttempts: 1,
      worker: (_) async {
        started.complete();
        await release.future;
        return {'success': true};
      },
    );
    try {
      await started.future;

      // Logout while the mutation is still running: retirement fails.
      await expectLater(slot.retire(), throwsA(isA<StateError>()));
      expect(slot.retirementPending, true);

      // Login must not build a second runtime on top of unsettled work.
      await expectLater(slot.get(), throwsA(isA<StateError>()));
      expect(created, 1);
      expect(slot.current, same(first));

      // The work settles; the next login retries the retirement and succeeds.
      release.complete();
      await save;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final second = await slot.get();
      expect(created, 2);
      expect(second, isNot(same(first)));
      expect(slot.current, same(second));
      expect(first.coordinator.status()['closed'], true);
      expect(slot.retirementPending, false);
    } finally {
      if (!release.isCompleted) release.complete();
    }
  });

  test('retiring a runtime that is no longer current is a no-op', () async {
    var closes = 0;
    final slot = RuntimeSlot<_Runtime>(
      create: () async => _Runtime(1),
      close: (runtime) async {
        closes++;
      },
    );
    final first = await slot.get();
    await slot.retire(first);
    expect(closes, 1);
    expect(slot.current, null);
    final second = await slot.get();
    await slot.retire(first); // stale handle must not retire the new runtime
    expect(closes, 1);
    expect(slot.current, same(second));
  });

  test('failed creation is not cached', () async {
    var attempts = 0;
    final slot = RuntimeSlot<_Runtime>(
      create: () async {
        if (++attempts == 1) throw StateError('storage unavailable');
        return _Runtime(attempts);
      },
      close: (runtime) async {},
    );
    await expectLater(slot.get(), throwsA(isA<StateError>()));
    final runtime = await slot.get();
    expect(attempts, 2);
    expect(slot.current, same(runtime));
  });
}
