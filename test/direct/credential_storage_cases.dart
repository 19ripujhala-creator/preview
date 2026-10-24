import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/services/core/secure_storage_service.dart';

void _check(bool value, String description) {
  if (!value) throw StateError(description);
}

Map<String, String> _record(String account) => {
  'shala_id': '$account-school',
  'shala_pass': '$account-school-pass',
  'staff_id': '$account-staff',
  'staff_pass': '$account-staff-pass',
  'rajsims_id': '$account-sso',
  'rajsims_pass': '$account-sso-pass',
};
Map<String, String> _expected(String account) => {
  'school_id': '$account-school',
  'school_password': '$account-school-pass',
  'staff_id': '$account-staff',
  'staff_password': '$account-staff-pass',
  'sso_id': '$account-sso',
  'sso_password': '$account-sso-pass',
};
Future<void> _save(String account) => SecureStorageService.saveAllPortals(
  shalaId: '$account-school',
  shalaPass: '$account-school-pass',
  staffId: '$account-staff',
  staffPass: '$account-staff-pass',
  rajsimsId: '$account-sso',
  rajsimsPass: '$account-sso-pass',
);
bool _same(Map actual, Map expected) =>
    actual.length == expected.length &&
    expected.entries.every((entry) => actual[entry.key] == entry.value);

class _MemoryStorage {
  _MemoryStorage({String? account}) {
    if (account != null) {
      values.addAll(_record(account));
      values['portal_credentials_v2'] = jsonEncode(_record(account));
      values['is_app_configured'] = 'true';
    }
  }
  final values = <String, String>{};
  final calls = <(String, String)>[];
  (String, String)? pause, fail;
  final entered = Completer<void>(), release = Completer<void>();
  Future<void> _after(String method, String key) async {
    if (pause == (method, key) && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
  }

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments as Map;
    final key = args['key'] as String;
    calls.add((call.method, key));
    if (fail == (call.method, key)) {
      fail = null;
      throw PlatformException(code: 'offline-storage-failure');
    }
    if (call.method == 'read') {
      final captured = values[key];
      await _after(call.method, key);
      return captured;
    }
    if (call.method == 'write') {
      values[key] = args['value'] as String;
    } else if (call.method == 'delete') {
      values.remove(key);
    } else {
      throw StateError('Unexpected storage call ${call.method}');
    }
    await _after(call.method, key);
    return null;
  }
}

Future<void> _withStorage(
  Future<void> Function(_MemoryStorage) body, {
  String? account = 'A',
  Map<String, Object> preferences = const {},
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(preferences);
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final memory = _MemoryStorage(account: account);
  messenger.setMockMethodCallHandler(channel, memory.handle);
  try {
    await body(memory);
  } finally {
    if (!memory.release.isCompleted) memory.release.complete();
    messenger.setMockMethodCallHandler(channel, null);
  }
}

Map<String, Future<void> Function()> credentialStorageCases() => {
  'one getAll snapshot cannot mix old School with new Staff and SSO': () =>
      _withStorage((m) async {
        m.pause = ('read', 'portal_credentials_v2');
        final reading = SecureStorageService.getAllPortalCreds();
        await m.entered.future;
        final saving = _save('B');
        await Future<void>.delayed(Duration.zero);
        m.release.complete();
        final snapshot = await reading;
        await saving;
        _check(
          _same(snapshot, _expected('A')),
          'Credential snapshot mixed accounts',
        );
        _check(
          _same(await SecureStorageService.getAllPortalCreds(), _expected('B')),
          'Next snapshot did not see the committed account',
        );
      }),
  for (final portal in ['School', 'Staff', 'SSO'])
    '$portal read waits for the preceding account save': () =>
        _withStorage((m) async {
          m.pause = ('write', 'is_app_configured');
          final saving = _save('B');
          await m.entered.future;
          final reading = portal == 'School'
              ? SecureStorageService.getShaladarpanCreds()
              : portal == 'Staff'
              ? SecureStorageService.getStaffCreds()
              : SecureStorageService.getRajSimsCreds();
          await Future<void>.delayed(Duration.zero);
          m.release.complete();
          await saving;
          final result = await reading;
          final suffix = portal == 'School'
              ? 'school'
              : portal == 'Staff'
              ? 'staff'
              : 'sso';
          _check(
            result['id'] == 'B-$suffix' && result['pass'] == 'B-$suffix-pass',
            '$portal read overtook a preceding credential save',
          );
        }),
  'overlapping saves commit in invocation order with consistent metadata': () =>
      _withStorage((m) async {
        m.pause = ('write', 'is_app_configured');
        final first = _save('B');
        await m.entered.future;
        final second = _save('C');
        await Future<void>.delayed(Duration.zero);
        m.release.complete();
        await Future.wait([first, second]);
        _check(
          _same(await SecureStorageService.getAllPortalCreds(), _expected('C')),
          'An older slow save overwrote the newer account',
        );
        final prefs = await SharedPreferences.getInstance();
        _check(
          prefs.getString('saved_staff_id') == 'C-staff' &&
              prefs.getString('school_id') == 'C-school',
          'Account metadata disagrees with saved credentials',
        );
        _check(
          _record('C').entries.every((e) => m.values[e.key] == e.value),
          'Individual secure keys disagree with committed record',
        );
      }),
  'clearAll called after an in-flight save remains cleared': () =>
      _withStorage((m) async {
        m.pause = ('write', 'is_app_configured');
        final saving = _save('B');
        await m.entered.future;
        final clearing = SecureStorageService.clearAll();
        await Future<void>.delayed(Duration.zero);
        m.release.complete();
        await Future.wait([saving, clearing]);
        final result = await SecureStorageService.getAllPortalCreds();
        _check(
          result.values.every((value) => value.isEmpty),
          'An older save restored credentials after clearAll',
        );
        _check(
          m.values.isEmpty,
          'Secure credential keys were restored after clearAll',
        );
      }),
  'reader during clearAll cannot restore a half-deleted legacy record': () =>
      _withStorage((m) async {
        m.pause = ('delete', 'portal_credentials_v2');
        final clearing = SecureStorageService.clearAll();
        await m.entered.future;
        final reading = SecureStorageService.getAllPortalCreds();
        await Future<void>.delayed(Duration.zero);
        m.release.complete();
        await clearing;
        _check(
          (await reading).values.every((value) => value.isEmpty),
          'Reader observed a half-cleared account',
        );
      }),
  'storage write failure propagates and releases the operation queue': () =>
      _withStorage((m) async {
        m.fail = ('write', 'staff_pass');
        var failed = false;
        try {
          await _save('B');
        } on PlatformException {
          failed = true;
        }
        _check(failed, 'Storage failure was swallowed');
        await _save('C');
        _check(
          _same(await SecureStorageService.getAllPortalCreds(), _expected('C')),
          'Failed save poisoned later storage operations',
        );
      }),
  'legacy SharedPreferences credentials still restore': () => _withStorage(
    (m) async {
      _check(
        _same(await SecureStorageService.getAllPortalCreds(), _expected('L')),
        'Legacy credential compatibility changed',
      );
    },
    account: null,
    preferences: {
      'saved_school_id': 'L-school',
      'saved_shala_pass': 'L-school-pass',
      'saved_staff_id': 'L-staff',
      'saved_staff_pass': 'L-staff-pass',
      'saved_sso_id': 'L-sso',
      'saved_sso_pass': 'L-sso-pass',
    },
  ),
  'normal save trims IDs, preserves passwords, and removes legacy plaintext passwords':
      () => _withStorage(
        (m) async {
          await SecureStorageService.saveAllPortals(
            shalaId: ' B-school ',
            shalaPass: ' school pass ',
            staffId: ' B-staff ',
            staffPass: ' staff pass ',
            rajsimsId: ' B-sso ',
            rajsimsPass: ' sso pass ',
          );
          final result = await SecureStorageService.getAllPortalCreds();
          _check(
            result['school_id'] == 'B-school' &&
                result['staff_id'] == 'B-staff' &&
                result['sso_id'] == 'B-sso',
            'IDs were not normalized',
          );
          _check(
            result['school_password'] == ' school pass ' &&
                result['staff_password'] == ' staff pass ' &&
                result['sso_password'] == ' sso pass ',
            'Password whitespace changed',
          );
          final prefs = await SharedPreferences.getInstance();
          _check(
            [
              'saved_shala_pass',
              'saved_staff_pass',
              'saved_sso_pass',
            ].every((k) => !prefs.containsKey(k)),
            'Legacy plaintext password survived migration',
          );
        },
        preferences: {
          'saved_shala_pass': 'old',
          'saved_staff_pass': 'old',
          'saved_sso_pass': 'old',
        },
      ),
  for (final sameSchool in [false, true])
    'school cache invalidation retains existing rules (sameSchool=$sameSchool)':
        () => _withStorage(
          (m) async {
            await _save(sameSchool ? 'A' : 'B');
            final prefs = await SharedPreferences.getInstance();
            _check(
              prefs.containsKey('cached_student_kpi') == sameSchool &&
                  prefs.containsKey('cached_staff_attendance') == sameSchool,
              'School cache invalidation changed',
            );
          },
          preferences: {
            'cached_student_kpi': '{}',
            'cached_staff_attendance': '{}',
          },
        ),
  'configured status remains false for missing credentials and true for complete save':
      () => _withStorage((m) async {
        _check(
          await SecureStorageService.isAppConfigured() == false,
          'Empty storage marked configured',
        );
        await _save('B');
        _check(
          await SecureStorageService.isAppConfigured(),
          'Complete save not configured',
        );
        await SecureStorageService.clearAll();
        _check(
          await SecureStorageService.isAppConfigured() == false,
          'Cleared storage marked configured',
        );
      }, account: null),
  'legacy individual secure fields still restore when v2 record is absent':
      () => _withStorage((m) async {
        m.values.addAll(_record('L'));
        _check(
          _same(await SecureStorageService.getAllPortalCreds(), _expected('L')),
          'Legacy secure field compatibility changed',
        );
      }, account: null),
};
