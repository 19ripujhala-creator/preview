import '../services/core/direct/coordinator.dart';
import '../services/core/direct/errors.dart';
import '../services/portals/shaladarpan/direct/monthly_tasks_worker.dart';
import '../services/portals/shaladarpan/direct/ranking_status_cache.dart';
import '../services/portals/shaladarpan/direct/viffs_mpr_http.dart';
import 'direct_portal_auth.dart';

/// Router parity: all monthly actions share the original school.monthly lease.
class DirectMonthlyTaskService {
  DirectMonthlyTaskService(this.auth) {
    worker = MonthlyTasksWorker(
      request: auth.monthlyRequest,
      baseUrl: () => Uri.https(
        'rajshaladarpan.rajasthan.gov.in',
        '/${auth.verifiedNode}/',
      ),
      schoolId: () => auth.authenticatedSchoolId ?? '',
      sessionKey: () => auth.schoolSessionIdentity,
      check: () {
        if (!auth.isVerified)
          throw const MonthlyError(
            'School portal session expired.',
            'SESSION_EXPIRED',
          );
      },
    );
  }
  final DirectPortalAuth auth;
  late final MonthlyTasksWorker worker;
  final _loginReads = <String, Future<Map<String, dynamic>>>{};

  /// /viffs/monthly-summary: read only, sharing the school.monthly lease.
  Future<Map<String, dynamic>> fetchViffsSummary({
    required String school,
    required int year,
    required int month,
    String tablet = 'P',
  }) async {
    if (year < 2000 ||
        year > 2100 ||
        month < 1 ||
        month > 12 ||
        !['P', 'B'].contains(tablet)) {
      return ViffsMprHttp.failure(
        'INVALID_SELECTION',
        'VIFFS reporting year/month or tablet is invalid.',
      );
    }
    Future<Map<String, dynamic>> execute() async {
      if (!auth.isVerified) {
        return ViffsMprHttp.failure(
          'SESSION_EXPIRED',
          'School portal session expired.',
        );
      }
      return ViffsMprHttp(
        request: auth.monthlyRequest,
        baseUrl: () => Uri.https(
          'rajshaladarpan.rajasthan.gov.in',
          '/${auth.verifiedNode}/',
        ),
        schoolId: () => auth.authenticatedSchoolId ?? '',
        sessionKey: () => auth.schoolSessionIdentity,
        check: () {
          if (!auth.isVerified) {
            throw const MonthlyError(
              'School portal session expired.',
              'SESSION_EXPIRED',
            );
          }
        },
      ).fetchSummary(school: school, year: year, month: month, tablet: tablet);
    }

    try {
      final co = auth.coordinator;
      if (co == null) return await execute();
      return await co.run(
        resource: 'school.monthly',
        kind: Kind.read,
        timeout: 180,
        maxAttempts: 3,
        label: 'viffs_mpr_summary',
        worker: (_) => execute(),
      );
    } on CoordinatorError catch (e) {
      return ViffsMprHttp.failure(e.kind.code, e.message);
    }
  }

  /// Original collect_ranking_status router policy: automatic checks through day 5.
  Future<Map<String, dynamic>> collectRankingStatus(
    String school, {
    DateTime? indiaDate,
  }) async {
    final now = indiaDate ?? RankingStatusCache.indiaNow(),
        period = RankingStatusCache.duePeriod(indiaDate);
    final cached = await worker.statusCache.readStatus(
          school,
          period.year,
          period.month,
        ),
        data = <String, dynamic>{};
    if (cached?['form'] is Map) {
      final form = monthlyCopy(Map<String, dynamic>.from(cached!['form']));
      form['snapshot'] = worker.signature(form, school);
      data['ranking_form'] = form;
    }
    Map<String, dynamic> unknown(String source) => {
      'school_id': school,
      'year': period.year,
      'month': period.month,
      'completed': null,
      'source': source,
    };
    if (!RankingStatusCache.needsLoginCheck(cached, indiaDate: now)) {
      data['ranking_status'] = {
        ...cached ?? unknown('not_checked'),
        'cached': cached != null,
        'auto_check_enabled': now.day <= 5,
      };
      return data;
    }
    final key = '$school/${period.year}/${period.month}';
    var task = _loginReads[key];
    if (task == null) {
      Future<Map<String, dynamic>> load() async {
        final result = await request('form', {
          'school_id': school,
          'task': 'ranking',
          'selection': {
            'ContentPlaceHolder1_ddlyear': '${period.year}',
            'ContentPlaceHolder1_ddlMonth1': '${period.month}',
          },
        });
        if (result['success'] != true)
          throw const MonthlyError(
            'Ranking status read unavailable.',
            'MONTHLY_UNAVAILABLE',
          );
        final fresh = await worker.statusCache.readStatus(
          school,
          period.year,
          period.month,
        );
        return {
          ...fresh ?? unknown('portal_unknown'),
          'cached': false,
          'auto_check_enabled': true,
        };
      }

      task = load();
      _loginReads[key] = task;
    }
    try {
      data['ranking_status'] = await task;
      final fresh = await worker.statusCache.readStatus(
        school,
        period.year,
        period.month,
      );
      if (fresh?['form'] is Map)
        data['ranking_form'] = monthlyCopy(
          Map<String, dynamic>.from(fresh!['form']),
        );
    } catch (_) {
      data['ranking_status'] = {
        ...cached ??
            {
              'school_id': school,
              'year': period.year,
              'month': period.month,
              'completed': null,
            },
        'cached': cached != null,
        'auto_check_enabled': true,
        'check_failed': true,
      };
    } finally {
      if (identical(_loginReads[key], task)) _loginReads.remove(key);
    }
    return data;
  }

  Future<Map<String, dynamic>> request(
    String path,
    Map<String, dynamic> body,
  ) async {
    final mutation = path != 'form',
        school = body['school_id']?.toString() ?? '',
        task = body['task']?.toString() ?? '';
    final selection = Map<String, String>.from(body['selection'] as Map),
        snapshot = body['snapshot']?.toString() ?? '';
    Future<Map<String, dynamic>> execute() async {
      try {
        if (!auth.isVerified)
          throw const MonthlyError(
            'School portal session expired.',
            'SESSION_EXPIRED',
          );
        if (school.trim() != auth.authenticatedSchoolId?.trim())
          throw const MonthlyError(
            'The logged-in school changed. Refresh the form.',
            'ACCOUNT_CHANGED',
          );
        if (!{'ranking', 'viffs'}.contains(task))
          throw const MonthlyError(
            'Unsupported monthly task.',
            'INVALID_PAYLOAD',
          );
        if (mutation && (body['confirmed'] != true || snapshot.isEmpty))
          throw const MonthlyError(
            'Review and confirm the monthly form before submitting.',
            'INVALID_PAYLOAD',
          );
        switch (path) {
          case 'form':
            return {
              'success': true,
              'data': await worker.readForm(
                task,
                selection,
                school,
                refresh: body['refresh'] == true,
              ),
            };
          case 'submit':
            return await worker.submitForm(
              task,
              selection,
              school,
              snapshot,
              Map<String, String>.from(body['values'] as Map),
              editing: body['editing'] == true,
            );
          case 'lock':
            return await worker.lockForm(task, selection, school, snapshot);
          case 'ranking/edit':
            if (task != 'ranking')
              throw const MonthlyError(
                'Unsupported monthly action.',
                'INVALID_PAYLOAD',
              );
            return await worker.editRanking(selection, school, snapshot);
          case 'ranking/delete':
            if (task != 'ranking')
              throw const MonthlyError(
                'Unsupported monthly action.',
                'INVALID_PAYLOAD',
              );
            return await worker.deleteRanking(selection, school, snapshot);
          default:
            throw const MonthlyError(
              'Unsupported monthly action.',
              'INVALID_PAYLOAD',
            );
        }
      } on MonthlyError catch (e) {
        return e.response;
      }
    }

    try {
      final co = auth.coordinator;
      if (co == null) return await execute();
      return await co.run(
        resource: 'school.monthly',
        kind: mutation ? Kind.mutation : Kind.read,
        timeout: path == 'form' || path == 'ranking/edit' ? 120 : 180,
        maxAttempts: mutation ? 1 : 3,
        label: 'monthly_${path.replaceAll('/', '_')}',
        worker: (_) => execute(),
      );
    } on CoordinatorError catch (e) {
      return MonthlyError(e.message, e.kind.code, attempted: mutation).response;
    }
  }
}
