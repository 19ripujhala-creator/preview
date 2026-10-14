/// Session/profile and public login contract from RajSIMS auth_manager.py.
/// The HTTPX SSO implementation is supplied separately, as in the Python installer.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/direct/coordinator.dart' show Probe;
import 'http_context.dart';

typedef RajsimsLoginImplementation = Future<Map<String, dynamic>> Function(
  String username,
  String password,
  bool forceFresh,
);

bool _truth(Object? value) {
  if (value == null || value == false || value == '' || value == 0)
    return false;
  if (value is Map) return value.isNotEmpty;
  if (value is Iterable) return value.isNotEmpty;
  return true;
}

int? _toInt(Object? value) {
  if (value == null || value is bool) return null;
  final number = double.tryParse(value.toString().trim());
  if (number == null ||
      !number.isFinite ||
      number != number.truncateToDouble()) {
    return null;
  }
  return number.toInt();
}

Map<dynamic, dynamic> _asDict(Object? value) {
  if (value is String) {
    try {
      value = jsonDecode(value);
    } catch (_) {
      return {};
    }
  }
  return value is Map ? value : {};
}

Iterable<Map<dynamic, dynamic>> _profileBlocks(
  Object? data, [
  int depth = 0,
]) sync* {
  if (depth > 8) return;
  if (data is String) {
    try {
      data = jsonDecode(data);
    } catch (_) {
      return;
    }
  }
  if (data is Map) {
    yield data;
    for (final value in data.values) {
      yield* _profileBlocks(value, depth + 1);
    }
  } else if (data is List) {
    for (final value in data) {
      yield* _profileBlocks(value, depth + 1);
    }
  }
}

/// Original OCR normalization: reject unknown characters, extra characters and
/// whitespace instead of extracting six digits from a longer OCR result.
String extractSixDigits(String? rawOutput) {
  if (rawOutput == null || rawOutput.isEmpty) return '';
  var cleaned = rawOutput.toUpperCase();
  const replacements = {
    'O': '0',
    'Q': '0',
    'D': '0',
    'I': '1',
    'L': '1',
    'J': '1',
    'Z': '2',
    'S': '5',
    'G': '6',
    'T': '7',
    'B': '8',
  };
  for (final entry in replacements.entries) {
    cleaned = cleaned.replaceAll(entry.key, entry.value);
  }
  return RegExp(r'^[0-9]{6}$').hasMatch(cleaned) && cleaned.length == 6
      ? cleaned
      : '';
}

String rajsimsMobileDigits(String value) => _mobileDigits(value);

// Python str.isdigit/int Unicode behavior for profile mobile numbers.
String _mobileDigits(String value) {
  const digitRanges = <(int, int)>[
    (0x30, 0x39),
    (0xb2, 0xb3),
    (0xb9, 0xb9),
    (0x660, 0x669),
    (0x6f0, 0x6f9),
    (0x7c0, 0x7c9),
    (0x966, 0x96f),
    (0x9e6, 0x9ef),
    (0xa66, 0xa6f),
    (0xae6, 0xaef),
    (0xb66, 0xb6f),
    (0xbe6, 0xbef),
    (0xc66, 0xc6f),
    (0xce6, 0xcef),
    (0xd66, 0xd6f),
    (0xde6, 0xdef),
    (0xe50, 0xe59),
    (0xed0, 0xed9),
    (0xf20, 0xf29),
    (0x1040, 0x1049),
    (0x1090, 0x1099),
    (0x1369, 0x1371),
    (0x17e0, 0x17e9),
    (0x1810, 0x1819),
    (0x1946, 0x194f),
    (0x19d0, 0x19da),
    (0x1a80, 0x1a89),
    (0x1a90, 0x1a99),
    (0x1b50, 0x1b59),
    (0x1bb0, 0x1bb9),
    (0x1c40, 0x1c49),
    (0x1c50, 0x1c59),
    (0x2070, 0x2070),
    (0x2074, 0x2079),
    (0x2080, 0x2089),
    (0x2460, 0x2468),
    (0x2474, 0x247c),
    (0x2488, 0x2490),
    (0x24ea, 0x24ea),
    (0x24f5, 0x24fd),
    (0x24ff, 0x24ff),
    (0x2776, 0x277e),
    (0x2780, 0x2788),
    (0x278a, 0x2792),
    (0xa620, 0xa629),
    (0xa8d0, 0xa8d9),
    (0xa900, 0xa909),
    (0xa9d0, 0xa9d9),
    (0xa9f0, 0xa9f9),
    (0xaa50, 0xaa59),
    (0xabf0, 0xabf9),
    (0xff10, 0xff19),
    (0x104a0, 0x104a9),
    (0x10a40, 0x10a43),
    (0x10d30, 0x10d39),
    (0x10e60, 0x10e68),
    (0x11052, 0x1105a),
    (0x11066, 0x1106f),
    (0x110f0, 0x110f9),
    (0x11136, 0x1113f),
    (0x111d0, 0x111d9),
    (0x112f0, 0x112f9),
    (0x11450, 0x11459),
    (0x114d0, 0x114d9),
    (0x11650, 0x11659),
    (0x116c0, 0x116c9),
    (0x11730, 0x11739),
    (0x118e0, 0x118e9),
    (0x11950, 0x11959),
    (0x11c50, 0x11c59),
    (0x11d50, 0x11d59),
    (0x11da0, 0x11da9),
    (0x11f50, 0x11f59),
    (0x16a60, 0x16a69),
    (0x16ac0, 0x16ac9),
    (0x16b50, 0x16b59),
    (0x1d7ce, 0x1d7ff),
    (0x1e140, 0x1e149),
    (0x1e2f0, 0x1e2f9),
    (0x1e4f0, 0x1e4f9),
    (0x1e950, 0x1e959),
    (0x1f100, 0x1f10a),
    (0x1fbf0, 0x1fbf9),
  ];
  const decimalZeros = <int>[
    0x30,
    0x660,
    0x6f0,
    0x7c0,
    0x966,
    0x9e6,
    0xa66,
    0xae6,
    0xb66,
    0xbe6,
    0xc66,
    0xce6,
    0xd66,
    0xde6,
    0xe50,
    0xed0,
    0xf20,
    0x1040,
    0x1090,
    0x17e0,
    0x1810,
    0x1946,
    0x19d0,
    0x1a80,
    0x1a90,
    0x1b50,
    0x1bb0,
    0x1c40,
    0x1c50,
    0xa620,
    0xa8d0,
    0xa900,
    0xa9d0,
    0xa9f0,
    0xaa50,
    0xabf0,
    0xff10,
    0x104a0,
    0x10d30,
    0x11066,
    0x110f0,
    0x11136,
    0x111d0,
    0x112f0,
    0x11450,
    0x114d0,
    0x11650,
    0x116c0,
    0x11730,
    0x118e0,
    0x11950,
    0x11c50,
    0x11d50,
    0x11da0,
    0x11f50,
    0x16a60,
    0x16ac0,
    0x16b50,
    0x1d7ce,
    0x1d7d8,
    0x1d7e2,
    0x1d7ec,
    0x1d7f6,
    0x1e140,
    0x1e2f0,
    0x1e4f0,
    0x1e950,
    0x1fbf0,
  ];
  final digits = <int>[
    for (final cp in value.runes)
      if (digitRanges.any((range) => cp >= range.$1 && cp <= range.$2)) cp,
  ];
  if (digits.length != 10) return '';
  final result = StringBuffer();
  for (final cp in digits) {
    final zero = decimalZeros.where((zero) => cp >= zero && cp <= zero + 9);
    if (zero.isEmpty) throw const FormatException('Invalid integer digits');
    result.write(cp - zero.first);
  }
  return result.toString();
}

class RajsimsAuthManager {
  RajsimsAuthManager({
    required this.currentContext,
    required this.loginImplementation,
    required this.bodyStatusCode,
    required this.persistState,
    required this.persistUsername,
    required this.clearUserInfoCache,
  });

  final RajsimsHttpContext? Function() currentContext;
  final RajsimsLoginImplementation loginImplementation;
  final int? Function(Object? data) bodyStatusCode;
  final Future<void> Function(RajsimsHttpContext context) persistState;
  final Future<void> Function(String username) persistUsername;
  final void Function() clearUserInfoCache;
  RajsimsHttpContext? _authContext;
  String? _id, _key;
  final Map<String, dynamic> _user = {
    'name': null,
    'mobile': null,
    'office_name': null,
    'office_id': null,
    'org_id': null,
    'scheme_id': null,
    'office_type_id': null,
    'group_id': null,
    'group_name': null,
  };
  Future<void> _loginTail = Future.value();

  bool _owns(RajsimsHttpContext? context) =>
      context != null &&
      identical(context, _authContext) &&
      identical(context, currentContext());

  /// Called at the same binding point as install_httpx_signin, after successful
  /// official bootstrap. Profile verification must follow before login success.
  void bindContext(
    RajsimsHttpContext context,
    String authId,
    String authKey, {
    bool preserveTokenValues = false,
  }) {
    _authContext = context;
    // Browser request interception cleans headers; the HTTPX installer assigns
    // the verified URL token strings verbatim. Keep both source binding points.
    _id = preserveTokenValues ? authId : _cleanAuth(authId);
    _key = preserveTokenValues ? authKey : _cleanAuth(authKey);
  }

  static String? _cleanAuth(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  (String?, String?) getAuth([RajsimsHttpContext? context]) {
    context ??= currentContext();
    return _owns(context) ? (_id, _key) : (null, null);
  }

  Map<String, dynamic> getUserInfo([RajsimsHttpContext? context]) {
    context ??= currentContext();
    return _owns(context) ? Map.of(_user) : {};
  }

  void clearAuth() {
    _authContext = null;
    _id = null;
    _key = null;
    for (final key in _user.keys) {
      _user[key] = null;
    }
    // Source cache-clearing failure is non-fatal.
    try {
      clearUserInfoCache();
    } catch (_) {}
  }

  /// Office and organization must occur together in one identity block. All
  /// discovered identity pairs must agree, including nested JSON wrappers.
  bool mergeProfile(Object? data, RajsimsHttpContext context) {
    if (!_owns(context)) return false;
    final blocks = _profileBlocks(data).toList();
    final identities = <(int, int, Map<String, dynamic>)>[];
    for (final block in blocks) {
      final fields = {
        for (final entry in block.entries)
          entry.key.toString().toLowerCase(): entry.value,
      };
      final office = _toInt(fields['officeid']), org = _toInt(fields['orgid']);
      if (office != null && office > 0 && org != null && org > 0) {
        identities.add((office, org, fields));
      }
    }
    if (identities.map((item) => (item.$1, item.$2)).toSet().length != 1) {
      return false;
    }
    final (office, org, fields) = identities.first;
    if (_truth(_user['office_id']) &&
        _truth(_user['org_id']) &&
        (_user['office_id'] != office || _user['org_id'] != org))
      return false;
    var personal = _asDict(fields['personaldetails']);
    if (personal.isEmpty) {
      search:
      for (final block in blocks) {
        for (final entry in block.entries) {
          if (entry.key.toString().toLowerCase() == 'personaldetails') {
            final candidate = _asDict(entry.value);
            if (candidate.isNotEmpty) {
              personal = candidate;
              break search;
            }
          }
        }
      }
    }
    final normalized = {
      for (final entry in personal.entries)
        entry.key.toString().toLowerCase(): entry.value,
    };
    // This synchronous commit has no await, equivalent to the source auth lock.
    if (!_owns(context)) return false;
    _user.addAll({'office_id': office, 'org_id': org});
    for (final pair in const [
      ('office_type_id', 'officetypeid'),
      ('scheme_id', 'schemeid'),
      ('group_id', 'groupid'),
    ]) {
      final value = _toInt(fields[pair.$2]);
      if (value != null && value > 0) _user[pair.$1] = value;
    }
    Object? first(List<Object?> values) {
      for (final value in values) {
        if (_truth(value)) return value;
      }
      return null;
    }

    final names = {
      'name': first([
        normalized['name'],
        normalized['fullname'],
        fields['fullname'],
      ]),
      'office_name': fields['officename'],
      'group_name': fields['groupname'],
    };
    for (final entry in names.entries) {
      if (_truth(entry.value)) _user[entry.key] = entry.value.toString().trim();
    }
    final mobileRaw = first([
      normalized['mobilenumber'],
      normalized['mobileno'],
      normalized['mobile'],
      fields['mobilenumber'],
      fields['mobileno'],
      fields['mobile'],
    ]);
    final mobile = _mobileDigits((mobileRaw ?? '').toString());
    if (mobile.length == 10) _user['mobile'] = int.parse(mobile);
    return true;
  }

  /// HTTP 403 remains unknown; only HTTP/body 401 proves session expiry.
  Future<Probe> probe(RajsimsHttpContext context) async {
    final (id, key) = getAuth(context);
    if (id == null || key == null) return Probe.unknown;
    try {
      final response = await context.request.post(
        rajsimsGateway,
        headers: {
          'Accept': '*/*',
          'Content-Type': 'application/json',
          'Authid': id,
          'Authkey': key,
        },
        data: jsonEncode({
          'ApiKey': 'ValidateTokenAndGetUserDetail',
          'ApiParams': {'AuthId': id, 'AuthKey': key},
          'OrgId': 0,
        }),
        timeout: 8000,
        maxRedirects: 0,
      );
      Object? data;
      try {
        data = jsonDecode(response.text);
      } catch (_) {}
      final status = bodyStatusCode(data);
      if (response.statusCode == 401 || status == 401) return Probe.dead;
      if (response.statusCode != 200 ||
          status == 403 ||
          status == 429 ||
          (status != null && status >= 400))
        return Probe.unknown;
      if (data is! Map || data['IsSuccess'] == false) return Probe.unknown;
      return mergeProfile(data, context) ? Probe.alive : Probe.unknown;
    } catch (_) {
      return Probe.unknown;
    }
  }

  /// Preserve the source public login lock and save state/account only on success.
  /// No retry is introduced by this wrapper.
  Future<Map<String, dynamic>> executeLogin(
    String username,
    String password, {
    bool forceFresh = false,
  }) async {
    if (username.trim().isEmpty || password.isEmpty) {
      return {
        'success': false,
        'code': 'NO_CREDENTIALS',
        'message': 'SSO credentials are required.',
      };
    }
    final previous = _loginTail;
    final release = Completer<void>();
    _loginTail = release.future;
    await previous;
    try {
      final result = await loginImplementation(username, password, forceFresh);
      if (identical(result['success'], true)) {
        final context = currentContext();
        if (_owns(context)) {
          try {
            await persistState(context!);
          } catch (_) {}
          try {
            await persistUsername(username.trim());
          } on FileSystemException {
            // Equivalent to source OSError; successful login remains successful.
          }
        }
      }
      return result;
    } finally {
      release.complete();
    }
  }
}
