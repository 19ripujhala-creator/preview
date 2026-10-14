/// Effective auth_manager.execute_rajsims_login + install_httpx_signin binding.
/// Public lock, saved-account check, single launch and verified profile retained.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../shaladarpan/direct/auth_manager.dart'
    show SchoolAuthStorage, SecureSchoolAuthStorage;
import 'auth_manager.dart';
import 'http_context.dart';
import 'rajsims_sso_httpx.dart';

class RajsimsHttpAuth {
  RajsimsHttpAuth({
    required this.sso,
    SchoolAuthStorage? storage,
    this.clearWorkerUserInfoCache,
  }) : storage = storage ?? SecureSchoolAuthStorage() {
    auth = RajsimsAuthManager(
      currentContext: current,
      loginImplementation: _execute,
      bodyStatusCode: rajsimsBodyStatusCode,
      persistState: persist,
      persistUsername: _persistUsername,
      clearUserInfoCache: () => clearWorkerUserInfoCache?.call(),
    );
  }
  final RajssoHttpx sso;
  final SchoolAuthStorage storage;
  final void Function()? clearWorkerUserInfoCache;
  late final RajsimsAuthManager auth;
  static const stateKey = 'rajsims_httpx_state',
      userKey = 'rajsims_httpx_state_user';
  RajsimsHttpContext? _context;
  String _contextUser = '';
  String get username => current() == null ? '' : _contextUser;
  Future<void> _writes = Future.value();
  int _epoch = 0;
  bool _closed = false;

  RajsimsHttpContext? current() =>
      _closed || _context?.closed == true ? null : _context;

  Future<Map<String, dynamic>?> _saved(String username, bool forceFresh) async {
    if (forceFresh) return null;
    try {
      final savedUsername = await storage.read(userKey);
      if (savedUsername?.trim() != username.trim()) return null;
      final text = await storage.read(stateKey);
      if (text == null) return null;
      final saved = jsonDecode(text);
      // Native storage writes are asynchronous. Store the owner in the same
      // atomic JSON value as cookies, as the existing Staff registry does.
      // A process stop between state/marker writes must never adopt another
      // account's cookies under an old username marker.
      if (saved is! Map || saved['user'] != username.trim()) return null;
      return Map<String, dynamic>.from(saved);
    } catch (_) {
      return null;
    }
  }

  Future<void> persist(RajsimsHttpContext context) {
    final epoch = _epoch;
    final task = _writes.then((_) async {
      if (_closed || epoch != _epoch || !identical(context, current())) return;
      final state = await context.storageState();
      if (_closed || epoch != _epoch || !identical(context, current())) return;
      await storage.write(
        stateKey,
        jsonEncode({...state, 'user': _contextUser}),
      );
    });
    _writes = task.catchError((Object _) {});
    return task;
  }

  Future<void> _persistUsername(String username) {
    final epoch = _epoch;
    final context = current();
    final task = _writes.then((_) async {
      if (_closed ||
          epoch != _epoch ||
          context == null ||
          !identical(context, current()))
        return;
      try {
        await storage.write(userKey, username);
      } catch (_) {
        // Android/iOS secure storage errors are the native equivalent of the
        // source marker-file OSError, which never overturns successful login.
        throw const FileSystemException(
          'RajSIMS account marker could not be saved.',
        );
      }
    });
    _writes = task.catchError((Object _) {});
    return task;
  }

  Map<String, dynamic> _failure(RajssoError error) => {
    'success': false,
    'code': error.code,
    'message': error.message,
    if (error.portalMessage) 'message_source': 'portal',
    if (error.diagnostics != null) 'diagnostics': error.diagnostics,
  };

  Future<Map<String, dynamic>> _execute(
    String user,
    String password,
    bool forceFresh,
  ) async {
    if (_closed) throw StateError('RajSIMS HTTP authentication is closed.');
    final epoch = _epoch;
    RajssoLoginResult result;
    try {
      final saved = await _saved(user, forceFresh);
      if (_closed || epoch != _epoch)
        throw const RajsimsSessionChanged('RajSIMS login session changed.');
      result = await sso.login(user, password, savedState: saved);
    } on RajssoError catch (error) {
      return _failure(error);
    } on SocketException {
      return {
        'success': false,
        'code': 'NETWORK_ERROR',
        'message': 'RajSSO did not respond; no automatic credential replay was attempted.',
      };
    } on HttpException {
      return {
        'success': false,
        'code': 'NETWORK_ERROR',
        'message': 'RajSSO did not respond; no automatic credential replay was attempted.',
      };
    } on TimeoutException {
      return {
        'success': false,
        'code': 'NETWORK_ERROR',
        'message': 'RajSSO did not respond; no automatic credential replay was attempted.',
      };
    }
    var retained = false;
    try {
      final launched = await sso.launch(result);
      if (_closed || epoch != _epoch)
        throw const RajsimsSessionChanged('RajSIMS login session changed.');
      final previous = current();
      auth.clearAuth();
      final context = RajsimsHttpContext(result.client);
      _context = context;
      _contextUser = user.trim();
      auth.bindContext(
        context,
        launched.authId,
        launched.authKey,
        preserveTokenValues: true,
      );
      if (!auth.mergeProfile(launched.profile, context)) {
        _context = null;
        _contextUser = '';
        await context.close();
        auth.clearAuth();
        if (previous != null) await previous.close();
        return {
          'success': false,
          'code': 'SCHOOL_IDENTITY_NOT_VERIFIED',
          'message': 'RajSIMS token did not identify one verified school/organization.',
        };
      }
      if (previous != null) await previous.close();
      retained = true;
      final uri = launched.url;
      return {
        'success': true,
        'message':
            rajssoPortalMessage(launched.profile) ??
            'RajSIMS HTTPX token and school session verified',
        if (rajssoPortalMessage(launched.profile) != null)
          'message_source': 'portal',
        'current_url': '${uri.scheme}://${uri.authority}${uri.path}',
      };
    } on RajssoError catch (error) {
      return _failure(error);
    } on SocketException {
      return {
        'success': false,
        'code': 'PORTAL_LAUNCH_UNCONFIRMED',
        'message':
            'RajSIMS launch did not respond; no launch POST was replayed.',
      };
    } on HttpException {
      return {
        'success': false,
        'code': 'PORTAL_LAUNCH_UNCONFIRMED',
        'message':
            'RajSIMS launch did not respond; no launch POST was replayed.',
      };
    } on TimeoutException {
      return {
        'success': false,
        'code': 'PORTAL_LAUNCH_UNCONFIRMED',
        'message':
            'RajSIMS launch did not respond; no launch POST was replayed.',
      };
    } finally {
      if (!retained) await result.client.close();
    }
  }

  Future<void> forgetSavedSession() async {
    _epoch++;
    final context = _context;
    _context = null;
    _contextUser = '';
    auth.clearAuth();
    if (context != null) await context.close();
    await _writes;
    await storage.delete(stateKey);
    await storage.delete(userKey);
  }

  Future<void> closeSession() async {
    if (_closed) return;
    _closed = true;
    _epoch++;
    final context = _context;
    _context = null;
    _contextUser = '';
    auth.clearAuth();
    if (context != null) await context.close();
    await _writes;
  }
}

/// Exact original MDM worker top-level Status interpretation used by auth probe.
/// StatusCode is deliberately not substituted: the source uses it only during
/// initial bootstrap, while subsequent coordinator probes use Status.
int? rajsimsBodyStatusCode(Object? data) {
  if (data is! Map) return null;
  final value = data['Status'];
  if (value is bool) return null;
  final int? code;
  if (value is int) {
    code = value;
  } else if (value is String && RegExp(r'^[0-9]+$').hasMatch(value.trim())) {
    code = int.tryParse(value.trim());
  } else {
    code = null;
  }
  return code != null && code >= 100 && code <= 599 ? code : null;
}
