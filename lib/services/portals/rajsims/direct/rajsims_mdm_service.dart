/// Native equivalent of RajSIMS routes: original resources/deadlines/contracts.
library;

import 'dart:async';

import '../../../core/direct/coordinator.dart';
import '../../../core/direct/errors.dart';
import 'http_auth.dart';
import 'rajsims_mdm_worker.dart';

class RajsimsMdmService {
  RajsimsMdmService({
    required this.registry,
    required this.worker,
    required this.coordinator,
  });
  final RajsimsHttpAuth registry;
  final RajsimsMdmWorker worker;
  final PortalCoordinator coordinator;
  static const preMutationCodes = {
    'INVALID_PAYLOAD',
    'BAD_DATE',
    'BAD_COUNT',
    'BAD_PRODUCT',
    'NO_USER',
    'VALIDATION_FAILED',
  };
  Future<MdmMap> run(
    String user,
    Future<MdmMap> Function() action, {
    String resource = 'rajsims.mdm',
    Kind kind = Kind.read,
    double timeout = 45,
    String label = 'rajsims_read',
    int? maxAttempts,
  }) async {
    if (user.isEmpty || registry.username != user)
      return {
        'success': false,
        'code': 'ACCOUNT_CHANGED',
        'message': 'RajSIMS login changed.',
      };
    try {
      return await coordinator.run(
        resource: resource,
        kind: kind,
        timeout: timeout,
        label: label,
        maxAttempts: maxAttempts,
        preMutationCodes: kind == Kind.mutation ? preMutationCodes : const {},
        worker: (_) async {
          final context = registry.current();
          if (context == null || registry.username != user)
            return {
              'success': false,
              'code': 'SESSION_EXPIRED',
              'message': 'RajSIMS authentication required.',
            };
          final result = await action();
          if (!identical(context, registry.current()) ||
              registry.username != user)
            return {
              'success': false,
              'code': 'SESSION_CHANGED',
              'message': 'RajSIMS session changed. Fetch again.',
            };
          return result;
        },
      );
    } on CoordinatorError catch (e) {
      return e.asDetail();
    }
  }

  Future<MdmMap> stock(String u, {bool force = false}) => run(
    u,
    () => worker.stock(registry.current(), allowStale: !force, force: force),
    timeout: 35,
    label: 'mdm_stock',
  );
  Future<MdmMap> status(String u, {bool force = false}) => run(
    u,
    () => worker.status(registry.current(), force: force),
    label: 'mdm_fetch',
  );
  Future<MdmMap> history(String u, {bool legacy = false, bool force = false}) =>
      run(
        u,
        () =>
            worker.history(registry.current(), isLegacy: legacy, force: force),
        timeout: 120,
        label: 'mdm_list',
      );
  Future<MdmMap> entry(String u, String no, {bool legacy = false}) {
    if (no.trim().isEmpty)
      return Future.value({
        'success': false,
        'code': 'INVALID_PAYLOAD',
        'message': 'Distribution number is required.',
      });
    return run(
      u,
      () => worker.entry(no.trim(), registry.current(), legacy: legacy),
      timeout: 120,
      label: 'mdm_entry',
    );
  }

  static MdmMap? validate(MdmMap p, {bool update = false}) {
    MdmMap fail(String code, String message) => {
      'success': false,
      'code': code,
      'message': message,
      'status_code': 400,
    };
    final product = (p['product_name'] ?? '').toString().trim();
    if (product.isEmpty ||
        product.length > 200 ||
        product.runes.any((c) => c < 32))
      return fail(
        'INVALID_PAYLOAD',
        'Product name is required and must be valid.',
      );
    p['product_name'] = product;
    for (final k in ['beneficiary_count', 'atithi_mata_count']) {
      final v = p[k];
      if (v is! int || v < 0 || v > 9999)
        return fail('INVALID_PAYLOAD', 'Invalid ${k.replaceAll('_', ' ')}.');
    }
    final choice = p['atithi_mata_choice'];
    if (!{'0', '1'}.contains(choice))
      return fail('INVALID_PAYLOAD', 'Invalid Atithi Mata selection.');
    if (choice == '1' && p['atithi_mata_count'] <= 0)
      return fail('BAD_COUNT', 'Atithi Mata count must be positive.');
    if (p['is_zero_consumption'] != true && p['beneficiary_count'] <= 0)
      return fail(
        'BAD_COUNT',
        'Beneficiary count must be positive for consumption.',
      );
    if (p['is_zero_consumption'] == true) {
      final reason = (p['zero_reason'] ?? '').toString().trim();
      if (reason.isEmpty ||
          reason.length > 2000 ||
          reason.runes.any((c) => c < 32))
        return fail(
          'INVALID_PAYLOAD',
          'Zero consumption reason is required and must be valid.',
        );
      p['zero_reason'] = reason;
    }
    if (!update) {
      final raw = p['legacy_date'];
      if (p['legacy'] == true && (raw == null || raw.toString().isEmpty))
        return fail('BAD_DATE', 'Legacy distribution date is required.');
      if (raw != null && raw.toString().isNotEmpty) {
        final text = raw.toString().trim();
        final d =
            RegExp(
              r'^(?:[0-9]{1,2}[/-][0-9]{1,2}[/-][0-9]{4}|[0-9]{4}-[0-9]{1,2}-[0-9]{1,2})$',
            ).hasMatch(text)
            ? mdmParseDate(text)
            : null;
        if (d == null)
          return fail('BAD_DATE', 'Invalid calendar date. Use DD/MM/YYYY.');
        p['legacy_date'] =
            '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';
      }
    }
    return null;
  }

  static MdmMap _payload(MdmMap raw, {bool update = false}) => {
    'product_name': raw['product_name'],
    'beneficiary_count': raw['beneficiary_count'],
    'is_zero_consumption': raw['is_zero_consumption'] ?? false,
    'zero_reason': raw['zero_reason'],
    'atithi_mata_choice': raw['atithi_mata_choice'] ?? '0',
    'atithi_mata_count': raw['atithi_mata_count'] ?? 1,
    if (!update) 'legacy_date': raw['legacy_date'],
    'legacy': raw['legacy'] ?? false,
  };
  Future<MdmMap> submit(String u, MdmMap raw) {
    final p = _payload(raw), error = validate(p);
    if (error != null) return Future.value(error);
    return run(
      u,
      () => worker.submit(registry.current(), p),
      kind: Kind.mutation,
      label: 'mdm_submit',
    );
  }

  Future<MdmMap> update(String u, MdmMap raw) {
    final p = _payload(raw, update: true), error = validate(p, update: true);
    if (error != null) return Future.value(error);
    final no = (raw['dist_no'] ?? '').toString().trim();
    if (no.isEmpty)
      return Future.value({
        'success': false,
        'code': 'INVALID_PAYLOAD',
        'message': 'Distribution number is required.',
      });
    return run(
      u,
      () => worker.update(
        no,
        p,
        registry.current(),
        legacy: p.remove('legacy') == true,
      ),
      kind: Kind.mutation,
      timeout: 120,
      label: 'mdm_update',
    );
  }

  Future<MdmMap> monthly(String u, int year, int month, {bool bundle = false}) {
    if (year < 2000 || year > 2100 || month < 1 || month > 12)
      return Future.value({
        'success': false,
        'code': 'INVALID_PAYLOAD',
        'message': 'Report month is invalid.',
      });
    return run(
      u,
      () => worker.monthlySummary(registry.current(), year, month),
      resource: bundle ? 'mpr.monthly' : 'rajsims.mdm',
      timeout: bundle ? 90 : 180,
      label: bundle ? 'mpr_monthly_http' : 'mdm_monthly_summary',
      maxAttempts: bundle ? 1 : null,
    );
  }

  Future<MdmMap> profile(String u, {bool bundle = false}) => run(
    u,
    () => worker.mprProfile(registry.current()),
    resource: bundle ? 'mpr.profile' : 'rajsims.mdm',
    timeout: bundle ? 20 : 45,
    label: bundle ? 'mpr_profile_http' : 'mpr_profile',
    maxAttempts: bundle ? 1 : null,
  );
  Future<MdmMap> bundle(
    String u,
    int year,
    int month,
    Future<MdmMap> Function() school,
  ) async {
    final watch = Stopwatch()..start(), timings = <String, int>{};
    Future<MdmMap?> timed(String key, Future<MdmMap> Function() fn) async {
      final w = Stopwatch()..start();
      try {
        final r = await fn();
        return r['success'] == true ? r : null;
      } catch (_) {
        return null;
      } finally {
        timings['${key}_ms'] = w.elapsedMilliseconds;
      }
    }

    final result = await Future.wait([
      timed('enrolment', school),
      timed('monthly', () => monthly(u, year, month, bundle: true)),
      timed('profile', () => profile(u, bundle: true)),
    ]);
    timings['total_ms'] = watch.elapsedMilliseconds;
    return {
      'success': true,
      'school': result[0],
      'monthly': result[1],
      'profile': result[2],
      'viffs_p': null,
      'viffs_b': null,
      'viffs_source': 'monthly_task_status',
      'timings': timings,
      'timing_ms': watch.elapsedMilliseconds,
      'transport': 'http',
    };
  }
}
