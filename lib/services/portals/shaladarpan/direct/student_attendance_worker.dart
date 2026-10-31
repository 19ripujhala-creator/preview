/// Clean Finite-State-Machine Student Attendance Worker for Shala Darpan
/// (`Home/School/StudentdailyAttendanceStatus_Web_NewVersion.aspx`).
///
/// Server-side WebForms State Machine Rules:
/// - Mode 1 (`_PortalPageMode.summary`):
///   `#ContentPlaceHolder1_txtdate` and `#ContentPlaceHolder1_btn_Show` are
///   ENABLED, and `#ContentPlaceHolder1_grd_Student` holds class summary rows.
///   Allowed transitions: `SHOW` (date change/refresh) or `CLASS_ENTRY`.
/// - Mode 2 (`_PortalPageMode.entry`):
///   `#ContentPlaceHolder1_txtdate` and `#ContentPlaceHolder1_btn_Show` are
///   DISABLED, `#ContentPlaceHolder1_btnback` and `#ContentPlaceHolder1_btnsubmit`
///   are ENABLED, and the student roster table is rendered inside `#ContentPlaceHolder1_upPnl`.
///   Allowed transitions: `BACK` (return to summary) or `SUBMIT` (save roster).
import 'dart:async';

import 'portal_messages.dart';
import 'ranking_http.dart' show RankingHttp;

import '../../../core/direct/portal_diagnostics.dart';
import '../../../core/direct/mutation_dispatch.dart';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../../../experiments/student_attendance_parity.dart';

typedef AttendanceHttpReply = ({Uri url, int status, String html});
typedef AttendanceHttpRequest = Future<AttendanceHttpReply> Function(
  Uri url, {
  Map<String, Object?>? fields,
  Uri? referer,
  bool mutation,
});

enum _PortalPageMode { summary, entry }

class AttendanceWorkerError implements Exception {
  const AttendanceWorkerError(this.code, this.message, [this.extra = const {}]);
  final String code, message;
  final Map<String, dynamic> extra;
  Map<String, dynamic> asResult() => {
    'success': false,
    'code': code,
    'message': message,
    ...extra,
  };
  @override
  String toString() => '$code: $message';
}

/// Pure WebForms form serializer. Repeated form names and multi-select values
/// remain lists, matching browser and HTTPX form submission semantics.
class AttendanceForm {
  static dom.Element? enclosing(dom.Element control) {
    dom.Element? form = control;
    while (form != null && form.localName != 'form') {
      form = form.parent;
    }
    return form;
  }

  static Map<String, Object?> payload(
    dom.Element form,
    dom.Element button, {
    bool microsoftAjax = false,
  }) {
    final fields = <String, Object?>{};
    for (final field in form.querySelectorAll(
      'input[name], select[name], textarea[name]',
    )) {
      // Captured Microsoft AJAX posts include disabled text/select controls.
      // Ordinary full-form posts keep their existing successful-control rules.
      if (!microsoftAjax && field.attributes.containsKey('disabled')) continue;
      final name = field.attributes['name']!;
      final kind = (field.attributes['type'] ?? 'text').toLowerCase();
      Object value;
      if (field.localName == 'input') {
        if (['submit', 'button', 'image', 'reset', 'file'].contains(kind)) {
          continue;
        }
        if (['checkbox', 'radio'].contains(kind) &&
            !field.attributes.containsKey('checked')) {
          continue;
        }
        value =
            field.attributes['value'] ??
            (['checkbox', 'radio'].contains(kind) ? 'on' : '');
      } else if (field.localName == 'select') {
        final options = field.querySelectorAll('option');
        var selected = options
            .where((o) => o.attributes.containsKey('selected'))
            .toList();
        if (selected.isEmpty &&
            options.isNotEmpty &&
            !field.attributes.containsKey('multiple')) {
          selected = [options.first];
        }
        value = selected.map((o) => o.attributes['value'] ?? o.text).toList();
      } else {
        value = field.text;
      }
      if (fields.containsKey(name)) {
        final previous = fields[name];
        fields[name] = [
          if (previous is List) ...previous else previous,
          if (value is List) ...value else value,
        ];
      } else {
        fields[name] = value;
      }
    }
    fields['__EVENTTARGET'] = '';
    fields['__EVENTARGUMENT'] = '';
    fields.remove('__ASYNCPOST');
    final name = button.attributes['name'];
    final kind = (button.attributes['type'] ?? 'submit').toLowerCase();
    if (name != null && kind == 'submit') {
      fields[name] = button.attributes['value'] ?? button.text.trim();
    } else if (name != null && kind == 'image') {
      fields['$name.x'] = '0';
      fields['$name.y'] = '0';
    } else {
      final script =
          '${button.attributes['href'] ?? ''} '
          '${button.attributes['onclick'] ?? ''}';
      final match = RegExp(
        r'''(?:__doPostBack\s*\(|WebForm_PostBackOptions\s*\()\s*['"]([^'"]+)['"]''',
      ).firstMatch(script);
      if (match == null) {
        throw const AttendanceWorkerError(
          'PAGE_NOT_READY',
          'GENDER_SHOW_POSTBACK_NOT_FOUND',
        );
      }
      fields['__EVENTTARGET'] = match.group(1)!;
    }
    return fields;
  }

  static String encode(Map<String, Object?> fields) {
    final pairs = <String>[];
    for (final entry in fields.entries) {
      final value = entry.value;
      for (final item in value is List ? value : [value]) {
        pairs.add(
          '${Uri.encodeQueryComponent(entry.key)}='
          '${Uri.encodeQueryComponent(item?.toString() ?? '')}',
        );
      }
    }
    return pairs.join('&');
  }
}

/// Deterministic page state machine for a single attendance operation.
class _AttendanceDocument {
  _AttendanceDocument(this.worker, {this.allowSummaryNavigation = false});
  final bool allowSummaryNavigation;
  final StudentAttendanceWorker worker;
  late Uri url;
  late dom.Document soup;
  bool loaded = false;
  bool responseUnconsumed = false;
  bool usedRetainedEnvelope = false;
  bool restoredSummaryNavigation = false;
  String? navigationClassId, navigationSection;
  String identity = '';
  Duration loadedAt = Duration.zero;

  _PortalPageMode get mode =>
      soup
              .getElementById(StudentAttendanceWorker.dateId)
              ?.attributes
              .containsKey('disabled') ==
          true
      ? _PortalPageMode.entry
      : _PortalPageMode.summary;

  Future<void> request(
    Uri target, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    worker._entryForm = null;
    restoredSummaryNavigation = false;
    if (mutation) worker._summaryNavigation = null;
    if (mutation) MutationDispatch.current?.enterRequest();
    final action = mutation
        ? 'SUBMIT'
        : fields?['__READ_ONLY_ACTION']?.toString() ?? 'GET_PAGE';
    final response = await PortalDiagnostics.withAction(
      action,
      () => worker.request(
        target,
        fields: fields,
        referer: referer,
        mutation: mutation,
      ),
    );
    url = response.url;
    soup = await PortalDiagnostics.measure(
      PortalPhase.studentParse,
      () async => StudentAttendanceWorker.mergeResponse(
        loaded ? soup : null,
        response.html,
      ),
    );
    if (soup.querySelector('#bodyContent_txtUName, #txtUserId') != null) {
      throw const AttendanceWorkerError(
        'SESSION_EXPIRED',
        'School portal session expired.',
      );
    }
    if (StudentAttendanceWorker._isPublicDefaultRedirect(url.toString())) {
      throw StudentAttendanceWorker._publicRedirectError(url.toString());
    }
    if (StudentAttendanceWorker.isLoginRedirect(url)) {
      throw const AttendanceWorkerError(
        'SESSION_EXPIRED',
        'School portal session expired.',
      );
    }
    for (final heading in soup.querySelectorAll('h1, h2')) {
      final message = StudentAttendanceWorker.text(heading);
      if (StudentAttendanceWorker._staleFormText(message)) {
        throw AttendanceWorkerError('PORTAL_RESPONSE_ERROR', message, {
          'form_state_rejected': true,
        });
      }
    }
    final title = StudentAttendanceWorker.text(soup.querySelector('title'));
    final heading = StudentAttendanceWorker.text(soup.querySelector('h1'));
    if ([
      'server error',
      'runtime error',
      'nullreference',
      'object reference',
      'validation of viewstate',
      'invalid postback or callback argument',
      'the state information is invalid',
    ].any((x) => '$title $heading'.toLowerCase().contains(x))) {
      throw AttendanceWorkerError(
        'PORTAL_RESPONSE_ERROR',
        title.isNotEmpty ? title : heading,
      );
    }
    if (response.status < 200 || response.status >= 300) {
      throw AttendanceWorkerError('PORTAL_HTTP', 'HTTP ${response.status}');
    }
    await worker.observeUrl?.call(url);
    loaded = true;
    responseUnconsumed = true;
    identity = worker.sessionIdentity?.call() ?? '';
    loadedAt = worker._formNow;
  }

  Future<void> click(
    dom.Element? button, {
    Map<String, Object?> overrides = const {},
    bool mutation = false,
  }) async {
    if (button == null || button.attributes.containsKey('disabled')) {
      throw const AttendanceWorkerError(
        'PAGE_NOT_READY',
        'Portal form control is missing or disabled.',
      );
    }
    final form = AttendanceForm.enclosing(button);
    if (form == null) {
      throw const AttendanceWorkerError(
        'PAGE_NOT_READY',
        'Portal form is missing.',
      );
    }
    final microsoftAjax =
        form.querySelector('#ContentPlaceHolder1_upPnl') != null &&
        (!mutation || button.id == 'ContentPlaceHolder1_btnsubmit');
    final fields = AttendanceForm.payload(
      form,
      button,
      microsoftAjax: microsoftAjax,
    )..addAll(overrides);
    final action = url.resolve(form.attributes['action'] ?? url.toString());
    if (action.authority != url.authority || action.scheme != url.scheme) {
      throw const AttendanceWorkerError(
        'PORTAL_RESPONSE_ERROR',
        'Unexpected form destination.',
      );
    }
    // Local transport markers are removed before encoding the HTTP request.
    if (mutation) {
      fields['__APPROVED_SAVE_CONTROL'] = button.id;
      fields['__APPROVED_SAVE_NAME'] =
          button.attributes['name'] ?? fields['__EVENTTARGET'];
    } else {
      fields['__READ_ONLY_ACTION'] = button.id == StudentAttendanceWorker.showId
          ? 'SHOW'
          : button.id == StudentAttendanceWorker.backId
          ? 'BACK'
          : 'CLASS_ENTRY';
    }
    // Native capture proves both Entry and btnsubmit use this AJAX panel.
    if (microsoftAjax) {
      final control = '${fields['__EVENTTARGET'] ?? ''}'.isNotEmpty
          ? '${fields['__EVENTTARGET']}'
          : button.attributes['name'];
      if (control != null && control.isNotEmpty) {
        fields[r'ctl00$ScriptManager1'] =
            'ctl00\$ContentPlaceHolder1\$upPnl|$control';
        fields['__ASYNCPOST'] = 'true';
      }
    }
    await request(action, fields: fields, referer: url, mutation: mutation);
  }

  Future<void> _fetchInitialPageWithHomeFallback(Uri base, Uri target) async {
    try {
      await request(target);
    } on AttendanceWorkerError catch (error) {
      if (error.code != 'PORTAL_RESPONSE_ERROR') rethrow;
      await request(base.resolve('Home/School/Home_New.aspx'));
      final resolvedBase = Uri.parse(
        '${url.scheme}://${url.authority}/'
        '${url.path.split('/').where((p) => p.isNotEmpty).first}/',
      );
      var entry = resolvedBase.resolve(
        'Home/School/${StudentAttendanceWorker.pageName}',
      );
      for (final link in soup.querySelectorAll('a[href]')) {
        final resolved = url.resolve(link.attributes['href']!);
        if (resolved.toString().toLowerCase() ==
            entry.toString().toLowerCase()) {
          entry = resolved;
          break;
        }
      }
      await request(entry);
    }
  }

  /// Exit retained server-side `ENTRY_MODE` if a fresh `GET` still returned
  /// disabled date/show controls with an enabled native `Back` button.
  Future<bool> _exitServerRetainedEntryIfPresent() async {
    if (mode != _PortalPageMode.entry) return false;
    final backBtn = soup.getElementById(StudentAttendanceWorker.backId);
    if (backBtn == null || backBtn.attributes.containsKey('disabled')) {
      return false;
    }
    await click(backBtn);
    return true;
  }

  Future<Map<String, dynamic>> summary(String? date) async {
    final base = worker.baseUrl();
    final target = base.resolve(
      'Home/School/${StudentAttendanceWorker.pageName}',
    );
    var reused = (allowSummaryNavigation && worker._restoreSummaryNavigation(this, date)) ||
        worker._restoreReadForm(this);
    usedRetainedEnvelope = reused;
    var returnedToSummary = false;

    // A scoped summary snapshot can authorize direct read-only Entry navigation.
    // Without that snapshot, retain native Back using the latest Entry state.
    if (reused && mode == _PortalPageMode.entry) {
      try {
        await click(soup.getElementById(StudentAttendanceWorker.backId));
        returnedToSummary = true;
        if (mode != _PortalPageMode.summary ||
            !worker._usableReadForm(url, soup)) {
          reused = false;
          usedRetainedEnvelope = false;
        }
      } on AttendanceWorkerError catch (error) {
        if (!StudentAttendanceWorker._staleFormError(error)) rethrow;
        worker._summaryNavigation = null;
      worker._blockedReadIdentity = worker.sessionIdentity?.call();
        worker._readForm = null;
        reused = false;
        usedRetainedEnvelope = false;
      }
    }

    // Transition 2: Cold GET when no reusable form is available, plus recovery
    // if the server's session retained an open ENTRY_MODE panel across GET.
    if (!reused) {
      await _fetchInitialPageWithHomeFallback(base, target);
      if (await _exitServerRetainedEntryIfPresent()) {
        returnedToSummary = true;
      }
    }

    final field = soup.getElementById(StudentAttendanceWorker.dateId);
    final button = soup.getElementById(StudentAttendanceWorker.showId);
    if (field == null || field.attributes['name'] == null || button == null) {
      throw const AttendanceWorkerError(
        'PAGE_NOT_READY',
        'Attendance date or Show control missing.',
      );
    }
    final selected = date ?? field.attributes['value'];

    // Transition 3: Unconsumed summary fast-path (after fresh GET, native Back,
    // or background summary fetch when date already matches).
    if ((!reused || returnedToSummary || responseUnconsumed) &&
        worker._usableReadForm(url, soup)) {
      String? initialDate;
      try {
        initialDate = StudentAttendanceWorker.validDate(
          field.attributes['value'],
        );
      } on AttendanceWorkerError {
        initialDate = null;
      }
      if (initialDate != null &&
          initialDate == StudentAttendanceWorker.validDate(selected)) {
        final initial = StudentAttendanceWorker.parseClassSummary(soup);
        if (initial['found'] == true &&
            (initial['classes'] as List).isNotEmpty) {
          worker._rememberReadForm(this);
          worker._rememberSummaryNavigation(this, initial);
          return initial;
        }
      }
    }

    // Transition 4: Explicit SHOW postback to load the target date's summary.
    final previousDateAttr = field.attributes['value'];
    if (selected != null) {
      field.attributes['value'] = selected;
    }
    try {
      await click(
        button,
        overrides: {field.attributes['name']!: selected ?? ''},
      );
    } on AttendanceWorkerError catch (error) {
      if (previousDateAttr != null) {
        field.attributes['value'] = previousDateAttr;
      }
      if (!reused || !StudentAttendanceWorker._staleFormError(error)) rethrow;
      worker._summaryNavigation = null;
      worker._blockedReadIdentity = worker.sessionIdentity?.call();
      worker._readForm = null;
      usedRetainedEnvelope = false;
      await request(target);
      await _exitServerRetainedEntryIfPresent();
      final freshDate = soup.getElementById(StudentAttendanceWorker.dateId);
      final freshShow = soup.getElementById(StudentAttendanceWorker.showId);
      if (freshDate?.attributes['name'] == null || freshShow == null) {
        throw const AttendanceWorkerError(
          'PAGE_NOT_READY',
          'Attendance date or Show control missing.',
        );
      }
      if (selected != null) {
        freshDate!.attributes['value'] = selected;
      }
      await click(
        freshShow,
        overrides: {freshDate!.attributes['name']!: selected ?? ''},
      );
    }

    checkDate(selected);
    final parsed = StudentAttendanceWorker.parseClassSummary(
      soup,
      date: selected,
    );
    if (parsed['found'] != true) {
      final messages = StudentAttendanceWorker._portalMessages(soup);
      if (messages.isNotEmpty) {
        final joined = messages.join('\n');
        throw AttendanceWorkerError('PORTAL_MESSAGE', joined, {
          'portal_message': joined,
          'message_source': 'portal',
        });
      }
      final content = StudentAttendanceWorker.text(soup.body).toLowerCase();
      if (!['no record found', 'रिकॉर्ड उपलब्ध नहीं'].any(content.contains)) {
        throw const AttendanceWorkerError(
          'SHOW_TIMEOUT',
          'Attendance summary grid missing.',
        );
      }
    }
    worker._rememberReadForm(this);
    worker._rememberSummaryNavigation(this, parsed);
    return parsed;
  }

  void checkDate(String? wanted) {
    final actual = soup
        .getElementById(StudentAttendanceWorker.dateId)
        ?.attributes['value'];
    if (wanted == null || wanted.isEmpty || actual == null || actual.isEmpty) {
      return;
    }
    if (StudentAttendanceWorker.validDate(actual) !=
        StudentAttendanceWorker.validDate(wanted)) {
      throw const AttendanceWorkerError(
        'DATE_MISMATCH',
        'Portal attendance date did not match this request.',
      );
    }
  }
}

class StudentAttendanceWorker {
  StudentAttendanceWorker({
    required this.request,
    required this.baseUrl,
    this.observeUrl,
    this.sessionIdentity,
    this.readFormLifetime = const Duration(seconds: 45),
    this.retainSummaryNavigation = false,
    this.summaryNavigationLifetime = const Duration(minutes: 2),
    this.formElapsed,
    this.activityStamp,
    DateTime Function()? indiaNow,
  }) : indiaNow =
           indiaNow ??
           (() => DateTime.now().toUtc().add(
             const Duration(hours: 5, minutes: 30),
           ));

  final bool retainSummaryNavigation;
  final Duration summaryNavigationLifetime;
  // Separate read-navigation tokens from the single latest Entry/save form.
  ({Uri url, String html, String identity, Duration at, String date})?
      _summaryNavigation;

  final Object? Function()? activityStamp;
  ({
    _AttendanceDocument doc,
    Map<String, dynamic> result,
    List<dom.Element> rows,
    Object activity,
  })?
  _entryForm;
  final AttendanceHttpRequest request;
  final Uri Function() baseUrl;
  final Future<void> Function(Uri)? observeUrl;
  final DateTime Function() indiaNow;
  final String Function()? sessionIdentity;
  final Duration readFormLifetime;
  final Duration Function()? formElapsed;
  final Stopwatch _formClock = Stopwatch()..start();
  ({Uri url, dom.Document soup, String identity, Duration at, bool unconsumed})?
  _readForm;
  Duration get _formNow => formElapsed?.call() ?? _formClock.elapsed;
  String? _blockedReadIdentity;
  int _summaryRevision = 0;
  ({int revision, String? date, List<Map<String, dynamic>> classes})?
  _lastSummarySnapshot;
  ({int revision, String? date, List<Map<String, dynamic>> classes})?
  get lastSummarySnapshot => _lastSummarySnapshot;

  void _recordSummarySnapshot(
    String? date,
    List<Map<String, dynamic>> classes,
  ) {
    if (classes.isEmpty) return;
    _lastSummarySnapshot = (
      revision: ++_summaryRevision,
      date: validDate(date),
      classes: List<Map<String, dynamic>>.unmodifiable(
        classes.map((r) => Map<String, dynamic>.unmodifiable(r)),
      ),
    );
  }

  bool get hasFreshSessionForm {
    final cached = _readForm;
    if (cached != null &&
        _freshReadForm(cached.identity, cached.at) &&
        _usableReadForm(cached.url, cached.soup)) {
      return true;
    }
    final live = _entryForm;
    if (live != null &&
        _freshReadForm(live.doc.identity, live.doc.loadedAt) &&
        _usableReadForm(live.doc.url, live.doc.soup)) {
      return true;
    }
    return false;
  }

  /// Merge native MS-Ajax panels and hidden fields into the latest form.
  /// Length parsing is UTF-16 aware; never split deltas on pipe characters.
  static dom.Document mergeResponse(dom.Document? previous, String response) {
    if (!RegExp(r'^\d+\|').hasMatch(response)) return html.parse(response);
    if (previous == null) {
      throw const AttendanceWorkerError(
        'PAGE_NOT_READY',
        'Missing WebForms document for attendance AJAX response.',
      );
    }
    late List<(String, String, String)> records;
    try {
      records = RankingHttp.parseDelta(response);
    } on FormatException {
      throw const AttendanceWorkerError(
        'PORTAL_RESPONSE_ERROR',
        'Incomplete attendance AJAX response.',
      );
    }
    final merged = previous.clone(true);
    for (final script in merged.querySelectorAll(
      'script[data-attendance-response]',
    )) {
      script.remove();
    }
    var updated = false;
    for (final (type, name, value) in records) {
      if (type == 'error') {
        throw AttendanceWorkerError('PORTAL_MESSAGE', value, {
          'portal_message': value,
          'message_source': 'portal',
        });
      }
      if (type == 'pageRedirect') {
        if (_isPublicDefaultRedirect(value)) {
          throw _publicRedirectError(value);
        }
        throw AttendanceWorkerError(
          'SESSION_EXPIRED',
          'School session changed during attendance navigation.',
          {'page_redirect': value},
        );
      }
      if (type == 'updatePanel') {
        final panel = merged.getElementById(name);
        if (panel == null) {
          throw const AttendanceWorkerError(
            'PAGE_NOT_READY',
            'Attendance UpdatePanel missing from the current form.',
          );
        }
        panel.innerHtml = value;
        updated = true;
      } else if (type == 'hiddenField') {
        final matches = merged
            .querySelectorAll('input[name]')
            .where((input) => input.attributes['name'] == name)
            .toList();
        if (matches.isEmpty) {
          final form = merged.querySelector('form');
          if (form == null) {
            throw const AttendanceWorkerError(
              'PAGE_NOT_READY',
              'Attendance form missing from AJAX state.',
            );
          }
          form.append(
            dom.Element.tag('input')
              ..attributes.addAll({
                'type': 'hidden',
                'name': name,
                'id': name,
                'value': value,
              }),
          );
        } else {
          for (final input in matches) {
            input.attributes['value'] = value;
          }
        }
      } else if (type == 'formAction') {
        merged.querySelector('form')?.attributes['action'] = value;
      } else if (type == 'scriptBlock' || type == 'scriptStartupBlock') {
        // Keep native portal alerts available to the existing message parser.
        merged.body?.append(
          dom.Element.tag('script')
            ..attributes['data-attendance-response'] = 'true'
            ..text = value,
        );
      }
    }
    if (!updated) {
      final messages = _portalMessages(merged);
      if (messages.isNotEmpty) {
        final joined = messages.join('\n');
        throw AttendanceWorkerError('PORTAL_MESSAGE', joined, {
          'portal_message': joined,
          'message_source': 'portal',
        });
      }
      throw const AttendanceWorkerError(
        'PAGE_NOT_READY',
        'Attendance AJAX response contains no updated panel.',
      );
    }
    return merged;
  }

  static bool _staleFormText(String message) => [
    'validation of viewstate',
    'invalid postback or callback argument',
    'the state information is invalid',
  ].any(message.toLowerCase().contains);

  static bool _staleFormError(AttendanceWorkerError error) =>
      (error.code == 'PORTAL_RESPONSE_ERROR' ||
          error.code == 'PORTAL_MESSAGE') &&
      (error.extra['form_state_rejected'] == true ||
          _staleFormText(error.message));

  bool _usableReadForm(Uri url, dom.Document soup) {
    final target = baseUrl().resolve('Home/School/$pageName');
    if (url.query.isNotEmpty ||
        url.scheme != target.scheme ||
        url.authority != target.authority ||
        url.path.toLowerCase() != target.path.toLowerCase()) {
      return false;
    }
    final show = soup.getElementById(showId);
    final date = soup.getElementById(dateId);
    if (date == null || date.attributes['name'] == null) return false;
    final navigation = date.attributes.containsKey('disabled')
        ? soup.getElementById(backId)
        : show;
    if (navigation == null || navigation.attributes.containsKey('disabled')) {
      return false;
    }
    final form = AttendanceForm.enclosing(navigation);
    if (form == null || !identical(AttendanceForm.enclosing(date), form)) {
      return false;
    }
    for (final name in ['__VIEWSTATE', '__EVENTVALIDATION']) {
      if (form
              .querySelector('input[name="$name"]')
              ?.attributes['value']
              ?.isNotEmpty !=
          true) {
        return false;
      }
    }
    final action = url.resolve(form.attributes['action'] ?? url.toString());
    return action.query.isEmpty &&
        action.scheme == target.scheme &&
        action.authority == target.authority &&
        action.path.toLowerCase() == target.path.toLowerCase();
  }

  bool _freshReadForm(String identity, Duration at) {
    final current = sessionIdentity?.call() ?? '';
    final age = _formNow - at;
    return current.isNotEmpty &&
        current != _blockedReadIdentity &&
        current == identity &&
        !age.isNegative &&
        age < readFormLifetime;
  }

  Map<String, dynamic>? freshDashboardSummary(String date) {
    final cached = _summaryNavigation;
    if (cached == null || !_freshReadForm(cached.identity, cached.at) ||
        _formNow - cached.at >= const Duration(seconds: 30) ||
        validDate(date) != cached.date) return null;
    final soup = html.parse(cached.html);
    if (!_usableReadForm(cached.url, soup)) return null;
    final parsed = parseClassSummary(soup, date: cached.date);
    if (parsed['found'] != true || (parsed['classes'] as List).isEmpty) return null;
    return {'success': true, ...parsed};
  }

  bool _restoreSummaryNavigation(_AttendanceDocument doc, String? wanted) {
    if (!retainSummaryNavigation || doc.loaded || wanted == null) return false;
    final cached = _summaryNavigation;
    if (cached == null) return false;
    final age = _formNow - cached.at;
    if (!_freshReadForm(cached.identity, cached.at) || age >= summaryNavigationLifetime) {
      _summaryNavigation = null;
      return false;
    }
    if (validDate(wanted) != cached.date) return false;
    final soup = html.parse(cached.html);
    if (!_usableReadForm(cached.url, soup) ||
        soup.getElementById(dateId)?.attributes.containsKey('disabled') == true ||
        soup.getElementById(gridId) == null) {
      _summaryNavigation = null;
      return false;
    }
    final wantedClass = doc.navigationClassId;
    if (wantedClass != null) {
      final parsed = parseClassSummary(soup, date: cached.date);
      final matches = (parsed['classes'] as List).cast<Map<String, dynamic>>()
          .where((row) => _classMatches(row, wantedClass) &&
              (doc.navigationSection == null || doc.navigationSection!.isEmpty ||
               _sectionMatches(row, doc.navigationSection!)));
      // Pending first-Save branches were not established by the live fast-path
      // captures. Preserve the native summary refresh for those classes.
      if (matches.isEmpty || matches.first['done'] != true) return false;
    }
    doc.url = cached.url;
    doc.soup = soup; // Clone: Entry response merging must not mutate the snapshot.
    doc.identity = cached.identity;
    doc.loadedAt = cached.at; // Reuse never extends the original snapshot age.
    doc.loaded = true;
    doc.responseUnconsumed = true;
    doc.restoredSummaryNavigation = true;
    return true;
  }

  void _rememberSummaryNavigation(
    _AttendanceDocument doc, Map<String, dynamic> parsed,
  ) {
    if (!retainSummaryNavigation || !doc.loaded ||
        doc.mode != _PortalPageMode.summary || parsed['found'] != true ||
        (parsed['classes'] as List).isEmpty ||
        !_freshReadForm(doc.identity, doc.loadedAt) ||
        !_usableReadForm(doc.url, doc.soup)) return;
    final date = validDate(parsed['date'] as String?);
    if (date == null) return;
    _summaryNavigation = (url: doc.url, html: doc.soup.outerHtml,
      identity: doc.identity, at: doc.loadedAt, date: date);
  }

  bool _restoreReadForm(_AttendanceDocument doc) {
    // Reuse only the navigation envelope, never its roster or marked status.
    // Each invocation reads a fresh summary (Show or native Back) and roster.
    final cached = _readForm;
    _readForm = null; // Consume once: a rejected form is not silently retried.
    if (doc.loaded &&
        _freshReadForm(doc.identity, doc.loadedAt) &&
        _usableReadForm(doc.url, doc.soup)) {
      return true;
    }
    if (cached == null ||
        !_freshReadForm(cached.identity, cached.at) ||
        !_usableReadForm(cached.url, cached.soup)) {
      return false;
    }
    doc.url = cached.url;
    doc.soup = cached.soup;
    doc.loaded = true;
    doc.identity = cached.identity;
    doc.loadedAt = cached.at;
    doc.responseUnconsumed = cached.unconsumed;
    return true;
  }

  void _rememberReadForm(_AttendanceDocument doc, {bool unconsumed = false}) {
    doc.responseUnconsumed = unconsumed;
    if (doc.loaded &&
        _freshReadForm(doc.identity, doc.loadedAt) &&
        _usableReadForm(doc.url, doc.soup)) {
      _readForm = (
        url: doc.url,
        soup: doc.soup,
        identity: doc.identity,
        at: doc.loadedAt,
        unconsumed: unconsumed,
      );
    } else {
      _readForm = null;
    }
  }

  static const pageName = 'StudentdailyAttendanceStatus_Web_NewVersion.aspx';
  static const gridId = 'ContentPlaceHolder1_grd_Student';
  static const dateId = 'ContentPlaceHolder1_txtdate';
  static const backId = 'ContentPlaceHolder1_btnback';
  static const showId = 'ContentPlaceHolder1_btn_Show';
  static const statuses = StudentAttendanceParity.statuses;

  static String text(dom.Element? element) {
    if (element == null) return '';
    final parts = <String>[];
    void walk(dom.Node node) {
      if (node is dom.Text) {
        final value = node.data.trim();
        if (value.isNotEmpty) parts.add(value);
      } else {
        for (final child in node.nodes) {
          walk(child);
        }
      }
    }

    walk(element);
    return parts.join(' ');
  }

  // A native 28-Oct Class 1 read redirects here while later protected
  // reads still work. This public landing page alone cannot prove expiry.
  static bool _isPublicDefaultRedirect(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        RegExp(
          r'(?:^|/)Public2/Default\.aspx$',
          caseSensitive: false,
        ).hasMatch(uri.path);
  }

  static AttendanceWorkerError _publicRedirectError(String destination) =>
      AttendanceWorkerError(
        'PORTAL_RESPONSE_ERROR',
        'The portal redirected to its public page instead of returning '
            'the requested attendance. This class/date could not be loaded.',
        {
          'page_redirect': destination,
          'attendance_public_redirect': true,
          'session_expiry_confirmed': false,
        },
      );

  static bool isLoginRedirect(Uri url) => RegExp(
    r'(officelogin|login\.aspx|default\.aspx|/public)',
    caseSensitive: false,
  ).hasMatch(url.toString());

  static String? validDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final match = RegExp(r'^\s*(\d{1,2})[/-](\d{1,2})[/-](\d{4})\s*$')
        .firstMatch(value);
    if (match == null ||
        int.parse(match.group(1)!) < 1 ||
        int.parse(match.group(1)!) > 31 ||
        int.parse(match.group(2)!) < 1 ||
        int.parse(match.group(2)!) > 12) {
      throw AttendanceWorkerError(
        'BAD_DATE',
        "Invalid date '$value' (expected DD/MM/YYYY)",
      );
    }
    if (int.parse(match.group(3)!) == 0) {
      throw const AttendanceWorkerError('BAD_DATE', 'Invalid attendance date.');
    }
    try {
      StudentAttendanceParity.normalizeDate(value);
      return '${match.group(1)!.padLeft(2, '0')}/'
          '${match.group(2)!.padLeft(2, '0')}/${match.group(3)}';
    } on AttendanceParityException {
      throw const AttendanceWorkerError('BAD_DATE', 'Invalid attendance date.');
    }
  }

  static int? _toInt(String value) =>
      int.tryParse(RegExp(r'-?\d+').firstMatch(value)?.group(0) ?? '');

  static Map<String, dynamic> submissionFields(Map<String, dynamic> row) {
    final status = '${row['status'] ?? ''}'.trim().toLowerCase();
    final pending = [
      'pending',
      'unmarked',
      'not marked',
      'not_marked',
      'not done',
      'not_done',
    ].any(status.contains);
    final marked = row['done'] == true && !pending;
    return {
      'attendance_status': marked ? 'marked' : 'pending',
      'is_already_marked': marked,
      'attendance_verified': marked,
    };
  }

  static Map<String, dynamic> parseClassSummary(
    dom.Document soup, {
    String? date,
  }) {
    final grid = soup.getElementById(gridId);
    date ??= soup.getElementById(dateId)?.attributes['value'];
    if (grid == null) {
      return {'found': false, 'date': date, 'classes': [], 'totals': null};
    }
    String value(String id) => text(grid.querySelector('[id="$id"]'));
    final classes = <Map<String, dynamic>>[];
    final pattern = RegExp('^${gridId}_hdn_ClassID_(\\d+)\$');
    for (final hidden in grid.querySelectorAll('input[id]')) {
      final match = pattern.firstMatch(hidden.id);
      if (match == null) continue;
      final n = match.group(1)!;
      final link = grid.querySelector('[id="${gridId}_btn_Entry_$n"]');
      final status = value('${gridId}_lblStatus_PA_$n');
      classes.add({
        'rowIndex': int.parse(n),
        'classId': hidden.attributes['value']?.trim() ?? '',
        'section': link?.text.trim() ?? '',
        'total': _toInt(value('${gridId}_lbl_TotStudent_$n')),
        'present': (_toInt(value('${gridId}_lbl_P_Web_$n')) ?? 0) > 0
            ? _toInt(value('${gridId}_lbl_P_Web_$n'))
            : (_toInt(value('${gridId}_lbl_P_App_$n')) ??
                  _toInt(value('${gridId}_lbl_P_Web_$n'))),
        'absent': _toInt(value('${gridId}_lblA_Web_$n')),
        'status': status,
        'done': status.toLowerCase().startsWith('done'),
        'entrySource': value('${gridId}_lblEntry_Source_$n'),
        'entryLinkId': link?.id,
      });
    }
    final totals =
        grid.querySelector('[id="${gridId}_lbl_TotStudent_F"]') == null
        ? null
        : {
            'total': _toInt(value('${gridId}_lbl_TotStudent_F')),
            'present': _toInt(value('${gridId}_lbl_P_Web_F')),
            'absent': _toInt(value('${gridId}_lbl_A_Web_F')),
          };
    return {'found': true, 'date': date, 'classes': classes, 'totals': totals};
  }

  static Map<String, int> _mapColumns(List<String> headers) {
    final result = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      final raw = headers[i].trim();
      final h = raw.toLowerCase();
      final norm = h.replaceAll(RegExp(r'[\s.\-_]'), '');
      final compact = raw.replaceAll(RegExp(r'\s+'), '');
      final dottedSrOrdinal = RegExp(r'^[Ss][Rr]\.[Nn][Oo]\.?$')
          .hasMatch(compact);
      String? key;
      if (h.contains('father') || h.contains('पिता')) {
        key = 'father';
      } else if (h.contains('mother') || h.contains('माता')) {
        key = 'mother';
      } else if (h.contains('name') || h.contains('नाम')) {
        key = 'name';
      } else if (['sno', 'slno'].contains(norm) ||
          (i == 0 && dottedSrOrdinal)) {
        key = 'serial';
      } else if (['srno', 'sr', 'srnumber'].contains(norm) ||
          h.contains('scholar') ||
          h.contains('प्रवेशांक') ||
          norm.contains('एसआर') ||
          h.contains('स्कॉलर')) {
        key = 'sr';
      } else if (h.contains('क्रम')) {
        key = 'serial';
      } else if (h.contains('roll') || h.contains('रोल')) {
        key = 'roll';
      } else if (h.contains('gender') ||
          h.contains('sex') ||
          h.contains('लिंग')) {
        key = 'gender';
      } else if (h.contains('nic') || h.contains('code') || h.contains('कोड')) {
        key = 'nic';
      }
      if (key != null) result.putIfAbsent(key, () => i);
    }
    return result;
  }

  static dom.Element? _nearestTable(dom.Element element) {
    dom.Element? parent = element.parent;
    while (parent != null && parent.localName != 'table') {
      parent = parent.parent;
    }
    return parent;
  }

  static Map<String, dom.Element> _labels(dom.Document soup) {
    final result = <String, dom.Element>{};
    for (final label in soup.querySelectorAll('label[for]')) {
      result.putIfAbsent(label.attributes['for']!, () => label);
    }
    return result;
  }

  static ({Map<String, dynamic> built, List<dom.Element> rows}) studentRows(
    dom.Document soup,
  ) {
    dom.Element? best;
    var rows = <dom.Element>[];
    for (final table in soup.querySelectorAll('table')) {
      if (best != null && _nearestTable(table) == best) continue;
      dom.Element? ancestor = table;
      var popup = false;
      while (ancestor != null) {
        if (ancestor.id == 'divStreamnotmapp_pop') {
          popup = true;
          break;
        }
        ancestor = ancestor.parent;
      }
      if (popup) continue;
      final candidates = table
          .querySelectorAll('tr')
          .where(
            (tr) =>
                _nearestTable(tr) == table &&
                tr.querySelector(
                      'input[type="radio"], input[type="checkbox"]',
                    ) !=
                    null,
          )
          .toList();
      if (candidates.isNotEmpty && candidates.length >= rows.length) {
        best = table;
        rows = candidates;
      }
    }
    if (best == null) {
      throw const AttendanceWorkerError(
        'NO_STUDENT_TABLE',
        'Student attendance table missing.',
      );
    }
    final studentSet = rows.toSet();
    final labels = _labels(soup);
    var headers = <String>[];
    var bestHeaderScore = -1;
    var encounteredStudent = false;
    for (final tr in best.querySelectorAll('tr')) {
      if (_nearestTable(tr) != best) continue;
      if (studentSet.contains(tr)) {
        encounteredStudent = true;
        continue;
      }
      if (encounteredStudent) continue;
      final cells = tr.children
          .where((c) => ['td', 'th'].contains(c.localName))
          .map(text)
          .toList();
      if (cells.length > 1) {
        final mappedCols = _mapColumns(cells);
        final score =
            mappedCols.length +
            (mappedCols.containsKey('name') ? 10 : 0) +
            (mappedCols.containsKey('sr') ? 10 : 0);
        if (headers.isEmpty || score > bestHeaderScore) {
          headers = cells;
          bestHeaderScore = score;
        }
      }
    }
    final columns = _mapColumns(headers);
    final students = <Map<String, dynamic>>[];
    for (var n = 0; n < rows.length; n++) {
      final row = rows[n];
      final cells = row.children
          .where((c) => ['td', 'th'].contains(c.localName))
          .map(text)
          .toList();
      String cell(int? index) =>
          index != null && index >= 0 && index < cells.length
          ? cells[index]
          : '';
      final mapped = columns.containsKey('name');
      final fullName = cell(mapped ? columns['name'] : 1);
      var serial = cell(mapped ? columns['serial'] : 0);
      if (serial.isEmpty) serial = '${n + 1}';
      final tail = RegExp(r'\s*\(([^()]*)\)\s*$').firstMatch(fullName);
      final name = tail == null
          ? fullName.trim()
          : fullName.substring(0, tail.start).trim();
      if (name.isEmpty || cells.length < 2) {
        throw const AttendanceWorkerError(
          'NO_STUDENT_TABLE',
          'Some student rows could not be parsed.',
        );
      }
      var father = cell(mapped ? columns['father'] : 2);
      if (father.isEmpty) father = tail?.group(1)?.trim() ?? '';
      final radios = row.querySelectorAll('input[type="radio"]');
      final index = radios.indexWhere(
        (r) => r.attributes.containsKey('checked'),
      );
      var label = '';
      if (index >= 0) {
        final radio = radios[index];
        final element = radio.id.isEmpty ? null : labels[radio.id];
        label = element == null
            ? radio.attributes['value'] ?? ''
            : text(element);
      }
      final status = StudentAttendanceParity.normalizeStatus(label, index);
      final roll = mapped ? cell(columns['roll']) : '';
      var srVal = cell(mapped ? columns['sr'] : 4);
      if (srVal.isEmpty && !columns.containsKey('sr') && cells.length > 4) {
        srVal = cell(4);
      }
      students.add({
        'serialNo': _toInt(serial) == 0 ? n + 1 : _toInt(serial) ?? n + 1,
        'srNo': srVal,
        'rollNo': roll.isEmpty ? serial : roll,
        'nicCode': mapped ? cell(columns['nic']) : '',
        'name': name,
        'fullName': fullName,
        'fatherName': father,
        'motherName': cell(mapped ? columns['mother'] : 3),
        'gender': mapped ? cell(columns['gender']) : '',
        'status': status,
        'present': status == null ? null : status == 'Present',
      });
    }
    return (
      built: {
        'students': students,
        'columnsMapped':
            columns.containsKey('name') && columns.containsKey('sr'),
      },
      rows: rows,
    );
  }

  static String _sectionKey(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-()\[\]]+'), '');

  static bool _classMatches(Map<String, dynamic> row, String wanted) {
    final cid = _sectionKey('${row['classId'] ?? ''}');
    final section = _sectionKey('${row['section'] ?? ''}');
    final combined = '$cid$section';
    final w = _sectionKey(wanted);
    return cid == w ||
        section == w ||
        combined == w ||
        (int.tryParse(cid) != null && int.tryParse(cid) == int.tryParse(w)) ||
        RegExp(r'^\d+').firstMatch(section)?.group(0) == w;
  }

  static bool _sectionMatches(Map<String, dynamic> row, String wantedSection) {
    final w = _sectionKey(wantedSection);
    if (w.isEmpty) return true;
    final sec = _sectionKey('${row['section'] ?? ''}');
    final cid = _sectionKey('${row['classId'] ?? ''}');
    return sec == w || '$cid$sec' == w;
  }

  Future<({Map<String, dynamic> result, List<dom.Element> rows})> _fetchList(
    _AttendanceDocument doc,
    String classId,
    String? date,
    String? section, {
    bool Function()? shouldContinue,
    bool recordSummary = false,
  }) async {
    final wanted = classId.trim();
    if (wanted.isEmpty) {
      throw const AttendanceWorkerError('BAD_CLASS', 'class_id is required.');
    }
    doc.navigationClassId = classId;
    doc.navigationSection = section;
    var summary = await doc.summary(date);
    final usedSummaryNavigation = doc.restoredSummaryNavigation;
    var classes = (summary['classes'] as List).cast<Map<String, dynamic>>();
    if (recordSummary && !doc.restoredSummaryNavigation && classes.isNotEmpty) {
      _recordSummarySnapshot(summary['date'] as String?, classes);
    }
    if (shouldContinue != null && !shouldContinue()) {
      _rememberReadForm(doc, unconsumed: true);
      throw const AttendanceWorkerError(
        'STALE_ATTENDANCE_READ',
        'Attendance read superseded by a newer class selection.',
      );
    }
    var matches = classes
        .where(
          (r) =>
              _classMatches(r, wanted) &&
              (section == null ||
                  section.isEmpty ||
                  _sectionMatches(r, section)),
        )
        .toList();
    if (matches.isEmpty) {
      _rememberReadForm(doc, unconsumed: true);
      throw AttendanceWorkerError('BAD_CLASS', "Class '$wanted' not listed.", {
        'available': classes
            .map((r) => {'classId': r['classId'], 'section': r['section']})
            .toList(),
      });
    }
    var row = matches.first;
    Map<String, dynamic> currentBase() => <String, dynamic>{
      'success': true,
      'date': summary['date'],
      'classId': row['classId'],
      'section': row['section'],
      'summary': row,
      ...submissionFields(row),
    };
    if (row['total'] == 0) {
      _rememberReadForm(doc, unconsumed: true);
      return (
        result: {
          ...currentBase(),
          'students': <Map<String, dynamic>>[],
          'total': 0,
          'verified': currentBase()['attendance_verified'],
          'data_verified': true,
          'warning': null,
          'columnsMapped': true,
        },
        rows: <dom.Element>[],
      );
    }
    dom.Element? resolveEntryLink() => row['entryLinkId'] == null
        ? null
        : doc.soup.getElementById('${row['entryLinkId']}');
    var link = resolveEntryLink();
    if (link == null) {
      throw const AttendanceWorkerError(
        'NO_ENTRY_LINK',
        'Class entry link missing.',
      );
    }
    try {
      await doc.click(link);
    } on AttendanceWorkerError catch (error) {
      if (!doc.usedRetainedEnvelope || !_staleFormError(error)) rethrow;
      _summaryNavigation = null;
      _blockedReadIdentity = sessionIdentity?.call();
      _readForm = null;
      doc.loaded = false;
      doc.usedRetainedEnvelope = false;
      summary = await doc.summary(date);
      classes = (summary['classes'] as List).cast<Map<String, dynamic>>();
      if (recordSummary && !doc.restoredSummaryNavigation && classes.isNotEmpty) {
        _recordSummarySnapshot(summary['date'] as String?, classes);
      }
      if (shouldContinue != null && !shouldContinue()) {
        _rememberReadForm(doc, unconsumed: true);
        throw const AttendanceWorkerError(
          'STALE_ATTENDANCE_READ',
          'Attendance read superseded by a newer class selection.',
        );
      }
      matches = classes
          .where(
            (r) =>
                _classMatches(r, wanted) &&
                (section == null ||
                    section.isEmpty ||
                    _sectionMatches(r, section)),
          )
          .toList();
      if (matches.isEmpty) {
        throw AttendanceWorkerError(
          'BAD_CLASS',
          "Class '$wanted' not listed.",
          {
            'available': classes
                .map((r) => {'classId': r['classId'], 'section': r['section']})
                .toList(),
          },
        );
      }
      row = matches.first;
      link = resolveEntryLink();
      if (link == null) {
        throw const AttendanceWorkerError(
          'NO_ENTRY_LINK',
          'Class entry link missing.',
        );
      }
      await doc.click(link);
    }
    // A rejected Entry can require a new summary. Build all response metadata
    // from the row that actually authorized the final successful Entry.
    final base = currentBase();
    _readForm = null; // The older summary envelope is now superseded.
    doc.checkDate(summary['date'] as String?);
    final entrySection = text(
      doc.soup.getElementById('ContentPlaceHolder1_lblentrySection'),
    );
    if (entrySection.isNotEmpty &&
        _sectionKey(entrySection) != _sectionKey('${row['section']}') &&
        _sectionKey(entrySection) !=
            _sectionKey('${row['classId']}${row['section']}')) {
      throw const AttendanceWorkerError(
        'MATCH_MISMATCH',
        'Portal student list belongs to a different class/section. Nothing was saved.',
      );
    }
    final rawEntryDate = text(
      doc.soup.getElementById('ContentPlaceHolder1_lbldateofAtt'),
    );
    final entryDateMatch = RegExp(r'(\d{1,2}[/-]\d{1,2}[/-]\d{4})')
        .firstMatch(rawEntryDate);
    final entryDate = entryDateMatch?.group(1) ?? rawEntryDate;
    if (entryDate.isNotEmpty &&
        validDate(entryDate) != validDate(summary['date'] as String?)) {
      throw const AttendanceWorkerError(
        'DATE_MISMATCH',
        'Portal student list belongs to a different attendance date. Nothing was saved.',
      );
    }
    late final ({Map<String, dynamic> built, List<dom.Element> rows}) table;
    try {
      table = studentRows(doc.soup);
    } on AttendanceWorkerError catch (error) {
      if (error.code == 'NO_STUDENT_TABLE') {
        final messages = _portalMessages(doc.soup);
        if (messages.isNotEmpty) {
          final joined = messages.join('\n');
          throw AttendanceWorkerError('PORTAL_MESSAGE', joined, {
            'portal_message': joined,
            'message_source': 'portal',
          });
        }
      }
      rethrow;
    }
    final students = (table.built['students'] as List)
        .cast<Map<String, dynamic>>();
    final counts = {
      for (final status in statuses)
        status: students.where((s) => s['status'] == status).length,
    };
    final portalDate = validDate(summary['date'] as String?);
    final isBackdate =
        portalDate != null &&
        !StudentAttendanceParity.canCorrectMarkedAttendance(
          portalDate: portalDate,
          indiaToday: indiaNow(),
        );
    final warnings = <String>[];
    final identities = students.map(StudentAttendanceParity.identity).toSet();
    if (identities.length != students.length) {
      warnings.add(
        'Portal student list contains duplicate student identities. Refresh before saving.',
      );
    }
    if (!isBackdate) {
      if (row['done'] == true && students.any((s) => s['status'] == null)) {
        warnings.add(
          'Marked attendance contains unselected or unrecognised statuses.',
        );
      }
      if (row['total'] != null && students.length != row['total']) {
        warnings.add('Portal summary and student row counts differ.');
      } else if (row['done'] == true &&
          row['present'] != null &&
          counts['Present'] != row['present']) {
        warnings.add('Portal summary and present count differ.');
      }
    } else {
      if (row['total'] != null && students.length != row['total']) {
        warnings.add('Portal summary and student row counts differ.');
      } else if (row['done'] == true) {
        if (students.isNotEmpty && students.any((s) => s['status'] == null)) {
          warnings.add(
            'Marked attendance contains unselected or unrecognised statuses.',
          );
        } else if (row['present'] != null) {
          final pCount = counts['Present'] ?? 0;
          final lCount = (counts['OnLeave'] ?? 0) + (counts['OnMedical'] ?? 0);
          final summaryPresent = row['present'] as int;
          if (pCount != summaryPresent && (pCount + lCount) != summaryPresent) {
            warnings.add('Portal summary and present count differ.');
          }
        }
      }
    }
    if (table.built['columnsMapped'] != true) {
      warnings.add('Column headers not fully recognised; read by position.');
    }
    int? lead(Object? value) => int.tryParse(
      RegExp(r'^\s*(\d+)').firstMatch('${value ?? ''}')?.group(1) ?? '',
    );
    final numbers =
        classes.map((r) => lead(r['section'])).whereType<int>().toSet().toList()
          ..sort();
    final current = lead(row['section']);
    final verified = base['attendance_verified'] == true && warnings.isEmpty;
    if (usedSummaryNavigation && warnings.isNotEmpty) {
      // External portal changes can make a short-lived summary's totals stale.
      // Refresh once before returning unverified data or preparing a mutation.
      _summaryNavigation = null;
      _readForm = null;
      doc.loaded = false;
      doc.usedRetainedEnvelope = false;
      doc.restoredSummaryNavigation = false;
      return _fetchList(doc, classId, date, section,
        shouldContinue: shouldContinue, recordSummary: recordSummary);
    }
    _rememberReadForm(doc); // Retain only the latest validated navigation form.
    return (
      result: {
        ...base,
        'students': students,
        'total': students.length,
        'presentCount': counts['Present'],
        'absentCount': counts['Absent'],
        'leaveCount': counts['OnLeave'],
        'medicalCount': counts['OnMedical'],
        'classes': numbers.map((n) => 'Class $n').toList(),
        'sections': classes
            .where((r) => current != null && lead(r['section']) == current)
            .map((r) => r['section'])
            .toList(),
        'data_verified': warnings.isEmpty,
        'verified': verified,
        'attendance_verified': verified,
        'warning': warnings.isEmpty ? null : warnings.join(' '),
        'columnsMapped': table.built['columnsMapped'],
      },
      rows: table.rows,
    );
  }

  void _rememberEntry(
    _AttendanceDocument doc,
    Map<String, dynamic> result,
    List<dom.Element> rows,
  ) {
    _entryForm = null;
    final stamp = activityStamp?.call();
    if (stamp == null ||
        !doc.loaded ||
        result['data_verified'] != true ||
        rows.isEmpty ||
        !_freshReadForm(doc.identity, doc.loadedAt) ||
        !_usableReadForm(doc.url, doc.soup) ||
        doc.soup.getElementById('ContentPlaceHolder1_upPnl') == null ||
        _saveButton(doc.soup)?.id != 'ContentPlaceHolder1_btnsubmit' ||
        text(doc.soup.getElementById('ContentPlaceHolder1_lblentrySection'))
            .isEmpty ||
        text(doc.soup.getElementById('ContentPlaceHolder1_lbldateofAtt'))
            .isEmpty) {
      return;
    }
    final profiles = <String>{};
    for (final row in rows) {
      final profile = row
          .querySelector(r'input[name$="hdn_StudentProfileId"]')
          ?.attributes['value'];
      if (profile == null || profile.isEmpty || !profiles.add(profile)) return;
    }
    _entryForm = (
      doc: doc,
      result: {
        ...result,
        'summary': Map<String, dynamic>.unmodifiable(result['summary'] as Map),
        'students': List<Map<String, dynamic>>.unmodifiable(
          (result['students'] as List).map(
            (s) => Map<String, dynamic>.unmodifiable(s as Map),
          ),
        ),
      },
      rows: rows,
      activity: stamp,
    );
  }

  static List<String> _portalMessages(dom.Document soup) {
    final messages = SchoolPortalMessages.fromDocument(soup);
    final modal = RegExp(
      r'''(?<![\w.])openModal\s*\(\s*(['"])((?:\\.|(?!\1).)*?)\1\s*\)''',
      dotAll: true,
    );
    for (final script in soup.querySelectorAll('script')) {
      for (final match in modal.allMatches(script.text)) {
        for (final message in SchoolPortalMessages.parse(
          '<script>alert(${match.group(1)}${match.group(2)}${match.group(1)});</script>',
        )) {
          if (!messages.contains(message)) messages.add(message);
        }
      }
    }
    return messages;
  }

  static Map<String, dynamic> failure(Object error) {
    if (error is AttendanceWorkerError) return error.asResult();
    if (error is AttendanceParityException) {
      return {'success': false, 'code': error.code, 'message': error.message};
    }
    if (error is TimeoutException) {
      return {
        'success': false,
        'code': 'PORTAL_SLOW',
        'message': 'Portal request timed out.',
      };
    }
    return {
      'success': false,
      'code': 'UNEXPECTED',
      'message': error.toString(),
    };
  }

  Future<Map<String, dynamic>> fetchClassSummary({
    String? attendanceDate,
  }) async {
    try {
      final doc = _AttendanceDocument(this);
      final parsed = await doc.summary(validDate(attendanceDate));
      final classes = (parsed['classes'] as List).cast<Map<String, dynamic>>();
      if (classes.isNotEmpty) {
        _recordSummarySnapshot(parsed['date'] as String?, classes);
        _rememberReadForm(doc, unconsumed: true);
      }
      return {
        'success': true,
        ...parsed,
        'message': (parsed['classes'] as List).isEmpty
            ? 'No class attendance rows found for this date.'
            : '',
      };
    } catch (error) {
      _readForm = null;
      return failure(error);
    }
  }

  Future<Map<String, dynamic>> _verifyAttendanceReadRedirect(
    AttendanceWorkerError error, {
    bool Function()? shouldContinue,
  }) async {
    _readForm = null;
    _summaryNavigation = null;
    _entryForm = null;
    Map<String, dynamic> failed() => {...error.asResult(), 'students': []};
    if (shouldContinue != null && !shouldContinue()) {
      return {
        ...failure(const AttendanceWorkerError(
          'STALE_ATTENDANCE_READ',
          'Attendance read superseded by a newer class selection.',
        )),
        'students': [],
      };
    }
    final originalIdentity = sessionIdentity?.call() ?? '';
    final check = _AttendanceDocument(this);
    try {
      // One protected GET verifies the session, without following the public
      // destination, repeating the failing class, or dispatching any Save.
      await PortalDiagnostics.measure(
        PortalPhase.sessionProbe,
        () => check.request(baseUrl().resolve('Home/School/$pageName')),
      );
      if ((sessionIdentity?.call() ?? '') != originalIdentity) {
        return {
          ...failure(const AttendanceWorkerError(
            'ACCOUNT_CHANGED',
            'School session changed. Fetch the data again.',
          )),
          'students': [],
        };
      }
      if (_usableReadForm(check.url, check.soup)) {
        _rememberReadForm(check, unconsumed: true);
        if (shouldContinue != null && !shouldContinue()) {
          return {
            ...failure(const AttendanceWorkerError(
              'STALE_ATTENDANCE_READ',
              'Attendance read superseded by a newer class selection.',
            )),
            'students': [],
          };
        }
        return {
          ...failed(),
          'portal_session_alive': true,
          'message': '${error.message} The school session is still active; '
              'you can open another class or date.',
        };
      }
    } on AttendanceWorkerError catch (checkError) {
      if (checkError.code == 'SESSION_EXPIRED') {
        return {...checkError.asResult(), 'students': []};
      }
    } catch (_) {
      // An unavailable verification read proves neither alive nor expired.
    }
    return failed();
  }

  Future<Map<String, dynamic>> fetchStudentAttendanceList({
    required String classId,
    String? attendanceDate,
    String? section,
    bool Function()? shouldContinue,
  }) async {
    try {
      final doc = _AttendanceDocument(this, allowSummaryNavigation: true);
      final fetched = await _fetchList(
        doc,
        classId,
        validDate(attendanceDate),
        section,
        shouldContinue: shouldContinue,
        recordSummary: true,
      );
      _rememberEntry(doc, fetched.result, fetched.rows);
      return fetched.result;
    } catch (error) {
      if (error is AttendanceWorkerError &&
          error.extra['attendance_public_redirect'] == true) {
        return _verifyAttendanceReadRedirect(
          error,
          shouldContinue: shouldContinue,
        );
      }
      if (error is! AttendanceWorkerError ||
          (error.code != 'STALE_ATTENDANCE_READ' &&
              error.code != 'BAD_CLASS')) {
        _readForm = null;
        _summaryNavigation = null;
      }
      return {...failure(error), 'students': []};
    }
  }

  static ({
    List<Map<String, dynamic>> expected,
    Map<String, Object?> overrides,
    int changed,
  })
  applyUpdates(
    Map<String, dynamic> result,
    List<dom.Element> portalRows,
    List<Map<String, Object?>> requested,
    dom.Document soup,
  ) {
    if (requested.isEmpty || requested.length != portalRows.length) {
      throw const AttendanceWorkerError(
        'MATCH_MISMATCH',
        'Submitted students do not match all portal rows. Nothing was saved.',
      );
    }
    final updates = <String, Map<String, Object?>>{};
    for (final student in requested) {
      final key = StudentAttendanceParity.identity(student);
      final status = StudentAttendanceParity.requestedStatus(student);
      if (updates.containsKey(key)) {
        throw const AttendanceWorkerError(
          'MATCH_MISMATCH',
          'Invalid status or duplicate student. Nothing was saved.',
        );
      }
      updates[key] = {...student, 'status': status};
    }
    final expected = <Map<String, dynamic>>[];
    final overrides = <String, Object?>{};
    final seen = <String>{};
    var changed = 0;
    final current = (result['students'] as List).cast<Map<String, dynamic>>();
    final labels = _labels(soup);
    for (var i = 0; i < current.length; i++) {
      final key = StudentAttendanceParity.identity(current[i]);
      final update = updates[key];
      if (update == null || !seen.add(key)) {
        throw const AttendanceWorkerError(
          'MATCH_MISMATCH',
          'Student identity mismatch. Nothing was saved.',
        );
      }
      final radios = portalRows[i].querySelectorAll('input[type="radio"]');
      dom.Element? target;
      for (var index = 0; index < radios.length; index++) {
        final radio = radios[index];
        final label = radio.id.isEmpty ? null : labels[radio.id];
        if (StudentAttendanceParity.normalizeStatus(text(label), index) ==
            update['status']) {
          target = radio;
          break;
        }
      }
      if (target == null ||
          target.attributes['name'] == null ||
          target.attributes.containsKey('disabled')) {
        throw const AttendanceWorkerError(
          'RADIO_FAILED',
          'Attendance radio control missing or disabled.',
        );
      }
      final name = target.attributes['name']!;
      if (overrides.containsKey(name)) {
        throw const AttendanceWorkerError(
          'RADIO_FAILED',
          'Duplicate attendance radio group.',
        );
      }
      overrides[name] = target.attributes['value'] ?? 'on';
      if (current[i]['status'] != update['status']) changed++;
      expected.add({...current[i], 'status': update['status']});
    }
    return (expected: expected, overrides: overrides, changed: changed);
  }

  static bool savedStudentsMatch(
    List<Map<String, Object?>> expected,
    List<Map<String, Object?>> actual,
  ) {
    if (expected.isEmpty) return false;
    try {
      final plan = StudentAttendanceParity.plan(
        current: expected,
        requested: expected,
      );
      return StudentAttendanceParity.readBackMatches(plan, actual);
    } on AttendanceParityException {
      return false;
    }
  }

  static dom.Element? _saveButton(dom.Document soup) {
    for (final id in [
      'ContentPlaceHolder1_btnsubmit',
      'ContentPlaceHolder1_btnSave',
      'ContentPlaceHolder1_btn_Save',
      'ContentPlaceHolder1_btnSubmit',
      'ContentPlaceHolder1_btn_Submit',
      'ContentPlaceHolder1_btnAttendanceSubmit',
      'ContentPlaceHolder1_btnVerify',
    ]) {
      final button = soup.getElementById(id);
      if (button != null) return button;
    }
    for (final candidate in soup.querySelectorAll(
      'input[type="submit"], input[type="button"], button',
    )) {
      final label =
          '${candidate.attributes['value'] ?? ''} ${text(candidate)} ${candidate.id}'
              .toLowerCase();
      if (!label.contains('back') &&
          !label.contains('btn_show') &&
          ['save', 'submit', 'सुरक्षित', 'दर्ज'].any(label.contains)) {
        return candidate;
      }
    }
    return null;
  }

  bool _submitReturnedDoneSummary(
    _AttendanceDocument doc,
    Map<String, dynamic> result,
  ) {
    if (!doc.loaded ||
        doc.mode != _PortalPageMode.summary ||
        !_usableReadForm(doc.url, doc.soup)) {
      return false;
    }
    final wantedDate = validDate(result['date'] as String?);
    final fieldDate = doc.soup.getElementById(dateId)?.attributes['value'];
    try {
      if (wantedDate == null || validDate(fieldDate) != wantedDate) {
        return false;
      }
    } on AttendanceWorkerError {
      return false;
    }
    final parsed = parseClassSummary(doc.soup, date: wantedDate);
    if (parsed['found'] != true ||
        validDate(parsed['date'] as String?) != wantedDate) {
      return false;
    }
    final classes = (parsed['classes'] as List).cast<Map<String, dynamic>>();
    final wantedClass = '${result['classId'] ?? ''}'.trim();
    final wantedSection = '${result['section'] ?? ''}'.trim();
    final matches = classes
        .where(
          (r) =>
              _classMatches(r, wantedClass) &&
              (wantedSection.isEmpty || _sectionMatches(r, wantedSection)),
        )
        .toList();
    return matches.isNotEmpty &&
        submissionFields(matches.first)['attendance_verified'] == true;
  }

  bool _liveEntryMatches(String classId, String? date, String? section) {
    final live = _entryForm;
    return live != null &&
        live.activity == activityStamp?.call() &&
        _freshReadForm(live.doc.identity, live.doc.loadedAt) &&
        _usableReadForm(live.doc.url, live.doc.soup) &&
        _classMatches(
          live.result['summary'] as Map<String, dynamic>,
          classId,
        ) &&
        validDate(live.result['date'] as String?) == validDate(date) &&
        (section == null ||
            section.isEmpty ||
            _sectionMatches(
              live.result['summary'] as Map<String, dynamic>,
              section,
            ));
  }

  /// Read-only preparation while the user reviews the confirmation sheet.
  /// Save still rechecks the envelope and all roster identities before dispatch.
  Future<void> prepareStudentAttendanceSave({
    required String classId,
    String? attendanceDate,
    String? section,
  }) async {
    if (_liveEntryMatches(classId, attendanceDate, section)) return;
    final doc = _AttendanceDocument(this, allowSummaryNavigation: true);
    final fetched = await _fetchList(doc, classId, attendanceDate, section);
    _rememberEntry(doc, fetched.result, fetched.rows);
  }

  Future<Map<String, dynamic>> saveStudentAttendance({
    required String classId,
    required List<Map<String, Object?>> students,
    String? attendanceDate,
    String? section,
    required bool userConfirmed,
  }) async {
    if (!userConfirmed) {
      return {
        'success': false,
        'code': 'CONFIRM_REQUIRED',
        'message': 'User confirmation required',
        'submission_attempted': false,
      };
    }
    final dispatch = MutationDispatch.current ?? MutationDispatch();
    var portalMessages = <String>[];
    try {
      final date = validDate(attendanceDate);
      var doc = _AttendanceDocument(this);
      final live = _entryForm;
      _entryForm = null; // Single use, including failures before dispatch.
      ({Map<String, dynamic> result, List<dom.Element> rows})? reusable;
      if (live != null &&
          live.activity == activityStamp?.call() &&
          _freshReadForm(live.doc.identity, live.doc.loadedAt) &&
          _usableReadForm(live.doc.url, live.doc.soup) &&
          _classMatches(
            live.result['summary'] as Map<String, dynamic>,
            classId,
          ) &&
          validDate(live.result['date'] as String?) == date &&
          (section == null ||
              section.isEmpty ||
              _sectionMatches(
                live.result['summary'] as Map<String, dynamic>,
                section,
              )) &&
          !(live.result['is_already_marked'] == true &&
              savedStudentsMatch(
                students,
                (live.result['students'] as List).cast<Map<String, Object?>>(),
              ))) {
        doc = live.doc;
        reusable = (result: live.result, rows: live.rows);
      }
      final ({Map<String, dynamic> result, List<dom.Element> rows}) fetched =
          reusable ??
          await PortalDiagnostics.measure(
            PortalPhase.studentPreflight,
            () => _fetchList(doc, classId, date, section),
          );
      final result = fetched.result;
      if (result['data_verified'] != true) {
        throw const AttendanceWorkerError(
          'MATCH_MISMATCH',
          'Portal student data could not be verified. Nothing was saved.',
        );
      }
      final updates = applyUpdates(result, fetched.rows, students, doc.soup);
      final wasMarked = result['is_already_marked'] == true;
      Map<String, dynamic> success(
        Map<String, dynamic> confirmation, {
        required bool unchanged,
      }) => {
        'success': true,
        'message': portalMessages.isNotEmpty
            ? portalMessages.join('\n')
            : unchanged
            ? 'Attendance already matches the portal. No changes submitted.'
            : wasMarked
            ? 'Student attendance updated and verified on Shala Darpan portal.'
            : 'Student attendance saved and verified on Shala Darpan portal.',
        'classId': result['classId'],
        'date': confirmation['date'],
        'section': confirmation['section'],
        'attendance_status': 'marked',
        'is_already_marked': true,
        'attendance_verified': true,
        'verified': true,
        'summary': confirmation['summary'],
        'verified_students': confirmation['students'],
        'updatedCount': unchanged ? 0 : updates.changed,
        'portalMessages': portalMessages,
        if (portalMessages.isNotEmpty) ...{
          'portal_message': portalMessages.join('\n'),
          'message_source': 'portal',
        },
        'submission_attempted': !unchanged,
        'action': unchanged
            ? 'unchanged'
            : wasMarked
            ? 'updated'
            : 'marked',
      };
      if (wasMarked) {
        if (updates.changed == 0) {
          if (!savedStudentsMatch(
            updates.expected,
            (result['students'] as List).cast<Map<String, Object?>>(),
          )) {
            throw const AttendanceWorkerError(
              'MATCH_MISMATCH',
              'Existing attendance could not be matched. Nothing was submitted.',
            );
          }
          return success(result, unchanged: true);
        }
        final portalDate = validDate(result['date'] as String?);
        if (portalDate == null ||
            !StudentAttendanceParity.canCorrectMarkedAttendance(
              portalDate: portalDate,
              indiaToday: indiaNow(),
            )) {
          throw const AttendanceWorkerError(
            'ALREADY_MARKED',
            'Attendance is already marked for this date. Updates are allowed only on the same day. Nothing was submitted.',
          );
        }
      }
      final button = _saveButton(doc.soup);
      if (button == null) {
        throw const AttendanceWorkerError(
          'NO_SAVE_BUTTON',
          'Attendance Save/Submit control missing.',
        );
      }
      if (AttendanceForm.enclosing(button) == null ||
          button.attributes.containsKey('disabled')) {
        throw const AttendanceWorkerError(
          'NO_SAVE_BUTTON',
          'Save form missing or disabled.',
        );
      }
      final beforeMessages = _portalMessages(doc.soup).toSet();
      _readForm = null; // Never carry a pre-SAVE form into verification.
      // Once this starts, neither this worker nor the transport replays it.
      await dispatch.run(
        () => PortalDiagnostics.measure(
          PortalPhase.studentSubmit,
          () => doc.click(button, overrides: updates.overrides, mutation: true),
        ),
      );
      portalMessages = _portalMessages(doc.soup)
          .where((message) => !beforeMessages.contains(message))
          .toList();
      // A successful-looking SAVE response only confirms submission. Never
      // use its summary as proof; verification must perform a fresh portal read.
      doc.responseUnconsumed = false;
      for (var attempt = 0; attempt < 2; attempt++) {
        final fresh = await PortalDiagnostics.measure(
          PortalPhase.studentVerify,
          () => _fetchList(
            doc,
            '${result['classId']}',
            result['date'] as String?,
            result['section'] as String?,
          ),
        );
        if (fresh.result['attendance_verified'] == true &&
            savedStudentsMatch(
              updates.expected,
              (fresh.result['students'] as List).cast<Map<String, Object?>>(),
            )) {
          _rememberEntry(doc, fresh.result, fresh.rows);
          return success(fresh.result, unchanged: false);
        }
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      _readForm = null;
      _summaryNavigation = null;
      return {
        'success': false,
        'code': 'SAVE_UNCONFIRMED',
        'message': portalMessages.isNotEmpty ? portalMessages.join('\n') : 'Save was submitted but not verified. Refresh before submitting again.',
        if (portalMessages.isNotEmpty) ...{
          'portal_message': portalMessages.join('\n'),
          'portalMessages': portalMessages,
          'message_source': 'portal',
          'verification_message': 'Save was submitted but not verified. Refresh before submitting again.',
        },
        'attendance_verified': false,
        'submission_attempted': true,
      };
    } catch (error) {
      _readForm = null;
      _summaryNavigation = null;
      if (dispatch.mayHaveStarted) {
        return {
          'success': false,
          'code': 'SAVE_UNCONFIRMED',
          'message': portalMessages.isNotEmpty ? portalMessages.join('\n') : 'Submission outcome is uncertain. Refresh before submitting again.',
          if (portalMessages.isNotEmpty) ...{
            'portal_message': portalMessages.join('\n'),
            'portalMessages': portalMessages,
            'message_source': 'portal',
            'verification_message': 'Submission outcome is uncertain. Refresh before submitting again.',
          },
          'attendance_verified': false,
          'submission_attempted': true,
          'detail': error.toString(),
          if (error is AttendanceWorkerError) 'failure_code': error.code,
          if (portalMessages.isEmpty &&
              error is AttendanceWorkerError &&
              error.code == 'PORTAL_RESPONSE_ERROR')
            'portal_message': error.message,
        };
      }
      return {...failure(error), 'submission_attempted': false};
    }
  }
}
