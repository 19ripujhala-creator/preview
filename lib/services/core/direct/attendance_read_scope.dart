/// A UI snapshot belongs to one account, session and attendance revision.
/// Session objects stay in memory; cookies and credentials are never exposed.
class AttendanceReadScope {
  const AttendanceReadScope({
    required this.school,
    required this.session,
    required this.identity,
    required this.revision,
  });

  final String school;
  final Object session;
  final String identity;
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is AttendanceReadScope &&
      school == other.school &&
      identical(session, other.session) &&
      identity == other.identity &&
      revision == other.revision;

  @override
  int get hashCode =>
      Object.hash(school, identityHashCode(session), identity, revision);
}

/// Short-lived display cache. It never authorizes a portal SAVE or skips its
/// roster preflight. A monotonic clock avoids device wall-clock changes.
class AttendanceReadCache<T> {
  AttendanceReadCache({
    this.ttl = const Duration(seconds: 45),
    this.maxEntries = 12,
    Duration Function()? elapsed,
  }) : assert(maxEntries > 0) {
    final clock = Stopwatch()..start();
    _elapsed = elapsed ?? (() => clock.elapsed);
  }

  final Duration ttl;
  final int maxEntries;
  late final Duration Function() _elapsed;
  AttendanceReadScope? _scope;
  final Map<String, ({Duration at, T value})> _entries = {};

  void _bind(AttendanceReadScope scope) {
    if (_scope != scope) {
      _entries.clear();
      _scope = scope;
    }
  }

  T? read(AttendanceReadScope scope, String key) {
    _bind(scope);
    final entry = _entries[key];
    if (entry == null) return null;
    final age = _elapsed() - entry.at;
    if (age.isNegative || age >= ttl) {
      _entries.remove(key);
      return null;
    }
    return entry.value;
  }

  void write(AttendanceReadScope scope, String key, T value) {
    _bind(scope);
    _entries.remove(key);
    while (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = (at: _elapsed(), value: value);
  }

  Iterable<T> get values => _entries.values.map((entry) => entry.value);

  void clear() {
    _entries.clear();
    _scope = null;
  }
}
