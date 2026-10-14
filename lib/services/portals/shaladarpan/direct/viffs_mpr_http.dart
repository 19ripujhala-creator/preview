/// Complete authenticated HTTP workflow from viffs_mpr_http.py.
import 'dart:async';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'monthly_tasks_worker.dart';
import '../portal_state.dart';
import 'viffs_mpr_worker.dart';
import 'viffs_worker.dart';
import '../../../core/direct/async_primitives.dart';
import 'student_attendance_worker.dart';

class ViffsMprHttp {
  ViffsMprHttp({
    required this.request,
    required this.baseUrl,
    required this.schoolId,
    required this.sessionKey,
    this.check,
  });
  final MonthlyRequest request;
  final Uri Function() baseUrl;
  final String Function() schoolId, sessionKey;
  final void Function()? check;
  static const prefix = MonthlyTasksWorker.prefix;
  static const path = 'Home/School/RMSA_SchoolMonthly_NP_tablets.aspx';
  static const names = {
    '${prefix}ddlStudentType': r'ctl00$ContentPlaceHolder1$ddlStudentType',
    '${prefix}ddlClass': r'ctl00$ContentPlaceHolder1$ddlClass',
    '${prefix}ddlmonth': r'ctl00$ContentPlaceHolder1$ddlmonth',
  };
  static MonthlyError fail(
    String message, [
    String code = 'VIFFS_REPORT_INCOMPLETE',
  ]) => MonthlyError(message, code);
  static Map<String, dynamic> failure(String code, String message) => {
    'success': false,
    'complete': false,
    'code': code,
    'message': message,
    'transport': 'http',
  };
  void current(String school, String key) {
    OperationCancellation.current?.check();
    check?.call();
    if (key.isEmpty || key != sessionKey() || school != schoolId().trim()) {
      throw fail(
        'ShalaDarpan session changed while VIFFS data was loading.',
        'SESSION_CHANGED',
      );
    }
  }

  static Uri validateBase(Uri base) {
    if (base.scheme != 'https' ||
        base.host != 'rajshaladarpan.rajasthan.gov.in' ||
        base.port != 443 ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        !RegExp(r'^/SD[1-5]/?$', caseSensitive: false).hasMatch(base.path)) {
      throw fail(
        'Active ShalaDarpan server base is invalid.',
        'SESSION_CHANGED',
      );
    }
    return base.path.endsWith('/') ? base : base.replace(path: '${base.path}/');
  }

  dom.Document checked(MonthlyReply response, String school, String key) {
    current(school, key);
    try {
      validateSchoolDocument(response.url, response.html, response.status);
    } on SchoolDocumentError catch (e) {
      throw fail(e.message, e.code ?? 'VIFFS_REPORT_INCOMPLETE');
    }
    if (response.url.scheme != 'https' ||
        response.url.host != 'rajshaladarpan.rajasthan.gov.in' ||
        !response.url.path.toLowerCase().endsWith('/${path.toLowerCase()}')) {
      throw fail(
        'VIFFS request was redirected away from the authenticated monthly form.',
        'SESSION_CHANGED',
      );
    }
    return html.parse(response.html);
  }

  /// Native successful controls: exactly the source's dictionary semantics.
  static Map<String, Object?> successfulFormFields(dom.Document document) {
    final form = document.querySelector('form');
    if (form == null) throw fail('VIFFS form is unavailable.');
    final fields = <String, Object?>{};
    for (final node in form.querySelectorAll('input, textarea')) {
      final name = node.attributes['name'];
      if (name == null ||
          name.isEmpty ||
          node.attributes.containsKey('disabled'))
        continue;
      if (node.localName == 'textarea') {
        fields[name] = node.text;
        continue;
      }
      final type = (node.attributes['type'] ?? 'text').toLowerCase();
      if (['submit', 'button', 'image', 'file', 'reset'].contains(type))
        continue;
      if (['checkbox', 'radio'].contains(type) &&
          !node.attributes.containsKey('checked'))
        continue;
      fields[name] = node.attributes['value'] ?? '';
    }
    for (final node in form.querySelectorAll('select')) {
      final name = node.attributes['name'];
      if (name == null ||
          name.isEmpty ||
          node.attributes.containsKey('disabled'))
        continue;
      final selected =
          node.querySelector('option[selected]') ??
          node.querySelector('option');
      fields[name] = selected == null
          ? ''
          : selected.attributes['value'] ?? monthlyText(selected);
    }
    fields.remove('__ASYNCPOST');
    fields.removeWhere(
      (name, _) => name.toLowerCase().endsWith('scriptmanager1'),
    );
    if (fields['__VIEWSTATE'] == null ||
        fields['__VIEWSTATE'] == '' ||
        fields['__EVENTVALIDATION'] == null ||
        fields['__EVENTVALIDATION'] == '') {
      throw fail('VIFFS form tokens are missing.');
    }
    fields.putIfAbsent('__EVENTARGUMENT', () => '');
    return fields;
  }

  static List<String> selectorOptions(dom.Document soup, String id) {
    final node = soup.getElementById(id);
    if (node == null || node.attributes.containsKey('disabled')) {
      throw fail('VIFFS selector was not returned by the portal.');
    }
    return node
        .querySelectorAll('option')
        .where((o) => !o.attributes.containsKey('disabled'))
        .map((o) => o.attributes['value'] ?? monthlyText(o))
        .toList();
  }

  static Map<String, Object?> buttonPostFields(dom.Document soup) {
    final button = soup.getElementById('${prefix}Button1');
    if (button == null || button.attributes.containsKey('disabled')) {
      throw fail('VIFFS Show button is unavailable on the portal form.');
    }
    final name = button.attributes['name'];
    if (name == null || name.isEmpty) {
      throw fail('VIFFS Show button name is unavailable on the portal form.');
    }
    if ((button.attributes['type'] ?? '').toLowerCase() == 'image') {
      return {'${name}.x': '1', '${name}.y': '1'};
    }
    return {
      name: (button.attributes['value'] ?? '').isEmpty
          ? 'Show'
          : button.attributes['value'],
    };
  }

  Future<dom.Document> post(
    Uri url,
    dom.Document soup,
    Map<String, Object?> fields,
    String school,
    String key,
    Duration timeout,
  ) async {
    current(school, key);
    final response = await request(
      url,
      body: AttendanceForm.encode(fields),
      referer: url,
      timeout: timeout,
      followRedirects: false,
    );
    return checked(response, school, key);
  }

  Future<dom.Document> postSelect(
    Uri url,
    dom.Document soup,
    String id,
    String value,
    String school,
    String key,
    Duration timeout,
  ) {
    if (!selectorOptions(soup, id).contains(value) || value == '0') {
      throw fail(
        'Requested VIFFS period/tablet option is unavailable.',
        'INVALID_SELECTION',
      );
    }
    final name = names[id]!;
    final fields = successfulFormFields(soup)
      ..addAll({'__EVENTTARGET': name, '__EVENTARGUMENT': '', name: value});
    return post(url, soup, fields, school, key, timeout);
  }

  Future<Map<String, dynamic>> fetchSummary({
    required String school,
    required Object year,
    required Object month,
    String tablet = 'P',
    num timeoutMs = 30000,
  }) async {
    try {
      final base = validateBase(baseUrl());
      final yt = '$year', mt = '$month';
      if (!RegExp(r'^\d{4}$').hasMatch(yt) ||
          !RegExp(r'^\d{1,2}$').hasMatch(mt) ||
          !ViffsWorker.isDecimal(mt) ||
          ViffsWorker.decimalInteger(mt) < 1 ||
          ViffsWorker.decimalInteger(mt) > 12) {
        throw fail(
          'VIFFS reporting year/month is invalid.',
          'INVALID_SELECTION',
        );
      }
      if (!timeoutMs.isFinite || timeoutMs <= 0) {
        throw fail('VIFFS request timeout is invalid.', 'INVALID_SELECTION');
      }
      if (!['P', 'B'].contains(tablet)) {
        throw fail(
          'VIFFS tablet category must be P or B.',
          'INVALID_SELECTION',
        );
      }
      school = school.trim();
      if (school.isEmpty ||
          school != schoolId().trim() ||
          sessionKey().isEmpty) {
        throw fail(
          'ShalaDarpan authenticated session is unavailable.',
          'SESSION_CHANGED',
        );
      }
      final key = sessionKey();
      current(school, key);
      final y = int.parse(yt), m = ViffsWorker.decimalInteger(mt);
      final timeout = Duration(microseconds: (timeoutMs * 1000).round());
      final url = base.resolve(path);
      var soup = checked(
        await request(url, timeout: timeout, followRedirects: true),
        school,
        key,
      );
      final metadata = MonthlyTasksWorker.parseForm(
        soup.outerHtml,
        'viffs',
        selection: {},
      );
      List options(String suffix) {
        final fields = (metadata['selectors'] as List)
            .where((f) => f['id'] == prefix + suffix)
            .toList();
        if (fields.length != 1)
          throw fail('VIFFS period selectors are unavailable.');
        return fields.single['options'] as List;
      }

      final pattern = ViffsMprWorker.sessionPattern(m >= 5 ? y : y - 1);
      final sessions = options('ddlStudentType')
          .where((o) => pattern.hasMatch('${o['value']}'.replaceAll(' ', '')))
          .toList();
      if (sessions.length != 1) {
        throw fail(
          'Requested VIFFS academic session is unavailable.',
          'INVALID_SELECTION',
        );
      }
      final session = '${sessions.single['value']}';
      soup = await postSelect(
        url,
        soup,
        '${prefix}ddlStudentType',
        session,
        school,
        key,
        timeout,
      );
      soup = await postSelect(
        url,
        soup,
        '${prefix}ddlClass',
        tablet,
        school,
        key,
        timeout,
      );
      final months = selectorOptions(soup, '${prefix}ddlmonth')
          .where(
            (v) =>
                ViffsWorker.isDecimal(v) && ViffsWorker.decimalInteger(v) == m,
          )
          .toList();
      if (months.length != 1) {
        throw fail(
          'Requested VIFFS month is unavailable.',
          'INVALID_SELECTION',
        );
      }
      final selectedMonth = months.single;
      soup = await postSelect(
        url,
        soup,
        '${prefix}ddlmonth',
        selectedMonth,
        school,
        key,
        timeout,
      );
      final fields = successfulFormFields(soup)
        ..addAll({'__EVENTTARGET': '', '__EVENTARGUMENT': ''})
        ..addAll(buttonPostFields(soup));
      soup = await post(url, soup, fields, school, key, timeout);
      final selection = <String, String>{
        '${prefix}ddlStudentType': session,
        '${prefix}ddlClass': tablet,
        '${prefix}ddlmonth': selectedMonth,
      };
      final form = MonthlyTasksWorker.parseForm(
        soup.outerHtml,
        'viffs',
        selection: selection,
      );
      if (selection.entries.any((e) => form['selection'][e.key] != e.value)) {
        throw fail(
          'Portal did not retain the requested VIFFS reporting period.',
          'SELECTION_CHANGED',
        );
      }
      form['school_id'] = school;
      final result = ViffsMprWorker.summarizeLockedForm(form, school, selection)
        ..addAll({
          'year': y,
          'month': m,
          'tablet': tablet,
          'metric': 'children_four_or_more_tablets',
          'transport': 'http',
        });
      current(school, key);
      return result;
    } on MonthlyError catch (e) {
      return failure(e.code, e.message);
    } on TimeoutException {
      return failure('PORTAL_SLOW', 'VIFFS report request timed out.');
    } on IOException {
      return failure('NETWORK_ERROR', 'Could not connect to the VIFFS report.');
    } catch (e) {
      return failure('VIFFS_HTTP_ERROR', e.toString());
    }
  }
}
