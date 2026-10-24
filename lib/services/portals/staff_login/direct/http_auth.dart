/// Complete Staff http_auth.py registry, persistence and cookie bridge.
import 'dart:convert';
import 'dart:io';

import '../../shaladarpan/direct/auth_manager.dart'
    show SchoolAuthStorage, SecureSchoolAuthStorage;
import 'http_session.dart';

const staffDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
const staffBrowserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
typedef StaffAuthStorage = SchoolAuthStorage;

class StaffHttpAuth {
  StaffHttpAuth({
    StaffAuthStorage? storage,
    StaffHttpSession Function()? sessionFactory,
  }) : storage = storage ?? SecureSchoolAuthStorage(),
       sessionFactory =
           sessionFactory ??
           (() => StaffHttpSession(
             client: DartStaffTransport(userAgent: staffBrowserUserAgent),
           ));
  final StaffAuthStorage storage;
  final StaffHttpSession Function() sessionFactory;
  static const cookieKey = 'staff_http_session';
  StaffHttpSession? _session;
  bool _restored = false;
  int _epoch = 0;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  StaffHttpSession? current() => _session;
  String sessionUser(StaffHttpSession? session) => session?.user ?? '';
  StaffHttpSession newSession() => sessionFactory();
  Future<void> initialize() => _initializing ??= _restore();
  Future<void> _restore() async {
    if (_restored || _session != null) return;
    _restored = true;
    final epoch = _epoch;
    StaffHttpSession? candidate;
    try {
      final text = await storage.read(cookieKey);
      if (text == null) return;
      final payload = jsonDecode(text) as Map;
      final base = staffNodeBase(payload['base'].toString());
      final user = payload['user'].toString().trim();
      final cookies = (payload['cookies'] as List)
          .cast<Map>()
          .where((c) => (c['name'] ?? '').toString().isNotEmpty)
          .toList();
      if (user.isEmpty || cookies.isEmpty) return;
      candidate = newSession();
      for (final item in cookies) {
        final cookie =
            Cookie(item['name'].toString(), (item['value'] ?? '').toString())
              ..domain = staffHost
              ..path = (item['path'] ?? '/').toString();
        candidate.client.jar.receive([cookie], Uri.parse('$base/'));
      }
      candidate.base = base;
      candidate.user = user;
      candidate.authenticated = true;
      // Python reads disk synchronously; device storage is asynchronous.
      // An install/forget during that read must win over the older restore.
      if (epoch != _epoch || _session != null) return;
      _session = candidate;
      candidate = null;
      // Adopted only. The coordinator starts UNKNOWN and must probe before use.
    } catch (_) {
      /* Unreadable Python state behaves as no saved session. */
    } finally {
      if (candidate != null) await candidate.close();
    }
  }

  Future<void> _write(Future<void> Function() operation) {
    final next = _writes.then((_) async {
      try {
        await operation();
      } catch (_) {}
    });
    _writes = next;
    return next;
  }

  List<Map<String, dynamic>> jarCookies(StaffHttpSession session) => [
    for (final cookie in session.client.jar.records())
      if (cookie['domain'].toString().replaceFirst(RegExp(r'^\.'), '') ==
          staffHost)
        {
          'name': cookie['name'],
          'value': cookie['value'],
          'domain': staffHost,
          'path': cookie['path'] ?? '/',
        },
  ];
  Future<void> persist(StaffHttpSession? session) async {
    if (session == null ||
        !identical(session, _session) ||
        !session.authenticated ||
        session.base == null)
      return;
    final epoch = _epoch;
    final text = jsonEncode({
      'base': session.base,
      'user': sessionUser(session),
      'cookies': jarCookies(session),
    });
    await _write(() async {
      // A queued write must still belong to this context/generation when it
      // reaches storage. The old worker may outlive replacement or forget.
      if (epoch != _epoch ||
          !identical(session, _session) ||
          !session.authenticated ||
          session.base == null)
        return;
      await storage.write(cookieKey, text);
    });
  }

  Future<void> install(StaffHttpSession session) async {
    _epoch++;
    final old = _session;
    _session = session;
    _restored = true;
    await persist(session);
    if (old != null && !identical(old, session)) {
      try {
        await old.close();
      } catch (_) {}
    }
  }

  void invalidate([StaffHttpSession? session]) {
    final target = session ?? _session;
    if (target != null && identical(target, _session))
      target.authenticated = false;
  }

  Future<void> forget() async {
    _epoch++;
    final old = _session;
    _session = null;
    _restored = true;
    await _write(() => storage.delete(cookieKey));
    if (old != null) {
      try {
        await old.close();
      } catch (_) {}
    }
  }

  Future<void> closeSession() async {
    final old = _session;
    if (old == null) return;
    await persist(old);
    if (identical(_session, old)) {
      _epoch++;
      _session = null;
    }
    try {
      await old.close();
    } catch (_) {}
  }

  List<Map<String, dynamic>> browserCookies(StaffHttpSession session) => [
    for (final cookie in session.client.jar.records())
      if (cookie['domain'].toString().replaceFirst(RegExp(r'^\.'), '') ==
          staffHost)
        {...cookie, 'domain': staffHost, 'secure': true},
  ];
  bool syncFromBrowser(
    StaffHttpSession session,
    List<Map<String, dynamic>> cookies,
  ) {
    var changed = false;
    for (final item in cookies) {
      if ((item['domain'] ?? '').toString().replaceFirst(RegExp(r'^\.'), '') !=
              staffHost ||
          (item['value'] ?? '').toString().isEmpty)
        continue;
      final path = (item['path'] ?? '/').toString();
      final existing = session.client.jar
          .records()
          .where(
            (c) =>
                c['name'] == item['name'] &&
                c['domain'].toString().replaceFirst(RegExp(r'^\.'), '') ==
                    staffHost &&
                c['path'] == path,
          )
          .toList();
      if (existing.length == 1 && existing.single['value'] == item['value'])
        continue;
      final cookie = Cookie(item['name'].toString(), item['value'].toString())
        ..domain = staffHost
        ..path = path;
      session.client.jar.receive([cookie], Uri.parse('https://$staffHost/'));
      changed = true;
    }
    return changed;
  }
}
