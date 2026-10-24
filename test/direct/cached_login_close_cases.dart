import 'dart:async';

import '../../lib/services/core/direct/coordinator.dart';
import '../../lib/services/core/direct/coordinator_config.dart';

void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

class _Backend implements PortalBackend {
  Object? context;
  final logins = <(String, String, bool)>[];
  int probes = 0;
  Probe verdict = Probe.alive;
  bool probeThrows = false;
  Completer<void>? probeEntered, releaseProbe, authEntered, releaseAuth;
  @override
  Object? currentContext() => context;
  @override
  Future<Map<String, dynamic>> authenticate(
    String user,
    String password,
    bool fresh,
  ) async {
    logins.add((user, password, fresh));
    authEntered?.complete();
    final gate = releaseAuth;
    if (gate != null) await gate.future;
    context = Object();
    return {
      'success': true,
      'message': 'Original authentication result',
      'message_source': 'portal',
    };
  }

  @override
  Future<Probe> probe(Object context) async {
    probes++;
    probeEntered?.complete();
    final gate = releaseProbe;
    if (gate != null) await gate.future;
    if (probeThrows) throw StateError('Scripted probe transport failure');
    return verdict;
  }

  void unblock() {
    for (final gate in [releaseProbe, releaseAuth]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
  }
}

PortalCoordinator _co(_Backend b, {double age = 0}) => PortalCoordinator(
  name: 'sd',
  backend: b,
  config: CoordinatorConfig(
    probeMaxAge: age,
    probeTimeout: 2,
    authTimeout: 2,
    defaultLeaseWait: 2,
  ),
);
Future<void> _open(PortalCoordinator co) async {
  _check(
    (await co.authenticate('school-A', 'password-A'))['success'] == true,
    'Initial login failed',
  );
  await Future<void>.delayed(const Duration(milliseconds: 1));
}

Map<String, Future<void> Function()> cachedLoginCloseCases() => {
  for (final verdict in [Probe.alive, Probe.unknown, Probe.dead])
    'cached login cannot succeed after shutdown during probe: ${verdict.name}':
        () async {
          final b = _Backend()..verdict = verdict;
          final co = _co(b);
          try {
            await _open(co);
            b.probeEntered = Completer<void>();
            b.releaseProbe = Completer<void>();
            final login = co.authenticate('school-A', 'password-A');
            await b.probeEntered!.future;
            final generation = co.generation;
            final closing = co.shutdown(timeout: 1);
            _check(
              co.status()['closed'] == true,
              'Shutdown did not close admission',
            );
            b.releaseProbe!.complete();
            Map<String, dynamic>? result;
            try {
              result = await login;
            } catch (_) {}
            await closing;
            _check(
              result?['success'] != true,
              'Closed runtime returned cached login success',
            );
            _check(
              co.status()['keepalive'] == false,
              'Late login re-enabled keepalive',
            );
            _check(
              co.generation == generation && b.logins.length == 1,
              'Late probe started fresh auth',
            );
            _check(
              !co.hasPendingWork(),
              'Shutdown retained settled background work',
            );
          } finally {
            b.unblock();
            await co.shutdown(timeout: 1);
          }
        },
  'cached login probe exception during shutdown cannot retain session as success':
      () async {
        final b = _Backend()..probeThrows = true;
        final co = _co(b);
        try {
          await _open(co);
          b.probeEntered = Completer<void>();
          b.releaseProbe = Completer<void>();
          final login = co.authenticate('school-A', 'password-A');
          await b.probeEntered!.future;
          final closing = co.shutdown(timeout: 1);
          b.releaseProbe!.complete();
          Map<String, dynamic>? result;
          try {
            result = await login;
          } catch (_) {}
          await closing;
          _check(
            result?['success'] != true,
            'Failed late probe returned retained login success',
          );
          _check(
            co.status()['keepalive'] == false,
            'Failed late probe re-enabled keepalive',
          );
        } finally {
          b.unblock();
          await co.shutdown(timeout: 1);
        }
      },
  for (final verdict in [Probe.alive, Probe.unknown])
    'open cached login retains existing probe behavior: ${verdict.name}':
        () async {
          final b = _Backend()..verdict = verdict;
          final co = _co(b);
          try {
            await _open(co);
            final generation = co.generation;
            final result = await co.authenticate('school-A', 'password-A');
            _check(
              result['success'] == true && result['cached'] == true,
              'Open cached session rejected',
            );
            _check(
              result['session_verified'] == (verdict == Probe.alive),
              'Probe verdict was changed',
            );
            _check(
              b.logins.length == 1 &&
                  b.probes == 1 &&
                  co.generation == generation,
              'Cached login re-authenticated',
            );
          } finally {
            await co.shutdown(timeout: 1);
          }
        },
  'open cached login preserves uncertain probe exception without force login':
      () async {
        final b = _Backend()..probeThrows = true;
        final co = _co(b);
        try {
          await _open(co);
          final result = await co.authenticate('school-A', 'password-A');
          _check(
            result['success'] == true && result['session_verified'] == false,
            'Open uncertain session was discarded',
          );
          _check(b.logins.length == 1, 'Probe exception forced a new login');
        } finally {
          await co.shutdown(timeout: 1);
        }
      },
  'recent same credentials reuse ready session without probe': () async {
    final b = _Backend();
    final actual = _co(b, age: 60);
    try {
      await _open(actual);
      final result = await actual.authenticate('school-A', 'password-A');
      _check(
        result['success'] == true && result['cached'] == true,
        'Recent ready login failed',
      );
      _check(
        b.probes == 0 && b.logins.length == 1,
        'Recent login added network work',
      );
    } finally {
      await actual.shutdown(timeout: 1);
    }
  },
  'open dead probe still performs exactly one fresh login': () async {
    final b = _Backend()..verdict = Probe.dead;
    final co = _co(b);
    try {
      await _open(co);
      final result = await co.authenticate('school-A', 'password-A');
      _check(
        result['success'] == true && result['cached'] != true,
        'Dead session was retained',
      );
      _check(
        b.probes == 1 && b.logins.length == 2 && b.logins.last.$3,
        'Fresh auth sequence changed',
      );
      _check(
        result['message'] == 'Original authentication result' &&
            result['message_source'] == 'portal',
        'Portal result changed',
      );
    } finally {
      await co.shutdown(timeout: 1);
    }
  },
  'changed password bypasses cached session and authenticates once': () async {
    final b = _Backend();
    final co = _co(b, age: 60);
    try {
      await _open(co);
      final result = await co.authenticate('school-A', 'new-password');
      _check(
        result['success'] == true && result['cached'] != true,
        'Changed password used cached session',
      );
      _check(
        b.probes == 0 &&
            b.logins.length == 2 &&
            b.logins.last == ('school-A', 'new-password', true),
        'Changed password auth differed',
      );
    } finally {
      await co.shutdown(timeout: 1);
    }
  },
  'force fresh same-account login still bypasses cache': () async {
    final b = _Backend();
    final co = _co(b, age: 60);
    try {
      await _open(co);
      final result = await co.authenticate(
        'school-A',
        'password-A',
        forceFresh: true,
      );
      _check(
        result['success'] == true && b.logins.length == 2 && b.logins.last.$3,
        'Forced fresh login used cache',
      );
    } finally {
      await co.shutdown(timeout: 1);
    }
  },
  'fresh authentication settling after shutdown still returns shutdown failure':
      () async {
        final b = _Backend();
        final co = _co(b);
        try {
          b.authEntered = Completer<void>();
          b.releaseAuth = Completer<void>();
          final login = co.authenticate('school-A', 'password-A');
          await b.authEntered!.future;
          final closing = co.shutdown(timeout: 1);
          b.releaseAuth!.complete();
          final result = await login;
          await closing;
          _check(
            result['success'] == false && result['code'] == 'SHUTDOWN',
            'Fresh auth published success after close',
          );
          _check(
            co.status()['keepalive'] == false,
            'Fresh late login enabled keepalive',
          );
        } finally {
          b.unblock();
          await co.shutdown(timeout: 1);
        }
      },
  'read waiting behind cached login cannot start after shutdown': () async {
    final b = _Backend();
    final co = _co(b);
    var workers = 0;
    try {
      await _open(co);
      b.probeEntered = Completer<void>();
      b.releaseProbe = Completer<void>();
      final login = co.authenticate('school-A', 'password-A');
      await b.probeEntered!.future;
      final read = co.run(
        resource: 'school.read',
        kind: Kind.read,
        maxAttempts: 1,
        worker: (_) async {
          workers++;
          return {'success': true};
        },
      );
      final observed = read.then<Object>((r) => r, onError: (Object e) => e);
      final closing = co.shutdown(timeout: 1);
      b.releaseProbe!.complete();
      try {
        await login;
      } catch (_) {}
      await observed;
      await closing;
      _check(workers == 0, 'Waiting read entered closed runtime');
    } finally {
      b.unblock();
      await co.shutdown(timeout: 1);
    }
  },
};
