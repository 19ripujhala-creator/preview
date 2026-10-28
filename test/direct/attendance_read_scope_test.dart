import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/core/direct/attendance_read_scope.dart';

void main() {
  final session = Object();
  AttendanceReadScope scope({
    String school = 'one',
    Object? owner,
    String identity = 'generation1',
    int revision = 0,
  }) => AttendanceReadScope(
    school: school,
    session: owner ?? session,
    identity: identity,
    revision: revision,
  );

  test('same session values compare equal without exposing credentials', () {
    expect(scope(), scope());
    expect({scope(): 'snapshot'}[scope()], 'snapshot');
  });
  for (final change in ['school', 'owner', 'generation', 'revision']) {
    test('$change invalidates every cached class', () {
      final cache = AttendanceReadCache<String>();
      cache.write(scope(), '1A/date', 'old');
      cache.write(scope(), '2B/date', 'old too');
      final next = scope(
        school: change == 'school' ? 'two' : 'one',
        owner: change == 'owner' ? Object() : session,
        identity: change == 'generation' ? 'generation2' : 'generation1',
        revision: change == 'revision' ? 1 : 0,
      );
      expect(cache.read(next, '1A/date'), null);
      expect(cache.values, isEmpty);
    });
  }
  test('class section and date keys stay independent', () {
    final cache = AttendanceReadCache<String>();
    cache.write(scope(), '1A/day1', 'one');
    expect(cache.read(scope(), '1B/day1'), null);
    expect(cache.read(scope(), '1A/day2'), null);
    expect(cache.read(scope(), '1A/day1'), 'one');
  });
  test('reading a cache entry does not extend its freshness', () {
    var elapsed = Duration.zero;
    final cache = AttendanceReadCache<String>(elapsed: () => elapsed);
    cache.write(scope(), 'class', 'snapshot');
    elapsed = const Duration(seconds: 44);
    expect(cache.read(scope(), 'class'), 'snapshot');
    elapsed = const Duration(seconds: 45);
    expect(cache.read(scope(), 'class'), null);
  });
  test('clock regression cannot restore expired data', () {
    var elapsed = const Duration(seconds: 10);
    final cache = AttendanceReadCache<String>(elapsed: () => elapsed);
    cache.write(scope(), 'class', 'snapshot');
    elapsed = Duration.zero;
    expect(cache.read(scope(), 'class'), null);
  });
  test('cache stays bounded and updates replace old timestamps', () {
    var elapsed = Duration.zero;
    final cache = AttendanceReadCache<String>(
      maxEntries: 2,
      elapsed: () => elapsed,
    );
    cache.write(scope(), '1', 'first');
    cache.write(scope(), '2', 'second');
    cache.write(scope(), '3', 'third');
    expect(cache.read(scope(), '1'), null);
    elapsed = const Duration(seconds: 30);
    cache.write(scope(), '2', 'refreshed');
    elapsed = const Duration(seconds: 60);
    expect(cache.read(scope(), '2'), 'refreshed');
    expect(cache.read(scope(), '3'), null);
  });
  test('verified Save preserves other classes without extending their TTL', () {
    var elapsed = Duration.zero;
    final cache = AttendanceReadCache<String>(elapsed: () => elapsed);
    cache.write(scope(), 'A', 'old A'); cache.write(scope(), 'B', 'B');
    elapsed = const Duration(seconds: 40);
    expect(cache.rebaseAfterVerifiedSave(scope(), scope(revision: 2), 2), true);
    cache.removeWhere((key, _) => key == 'A');
    cache.write(scope(revision: 2), 'A', 'verified A');
    expect(cache.read(scope(revision: 2), 'B'), 'B');
    elapsed = const Duration(seconds: 45);
    expect(cache.read(scope(revision: 2), 'B'), null);
    expect(cache.read(scope(revision: 2), 'A'), 'verified A');
  });
  for (final kind in ['school','identity','owner','revision']) {
    test('local Save rebase rejects unexpected $kind', () {
      final cache = AttendanceReadCache<String>(); cache.write(scope(), 'A','old');
      expect(cache.rebaseAfterVerifiedSave(scope(), scope(
        school: kind == 'school' ? 'other' : 'one',
        identity: kind == 'identity' ? 'other' : 'generation1',
        owner: kind == 'owner' ? Object() : session,
        revision: kind == 'revision' ? 4 : 2), 2), false);
      expect(cache.values,isEmpty);
    });
  }
  test('clear removes cached data even in the same scope', () {
    final cache = AttendanceReadCache<String>();
    cache.write(scope(), 'class', 'snapshot');
    cache.clear();
    expect(cache.read(scope(), 'class'), null);
  });
}
