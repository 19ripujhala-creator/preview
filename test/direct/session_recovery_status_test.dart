import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:shaladarpan/services/core/direct/coordinator.dart';
import 'package:shaladarpan/services/core/ecosystem_service.dart';
import 'package:shaladarpan/experiments/direct_school_session.dart';

import 'class_mapping_test.dart' show MappingAuth, MappingPortal, updates;

class RecoveryBackend implements PortalBackend {
  RecoveryBackend(this.portal);
  final MappingPortal portal;
  Object? context;
  int logins = 0;
  Completer<void>? started, release;
  @override
  Object? currentContext() => context;
  @override
  Future<Probe> probe(Object context) async => Probe.alive;
  @override
  Future<Map<String, dynamic>> authenticate(
    String user,
    String password,
    bool forceFresh,
  ) async {
    logins++;
    started?.complete();
    await release?.future;
    context = Object();
    portal.key = 'session-$logins';
    return {'success': true};
  }
}

class RecoveryAuth extends MappingAuth {
  RecoveryAuth(super.portal, this.co);
  final PortalCoordinator co;
  bool closed = false;
  @override
  PortalCoordinator? get coordinator => co;
  @override
  bool get isVerified =>
      !closed && co.contextIsCurrent() && co.health == Health.ready;
  @override
  bool get canRecover => !closed && co.status()['closed'] != true;
  @override
  String get schoolSessionIdentity => isVerified ? portal.key : '';
  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  tearDown(DirectSchoolSession.reset);
  test('local status identifies absent sessions without any login', () {
    final row = EcosystemService.describeNativePortal(null);
    expect(row['coordinator_health'], 'IDLE');
    expect(row['live'], false);
  });
  test('status reads true READY context and never probes', () async {
    final backend = RecoveryBackend(MappingPortal());
    final co = PortalCoordinator(name: 'sd', backend: backend);
    try {
      await co.authenticate('123456', 'password');
      final row = EcosystemService.describeNativePortal(co);
      expect(row['state'], 'ready');
      expect(row['live'], true);
      expect(row['coordinator_health'], 'READY');
      expect(backend.logins, 1);
    } finally {
      await co.shutdown();
    }
  });
  test('stale READY context cannot be displayed as Active', () async {
    final backend = RecoveryBackend(MappingPortal());
    final co = PortalCoordinator(name: 'sd', backend: backend);
    try {
      await co.authenticate('123456', 'password');
      backend.context = null;
      expect(EcosystemService.describeNativePortal(co)['live'], false);
    } finally {
      await co.shutdown();
    }
  });
  test('UNKNOWN restored context stays unconfirmed', () async {
    final backend = RecoveryBackend(MappingPortal())..context = Object();
    final co = PortalCoordinator(name: 'sd', backend: backend);
    try {
      final row = EcosystemService.describeNativePortal(co);
      expect(row['coordinator_health'], 'UNKNOWN');
      expect(row['state'], 'unknown');
      expect(row['live'], false);
      expect(backend.logins, 0);
    } finally {
      await co.shutdown();
    }
  });
  test('attached School READ waits for one in-flight recovery and uses new identity', () async {
    final portal = MappingPortal();
    final backend = RecoveryBackend(portal);
    final co = PortalCoordinator(name: 'sd', backend: backend);
    try {
      await co.authenticate('123456', 'password');
      DirectSchoolSession.attach(RecoveryAuth(portal, co), '123456');
      backend.context = null;
      backend.started = Completer();
      backend.release = Completer();
      final recovery = co.handleExpiry(
        co.generation,
        'offline expiry',
        assumeDead: true,
      );
      await backend.started!.future;
      expect(DirectSchoolSession.ready, false);
      expect(DirectSchoolSession.available, true);
      final row = EcosystemService.describeNativePortal(co);
      expect(row['state'], 'loading');
      expect(row['live'], false);
      final read = DirectSchoolSession.classMappings!.fetch();
      expect(portal.gets, 0);
      backend.release!.complete();
      await recovery;
      final result = await read;
      expect(result['success'], true, reason: '$result');
      expect(portal.gets, 1);
      expect(portal.posts, 0);
      expect(backend.logins, 2);
    } finally {
      backend.release?.isCompleted == false
          ? backend.release!.complete()
          : null;
      await co.shutdown();
    }
  });
  test('mapping mutation review is not rebound after recovery', () async {
    final portal = MappingPortal();
    final backend = RecoveryBackend(portal);
    final co = PortalCoordinator(name: 'sd', backend: backend);
    try {
      await co.authenticate('123456', 'password');
      DirectSchoolSession.attach(RecoveryAuth(portal, co), '123456');
      await DirectSchoolSession.classMappings!.fetch();
      backend.context = null;
      backend.started = Completer();
      backend.release = Completer();
      final recovery = co.handleExpiry(
        co.generation,
        'offline expiry',
        assumeDead: true,
      );
      await backend.started!.future;
      final save = DirectSchoolSession.classMappings!.save(
        updates(),
        userConfirmed: true,
      );
      backend.release!.complete();
      await recovery;
      final result = await save;
      expect(result['success'], false);
      expect(portal.posts, 0);
    } finally {
      backend.release?.isCompleted == false
          ? backend.release!.complete()
          : null;
      await co.shutdown();
    }
  });
  test('logout removes recoverable service handles immediately', () async {
    final portal = MappingPortal();
    final backend = RecoveryBackend(portal);
    final co = PortalCoordinator(name: 'sd', backend: backend);
    try {
      await co.authenticate('123456', 'password');
      DirectSchoolSession.attach(RecoveryAuth(portal, co), '123456');
      DirectSchoolSession.reset();
      expect(DirectSchoolSession.available, false);
      expect(DirectSchoolSession.classMappings, null);
    } finally {
      await co.shutdown();
    }
  });
  test('native snapshot cannot mark a detached School view Active', () async {
    final portal = MappingPortal();
    final backend = RecoveryBackend(portal);
    final co = PortalCoordinator(name: 'sd', backend: backend);
    try {
      await co.authenticate('123456', 'password');
      final auth = RecoveryAuth(portal, co);
      DirectSchoolSession.attach(auth, '123456');
      auth.closed = true;
      final row =
          (EcosystemService.statusSnapshot()['portals'] as Map)['shaladarpan']
              as Map;
      expect(row['live'], false);
      expect(row['coordinator_health'], 'UNKNOWN');
    } finally {
      await co.shutdown();
    }
  });
}
