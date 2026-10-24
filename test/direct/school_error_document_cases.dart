import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../lib/services/core/direct/coordinator.dart';
import '../../lib/services/core/direct/coordinator_config.dart';
import '../../lib/services/core/direct/errors.dart';
import '../../lib/services/portals/shaladarpan/direct/auth_manager.dart';
import '../../lib/services/portals/shaladarpan/direct/school_runtime.dart';

const _base = 'https://rajshaladarpan.rajasthan.gov.in/SD1';
const _error =
    '<title>Server Error in /SD1 Application.</title><h2>Object reference not set to an instance of an object.</h2><p>System.NullReferenceException</p>';
const _errorText = 'Object reference not set to an instance of an object.';
const _form =
    '<form><input id="__VIEWSTATE" value="view"><input id="__EVENTVALIDATION" value="event"><input id="bodyContent_hdnfld" value="salt"><img id="bodyContent_Img2" src="Captcha.aspx"><p>Offline form padding to pass the existing node health threshold. Offline form padding to pass the existing node health threshold.</p></form>';
void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

class _Headers implements HttpHeaders {
  _Headers([Map<String, List<String>> values = const {}]) {
    for (final e in values.entries) {
      _values[e.key.toLowerCase()] = List.of(e.value);
    }
  }
  final _values = <String, List<String>>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = value is Iterable
        ? value.map((v) => v.toString()).toList()
        : [value.toString()];
  }

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];
  @override
  String? value(String name) => _values[name.toLowerCase()]?.first;
  @override
  void forEach(void Function(String, List<String>) action) =>
      _values.forEach(action);
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected header operation ${i.memberName}');
}

class _Reply extends Stream<List<int>> implements HttpClientResponse {
  _Reply(
    String text, {
    this.statusCode = 200,
    Map<String, List<String>> headers = const {},
    this.cookies = const [],
  }) : _bytes = utf8.encode(text),
       headers = _Headers(headers);
  final List<int> _bytes;
  @override
  final int statusCode;
  @override
  final HttpHeaders headers;
  @override
  final List<Cookie> cookies;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected response operation ${i.memberName}');
}

class _Request implements HttpClientRequest {
  _Request(this.method, this.uri, this.handle);
  @override
  final String method;
  @override
  final Uri uri;
  final _Reply Function(_Request) handle;
  final body = <int>[];
  @override
  final HttpHeaders headers = _Headers();
  @override
  final cookies = <Cookie>[];
  @override
  bool followRedirects = false;
  @override
  int contentLength = -1;
  @override
  void add(List<int> data) => body.addAll(data);
  @override
  Future<HttpClientResponse> close() async => handle(this);
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected request operation ${i.memberName}');
}

class _Client implements HttpClient {
  _Client(this.handle);
  final _Reply Function(_Request) handle;
  @override
  Duration? connectionTimeout;
  bool closed = false;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(method, url, handle);
  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected client operation ${i.memberName}');
}

class _Store implements SchoolAuthStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class SchoolAuthHttpFixture {
  SchoolAuthHttpFixture({
    this.home = _error,
    this.status = 200,
    this.saved = false,
  });
  String home;
  int status;
  final bool saved;
  final store = _Store(), requests = <_Request>[], clients = <_Client>[];
  int solved = 0;
  String? firstHome;
  int homeReads = 0;
  RememberSchoolCredentials? rememberCredentials;
  SchoolAuthManager? auth;
  _Reply reply(_Request request) {
    requests.add(request);
    final path = request.uri.path.toLowerCase();
    if (path.endsWith('/home_new.aspx')) {
      final text = homeReads++ == 0 && firstHome != null ? firstHome! : home;
      return _Reply(text, statusCode: status);
    }
    if (request.method == 'GET' && path.endsWith('/officeloginnew.aspx'))
      return _Reply(_form);
    if (path.endsWith('/officeloginnew.aspx/getuserid'))
      return _Reply('{"d":"SchoolABC"}');
    if (path.endsWith('/captcha.aspx')) return _Reply('png');
    if (request.method == 'POST' && path.endsWith('/officeloginnew.aspx')) {
      final node = RegExp(r'^/(SD[1-5])/')
          .firstMatch(request.uri.path)!
          .group(1)!;
      return _Reply(
        '',
        statusCode: 302,
        headers: {
          'location': ['/$node/Home/School/Home_New.aspx'],
          'set-cookie': ['ASP.NET_SessionId=new-cookie; Path=/'],
        },
        cookies: [Cookie('ASP.NET_SessionId', 'new-cookie')..path = '/'],
      );
    }
    throw StateError('Unplanned offline HTTP request ${request.method} $path');
  }

  Future<T> run<T>(Future<T> Function(SchoolAuthManager) action) =>
      HttpOverrides.runZoned(
        () async {
          if (saved)
            store.values['rajshala.direct.sd.session_v2'] = jsonEncode({
              'version': 2,
              'active': {
                'user': '123456',
                'server_base': _base,
                'session_id': 'saved-id',
              },
              'cookies': {'ASP.NET_SessionId': 'old-cookie'},
            });
          final manager = SchoolAuthManager(
            storage: store,
            rememberCredentials: rememberCredentials,
            solveCaptcha: (_) async {
              solved++;
              return '1234';
            },
          );
          auth = manager;
          await manager.initialize();
          try {
            return await action(manager);
          } finally {
            await manager.closeAuthenticatedClients();
            _check(
              clients.every((c) => c.closed),
              'HTTP clients were not retired after the scenario',
            );
          }
        },
        createHttpClient: (_) {
          final client = _Client(reply);
          clients.add(client);
          return client;
        },
      );
  int get credentialPosts => requests
      .where(
        (r) =>
            r.method == 'POST' &&
            r.uri.path.toLowerCase().endsWith('/officeloginnew.aspx'),
      )
      .length;
}

Map<String, dynamic> _home(String text, {String? url, int status = 200}) => {
  'status': status,
  'text': text,
  'url': url ?? '$_base/Home/School/Home_New.aspx',
};
Map<String, Future<void> Function()> schoolErrorDocumentCases() => {
  for (final entry in <String, String>{
    'ASP.NET error': _error,
    'exception marker': '<p>System.NullReferenceException</p>',
    'ViewState failure': '<h2>Validation of viewstate MAC failed.</h2>',
    'postback failure': '<h2>Invalid postback or callback argument.</h2>',
    'empty body': '',
  }.entries)
    'School Home HTTP 200 ${entry.key} is not session proof': () async {
      _check(
        SchoolAuthManager.classifyHome(_home(entry.value)) ==
            SchoolProbe.unknown,
        'Error/empty Home was accepted as ALIVE',
      );
    },
  for (final body in [
    '<a id="logout">Logout</a>',
    '<span id="x_lblSchoolName">School A</span>',
    '<p>Existing Home path fallback</p>',
  ])
    'School healthy Home compatibility: $body': () async {
      _check(
        SchoolAuthManager.classifyHome(_home(body)) == SchoolProbe.alive,
        'Healthy Home compatibility changed',
      );
    },
  'School actual protected Home probe rejects an error despite leftover logout control':
      () async {
        final f = SchoolAuthHttpFixture(
          saved: true,
          home: '$_error<a id="logout">Logout</a>',
        );
        await f.run((auth) async {
          final backend = SchoolHttpBackend(auth);
          final current = backend.currentContext();
          _check(current != null, 'Saved session missing');
          _check(
            await backend.probe(current!) == Probe.unknown,
            'Actual Home probe accepted server error',
          );
          _check(
            f.requests.length == 1 && f.credentialPosts == 0 && f.solved == 0,
            'Probe started authentication',
          );
          _check(
            auth.loadSessionCookies()['ASP.NET_SessionId'] == 'old-cookie',
            'Probe discarded saved cookies',
          );
        });
      },
  'School error Home cannot admit a mutation or trigger credential replay':
      () async {
        final f = SchoolAuthHttpFixture(saved: true);
        var writes = 0;
        await f.run((auth) async {
          final co = PortalCoordinator(
            name: 'sd',
            backend: SchoolHttpBackend(auth),
            config: const CoordinatorConfig(mutationProbeMaxAge: 0),
          );
          Object? failure;
          try {
            try {
              await co.run(
                resource: 'school.offline.save',
                kind: Kind.mutation,
                maxAttempts: 1,
                worker: (_) async {
                  writes++;
                  return {'success': true};
                },
              );
            } catch (e) {
              failure = e;
            }
            _check(
              writes == 0 &&
                  failure is CoordinatorError &&
                  failure.kind == ErrorKind.sessionUnverified,
              'Error Home admitted a mutation',
            );
            _check(
              f.credentialPosts == 0 && f.solved == 0,
              'Unknown Home caused credential replay',
            );
          } finally {
            await co.shutdown();
          }
        });
      },
  for (final status in [200, 500])
    'School fresh-login redirect to error Home HTTP $status is never success':
        () async {
          final f = SchoolAuthHttpFixture(status: status);
          await f.run((auth) async {
            final result = await auth.executeLogin(
              '123456',
              'offline-password',
            );
            _check(
              result['success'] == false && result['code'] == 'PAGE_NOT_READY',
              'Error Home was committed as successful login',
            );
            _check(
              result['message'] == _errorText,
              'Original portal heading was replaced',
            );
            _check(
              auth.sessionIdentity == null && auth.loadSessionCookies().isEmpty,
              'Failed login retained authenticated identity',
            );
            _check(
              f.credentialPosts == 1 && f.solved == 1,
              'Rejected Home replayed login credentials',
            );
          });
        },
  'School fresh-login empty Home response cannot create authenticated state':
      () async {
        final f = SchoolAuthHttpFixture(home: '');
        await f.run((auth) async {
          final result = await auth.executeLogin('123456', 'offline-password');
          _check(
            result['success'] == false &&
                result['code'] == 'PAGE_NOT_READY' &&
                auth.sessionIdentity == null,
            'Empty Home became authenticated session',
          );
          _check(
            f.credentialPosts == 1,
            'Empty Home caused duplicate credential POST',
          );
        });
      },
  'School healthy fresh-login sequence still commits the original cookie and identity':
      () async {
        final f = SchoolAuthHttpFixture(home: '<a id="logout">Logout</a>');
        await f.run((auth) async {
          final result = await auth.executeLogin('123456', 'offline-password');
          _check(
            result['success'] == true && result['cached'] != true,
            'Healthy fresh login failed',
          );
          _check(
            auth.sessionIdentity?.$1 == '123456' &&
                auth.loadSessionCookies()['ASP.NET_SessionId'] == 'new-cookie',
            'Healthy login lost cookies/identity',
          );
          _check(
            f.credentialPosts == 1 && f.solved == 1,
            'Healthy login sequence gained replay',
          );
        });
      },
  'School login form on Home URL retains explicit expiry classification':
      () async {
        _check(
          SchoolAuthManager.classifyHome(
                _home('<input id="bodyContent_txtUName">'),
              ) ==
              SchoolProbe.dead,
          'Login form was not expired',
        );
      },
  'School non-200 Home retains unconfirmed probe behavior': () async {
    _check(
      SchoolAuthManager.classifyHome(
            _home('<a id="logout"></a>', status: 503),
          ) ==
          SchoolProbe.unknown,
      'Server outage was treated as logout',
    );
  },
};
