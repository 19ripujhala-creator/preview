/// Complete Gateway transport/worker adapter from rajsims_httpx.py.
/// Business payloads and status/message interpretation remain worker callbacks.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../shaladarpan/direct/school_http.dart';
import 'http_context.dart';

const rajsimsReadKeys = {
  'GetBeneficiaryGroupProductList',
  'ValidateTokenAndGetUserDetail',
  'GetBeneficiaryDistributionList',
  'GetLegacyBeneficiaryDistributionList',
  'GetBeneficiaryDistributionDetailById',
  'GetAllChartData',
  'GetSummaryReport',
  'GetStockSummaryReportMonthWise',
  'GetStockSummaryReportMonthly',
};
const rajsimsWriteKeys = {
  'SaveEditlegancyBenefiDistribution',
  'SaveEditBeneficiaryDistribution',
  'SendDistributionCancelRequest',
};

class RajsimsGatewayReply {
  const RajsimsGatewayReply(this.response, this.data, this.status);
  final SchoolHttpReply response;
  final Object? data;
  final int status;
  bool get ok => status >= 200 && status < 300;
}

class _WriteReceipt {
  _WriteReceipt(this.time);
  String outcome = 'unknown';
  double time;
  RajsimsGatewayReply? reply;
}

/// Python json.dumps(sort_keys=True, ensure_ascii=False, allow_nan=False).
String _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}: ${_canonical(value[key])}').join(', ')}}';
  }
  if (value is List) return '[${value.map(_canonical).join(', ')}]';
  return jsonEncode(value);
}

class RajsimsGatewayTransport {
  RajsimsGatewayTransport(
    this.context,
    this.currentContext,
    String url, {
    RajsimsHttpTransport? client,
    this.timeout = const Duration(seconds: 15),
    String? userAgent,
    double Function()? monotonic,
  }) : url = Uri.parse(url),
       client = client ?? NativeRajsimsHttpTransport(userAgent: userAgent),
       monotonic = monotonic ?? _elapsed {
    final target = this.url;
    if (target.scheme != 'https' ||
        target.host != 'rajsims-mdm.rajasthan.gov.in' ||
        target.userInfo.isNotEmpty ||
        target.hasQuery ||
        target.hasFragment)
      throw ArgumentError(
        'RajSIMS Gateway must use the configured official HTTPS endpoint.',
      );
  }
  final RajsimsHttpContext context;
  final RajsimsHttpContext? Function() currentContext;
  final Uri url;
  final RajsimsHttpTransport client;
  final Duration timeout;
  final double Function() monotonic;
  static final _clock = Stopwatch()..start();
  static double _elapsed() => _clock.elapsedMicroseconds / 1000000;
  bool closed = false;
  final _writes = <String, _WriteReceipt>{};
  void check() {
    if (closed || context.closed || !identical(currentContext(), context))
      throw const RajsimsSessionChanged(
        'RajSIMS session changed; response withheld.',
      );
  }

  Future<RajsimsGatewayReply> postRead(
    Map<String, dynamic> payload,
    String authId,
    String authKey,
  ) => _post(payload, authId, authKey, allowWrite: false);
  Future<RajsimsGatewayReply> postWrite(
    Map<String, dynamic> payload,
    String authId,
    String authKey,
  ) async {
    check();
    if (!rajsimsWriteKeys.contains(payload['ApiKey']) ||
        authId.isEmpty ||
        authKey.isEmpty)
      throw ArgumentError(
        'Valid final operation and current auth headers are required.',
      );
    final signature = sha256
        .convert(
          utf8.encode('$authId\u0000$authKey\u0000${_canonical(payload)}'),
        )
        .toString();
    final now = monotonic();
    _writes.removeWhere(
      (_, receipt) => receipt.outcome == 'success' && now - receipt.time > 10,
    );
    final prior = _writes[signature];
    if (prior != null) {
      if (prior.reply != null) return prior.reply!;
      return RajsimsGatewayReply(
        SchoolHttpReply(url, 409, Uint8List(0), const {}),
        const {
          'Message': 'A matching save is in progress or its result is unknown. Check status/history before retrying.',
        },
        409,
      );
    }
    final receipt = _WriteReceipt(now);
    _writes[signature] = receipt;
    // Installed before the first await: in-flight/uncertain retries cannot POST.
    final result = await _post(payload, authId, authKey, allowWrite: true);
    final body = result.data, flag = body is Map ? body['IsSuccess'] : null;
    final rejected =
        flag == false || flag is String && flag.trim().toLowerCase() == 'false';
    final bodyStatus = body is Map ? (body['Status'] ?? '').toString() : '';
    if (rejected ||
        {'400', '401', '403', '404', '422'}.contains(bodyStatus) ||
        result.status >= 400 &&
            result.status < 500 &&
            !{408, 429}.contains(result.status)) {
      _writes.remove(signature);
    } else {
      final success =
          result.ok &&
          body is Map &&
          (flag == true ||
              flag is String && flag.trim().toLowerCase() == 'true' ||
              bodyStatus == '200');
      receipt
        ..outcome = success ? 'success' : 'unknown'
        ..time = monotonic()
        ..reply = result;
    }
    return result;
  }

  Future<RajsimsGatewayReply> _post(
    Map<String, dynamic> payload,
    String authId,
    String authKey, {
    required bool allowWrite,
  }) async {
    check();
    if (!(allowWrite ? rajsimsWriteKeys : rajsimsReadKeys).contains(
      payload['ApiKey'],
    ))
      throw ArgumentError(
        'Gateway API does not match the requested read/write operation.',
      );
    if (authId.isEmpty || authKey.isEmpty)
      throw ArgumentError(
        'Current RajSIMS authentication headers are required.',
      );
    final profile =
        !allowWrite && payload['ApiKey'] == 'ValidateTokenAndGetUserDetail';
    final target = profile ? Uri.parse(rajsimsBootstrap) : url;
    final params = payload['ApiParams'];
    if (profile &&
        (params is! Map ||
            params['AuthId'] != authId ||
            params['AuthKey'] != authKey))
      throw ArgumentError(
        'Token profile payload does not match the active session.',
      );
    final cookies = await context.cookies([target]);
    check();
    client.jar.clear();
    for (final cookie in cookies) {
      importRajsimsCookie(client.jar, cookie);
    }
    final headers = profile
        ? <String, String>{
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/json',
            'Origin': 'https://rajsims-mdm.rajasthan.gov.in',
            'Referer': 'https://rajsims-mdm.rajasthan.gov.in/',
          }
        : <String, String>{
            'Accept': '*/*',
            'Content-Type': 'application/json',
            'Authid': authId,
            'Authkey': authKey,
          };
    final response = await client.request(
      'POST',
      target,
      content: jsonEncode(payload),
      headers: headers,
      timeout: timeout,
    );
    check();
    final rotated = <Map<String, dynamic>>[];
    for (final raw in response.headers['set-cookie'] ?? <String>[]) {
      try {
        final cookie = Cookie.fromSetCookieValue(raw);
        if (cookie.expires != null &&
                !cookie.expires!.isAfter(DateTime.now().toUtc()) ||
            cookie.maxAge != null && cookie.maxAge! <= 0)
          continue;
        final domain = cookie.domain ?? target.host;
        final path = cookie.path ?? SchoolCookieJar.defaultPath(target.path);
        final item = <String, dynamic>{
          'name': cookie.name,
          'value': cookie.value,
          'domain': domain,
          'path': path,
          'secure': cookie.secure,
          'httpOnly': cookie.httpOnly,
        };
        if (cookie.expires != null)
          item['expires'] = cookie.expires!.millisecondsSinceEpoch / 1000;
        rotated.add(item);
      } on FormatException {
        /* HTTPX ignores malformed cookies. */
      }
    }
    if (rotated.isNotEmpty) await context.addCookies(rotated);
    check();
    Object? data;
    try {
      data = jsonDecode(response.text);
    } on FormatException {
      data = null;
    }
    return RajsimsGatewayReply(response, data, response.statusCode);
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    _writes.clear();
    await client.close();
  }
}

enum RajsimsWriteMode { legacy, disabled, enabled }

class RajsimsGatewayResult {
  const RajsimsGatewayResult(
    this.success,
    this.data,
    this.status,
    this.message,
  );
  final bool success;
  final Object? data;
  final int? status;
  final String message;
}

typedef RajsimsOriginalRequest = Future<RajsimsGatewayResult> Function(
  RajsimsHttpContext? context,
  Map<String, dynamic> payload, {
  required bool allowAuthRetry,
  bool? safeToRetry,
});

/// The original MDM worker supplies token/status/message callbacks and settings.
/// They are required here; their business logic is not guessed from API names.
class RajsimsGatewayAdapter {
  RajsimsGatewayAdapter({
    required this.currentContext,
    required this.waitForAuth,
    required this.bodyStatusCode,
    required this.responseErrorMessage,
    required this.apiUrl,
    required this.apiTimeout,
    required this.readRetries,
    required this.readRetryBackoff,
    this.writeMode = RajsimsWriteMode.legacy,
    this.originalRequest,
    this.userAgent,
    RajsimsHttpTransport Function()? clientFactory,
    Future<void> Function(Duration)? sleep,
  }) : clientFactory =
           clientFactory ??
           (() => NativeRajsimsHttpTransport(userAgent: userAgent)),
       sleep = sleep ?? ((duration) => Future<void>.delayed(duration));
  final RajsimsHttpContext? Function() currentContext;
  final Future<(String, String)> Function(RajsimsHttpContext) waitForAuth;
  final int? Function(Object?) bodyStatusCode;
  final String Function(SchoolHttpReply, Object?) responseErrorMessage;
  final String apiUrl;
  final Duration apiTimeout, readRetryBackoff;
  final int readRetries;
  RajsimsWriteMode writeMode;
  final RajsimsOriginalRequest? originalRequest;
  final String? userAgent;
  final RajsimsHttpTransport Function() clientFactory;
  final Future<void> Function(Duration) sleep;
  final _sessions = <RajsimsHttpContext, RajsimsGatewayTransport>{};

  Future<RajsimsGatewayResult> request(
    RajsimsHttpContext? context,
    Map<String, dynamic> payload, {
    bool allowAuthRetry = true,
    bool? safeToRetry,
  }) async {
    final safe = safeToRetry ?? allowAuthRetry,
        write = rajsimsWriteKeys.contains(payload['ApiKey']);
    if (write && writeMode == RajsimsWriteMode.disabled)
      return const RajsimsGatewayResult(
        false,
        null,
        403,
        'Final saving is disabled on this test backend.',
      );
    if (writeMode == RajsimsWriteMode.legacy &&
        (!safe || !rajsimsReadKeys.contains(payload['ApiKey']))) {
      if (originalRequest == null)
        throw StateError(
          'Original RajSIMS worker is required for legacy transport.',
        );
      return originalRequest!(
        context,
        payload,
        allowAuthRetry: allowAuthRetry,
        safeToRetry: safeToRetry,
      );
    }
    if (!rajsimsReadKeys.contains(payload['ApiKey']) &&
        !rajsimsWriteKeys.contains(payload['ApiKey']))
      return const RajsimsGatewayResult(
        false,
        null,
        400,
        'Unsupported Gateway API; no request was sent.',
      );
    if (context == null || !identical(currentContext(), context))
      return const RajsimsGatewayResult(
        false,
        null,
        null,
        'RajSIMS session changed before the read.',
      );
    final (authId, authKey) = await waitForAuth(context);
    if (authId.isEmpty || authKey.isEmpty)
      return const RajsimsGatewayResult(
        false,
        null,
        null,
        'RajSIMS authentication headers are unavailable for the current session.',
      );
    var transport = _sessions[context];
    if (transport == null) {
      transport = RajsimsGatewayTransport(
        context,
        currentContext,
        apiUrl,
        client: clientFactory(),
        timeout: apiTimeout,
        userAgent: userAgent,
      );
      _sessions[context] = transport;
      final session = transport;
      context.on('close', (_) async {
        if (identical(_sessions[context], session)) _sessions.remove(context);
        await session.close();
      });
    }
    final attempts = 1 + (!write && safe ? math.max(0, readRetries) : 0);
    var last = const RajsimsGatewayResult(
      false,
      null,
      null,
      'RajSIMS Gateway read failed.',
    );
    for (var attempt = 0; attempt < attempts; attempt++) {
      var retry = false;
      try {
        final reply = write
            ? await transport.postWrite(payload, authId, authKey)
            : await transport.postRead(payload, authId, authKey);
        final bodyStatus = bodyStatusCode(reply.data),
            effective = reply.status != 200
                ? reply.status
                : bodyStatus ?? reply.status;
        if ({401, 403}.contains(effective))
          return RajsimsGatewayResult(
            false,
            reply.data,
            effective,
            responseErrorMessage(reply.response, reply.data),
          );
        if (!reply.ok || bodyStatus != null && bodyStatus >= 400) {
          last = RajsimsGatewayResult(
            false,
            reply.data,
            effective,
            responseErrorMessage(reply.response, reply.data),
          );
          retry = effective == 429 || effective >= 500;
        } else if (reply.data is! Map) {
          return RajsimsGatewayResult(
            false,
            reply.data,
            reply.status,
            'RajSIMS Gateway returned invalid/non-JSON data.',
          );
        } else if ((reply.data as Map)['IsSuccess'] == false) {
          return RajsimsGatewayResult(
            false,
            reply.data,
            reply.status,
            responseErrorMessage(reply.response, reply.data),
          );
        } else {
          return RajsimsGatewayResult(true, reply.data, reply.status, '');
        }
      } on TimeoutException {
        last = RajsimsGatewayResult(
          false,
          null,
          null,
          write
              ? 'RajSIMS save result unknown. Check status/history before retrying.'
              : 'RajSIMS Gateway read timed out.',
        );
        retry = true;
      } on IOException {
        last = RajsimsGatewayResult(
          false,
          null,
          null,
          write
              ? 'RajSIMS save result unconfirmed. Check status/history before retrying.'
              : 'RajSIMS Gateway read connection failed.',
        );
        retry = true;
      } on RajsimsSessionChanged {
        return const RajsimsGatewayResult(
          false,
          null,
          null,
          'RajSIMS session changed during the read.',
        );
      } on ArgumentError catch (e) {
        return RajsimsGatewayResult(
          false,
          null,
          null,
          (e.message ?? '').toString(),
        );
      }
      if (!retry || attempt + 1 >= attempts) return last;
      await sleep(
        Duration(microseconds: readRetryBackoff.inMicroseconds * (attempt + 1)),
      );
    }
    return last;
  }

  Future<void> closeAll() async {
    final sessions = _sessions.values.toList();
    _sessions.clear();
    await Future.wait(sessions.map((s) => s.close()), eagerError: false);
  }
}
