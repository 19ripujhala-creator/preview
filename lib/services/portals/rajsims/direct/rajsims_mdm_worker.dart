/// File-equivalent of the effective HTTPX rajsims_mdm_worker.py.
/// All school identities and product mappings come from the active session.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../core/direct/async_primitives.dart';
import '../../shaladarpan/direct/school_http.dart';
import 'auth_manager.dart';
import 'http_context.dart';
import 'http_auth.dart';
import 'rajsims_httpx.dart';

typedef MdmMap = Map<String, dynamic>;
typedef MdmRequest = Future<RajsimsGatewayResult> Function(
  RajsimsHttpContext?,
  MdmMap, {
  bool allowAuthRetry,
  bool? safeToRetry,
});

bool _truth(Object? v) =>
    v != null &&
    v != false &&
    v != 0 &&
    v != '' &&
    !(v is Iterable && v.isEmpty) &&
    !(v is Map && v.isEmpty);
String _str(Object? v) => v == null
    ? 'None'
    : v == true
    ? 'True'
    : v == false
    ? 'False'
    : v.toString();
String _clean(Object? v) {
  if (v == null) return '';
  final s = _str(v).trim();
  return {'none', 'null', 'nan', '-'}.contains(s.toLowerCase()) ? '' : s;
}

double _float(Object? v) =>
    double.tryParse(_str(v).trim().replaceAll(',', '')) ?? 0;
int _int(Object? v) {
  final f = _float(v);
  return f.isFinite ? f.truncate() : 0;
}

Object? _first(Object? r, List<String> keys) {
  if (r is! Map) return null;
  for (final k in keys) {
    final v = r[k];
    if (v != null && v != '') return v;
  }
  return null;
}

Object? _or(Iterable<Object?> vs) {
  for (final v in vs) {
    if (_truth(v)) return v;
  }
  return vs.isEmpty ? null : vs.last;
}

MdmMap _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : {};
Object? _json(Object? v) {
  if (v is String) {
    try {
      return jsonDecode(v);
    } catch (_) {}
  }
  return v;
}

List<dynamic> mdmResponseList(
  Object? data, [
  List<String> keys = const [],
  int depth = 0,
]) {
  data = _json(data);
  if (data is List) return data;
  if (data is! Map || depth > 2) return [];
  for (final k in [
    ...keys,
    'CustomObject',
    'List',
    'Data',
    'Result',
    'Records',
    'Items',
  ]) {
    final v = _json(data[k]);
    if (v is List) return v;
    if (v is Map) {
      final rows = mdmResponseList(v, keys, depth + 1);
      if (rows.isNotEmpty) return rows;
    }
  }
  return [];
}

List<MdmMap>? mdmValidatedRecords(Object? data, [int depth = 0]) {
  data = _json(data);
  if (data is List)
    return data.every((v) => v is Map) ? data.map(_map).toList() : null;
  if (data is! Map || depth > 8) return null;
  final fields = {
    for (final e in data.entries) e.key.toString().toLowerCase(): e.value,
  };
  for (final k in [
    'customobject',
    'list',
    'data',
    'result',
    'records',
    'items',
  ]) {
    if (fields.containsKey(k)) {
      final r = mdmValidatedRecords(fields[k], depth + 1);
      if (r != null) return r;
    }
  }
  return null;
}

int? mdmReportedTotal(Object? data) {
  if (data is! Map) return null;
  for (final k in ['FilteredRecordCount', 'TotalRecordCount']) {
    final v = data[k];
    if (v is int && v >= 0) return v;
    if (v is String && RegExp(r'^\d+$').hasMatch(v.trim()))
      return int.tryParse(v.trim());
  }
  return null;
}

bool mdmBool(Object? v) => v is bool
    ? v
    : {
        'true',
        '1',
        'yes',
        'y',
      }.contains(_str(_or([v, ''])).trim().toLowerCase());
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String mdmFormatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${_months[d.month - 1]}-${d.year}';
DateTime? mdmParseDate(Object? raw) {
  if (raw == null) return null;
  final s = _str(raw).trim();
  if (s.isEmpty) return null;
  DateTime? make(
    int y,
    int m,
    int d, [
    int h = 0,
    int min = 0,
    int sec = 0,
    int micro = 0,
  ]) {
    if (y < 1 ||
        y > 9999 ||
        m < 1 ||
        m > 12 ||
        d < 1 ||
        d > 31 ||
        h > 23 ||
        min > 59 ||
        sec > 59)
      return null;
    final dt = DateTime.utc(y, m, d, h, min, sec, 0, micro);
    return dt.year == y && dt.month == m && dt.day == d ? dt : null;
  }

  final named = RegExp(r'^(\d{1,2})[-/ ]([A-Za-z]{3,9})[-/ ](\d{4})$')
      .firstMatch(s);
  if (named != null) {
    final month =
        _months.indexWhere(
          (v) => v.toLowerCase() == named[2]!.substring(0, 3).toLowerCase(),
        ) +
        1;
    return make(int.parse(named[3]!), month, int.parse(named[1]!));
  }
  final num = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$').firstMatch(s);
  if (num != null)
    return make(int.parse(num[3]!), int.parse(num[2]!), int.parse(num[1]!));
  final iso = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{1,2}):(\d{1,2})(?:\.(\d{1,6}))?)?$',
  ).firstMatch(s);
  if (iso != null)
    return make(
      int.parse(iso[1]!),
      int.parse(iso[2]!),
      int.parse(iso[3]!),
      int.parse(iso[4] ?? '0'),
      int.parse(iso[5] ?? '0'),
      int.parse(iso[6] ?? '0'),
      int.parse((iso[7] ?? '0').padRight(6, '0')),
    );
  try {
    final d = DateTime.parse(s);
    if (d.isUtc) {
      final ist = d.toUtc().add(const Duration(minutes: 330));
      return make(
        ist.year,
        ist.month,
        ist.day,
        ist.hour,
        ist.minute,
        ist.second,
        ist.millisecond * 1000 + ist.microsecond,
      );
    }
    return make(
      d.year,
      d.month,
      d.day,
      d.hour,
      d.minute,
      d.second,
      d.millisecond * 1000 + d.microsecond,
    );
  } catch (_) {
    return null;
  }
}

String? mdmNormalizeDate(Object? v) {
  final d = mdmParseDate(v);
  return d == null ? null : mdmFormatDate(d);
}

String _status(Object? v) =>
    _str(_or([v, '']))
        .trim()
        .toLowerCase()
        .replaceAll('_', '-')
        .split(RegExp(r'\s+'))
        .join(' ');
String _tid(MdmMap r) => _clean(
  _first(r, [
    'TransactionId',
    'TransactionID',
    'transactionId',
    'Id',
    'EntityId',
  ]),
);
String _dno(MdmMap r) =>
    _clean(_first(r, ['DistributionNo', 'DistributionNumber', 'distNo']));
int _ben(MdmMap r) => math.max(
  0,
  _int(_first(r, ['NoOfBeneficiary', 'BeneficiaryCount', 'beneficiary'])),
);
String _product(MdmMap r) =>
    _clean(_first(r, ['ProductName', 'Product', 'product'])).isEmpty
    ? '-'
    : _clean(_first(r, ['ProductName', 'Product', 'product']));
bool _submitOk(MdmMap d) {
  final v = d['IsSuccess'];
  return v == true ||
      v is String && v.trim().toLowerCase() == 'true' ||
      _str(d['Status'] ?? '').trim() == '200';
}

(String, String) _ids(Object? d, [int depth = 0]) {
  d = _json(d);
  if (depth > 3) return ('', '');
  if (d is List) return d.isEmpty ? ('', '') : _ids(d.first, depth + 1);
  if (d is! Map) return ('', '');
  var tid = _clean(
        _first(d, ['TransactionId', 'TransactionID', 'transactionId']),
      ),
      no = _dno(_map(d));
  for (final k in ['CustomObject', 'Data', 'Result']) {
    if (tid.isNotEmpty && no.isNotEmpty) break;
    final (t, n) = _ids(d[k], depth + 1);
    if (tid.isEmpty) tid = t;
    if (no.isEmpty) no = n;
  }
  return (tid, no);
}

String mdmProductName(Object? v) {
  final raw = _str(_or([v, '']))
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .join(' ');
  if (raw.isEmpty) return '';
  final stripped = raw
      .replaceAll(RegExp(r'\(.*?\)'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .join(' ');
  for (final c in [
    raw,
    stripped,
    ...RegExp(r'\((.*?)\)').allMatches(raw).map((m) => m[1]!.trim()),
  ]) {
    if (c == 'गेहूं' || c == 'गेहूँ') return 'wheat';
    if (c == 'चावल') return 'rice';
  }
  return stripped.isEmpty ? raw : stripped;
}

const _metaInt = {
  'product_id': ['ProductId'],
  'packing_id': ['PackingId', 'PackagingId'],
  'criteria_id': ['CriteriaId', 'CateriaId'],
  'product_group_id': ['ProductGroupId'],
  'product_uom_id': ['ProductUomId'],
};
const _metaStr = {
  'packing_name': ['PackingName', 'PackagingName'],
  'criteria_name': ['CriteriaName', 'CateriaName'],
  'product_group_name': ['ProductGroupName'],
  'product_uom_name': ['ProductUomName'],
  'batch_no': ['BatchNo'],
};
MdmMap mdmProductMeta(MdmMap r) {
  final m = <String, dynamic>{
    for (final e in _metaInt.entries) e.key: _int(_first(r, e.value)),
    for (final e in _metaStr.entries) e.key: _clean(_first(r, e.value)),
  };
  if (!_truth(m['batch_no']) && r['BatchDetails'] is List) {
    for (final b in r['BatchDetails']) {
      if (b is Map && _truth(b['BatchLotNo'])) {
        m['batch_no'] = _str(b['BatchLotNo']).trim();
        break;
      }
    }
  }
  m['quantity'] = _float(r['Quantity']);
  m['product_name'] = _clean(r['ProductName']);
  return m;
}

void _fill(MdmMap target, MdmMap source) {
  for (final e in source.entries) {
    if (e.key != 'product_name' && _truth(e.value) && !_truth(target[e.key]))
      target[e.key] = e.value;
  }
}

MdmMap? _findProduct(MdmMap ctx, Object? requested) {
  final products = _map(ctx['products']), key = mdmProductName(requested);
  if (products.containsKey(key)) return _map(products[key]);
  for (final e in products.entries) {
    if (key.isNotEmpty &&
        e.key.isNotEmpty &&
        (e.key.startsWith(key) || key.startsWith(e.key)))
      return _map(e.value);
  }
  return null;
}

MdmMap _copyCtx(MdmMap ctx) => {
  ...ctx,
  'products': {
    for (final e in _map(ctx['products']).entries) e.key: _map(e.value),
  },
};
MdmMap _copy(MdmMap data) => _map(jsonDecode(jsonEncode(data)));
int _halfEven(double n) {
  final floor = n.floor(), f = n - floor;
  if (f == .5) return floor.isEven ? floor : floor + 1;
  return n.round();
}

double _round3(double value) {
  if (!value.isFinite || value == 0) return value;
  final bytes = ByteData(8)..setFloat64(0, value.abs());
  final bits = bytes.getUint64(0);
  final exponent = ((bits >> 52) & 0x7ff);
  final fraction = BigInt.from(bits & 0xfffffffffffff);
  final mantissa = exponent == 0 ? fraction : fraction + (BigInt.one << 52);
  final shift = (exponent == 0 ? -1022 : exponent - 1023) - 52;
  var numerator = mantissa * BigInt.from(1000), denominator = BigInt.one;
  if (shift >= 0) {
    numerator <<= shift;
  } else {
    denominator <<= -shift;
  }
  var quotient = numerator ~/ denominator;
  final remainder = numerator % denominator, twice = remainder * BigInt.two;
  if (twice > denominator || twice == denominator && quotient.isOdd)
    quotient += BigInt.one;
  final rounded = quotient.toDouble() / 1000;
  return value.isNegative ? -rounded : rounded;
}

String _signature(MdmMap m) => jsonEncode(_sorted(m));
Object? _sorted(Object? v) {
  if (v is Map) {
    final ks = v.keys.cast<String>().toList()..sort();
    return {for (final k in ks) k: _sorted(v[k])};
  }
  if (v is List) return v.map(_sorted).toList();
  return v;
}

class RajsimsMdmConfig {
  const RajsimsMdmConfig({
    this.apiUrl = 'https://rajsims-mdm.rajasthan.gov.in/Gateway/api/Gateway_PostAuthAdminService/GetData',
    this.departmentId = 16229,
    this.schemeId = 43,
    this.officeTypeId = 224,
    this.transactionType = 59,
    this.customerType = 56,
    this.draftId = 1,
    this.approvedId = 5,
    this.updateStatus = 1,
    this.updateRefType = 'BEN_DIS',
    this.zeroReason = 184,
    this.stockWidget = 12,
    this.stockUnit = 1,
    this.defaultProduct = 'Wheat',
    this.contextWait = 8,
    this.lightContextWait = 4,
    this.listTimeout = 45,
    this.readRetries = 1,
    this.stockTtl = 20,
    this.statusTtl = 8,
    this.warmExtra = 25,
    this.stockStaleMax = 1800,
    this.packingFallback = const {'wheat': 200001, 'rice': 200000},
  });
  final String apiUrl, updateRefType, defaultProduct;
  final int departmentId,
      schemeId,
      officeTypeId,
      transactionType,
      customerType,
      draftId,
      approvedId,
      updateStatus,
      zeroReason,
      stockWidget,
      stockUnit,
      readRetries;
  final double contextWait,
      lightContextWait,
      listTimeout,
      stockTtl,
      statusTtl,
      warmExtra,
      stockStaleMax;
  final Map<String, int> packingFallback;
}

class RajsimsMdmWorker {
  RajsimsMdmWorker({
    required this.auth,
    required this.currentContext,
    this.config = const RajsimsMdmConfig(),
    MdmRequest? request,
    double Function()? monotonic,
    DateTime Function()? nowIst,
    Future<void> Function(Duration)? sleep,
    RajsimsHttpTransport Function()? clientFactory,
  }) : clock = monotonic ?? _elapsed,
       nowIst =
           nowIst ??
           (() => DateTime.now().toUtc().add(const Duration(minutes: 330))),
       sleep = sleep ?? ((d) => Future<void>.delayed(d)) {
    adapter = RajsimsGatewayAdapter(
      currentContext: currentContext,
      waitForAuth: (c) => waitForAuth(c),
      bodyStatusCode: rajsimsBodyStatusCode,
      responseErrorMessage: (r, d) => responseMessage(r, d),
      apiUrl: config.apiUrl,
      apiTimeout: const Duration(seconds: 15),
      readRetries: config.readRetries,
      readRetryBackoff: const Duration(milliseconds: 600),
      writeMode: RajsimsWriteMode.enabled,
      clientFactory: clientFactory,
      sleep: this.sleep,
    );
    post = request ?? adapter.request;
  }
  final RajsimsAuthManager auth;
  final RajsimsHttpContext? Function() currentContext;
  final RajsimsMdmConfig config;
  final double Function() clock;
  final DateTime Function() nowIst;
  final Future<void> Function(Duration) sleep;
  late final RajsimsGatewayAdapter adapter;
  late final MdmRequest post;
  static final _clock = Stopwatch()..start();
  static double _elapsed() => _clock.elapsedMicroseconds / 1000000;
  MdmMap _user = {};
  final _mapping = <String, (double, MdmMap)>{},
      _recent = <String, (double, MdmMap)>{};
  final _results = <String, (double, double, MdmMap)>{};
  final _inflight = <String, (Future<MdmMap>, int)>{};
  final _profiles = <RajsimsHttpContext, Future<(String?, int?)>>{};
  final _failProfile = <RajsimsHttpContext, double>{},
      _failContext = <RajsimsHttpContext?, double>{};
  final _locks = <String, AsyncMutex>{};
  int _generation = 0;
  void invalidateResults() {
    _generation++;
    _results.clear();
  }

  void clearUserInfoCache() {
    _user = {};
    _mapping.clear();
    invalidateResults();
    _inflight.clear();
    _profiles.clear();
    _failProfile.clear();
    _failContext.clear();
    _recent.clear();
  }

  Future<void> close() => adapter.closeAll();
  bool _usable(RajsimsHttpContext? c) =>
      c != null && !c.closed && identical(c, currentContext());
  MdmMap _authUser(RajsimsHttpContext? c) =>
      c == null ? {} : auth.getUserInfo(c);
  AsyncMutex _lock(String k) => _locks.putIfAbsent(k, () => AsyncMutex());
  String _contextKey(MdmMap c) => '${c['office_id']}/${c['org_id']}';
  MdmMap? _cachedMapping(MdmMap ctx) {
    final k = _contextKey(ctx), hit = _mapping[k];
    if (hit == null) return null;
    if (clock() - hit.$1 > 1800) {
      _mapping.remove(k);
      return null;
    }
    return _copyCtx(hit.$2);
  }

  void _spawn(Future<dynamic> task) {
    unawaited(task.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  }

  Future<(String, String)> waitForAuth(
    RajsimsHttpContext c, {
    double timeout = 2,
    (String?, String?)? stale,
  }) async {
    if (!_usable(c)) return ('', '');
    final deadline = clock() + math.max(0, timeout);
    while (true) {
      final pair = auth.getAuth(c);
      if (_truth(pair.$1) && _truth(pair.$2) && pair != stale)
        return (pair.$1!, pair.$2!);
      final left = deadline - clock();
      if (left <= 0) break;
      await sleep(
        Duration(microseconds: (math.min(.1, left) * 1000000).round()),
      );
      if (!_usable(c)) break;
    }
    return ('', '');
  }

  static String responseMessage(SchoolHttpReply r, Object? data) {
    if (data is Map) {
      for (final k in [
        'Message',
        'message',
        'ErrorMessage',
        'error',
        'Error',
        'ErrorDescription',
        'detail',
      ]) {
        final v = data[k];
        if (v is String && v.trim().isNotEmpty) return v;
      }
    }
    return 'RajSIMS API request failed (HTTP ${r.statusCode}).';
  }

  static MdmMap apiFailure(String msg, int? status) => {
    'success': false,
    'code': status == 401
        ? 'SESSION_EXPIRED'
        : status == 403
        ? 'ACCESS_DENIED'
        : status == 429
        ? 'RATE_LIMITED'
        : status == null || status >= 500
        ? 'NETWORK_ERROR'
        : 'PORTAL_RESPONSE_ERROR',
    'message': msg,
    'status_code': status,
  };
  bool setCachedUserInfo(Object? name, Object? mobile, [Object? office = '']) {
    final n = _truth(name) ? _str(name).trim() : '',
        digits = _digits(_or([mobile, ''])),
        o = _str(_or([office, ''])).trim();
    if (n.isEmpty && o.isEmpty) return false;
    _user = {
      ..._user,
      if (n.isNotEmpty) 'name': n,
      if (digits.length == 10) 'mobile': int.parse(digits),
      if (o.isNotEmpty) 'office_name': o,
    };
    _user.putIfAbsent('office_name', () => '');
    return _truth(_user['name']) && _truth(_user['mobile']);
  }

  static String _digits(Object? value) => rajsimsMobileDigits(_str(value));

  bool _profileOk(bool office) {
    if (!_truth(_user['name']) || !_truth(_user['mobile'])) return false;
    if (!office || _truth(_user['office_name'])) return true;
    final stamp = _user['profile_fetched_at'];
    return stamp is num && clock() - stamp < 60;
  }

  Future<(String?, int?)>? _profileTask(
    RajsimsHttpContext? c, {
    bool office = true,
  }) {
    if (c == null || _profileOk(office) || clock() < (_failProfile[c] ?? 0))
      return null;
    return _profiles.putIfAbsent(c, () {
      final task = extractUserInfo(c, requireOffice: office);
      task.then<void>(
        (_) => _profiles.remove(c),
        onError: (Object _, StackTrace __) {
          _profiles.remove(c);
        },
      );
      return task;
    });
  }

  Future<MdmMap> _cached(
    String name,
    double ttl,
    bool force,
    Future<MdmMap> Function() factory,
    RajsimsHttpContext? c, {
    double bonus = 0,
    double staleMax = 0,
  }) async {
    final key = '$name/${identityHashCode(c)}',
        now = clock(),
        hit = _results[key];
    if (hit != null && !force) {
      if (ttl > 0 && now - hit.$2 < ttl) return _copy(hit.$3);
      if (staleMax > 0 && now - hit.$1 < staleMax) {
        _spawn(_cached(name, ttl, true, factory, c, bonus: bonus));
        return {
          ..._copy(hit.$3),
          'stale': true,
          'age_seconds': math.max(0, (now - hit.$1).truncate()),
        };
      }
    }
    var pending = _inflight[key];
    if (pending == null || pending.$2 != _generation) {
      final gen = _generation;
      final task = Future<MdmMap>.sync(factory);
      pending = (task, gen);
      _inflight[key] = pending;
      task.then<void>(
        (_) {
          if (identical(_inflight[key]?.$1, task)) _inflight.remove(key);
        },
        onError: (Object _, StackTrace __) {
          if (identical(_inflight[key]?.$1, task)) _inflight.remove(key);
        },
      );
    }
    final result = await pending.$1;
    if (result['success'] == true &&
        ttl > 0 &&
        pending.$2 == _generation &&
        _usable(c)) {
      final t = clock();
      _results[key] = (t, t + bonus, _copy(result));
    }
    return _copy(result);
  }

  MdmMap _buildCtx(MdmMap u) => {
    'office_id': _int(u['office_id']),
    'org_id': _int(u['org_id']),
    'department_id': _int(u['department_id']) != 0
        ? _int(u['department_id'])
        : config.departmentId,
    'scheme_id': _int(u['scheme_id']) != 0
        ? _int(u['scheme_id'])
        : config.schemeId,
    'office_type_id': _int(u['office_type_id']),
    'group_id': _int(u['group_id']),
    'group_name': _clean(u['group_name']),
    'enrolment': null,
    'products': <String, dynamic>{},
  };
  Future<(MdmMap?, String?)> resolveLightContext(
    RajsimsHttpContext? c, {
    bool needOffice = false,
  }) async {
    MdmMap? build() {
      final u = _authUser(c), ctx = _buildCtx(u);
      if (!_truth(ctx['org_id']) && !needOffice)
        ctx['org_id'] = _int(_user['profile_org_id']);
      if (!_truth(ctx['office_id']) && needOffice)
        ctx['office_id'] = _int(_user['profile_office_id']);
      if (!_truth(ctx['org_id']) || needOffice && !_truth(ctx['office_id']))
        return null;
      if (!_truth(ctx['office_type_id']))
        ctx['office_type_id'] = config.officeTypeId;
      return ctx;
    }

    var ctx = build();
    if (ctx != null) return (ctx, null);
    if (!needOffice) _profileTask(c, office: false);
    final cooldown = clock() - (_failContext[c] ?? 0) < 3,
        deadline = clock() + (cooldown ? 0 : config.lightContextWait);
    while (clock() < deadline) {
      await sleep(const Duration(milliseconds: 100));
      ctx = build();
      if (ctx != null) return (ctx, null);
    }
    _failContext[c] = clock();
    return (
      null,
      'Could not resolve school ${needOffice ? 'Office/Org' : 'Org'} from the RajSIMS session. Please re-login.',
    );
  }

  Future<MdmMap?> _serverMappings(RajsimsHttpContext? c, MdmMap ctx) async {
    final reply = await post(c, {
      'ApiKey': 'GetBeneficiaryGroupProductList',
      'ApiParams': {
        'CurrentPageNumber': 0,
        'PageSize': 50,
        'SortBy': '',
        'SortOrder': '',
        'SearchText': '',
        'FilterParams': {
          'DepartmentId': ctx['department_id'],
          'SchemeId': ctx['scheme_id'],
          'BeneficiaryGroupId': 0,
          'UserOfficeId': ctx['office_id'],
          'UserDeptId': ctx['org_id'],
        },
      },
      'OrgId': ctx['org_id'],
    });
    if (!reply.success) return null;
    var records = mdmResponseList(reply.data, [
      'CustomObject',
    ]).whereType<Map>().map(_map).toList();
    if (_truth(ctx['group_id'])) {
      final matched = records
          .where((r) => _int(r['BeneficiaryGroupId']) == ctx['group_id'])
          .toList();
      if (matched.isNotEmpty) records = matched;
    }
    final result = <String, dynamic>{
      'group_id': null,
      'group_name': null,
      'enrolment': null,
      'products': <String, dynamic>{},
    };
    final products = result['products'] as MdmMap;
    for (final r in records) {
      final gid = _int(r['BeneficiaryGroupId']);
      if (gid > 0 && !_truth(result['group_id'])) {
        result['group_id'] = gid;
        result['group_name'] = _clean(r['BeneficiaryGroupName']).isEmpty
            ? null
            : _clean(r['BeneficiaryGroupName']);
      }
      final enrol = _int(r['EnrolmentCount']);
      if (enrol > 0 && !_truth(result['enrolment']))
        result['enrolment'] = enrol;
      final meta = mdmProductMeta(r);
      if (_int(meta['product_id']) > 0 && _truth(meta['product_name'])) {
        final key = mdmProductName(meta['product_name']);
        if (products.containsKey(key)) {
          _fill(products[key] as MdmMap, meta);
        } else {
          products[key] = meta;
        }
      }
    }
    return _truth(result['group_id']) ? result : null;
  }

  static bool _missingMeta(MdmMap products) => products.values.any(
    (m) => [
      'packing_id',
      'criteria_id',
      'product_group_id',
      'product_uom_id',
      'quantity',
    ].any((k) => !_truth(m[k])),
  );
  void _defaults(MdmMap ctx) {
    for (final v in _map(ctx['products']).values) {
      final m = v as MdmMap;
      for (final e in const {
        'criteria_id': 5,
        'criteria_name': 'Class Range',
        'product_group_id': 110,
        'product_group_name': 'Food Grain',
        'product_uom_id': 1,
        'product_uom_name': 'Kilogram',
        'packing_name': 'Kilogram',
      }.entries) {
        if (!_truth(m[e.key])) m[e.key] = e.value;
      }
      if (!_truth(m['packing_id'])) {
        final id = config.packingFallback[mdmProductName(m['product_name'])];
        if (id != null) m['packing_id'] = id;
      }
      if (!_truth(m['batch_no']))
        m['batch_no'] = '${m['product_name'] ?? ''}001';
    }
  }

  Future<void> _enrichHistory(RajsimsHttpContext? c, MdmMap ctx) async {
    final result = await post(
      c,
      distributionPayload(1, 3, false, ctx),
      allowAuthRetry: false,
    );
    if (!result.success) return;
    final products = _map(ctx['products']),
        byId = {
          for (final m in products.values)
            if (_truth(m['product_id'])) m['product_id']: m,
        };
    for (final raw in mdmResponseList(result.data, ['CustomObject']).take(3)) {
      if (raw is! Map) continue;
      final tid = _int(_tid(_map(raw)));
      if (tid <= 0) continue;
      final detail = await post(c, {
        'ApiKey': 'GetBeneficiaryDistributionDetailById',
        'ApiParams': {'TransactionId': tid},
        'OrgId': ctx['org_id'],
      }, allowAuthRetry: false);
      if (!detail.success || detail.data is! Map) continue;
      final custom = _json((detail.data as Map)['CustomObject']);
      if (custom is! Map) continue;
      for (final tx in custom['Transactions'] ?? []) {
        if (tx is! Map) continue;
        final meta = _or([
          byId[_int(tx['ProductId'])],
          products[mdmProductName(tx['ProductName'])],
        ]);
        if (meta is! Map) continue;
        final source = mdmProductMeta(_map(tx)),
            ben = _int(tx['NoOfBeneficiary']),
            qty = _float(tx['IssueQuantity']);
        source['quantity'] = ben > 0 && qty > 0 ? _round3(qty / ben) : 0.0;
        _fill(meta as MdmMap, source);
      }
      if (!_missingMeta(products)) break;
    }
  }

  Future<MdmMap> dynamicMappings(RajsimsHttpContext? c) async {
    final ctx = _buildCtx(_authUser(c));
    final unlock = await _lock('mapping').acquire();
    try {
      if (_truth(ctx['office_id']) && _truth(ctx['org_id'])) {
        final hit = _cachedMapping(ctx);
        if (hit != null) return hit;
      }
      if (!_usable(c)) {
        ctx['office_type_id'] = _or([
          ctx['office_type_id'],
          config.officeTypeId,
        ]);
        return ctx;
      }
      if (!_truth(ctx['office_id']) || !_truth(ctx['org_id'])) {
        final deadline =
            clock() +
            (clock() - (_failContext[c] ?? 0) < 3 ? 0 : config.contextWait);
        while ((!_truth(ctx['office_id']) || !_truth(ctx['org_id'])) &&
            clock() < deadline) {
          final u = _authUser(c);
          for (final k in [
            'office_id',
            'org_id',
            'office_type_id',
            'group_id',
          ]) {
            if (!_truth(ctx[k])) ctx[k] = _int(u[k]);
          }
          if (_int(u['scheme_id']) != 0)
            ctx['scheme_id'] = _int(u['scheme_id']);
          if (_truth(ctx['office_id']) && _truth(ctx['org_id'])) break;
          await sleep(const Duration(milliseconds: 300));
        }
        if (!_truth(ctx['office_id']) || !_truth(ctx['org_id'])) {
          _failContext[c] = clock();
          return ctx;
        }
        final hit = _cachedMapping(ctx);
        if (hit != null) return hit;
      }
      final server = await _serverMappings(c, ctx);
      if (server != null) {
        ctx['group_id'] = server['group_id'];
        ctx['group_name'] = _or([server['group_name'], ctx['group_name']]);
        ctx['enrolment'] = server['enrolment'];
        ctx['products'] = server['products'] ?? {};
      }
      final products = _map(ctx['products']);
      if (products.isNotEmpty) {
        if (_missingMeta(products)) {
          try {
            await _enrichHistory(c, ctx);
          } catch (_) {}
        }
        _defaults(ctx);
      }
      ctx['office_type_id'] = _or([ctx['office_type_id'], config.officeTypeId]);
      if (_truth(ctx['group_id']) && products.isNotEmpty && _usable(c))
        _mapping[_contextKey(ctx)] = (clock(), _copyCtx(ctx));
      return ctx;
    } finally {
      unlock();
    }
  }

  Future<(MdmMap?, String?)> resolveContext(RajsimsHttpContext? c) async {
    try {
      final ctx = await dynamicMappings(c);
      if (!_truth(ctx['office_id']) || !_truth(ctx['org_id']))
        return (
          null,
          'Could not resolve school Office/Org from the RajSIMS session. Please re-login.',
        );
      return (ctx, null);
    } catch (e) {
      return (null, 'Could not resolve RajSIMS office context: $e');
    }
  }

  static Object? _deep(
    Object? obj,
    List<String> keys, [
    int depth = 8,
    bool positiveInt = false,
  ]) {
    if (depth < 0) return null;
    obj = _json(obj);
    if (obj is Map) {
      for (final e in obj.entries) {
        if (keys.contains(e.key.toString().toLowerCase())) {
          if (positiveInt) {
            if (_int(e.value) > 0) return _int(e.value);
          } else if (e.value != null && e.value != '') {
            return _json(e.value);
          }
        }
      }
      for (final v in obj.values) {
        if (v is Map || v is List || v is String) {
          final f = _deep(v, keys, depth - 1, positiveInt);
          if (f != null) return f;
        }
      }
    } else if (obj is List) {
      for (final v in obj.take(100)) {
        final f = _deep(v, keys, depth - 1, positiveInt);
        if (f != null) return f;
      }
    }
    return null;
  }

  Future<(MdmMap?, String)> _fetchProfile(
    RajsimsHttpContext c, {
    double wait = 2,
  }) async {
    final (id, key) = await waitForAuth(c, timeout: wait);
    if (id.isEmpty || key.isEmpty) return (null, 'Auth headers not available.');
    final cached = _authUser(c), cd = _digits(_or([cached['mobile'], '']));
    if (_truth(cached['name']) &&
        cd.length == 10 &&
        _truth(cached['office_id']) &&
        _truth(cached['org_id']))
      return (
        {
          'name': _str(cached['name']),
          'mobile': int.parse(cd),
          'office_name': _str(_or([cached['office_name'], ''])),
          'office_id': cached['office_id'],
          'org_id': cached['org_id'],
        },
        '',
      );
    final result = await post(c, {
      'ApiKey': 'ValidateTokenAndGetUserDetail',
      'ApiParams': {'AuthId': id, 'AuthKey': key},
      'OrgId': 0,
    });
    if (!result.success)
      return (null, 'HTTP ${result.status}: ${result.message}');
    if (result.data is! Map)
      return (null, 'Response is not a dict: ${result.data.runtimeType}');
    final data = result.data, personal = _map(_deep(data, ['personaldetails']));
    final mobile = _or([
          personal['MobileNumber'],
          _deep(data, ['mobilenumber', 'mobileno', 'mobile']),
          cached['mobile'],
        ]),
        name = _or([
          personal['Name'],
          personal['FullName'],
          _deep(data, ['name', 'fullname']),
          cached['name'],
        ]),
        office = _or([
          personal['OfficeName'],
          _deep(data, ['officename']),
          cached['office_name'],
        ]);
    final pid = _int(_deep(data, ['officeid'], 6, true)),
        org = _int(_deep(data, ['orgid'], 6, true));
    if (pid != 0 && _truth(cached['office_id']) && pid != cached['office_id'] ||
        org != 0 && _truth(cached['org_id']) && org != cached['org_id'])
      return (
        null,
        'PROFILE_INCOMPLETE: Profile identity does not match the active school session.',
      );
    final digits = _digits(_or([mobile, '']));
    if (digits.length != 10)
      return (
        null,
        'PROFILE_INCOMPLETE: The authenticated profile did not provide a valid mobile number.',
      );
    final n = _str(_or([name, ''])).trim();
    if (n.isEmpty)
      return (
        null,
        'PROFILE_INCOMPLETE: The authenticated profile did not provide the user name.',
      );
    return (
      {
        'name': n,
        'mobile': int.parse(digits),
        'office_name': _str(_or([office, ''])).trim(),
        'office_id': _or([pid, cached['office_id']]),
        'org_id': _or([org, cached['org_id']]),
      },
      '',
    );
  }

  Future<(String?, int?)> extractUserInfo(
    RajsimsHttpContext? c, {
    bool requireOffice = false,
  }) async {
    final epoch = _generation;
    (String?, int?)? cached() => _profileOk(requireOffice)
        ? (_str(_user['name']), _int(_user['mobile']))
        : null;
    final hit = cached();
    if (hit != null) return hit;
    if (c == null) return (null, null);
    final unlock = await _lock('profile').acquire();
    try {
      final hit = cached();
      if (hit != null) return hit;
      if (clock() < (_failProfile[c] ?? 0)) return (null, null);
      for (var attempt = 1; attempt <= 3; attempt++) {
        MdmMap? p;
        String reason;
        try {
          (p, reason) = await _fetchProfile(c, wait: attempt == 1 ? 2 : 3);
        } catch (e) {
          p = null;
          reason = 'Exception: $e';
        }
        if (p != null) {
          if (epoch != _generation || !_usable(c)) return (null, null);
          _user = {
            ..._user,
            'name': p['name'],
            'mobile': p['mobile'],
            'office_name': _or([p['office_name'], _user['office_name'], '']),
            'profile_fetched_at': clock(),
            if (_truth(p['office_id'])) 'profile_office_id': p['office_id'],
            if (_truth(p['org_id'])) 'profile_org_id': p['org_id'],
          };
          _failProfile.remove(c);
          return (_str(p['name']), _int(p['mobile']));
        }
        final hit = cached();
        if (hit != null) return hit;
        if (reason.startsWith('PROFILE_INCOMPLETE:')) {
          if (epoch == _generation && _usable(c))
            _failProfile[c] = clock() + 30;
          break;
        }
        if (attempt < 3) await sleep(const Duration(milliseconds: 1500));
      }
      return (null, null);
    } finally {
      unlock();
    }
  }

  MdmMap distributionPayload(int page, int size, bool legacy, MdmMap ctx) => {
    'ApiKey': legacy
        ? 'GetLegacyBeneficiaryDistributionList'
        : 'GetBeneficiaryDistributionList',
    'ApiParams': {
      'SearchText': '',
      'CurrentPageNumber': page,
      'PageSize': size,
      'SortOrder': '',
      'SortBy': '',
      'FilterParams': {
        'DepartmentId': ctx['org_id'],
        'OfficeId': ctx['office_id'],
        'SchemeId': ctx['scheme_id'],
        'Fromdate': null,
        'Todate': null,
        if (legacy) 'StatusName': 'unsettled',
      },
    },
    'OrgId': ctx['org_id'],
  };
  String _pageSignature(List<MdmMap> rows) => jsonEncode(
    rows
        .map(
          (r) => [
            _tid(r),
            _dno(r),
            _clean(_or([r['DistributionDate'], r['Date']])),
          ],
        )
        .toList(),
  );
  bool _sortedOlder(List<MdmMap> rows, DateTime today) {
    final dates = <DateTime>[];
    for (final r in rows) {
      final d = mdmParseDate(_or([r['DistributionDate'], r['Date']]));
      if (d == null) return false;
      dates.add(DateTime.utc(d.year, d.month, d.day));
    }
    if (dates.isEmpty) return false;
    for (var i = 1; i < dates.length; i++) {
      if (dates[i].isAfter(dates[i - 1])) return false;
    }
    return dates.last.isBefore(
      DateTime.utc(today.year, today.month, today.day),
    );
  }

  Future<int> _beneficiaryDetail(
    RajsimsHttpContext? c,
    MdmMap ctx,
    String tid,
  ) async {
    final r = await post(c, {
      'ApiKey': 'GetBeneficiaryDistributionDetailById',
      'ApiParams': {'TransactionId': _int(tid)},
      'OrgId': ctx['org_id'],
    });
    if (!r.success || r.data is! Map) return 0;
    final custom = _json((r.data as Map)['CustomObject']);
    if (custom is! Map) return 0;
    var count = 0;
    for (final tx in custom['Transactions'] ?? []) {
      if (tx is! Map) continue;
      final ben = _int(tx['NoOfBeneficiary']);
      if (ben > 0) {
        count += ben;
        continue;
      }
      final qty = _float(tx['IssueQuantity']),
          rate = _float(_findProduct(ctx, tx['ProductName'])?['quantity']);
      if (qty > 0 && rate > 0) count += _halfEven(qty / rate);
    }
    return count;
  }

  Future<MdmMap> stock(
    RajsimsHttpContext? c, {
    bool allowStale = false,
    bool force = false,
  }) => _cached(
    'stock',
    config.stockTtl,
    force,
    () => _stock(c),
    c,
    staleMax: allowStale && !force ? config.stockStaleMax : 0,
  );
  Future<MdmMap> _stock(RajsimsHttpContext? c) async {
    final (ctx, err) = await resolveLightContext(c);
    if (err != null) return {'success': false, 'message': err};
    final r = await post(c, {
      'ApiKey': 'GetAllChartData',
      'ApiParams': {
        'FilterParams': {
          'widgetdetailid': config.stockWidget,
          'paraunitid': config.stockUnit,
        },
      },
      'OrgId': ctx!['org_id'],
    });
    if (!r.success) return apiFailure(r.message, r.status);
    double wheat = 0, rice = 0;
    bool w = false, b = false;
    for (final item in mdmResponseList(r.data, [
      'CustomObject',
      'List',
      'Data',
    ])) {
      if (item is! Map) continue;
      final name = mdmProductName(
            item.containsKey('NAME') ? item['NAME'] : item['Name'] ?? '',
          ),
          value = math.max(
            0.0,
            _float(
              item.containsKey('TOTAL') ? item['TOTAL'] : item['Stock'] ?? 0,
            ),
          );
      if (name.startsWith('wheat')) {
        wheat += value;
        w = true;
      } else if (name.startsWith('rice')) {
        rice += value;
        b = true;
      }
    }
    if (!w && !b)
      return {
        'success': false,
        'code': 'INVALID_RESULT',
        'message': 'RajSIMS response contained no recognized stock fields.',
      };
    return {
      'success': true,
      'stock': {'wheat': wheat, 'rice': rice, 'total_avail': wheat + rice},
      'stock_fields_found': {'wheat': w, 'rice': b},
    };
  }

  Future<MdmMap> status(RajsimsHttpContext? c, {bool force = false}) =>
      _cached('status', config.statusTtl, force, () => _statusRead(c), c);
  Future<MdmMap> _statusRead(RajsimsHttpContext? c) async {
    try {
      final today = mdmFormatDate(nowIst()), profile = _profileTask(c);
      final (ctx, err) = await resolveLightContext(c, needOffice: true);
      if (err != null) return {'success': false, 'message': err};
      final rows = <MdmMap>[], seen = <String>{}, started = clock();
      var page = 1;
      while (page <= 100) {
        final r = await post(c, distributionPayload(page, 10, false, ctx!));
        if (!r.success) return apiFailure(r.message, r.status);
        final raw = mdmValidatedRecords(r.data);
        if (raw == null)
          return {
            'success': false,
            'code': 'INVALID_RESULT',
            'message':
                'RajSIMS returned an unrecognized distribution-list response.',
          };
        if (raw.isEmpty) break;
        final sig = _pageSignature(raw);
        if (sig.isEmpty || !seen.add(sig))
          return {
            'success': false,
            'code': 'PARTIAL_REPORT',
            'message':
                'RajSIMS pagination repeated a page; the result is incomplete.',
          };
        rows.addAll(raw);
        if (raw.length < 10) break;
        if (raw.any(
          (r) =>
              mdmNormalizeDate(_or([r['DistributionDate'], r['Date']])) ==
              today,
        ))
          break;
        if (_sortedOlder(rows, nowIst())) break;
        if (clock() - started > config.listTimeout)
          return {
            'success': false,
            'message':
                "RajSIMS list scan timed out; could not confirm today's entry.",
          };
        page++;
      }
      if (page > 100)
        return {
          'success': false,
          'code': 'PARTIAL_REPORT',
          'message':
              'RajSIMS page limit reached before status could be confirmed.',
        };
      var exists = false, count = 0, tid = '', no = '';
      for (final r in rows) {
        if (mdmNormalizeDate(_or([r['DistributionDate'], r['Date']])) != today)
          continue;
        exists = true;
        tid = _tid(r);
        no = _dno(r);
        count = _ben(r);
        if (count <= 0 && tid.isNotEmpty) {
          try {
            count = await _beneficiaryDetail(
              c,
              _cachedMapping(ctx!) ?? ctx,
              tid,
            );
          } catch (_) {}
        }
        break;
      }
      if (profile != null && !_profileOk(true)) {
        try {
          await profile.timeout(const Duration(milliseconds: 2500));
        } catch (_) {}
      }
      var name = _or([_user['name'], 'MDM Incharge']),
          school = _or([_user['office_name'], '']);
      if (!_truth(school)) {
        final deadline = clock() + .5;
        while (clock() < deadline) {
          final u = _authUser(c);
          if (_truth(u['office_name'])) {
            school = u['office_name'];
            if (!_truth(_user['name'])) name = _or([u['name'], name]);
            break;
          }
          await sleep(const Duration(milliseconds: 100));
        }
      }
      if (!_truth(school)) school = 'GOVT. SCHOOL (${ctx!['office_id']})';
      return {
        'success': true,
        'today_entry_exists': exists,
        'beneficiary_count': count,
        'transaction_id': tid,
        'distribution_no': no,
        'school_name': school,
        'incharge_name': name,
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<MdmMap> warmUp(
    RajsimsHttpContext? c, {
    bool includeProfile = true,
  }) async {
    final jobs = <String, Future<dynamic>>{
      if (includeProfile) 'profile': extractUserInfo(c, requireOffice: true),
      'mapping': dynamicMappings(c)
          .then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      'stock': _cached(
        'stock',
        config.stockTtl,
        true,
        () => _stock(c),
        c,
        bonus: config.warmExtra,
      ),
      'status': _cached(
        'status',
        config.statusTtl,
        true,
        () => _statusRead(c),
        c,
        bonus: config.warmExtra,
      ),
    };
    final entries = await Future.wait(
      jobs.entries.map((e) async {
        try {
          final r = await e.value;
          return MapEntry(
            e.key,
            r is Map && r.containsKey('success')
                ? _truth(r['success'])
                : r is (String?, int?)
                ? _truth(r.$1) && _truth(r.$2)
                : true,
          );
        } catch (_) {
          return MapEntry(e.key, false);
        }
      }),
    );
    return Map.fromEntries(entries);
  }

  Future<bool> prefetchUserInfo(RajsimsHttpContext? c) async {
    _spawn(warmUp(c, includeProfile: false));
    if (_profileOk(true)) return true;
    final (_, mobile) = await extractUserInfo(c, requireOffice: true);
    return _truth(mobile);
  }

  MdmMap _legacyRow(
    MdmMap ctx,
    MdmMap m, {
    required double qty,
    required int ben,
    required String date,
    required int mobile,
    required int reason,
    int transactionId = 0,
    String distributionNo = '',
  }) => {
    'BenefciaryGroupId': ctx['group_id'],
    'BenefciaryGroupName': ctx['group_name'],
    'BenefitMonth': date,
    'CateriaId': m['criteria_id'],
    'CateriaName': m['criteria_name'],
    'CustomerType': config.customerType,
    'DistributionDate': date,
    'MobileNo': mobile,
    'NoOfBeneficiary': ben,
    'OfficeId': ctx['office_id'],
    'OfficeTypeId': ctx['office_type_id'],
    'OrgId': ctx['org_id'],
    'PackagingId': m['packing_id'],
    'PackagingName': m['packing_name'],
    'PackingQtyPerPack': 1,
    'ProductGroupId': m['product_group_id'],
    'ProductGroupName': m['product_group_name'],
    'ProductId': m['product_id'],
    'ProductName': m['product_name'],
    'ProductUomId': m['product_uom_id'],
    'ProductUomName': m['product_uom_name'],
    'Quantity': qty,
    'ReasonId': reason,
    'SchemeId': ctx['scheme_id'],
    'StatusId': config.draftId,
    'StatusName': 'Draft',
    'TransactionType': config.transactionType,
    if (transactionId > 0) 'TransactionId': transactionId,
    if (distributionNo.isNotEmpty) 'DistributionNo': distributionNo,
  };
  Future<MdmMap> submit(RajsimsHttpContext? c, MdmMap payload) async {
    final office = _int(_authUser(c)['office_id']).toString(),
        signature = '$office|${_signature(payload)}';
    final unlock = await _lock('submit:$office').acquire();
    try {
      final now = clock();
      _recent.removeWhere((_, v) => now - v.$1 > 10);
      final previous = _recent[signature];
      if (previous != null)
        return {..._copy(previous.$2), 'duplicate_ignored': true};
      final r = await _submit(c, payload);
      if (r['success'] == true) {
        _recent[signature] = (clock(), _copy(r));
        invalidateResults();
      }
      return r;
    } finally {
      unlock();
    }
  }

  Future<MdmMap> _submit(RajsimsHttpContext? c, MdmMap p) async {
    MdmMap fail(String m) => {'success': false, 'message': m};
    final raw = _or([p['legacy_date'], p['DistributionDate']]),
        today = mdmFormatDate(nowIst());
    var legacy = mdmBool(p['legacy'] ?? false);
    if (_truth(raw)) {
      final normalized = mdmNormalizeDate(raw);
      if (normalized != null && normalized != today) legacy = true;
    }
    final (ctx, err) = await resolveContext(c);
    if (err != null) return fail(err);
    final x = ctx!;
    if (!_truth(x['group_id']))
      return fail('Beneficiary group could not be resolved from RajSIMS.');
    final requested = _or([p['product_name'], config.defaultProduct]),
        m = _findProduct(x, requested);
    if (m == null) {
      final available = _map(x['products']).values
          .map((v) => v['product_name'])
          .join(', ');
      return fail(
        "Invalid product '$requested'. Available: ${available.isEmpty ? 'none' : available}.",
      );
    }
    final missing = [
      'product_id',
      'packing_id',
      'quantity',
    ].where((f) => !_truth(m[f])).toList();
    if (missing.isNotEmpty)
      return fail(
        "RajSIMS master data missing for ${m['product_name']}: ${missing.join(', ')}.",
      );
    final zero = mdmBool(p['is_zero_consumption'] ?? false);
    var ben = _int(p['beneficiary_count'] ?? 0);
    if (ben < 0) return fail('Beneficiary count cannot be negative.');
    final enrol = x['enrolment'];
    if (_truth(enrol) && ben > _int(enrol))
      return fail(
        'Beneficiary count cannot exceed enrolled students ($enrol).',
      );
    if (zero) {
      ben = 0;
    } else if (ben <= 0) {
      return fail('Beneficiary count must be greater than 0.');
    }
    final choice = _str(p['atithi_mata_choice'] ?? '0').trim();
    if (!{'0', '1'}.contains(choice))
      return fail('Invalid Atithi Mata selection.');
    var atithi = math.max(0, _int(p['atithi_mata_count'] ?? 0));
    if (choice == '1' && atithi <= 0)
      return fail('Atithi Mata count must be greater than 0.');
    if (choice == '0') atithi = 0;
    String date;
    if (legacy) {
      if (raw == null) return fail('Legacy distribution date is required.');
      final d = mdmParseDate(raw);
      if (d == null) return fail('Invalid legacy distribution date.');
      final now = nowIst();
      if (!DateTime.utc(
        d.year,
        d.month,
        d.day,
      ).isBefore(DateTime.utc(now.year, now.month, now.day)))
        return fail('Legacy distribution date must be before today.');
      date = mdmFormatDate(d);
    } else {
      final d = _truth(raw) ? mdmNormalizeDate(raw) : today;
      if (d == null) return fail('Invalid distribution date.');
      date = d;
    }
    final tid = _int(
          p['transaction_id'] ?? p['transactionId'] ?? p['TransactionId'] ?? 0,
        ),
        no = _clean(
          p['dist_no'] ?? p['distribution_no'] ?? p['DistributionNo'] ?? '',
        ),
        qty = zero ? 0.0 : _round3(ben * _float(m['quantity'])),
        explicitReason = _int(p['reason_id']),
        reason = zero
            ? (explicitReason > 0 ? explicitReason : config.zeroReason)
            : 0;
    if (zero && reason <= 0)
      return fail('A valid zero-consumption reason is required.');
    final (name, mobile) = await extractUserInfo(c);
    if (!_truth(name) || !_truth(mobile))
      return {
        'success': false,
        'code': 'NO_USER',
        'applied': false,
        'message': 'The authenticated user name/mobile is unavailable. No distribution was submitted.',
      };
    MdmMap body;
    if (legacy) {
      final rows = <MdmMap>[];
      for (final v in _map(x['products']).values) {
        final other = _map(v),
            selected = other['product_id'] == m['product_id'];
        if (!selected && !_truth(other['packing_id'])) continue;
        rows.add(
          _legacyRow(
            x,
            other,
            qty: selected ? qty : 0.0,
            ben: selected ? ben : 0,
            date: date,
            mobile: mobile!,
            reason: reason,
            transactionId: selected ? tid : 0,
            distributionNo: selected ? no : '',
          ),
        );
      }
      body = {
        'ApiKey': 'SaveEditlegancyBenefiDistribution',
        'OrgId': x['org_id'],
        'ApiParams': rows,
      };
    } else {
      body = {
        'ApiKey': 'SaveEditBeneficiaryDistribution',
        'OrgId': x['org_id'],
        'ApiParams': {
          'TransactionId': tid,
          'TransactionType': config.transactionType,
          'CustomerType': config.customerType,
          'IdentificationNumber': mobile.toString(),
          'AthitiMataCount': choice == '1' ? atithi : null,
          'Customer': {'CustomerId': 0, 'Name': name, 'MobileNo': mobile},
          'DistributionDate': date,
          'DistributionNo': no,
          'IsActive': 1,
          'IsAthitiMata': choice == '1' ? 1 : 0,
          'OfficeId': x['office_id'],
          'OfficeTypeId': x['office_type_id'],
          'OrgId': x['org_id'],
          'ReasonId': reason,
          'SchemeId': x['scheme_id'],
          'Status': 'Approved',
          'StatusId': config.approvedId,
          'StatusName': 'Approved',
          'Transactions': [
            {
              'DetailId': 0,
              'ProductId': m['product_id'],
              'ProductName': m['product_name'],
              'ProductGroupId': m['product_group_id'],
              'ProductGroupName': m['product_group_name'],
              'AvailableQuantity': 0,
              'BatchNo': m['batch_no'],
              'BenefciaryGroupId': x['group_id'],
              'BenefciaryGroupName': x['group_name'],
              'BenefitMonth': date,
              'CateriaId': m['criteria_id'],
              'CateriaName': m['criteria_name'],
              'DistributionFrequency': 'Daily',
              'DistributionFrequencyId': null,
              'ExpiryDate': '',
              'IssueQuantity': qty,
              'NoOfBeneficiary': ben,
              'PackagingId': m['packing_id'],
              'PackagingName': m['packing_name'],
              'PackingQtyPerPack': 1,
              'ProductUomId': m['product_uom_id'],
              'ProductUomName': m['product_uom_name'],
              'RequiredQuantity': qty,
            },
          ],
        },
      };
    }
    try {
      final r = await post(c, body, allowAuthRetry: false);
      if (!r.success) return apiFailure(r.message, r.status);
      if (r.data is! Map)
        return fail('RajSIMS returned an invalid submit response.');
      final d = _map(r.data);
      if (_submitOk(d)) {
        final (newTid, newNo) = _ids(d);
        return {
          'success': true,
          'message': _str(
            d.containsKey('Message')
                ? d['Message']
                : 'Distribution saved successfully.',
          ),
          'transaction_id': _int(newTid) != 0 ? _int(newTid) : tid,
          'distribution_no': newNo.isEmpty ? no : newNo,
        };
      }
      return {
        'success': false,
        'message': _str(
          d['Message'] ??
              d['ErrorMessage'] ??
              d['Error'] ??
              'Failed to save data.',
        ),
        'status_code': r.status,
      };
    } catch (e) {
      return fail(e.toString());
    }
  }

  Future<MdmMap> _directUpdate(
    String distNo,
    MdmMap data,
    RajsimsHttpContext? c, {
    bool legacy = false,
  }) async {
    final no = distNo.trim();
    if (no.isEmpty)
      return {
        'success': false,
        'message': 'Distribution number is required for update.',
      };
    final p = {...data, 'dist_no': no, 'legacy': legacy};
    var tid = _int(
      _or([p['transaction_id'], p['transactionId'], p['TransactionId']]),
    );
    if (tid <= 0) {
      final list = await history(c, isLegacy: legacy);
      if (list['success'] != true)
        return {
          'success': false,
          'message': _or([
            list['message'],
            'Could not look up the entry to update.',
          ]),
        };
      for (final r in list['records'] ?? []) {
        if (r is Map && _str(r['distNo'] ?? '').trim() == no) {
          tid = _int(r['transactionId']);
          break;
        }
      }
    }
    if (tid <= 0)
      return {
        'success': false,
        'message':
            'TransactionId not found for $no; refusing to create a duplicate entry.',
      };
    p['transaction_id'] = tid;
    return submit(c, p);
  }

  Future<MdmMap> entry(
    String distNo,
    RajsimsHttpContext? c, {
    bool legacy = false,
    int transactionId = 0,
  }) async {
    final no = distNo.trim();
    var tid = _int(transactionId);
    if (no.isEmpty && tid <= 0)
      return {'success': false, 'message': 'Distribution number is required.'};
    final (ctx, err) = await resolveContext(c);
    if (err != null) return {'success': false, 'message': err};
    if (tid <= 0 && no.isNotEmpty) {
      final list = await history(c, isLegacy: legacy);
      if (list['success'] == true) {
        for (final r in list['records'] ?? []) {
          if (r is Map && _str(r['distNo'] ?? '').trim() == no) {
            tid = _int(r['transactionId']);
            break;
          }
        }
      }
    }
    if (tid <= 0 && RegExp(r'^\d+$').hasMatch(no)) tid = _int(no);
    if (tid <= 0)
      return {'success': false, 'message': 'TransactionId not found for $no.'};
    final r = await post(c, {
      'ApiKey': 'GetBeneficiaryDistributionDetailById',
      'ApiParams': {'TransactionId': tid},
      'OrgId': ctx!['org_id'],
    });
    if (!r.success || r.data is! Map)
      return apiFailure(
        r.message.isEmpty ? 'Failed to fetch details.' : r.message,
        r.status,
      );
    final custom = _json((r.data as Map)['CustomObject']);
    if (custom is! Map)
      return {
        'success': false,
        'message': 'CustomObject missing in detail response.',
      };
    final master = _map(custom['MasterDetails']), items = <MdmMap>[];
    for (final tx in custom['Transactions'] ?? []) {
      if (tx is! Map) continue;
      items.add({
        'detailId': _int(tx['DetailId']),
        'transactionId': _or([_int(tx['TransactionId']), tid]),
        'distNo': _or([_clean(master['DistributionNo']), no]),
        'distributionDate': _clean(master['DistributionDate']),
        'productId': _int(tx['ProductId']),
        'product': _clean(tx['ProductName']),
        'beneficiary': _int(tx['NoOfBeneficiary']),
        'quantity': _float(
          tx.containsKey('IssueQuantity')
              ? tx['IssueQuantity']
              : tx['RequiredQuantity'] ?? 0.0,
        ),
        'packingId': _int(_first(tx, ['PackagingId', 'PackingId'])),
        'packingName': _clean(_first(tx, ['PackagingName', 'PackingName'])),
        'groupId': _or([_int(tx['BenefciaryGroupId']), ctx['group_id'], 0]),
        'groupName': _or([
          _clean(tx['BenefciaryGroupName']),
          ctx['group_name'],
          '',
        ]),
        'enrolment': _or([_int(tx['EnrolmentCount']), ctx['enrolment'], 0]),
      });
    }
    return {'success': true, 'master': master, 'items': items, 'raw': custom};
  }

  Future<MdmMap> sendUpdateRequest(RajsimsHttpContext? c, MdmMap p) async {
    MdmMap fail(String m) => {'success': false, 'message': m};
    final (ctx, err) = await resolveContext(c);
    if (err != null) return fail(err);
    final x = ctx!;
    var refId = _int(
          _or([
            p['transaction_id'],
            p['TransactionId'],
            p['transactionId'],
            p['RefId'],
          ]),
        ),
        refNo = _clean(_or([p['dist_no'], p['DistributionNo'], p['RefNo']]));
    MdmMap? details;
    if (refId <= 0 && refNo.isNotEmpty) {
      details = await entry(refNo, c);
      if (details['success'] == true && _truth(details['items']))
        refId = _int(details['items'][0]['transactionId']);
    }
    if (refId <= 0)
      return fail(
        'Valid TransactionId (RefId) is required for update request.',
      );
    if (details == null || details['success'] != true)
      details = await entry(
        refNo.isEmpty ? refId.toString() : refNo,
        c,
        transactionId: refId,
      );
    if (details['success'] != true || !_truth(details['items']))
      return fail('Failed to pull existing record details for update request.');
    final master = _map(details['master']),
        items = (details['items'] as List).map(_map).toList(),
        wanted = _int(p['detail_id']);
    final first = items.firstWhere(
      (i) => wanted != 0 && i['detailId'] == wanted,
      orElse: () => items.first,
    );
    if (refNo.isEmpty) refNo = _clean(master['DistributionNo']);
    final raw = _or([
          _clean(master['DistributionDate']),
          _clean(
            _or([p['distribution_date'], p['DistributionDate'], p['RefDate']]),
          ),
        ]),
        date = _or([mdmNormalizeDate(raw), raw, mdmFormatDate(nowIst())]);
    final product = _str(_or([p['product_name'], first['product'], ''])).trim(),
        count = p['beneficiary_count'] == null
            ? _int(first['beneficiary'])
            : _int(p['beneficiary_count']);
    if (count < 0) return fail('Beneficiary count cannot be negative.');
    final enrol = x['enrolment'];
    if (_truth(enrol) && count > _int(enrol))
      return fail(
        'Beneficiary count cannot exceed enrolled students ($enrol).',
      );
    final old = mdmProductName(first['product']);
    if (mdmProductName(product) == old && count == _int(first['beneficiary']))
      return {
        'success': false,
        'message': 'Please note that Request cannot be sent without making any changes ! Make sure all required information is Updated',
        'status_code': 400,
      };
    var m = _findProduct(x, product);
    if (m == null) {
      if (mdmProductName(product) == old && _truth(first['productId'])) {
        final ben = _int(first['beneficiary']), qty = _float(first['quantity']);
        m = {
          'product_id': first['productId'],
          'product_name': _or([first['product'], product]),
          'packing_id': first['packingId'] ?? 0,
          'packing_name': first['packingName'] ?? '',
          'quantity': ben > 0 && qty > 0 ? _round3(qty / ben) : 0.0,
        };
      } else {
        return fail("Invalid product '$product'.");
      }
    }
    final group = _or([x['group_id'], first['groupId']]);
    if (!_truth(group)) return fail('Beneficiary group could not be resolved.');
    final same =
            _truth(m['product_id']) && m['product_id'] == first['productId'],
        packing = same
            ? _or([first['packingId'], m['packing_id']])
            : m['packing_id'],
        packingName = same
            ? _or([first['packingName'], m['packing_name']])
            : m['packing_name'];
    if (!_truth(m['product_id']) || !_truth(packing))
      return fail(
        'RajSIMS master data missing (product/packing) for update request.',
      );
    final qty = _float(p['quantity']) != 0
        ? _float(p['quantity'])
        : _round3(count * _float(m['quantity']));
    if (qty <= 0 && count > 0)
      return fail('Per-student quantity could not be resolved from RajSIMS.');
    final r = await post(c, {
      'ApiKey': 'SendDistributionCancelRequest',
      'OrgId': x['org_id'],
      'ApiParams': {
        'RefType': config.updateRefType,
        'RefId': refId,
        'RefNo': refNo,
        'RefDate': date,
        'OrgId': x['org_id'],
        'OfficeId': x['office_id'],
        'SchemeId': x['scheme_id'],
        'StatusId': config.updateStatus,
        'ReasonId': _int(p['reason_id']) > 0 ? _int(p['reason_id']) : null,
        'distriTransUpdateDetails': [
          {
            'RefDetailId': first['detailId'],
            'BeneficiaryGroupId': group,
            'ProductId': m['product_id'],
            'ProductName': _or([m['product_name'], product]),
            'NoOfBeneficiary': count,
            'IssuedQuantity': qty,
            'PackingId': packing,
            'PackingName': packingName,
          },
        ],
      },
    }, allowAuthRetry: false);
    if (!r.success) return apiFailure(r.message, r.status);
    if (r.data is! Map)
      return fail('Invalid response received for update request.');
    final d = _map(r.data);
    if (_submitOk(d)) {
      invalidateResults();
      return {
        'success': true,
        'message': _str(
          d.containsKey('Message')
              ? d['Message']
              : 'Distribution update request sent successfully.',
        ),
        'transaction_id': refId,
        'distribution_no': refNo,
      };
    }
    return {
      'success': false,
      'message': _str(
        d['Message'] ?? d['ErrorMessage'] ?? 'Failed to send update request.',
      ),
      'status_code': r.status,
    };
  }

  Future<MdmMap> update(
    String distNo,
    MdmMap data,
    RajsimsHttpContext? c, {
    bool legacy = false,
  }) {
    final no = distNo.trim();
    if (no.isEmpty)
      return Future.value({
        'success': false,
        'message': 'Distribution number is required for update.',
      });
    if (legacy) return _directUpdate(no, data, c, legacy: true);
    return sendUpdateRequest(c, {...data, 'dist_no': no, 'legacy': false});
  }

  Future<MdmMap> history(
    RajsimsHttpContext? c, {
    bool isLegacy = false,
    bool force = false,
  }) async {
    final name = isLegacy ? 'Legacy Distribution List' : 'Distribution List',
        all = <MdmMap>[],
        started = clock(),
        seen = <String>{};
    var page = 1, pages = 0;
    int? total;
    MdmMap partial(String msg, {bool records = false, bool failed = false}) => {
      'success': false,
      'code': 'PARTIAL_REPORT',
      'message': msg,
      if (records) 'records': [],
      if (records) 'legacy': isLegacy,
      if (failed) 'failed_page': page,
    };
    try {
      final (ctx, err) = await resolveLightContext(c, needOffice: true);
      if (err != null)
        return {
          'success': false,
          'message': err,
          'records': [],
          'total_records': 0,
          'legacy': isLegacy,
        };
      while (page <= 100) {
        if (clock() - started > config.listTimeout)
          return {
            'success': false,
            'message': '$name scan timed out.',
            'records': [],
            'total_records': 0,
            'legacy': isLegacy,
            'failed_page': page,
          };
        final r = await post(c, distributionPayload(page, 10, isLegacy, ctx!));
        if (!r.success)
          return {
            ...apiFailure(r.message, r.status),
            'records': [],
            'total_records': 0,
            'legacy': isLegacy,
            'failed_page': page,
          };
        final raw = mdmValidatedRecords(r.data);
        if (raw == null)
          return {
            'success': false,
            'code': 'INVALID_RESULT',
            'message':
                'RajSIMS returned an unrecognized distribution-list response.',
            'records': [],
            'legacy': isLegacy,
          };
        final reported = mdmReportedTotal(r.data);
        if (reported != null) {
          if (total != null && reported != total)
            return partial(
              'RajSIMS history changed during pagination. Refresh the list.',
              failed: true,
            );
          total = reported;
        }
        if (raw.isEmpty) {
          if (total != null && all.length != total)
            return partial(
              'RajSIMS history ended before the reported record count was reached.',
              failed: true,
            );
          break;
        }
        final sig = _pageSignature(raw);
        if (sig.isEmpty || !seen.add(sig))
          return partial(
            'RajSIMS pagination repeated a page; the result is incomplete.',
          );
        all.addAll(raw);
        pages++;
        if (total != null) {
          if (all.length > total)
            return partial(
              'RajSIMS records exceeded the reported list count.',
              failed: true,
            );
          if (all.length == total) break;
        }
        if (raw.length < 10) {
          if (total != null)
            return partial(
              'RajSIMS history page was incomplete for the reported record count.',
              failed: true,
            );
          break;
        }
        page++;
      }
      if (page > 100)
        return partial('RajSIMS list page limit reached.', records: true);
      final formatted = <MdmMap>[];
      for (final r in all) {
        final status = _str(
          r.containsKey('StatusName') ? r['StatusName'] : r['Status'] ?? '',
        ).trim();
        if (isLegacy &&
            !{'unsettled', 'un-settled', 'pending'}.contains(_status(status)))
          continue;
        formatted.add({
          'sNo': (formatted.length + 1).toString(),
          'transactionId': _or([_tid(r), '-']),
          'distNo': _or([_dno(r), '-']),
          'date': _or([
            _clean(
              r.containsKey('DistributionDate')
                  ? r['DistributionDate']
                  : r['Date'] ?? '',
            ),
            '-',
          ]),
          'type': _or([
            _clean(
              r.containsKey('CustomerType')
                  ? r['CustomerType']
                  : r['CustomerTypeName'] ?? '',
            ),
            '-',
          ]),
          'status': _or([status, '-']),
          'beneficiary': _ben(r),
          'product': _product(r),
        });
      }
      return {
        'success': true,
        'records': formatted,
        'total_records': formatted.length,
        'legacy': isLegacy,
        'pages_fetched': pages,
      };
    } catch (e) {
      return {
        'success': false,
        'message': e.toString(),
        'records': [],
        'total_records': 0,
        'legacy': isLegacy,
      };
    }
  }

  Future<MdmMap> monthlySummary(
    RajsimsHttpContext? c,
    int year,
    int month,
  ) async {
    final started = clock();
    String keyOf(Object? name) {
      final k = mdmProductName(name);
      return k.startsWith('wheat')
          ? 'wheat'
          : k.startsWith('rice')
          ? 'rice'
          : k;
    }

    _MdmDecimal number(Object? v, String field) {
      try {
        return _MdmDecimal.parse(_str(v));
      } catch (_) {
        throw FormatException('Invalid $field in monthly report.');
      }
    }

    _MdmDecimal nonNegative(Object? v, String field) {
      final n = number(v, field);
      if (n < _MdmDecimal.zero)
        throw FormatException('Negative $field in monthly report.');
      return n;
    }

    int integer(Object? v, String field) {
      final n = nonNegative(v, field);
      if (!n.isInteger)
        throw FormatException('Non-integer $field in monthly report.');
      return n.toInt();
    }

    _MdmDecimal? rateFor(Object? name) {
      final raw = _str(_or([name, '']))
              .trim()
              .toLowerCase()
              .replaceAll('_', ' ')
              .replaceAll('-', ' ')
              .split(RegExp(r'\s+'))
              .join(' '),
          compact = raw.replaceAll(' ', '');
      if (raw.isEmpty) return null;
      if ([
        '1to8',
        '1stto8',
        'preprimaryto8',
        'primaryandupperprimary',
        'primaryupperprimary',
        'primary&upperprimary',
      ].any(compact.contains))
        throw const FormatException(
          'Primary + Upper Primary mixed beneficiary group cannot be derived from combined food-grain quantity.',
        );
      if (raw.contains('upper primary') ||
          compact.contains('upperprimary') ||
          raw.contains('6 to 8') ||
          compact.contains('6to8') ||
          raw.contains('class 6') ||
          raw.contains('vi to viii'))
        return _MdmDecimal.parse('0.150');
      if (raw.contains('primary') ||
          raw.contains('bal vatika') ||
          compact.contains('balvatika') ||
          raw.contains('pre primary to 5') ||
          compact.contains('preprimaryto5') ||
          raw.contains('1 to 5') ||
          compact.contains('1to5'))
        return _MdmDecimal.parse('0.100');
      return null;
    }

    Future<List<MdmMap>> read(MdmMap ctx, String key, MdmMap params) async {
      final r = await post(c, {
        'ApiKey': key,
        'OrgId': ctx['org_id'],
        'ApiParams': params,
      }, safeToRetry: true);
      if (!r.success)
        throw FormatException(
          r.message.isEmpty ? '$key failed (${r.status}).' : r.message,
        );
      final rows = r.data is Map ? (r.data as Map)['CustomObject'] : null;
      if (rows is! List || rows.any((v) => v is! Map))
        throw FormatException('$key returned an invalid record list.');
      return rows.map(_map).toList();
    }

    try {
      if (month < 1 || month > 12)
        throw const FormatException('Invalid report month.');
      final (ctx, error) = await resolveLightContext(c, needOffice: true);
      if (ctx == null)
        return {'success': false, 'complete': false, 'message': error};
      final startYear = month >= 4 ? year : year - 1,
          finYear = startYear * 10000 + startYear + 1,
          base = <String, dynamic>{
            'OrgId': ctx['org_id'],
            'OfficeId': ctx['office_id'],
            'SchemeId': ctx['scheme_id'],
            'ProductGroup': 110,
            'FinYear': finYear,
          },
          masterStarted = clock();
      final products =
          (await read(ctx, 'GetSummaryReport', {
                ...base,
                'ProductId': 0,
                'OfficeTypeId': ctx['office_type_id'],
                'FromDate': null,
                'ToDate': null,
              }))
              .where((r) => {'wheat', 'rice'}.contains(keyOf(r['ProductName'])))
              .toList();
      if (products.isEmpty)
        throw const FormatException(
          'Wheat/Rice food-grain mapping is unavailable.',
        );
      final productMap = <String, MdmMap>{};
      for (final p in products) {
        final key = keyOf(p['ProductName']),
            pid = integer(p['ProductId'], '$key ProductId'),
            pack = integer(p['PackingId'], '$key PackingId'),
            title = key[0].toUpperCase() + key.substring(1);
        if (pid == 0 || pack == 0)
          throw FormatException(
            '$title product/packing mapping is incomplete.',
          );
        if (productMap.containsKey(key))
          throw FormatException(
            'Duplicate $key product mapping returned by RajSIMS.',
          );
        productMap[key] = {'record': p, 'product_id': pid, 'packing_id': pack};
      }
      if (productMap.length != 2 ||
          !productMap.containsKey('wheat') ||
          !productMap.containsKey('rice'))
        throw const FormatException(
          'Both Wheat and Rice mappings are required.',
        );
      final masterMs = _halfEven((clock() - masterStarted) * 1000),
          reportsStarted = clock();
      final reports = await Future.wait(
        productMap.entries.map((e) async {
          final params = {
            ...base,
            'ProductId': e.value['product_id'],
            'PackingId': e.value['packing_id'],
          };
          final rows = await Future.wait([
            read(ctx, 'GetStockSummaryReportMonthWise', params),
            read(ctx, 'GetStockSummaryReportMonthly', {
              ...params,
              'Month': month,
            }),
          ]);
          return (e.key, e.value, rows[0], rows[1]);
        }),
      );
      final reportsMs = _halfEven((clock() - reportsStarted) * 1000),
          stocks = <MdmMap>[],
          daily = <String, Map<String, _MdmDecimal>>{};
      for (final (key, meta, monthRows, ledger) in reports) {
        final p = _map(meta['record']),
            pid = meta['product_id'],
            pack = meta['packing_id'],
            title = key[0].toUpperCase() + key.substring(1),
            byMonth = <int, MdmMap>{};
        for (final r in monthRows) {
          if (integer(r['ProductId'], 'monthly stock ProductId') != pid)
            throw FormatException('$title monthly stock product mismatch.');
          final m = integer(r['MonthId'], 'MonthId');
          if (m < 1 || m > 12)
            throw const FormatException(
              'Monthly stock contains an invalid month.',
            );
          if (byMonth.containsKey(m))
            throw FormatException('Duplicate $key stock row for month $m.');
          byMonth[m] = r;
        }
        var opening = nonNegative(
          p['OpeningBalance'],
          '$key financial-year opening balance',
        );
        MdmMap? selected;
        for (final m in [4, 5, 6, 7, 8, 9, 10, 11, 12, 1, 2, 3]) {
          final r = byMonth[m],
              inward = r == null
                  ? _MdmDecimal.zero
                  : nonNegative(r['InWardQty'], '$key inward quantity'),
              outward = r == null
                  ? _MdmDecimal.zero
                  : nonNegative(r['OutWardQty'], '$key outward quantity'),
              closing = opening + inward - outward;
          if (closing < _MdmDecimal.zero)
            throw FormatException(
              '$title stock reconciliation produced a negative balance.',
            );
          if (m == month) {
            if (r == null)
              throw FormatException(
                '$title selected month is missing from stock summary.',
              );
            selected = {
              'product_id': pid,
              'product_name': p['ProductName'],
              'packing_id': pack,
              'unit': _or([p['UnitOfMesurement'], r['UnitOfMesurement']]),
              'opening': opening.toDouble(),
              'received': inward.toDouble(),
              'outward': outward.toDouble(),
              'closing': closing.toDouble(),
            };
            break;
          }
          opening = closing;
        }
        if (selected == null)
          throw FormatException(
            '$title selected-month stock could not be resolved.',
          );
        stocks.add(selected);
        final seen = <String>{};
        for (final r in ledger) {
          if (integer(r['ProductId'], 'ledger ProductId') != pid)
            throw FormatException('$title daily ledger product mismatch.');
          final date = mdmParseDate(r['REFDATE']);
          if (date == null)
            throw FormatException('$title ledger contains an invalid REFDATE.');
          if (date.year != year || date.month != month)
            throw FormatException(
              '$title ledger returned a date outside the selected month.',
            );
          final dateKey =
              '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          if (!seen.add(dateKey))
            throw FormatException('Duplicate $key ledger row on $dateKey.');
          final outward = nonNegative(
                r['OutWardQty'],
                '$key daily outward quantity',
              ),
              bucket = daily.putIfAbsent(
                dateKey,
                () => {'wheat': _MdmDecimal.zero, 'rice': _MdmDecimal.zero},
              );
          bucket[key] = bucket[key]! + outward;
        }
        final total = daily.values.fold(
              _MdmDecimal.zero,
              (sum, v) => sum + v[key]!,
            ),
            out = number(selected['outward'], 'outward');
        if ((total - out).abs() > _MdmDecimal.parse('0.0001'))
          throw FormatException(
            '$title daily ledger total ($total) does not match monthly outward ($out).',
          );
      }
      var group = _int(ctx['group_id']),
          groupName = _clean(ctx['group_name']),
          rate = rateFor(groupName);
      if (rate == null || group == 0) {
        final (full, err) = await resolveContext(c);
        if (full != null) {
          group = _int(full['group_id']) != 0 ? _int(full['group_id']) : group;
          groupName = _clean(full['group_name']).isNotEmpty
              ? _clean(full['group_name'])
              : groupName;
          final rates = <_MdmDecimal>{};
          for (final k in ['wheat', 'rice']) {
            final p = _findProduct(full, k);
            if (p == null) continue;
            final qty = _float(p['quantity']);
            if (qty > 0) rates.add(_MdmDecimal.parse(qty.toString()));
          }
          if (rates.length == 1) {
            rate = rates.first;
          } else if (rates.length > 1) {
            throw const FormatException(
              'RajSIMS returned different per-student food-grain rates for Wheat and Rice.',
            );
          }
          rate ??= rateFor(groupName);
        } else if (err != null && rate == null) {
          throw FormatException(err);
        }
      }
      if (rate == null)
        throw const FormatException(
          'Beneficiary group could not be mapped safely to Primary (100 g) or Upper Primary (150 g).',
        );
      if (rate != _MdmDecimal.parse('0.100') &&
          rate != _MdmDecimal.parse('0.150'))
        throw FormatException(
          'Unsupported RajSIMS food-grain rate $rate kg per beneficiary.',
        );
      final sorted = daily.keys.toList()..sort(), dailyResults = <MdmMap>[];
      var totalMeals = 0, served = 0, grainTotal = _MdmDecimal.zero;
      for (final date in sorted) {
        final grain = daily[date]!,
            w = grain['wheat']!,
            r = grain['rice']!,
            total = w + r;
        grainTotal = grainTotal + total;
        final meals = total > _MdmDecimal.zero
                ? total / rate
                : _MdmDecimal.zero,
            rounded = meals.halfUp();
        if ((meals - _MdmDecimal.fromInt(rounded)).abs() >
            _MdmDecimal.parse('0.000001'))
          throw FormatException(
            'Food-grain quantity on $date ($total kg) does not map exactly to $rate kg per beneficiary.',
          );
        if (rounded > 0) served++;
        totalMeals += rounded;
        dailyResults.add({
          'transaction_id': null,
          'date': date,
          'groups': [
            {
              'group_id': group,
              'group_name': groupName.isEmpty ? null : groupName,
              'meals': rounded,
            },
          ],
          'grain': {
            'wheat': w.toDouble(),
            'rice': r.toDouble(),
            'total': total.toDouble(),
          },
        });
      }
      final stockTotal = stocks.fold(
        _MdmDecimal.zero,
        (sum, v) => sum + number(v['outward'], 'outward'),
      );
      if ((stockTotal - grainTotal).abs() > _MdmDecimal.parse('0.0001'))
        throw const FormatException(
          'Combined Wheat/Rice daily ledger does not match monthly stock outward total.',
        );
      final expected = grainTotal > _MdmDecimal.zero
          ? grainTotal / rate
          : _MdmDecimal.zero;
      if ((expected - _MdmDecimal.fromInt(totalMeals)).abs() >
          _MdmDecimal.parse('0.000001'))
        throw const FormatException(
          'Calculated beneficiary total does not reconcile with food-grain consumption.',
        );
      return {
        'success': true,
        'complete': true,
        'year': year,
        'month': month,
        'financial_year': finYear,
        'office_id': ctx['office_id'],
        'stock': stocks,
        'distribution_entries': sorted.length,
        'approved_entries': sorted.length,
        'excluded_unapproved_entries': 0,
        'total_meals': totalMeals,
        'served_days': served,
        'groups': [
          {
            'group_id': group,
            'group_name': groupName.isEmpty ? null : groupName,
            'total_meals': totalMeals,
            'served_days': served,
          },
        ],
        'daily': dailyResults,
        'food_grain': {
          'wheat_kg': daily.values
              .fold(_MdmDecimal.zero, (s, v) => s + v['wheat']!)
              .toDouble(),
          'rice_kg': daily.values
              .fold(_MdmDecimal.zero, (s, v) => s + v['rice']!)
              .toDouble(),
          'total_kg': grainTotal.toDouble(),
          'kg_per_beneficiary': rate.toDouble(),
        },
        'source': 'stock_summary_monthly_ledger',
        'timings': {
          'master_ms': masterMs,
          'stock_and_ledger_ms': reportsMs,
          'total_ms': _halfEven((clock() - started) * 1000),
        },
      };
    } catch (e) {
      return {
        'success': false,
        'complete': false,
        'message': e is FormatException ? e.message : e.toString(),
        'code': 'MONTHLY_REPORT_INCOMPLETE',
      };
    }
  }

  Future<MdmMap> mprProfile(RajsimsHttpContext? c) async {
    final epoch = _generation;
    if (!_usable(c))
      return {
        'success': false,
        'code': 'SESSION_CHANGED',
        'message': 'RajSIMS session changed. Fetch again.',
      };
    final (name, mobile) = await extractUserInfo(c);
    if (epoch != _generation || !_usable(c))
      return {
        'success': false,
        'code': 'SESSION_CHANGED',
        'message': 'RajSIMS session changed. Fetch again.',
      };
    var n = _str(_or([name, ''])).trim();
    if ({'MDM Incharge', 'School Incharge'}.contains(n)) n = '';
    final digits = _digits(_or([mobile, ''])),
        valid = digits.length == 10 ? digits : null,
        available = n.isNotEmpty && valid != null;
    return {
      'success': true,
      'complete': available,
      'profile_available': available,
      'incharge_name': n.isEmpty ? null : n,
      'incharge_mobile': valid,
      'office_id': _or([_user['profile_office_id'], _user['office_id']]),
      'source': 'authenticated_user_profile',
      'editable': true,
    };
  }
}

/// Exact base-ten quantities preserve Python Decimal reconciliation tolerances.
/// Division retains rational values so beneficiary integrality is never guessed.
class _MdmDecimal implements Comparable<_MdmDecimal> {
  _MdmDecimal(BigInt n, BigInt d) : n = n ~/ n.gcd(d), d = d ~/ n.gcd(d);
  final BigInt n, d;
  static final zero = _MdmDecimal(BigInt.zero, BigInt.one);
  factory _MdmDecimal.fromInt(int v) => _MdmDecimal(BigInt.from(v), BigInt.one);
  factory _MdmDecimal.parse(String text) {
    final s = text.trim(),
        m = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$')
            .firstMatch(s);
    if (m == null || (m[2] ?? '').isEmpty && (m[3] ?? '').isEmpty)
      throw const FormatException('Invalid decimal');
    final digits = '${m[2] ?? ''}${m[3] ?? ''}',
        exponent = int.parse(m[4] ?? '0') - (m[3]?.length ?? 0);
    if (exponent.abs() > 10000)
      throw const FormatException(
        'Decimal exponent outside supported report range',
      );
    var n = BigInt.parse(digits);
    if (m[1] == '-') n = -n;
    return exponent >= 0
        ? _MdmDecimal(n * BigInt.from(10).pow(exponent), BigInt.one)
        : _MdmDecimal(n, BigInt.from(10).pow(-exponent));
  }
  _MdmDecimal operator +(_MdmDecimal o) =>
      _MdmDecimal(n * o.d + o.n * d, d * o.d);
  _MdmDecimal operator -(_MdmDecimal o) =>
      _MdmDecimal(n * o.d - o.n * d, d * o.d);
  _MdmDecimal operator /(_MdmDecimal o) {
    if (o.n == BigInt.zero) throw const FormatException('Division by zero');
    return _MdmDecimal(n * o.d, d * o.n);
  }

  _MdmDecimal abs() => _MdmDecimal(n.abs(), d.abs());
  bool get isInteger => n % d == BigInt.zero;
  int toInt() => (n ~/ d).toInt();
  double toDouble() => n.toDouble() / d.toDouble();
  int halfUp() {
    final q = n.abs() ~/ d, rest = n.abs() % d;
    final rounded = rest * BigInt.two >= d ? q + BigInt.one : q;
    return (n.isNegative ? -rounded : rounded).toInt();
  }

  @override
  int compareTo(_MdmDecimal o) => (n * o.d).compareTo(o.n * d);
  bool operator <(_MdmDecimal o) => compareTo(o) < 0;
  bool operator >(_MdmDecimal o) => compareTo(o) > 0;
  @override
  bool operator ==(Object o) => o is _MdmDecimal && compareTo(o) == 0;
  @override
  int get hashCode => Object.hash(n, d);
  @override
  String toString() {
    if (d == BigInt.one) return n.toString();
    var div = d, twos = 0, fives = 0;
    while (div % BigInt.two == BigInt.zero) {
      div ~/= BigInt.two;
      twos++;
    }
    while (div % BigInt.from(5) == BigInt.zero) {
      div ~/= BigInt.from(5);
      fives++;
    }
    if (div != BigInt.one) return toDouble().toString();
    final places = math.max(twos, fives),
        scale = BigInt.from(10).pow(places),
        v = (n.abs() * scale ~/ d).toString().padLeft(places + 1, '0'),
        head = v.substring(0, v.length - places),
        tail = v.substring(v.length - places).replaceFirst(RegExp(r'0+$'), '');
    return '${n.isNegative ? '-' : ''}$head${tail.isEmpty ? '' : '.$tail'}';
  }
}
