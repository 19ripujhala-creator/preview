/// ShalaDarpan Format-5 Student Profiles. Isolated native HTTP/WebForms worker.
/// Only the controls verified in the portal captures are used. A Save is sent
/// at most once; an ambiguous POST result is never automatically replayed.
import 'dart:async';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'ranking_http.dart';
import 'portal_messages.dart';
import 'student_attendance_worker.dart';

typedef Format5Request = Future<AttendanceHttpReply> Function(
  Uri url, {
  Map<String, Object?>? fields,
  Uri? referer,
  bool mutation,
  Duration timeout,
});

class Format5Error implements Exception {
  const Format5Error(this.code, this.message, {this.attempted = false});
  final String code, message;
  final bool attempted;
  @override
  String toString() => message;
}

class Format5Worker {
  Format5Worker({
    required this.request,
    required this.baseUrl,
    required this.schoolId,
    required this.sessionIdentity,
    required this.check,
    this.now = DateTime.now,
  });

  final Format5Request request;
  final Uri Function() baseUrl;
  final String Function() schoolId, sessionIdentity;
  final void Function() check;
  final DateTime Function() now;
  DateTime? _editPreparedAt;

  static const path = 'Home/School/SchoolStudentProfiles_New.aspx';
  static const sessionId = 'ddlSession';
  static const classId = 'ContentPlaceHolder1_ddlClass';
  static const sectionId = 'ContentPlaceHolder1_ddlSection';
  static const showId = 'ContentPlaceHolder1_btnSearch';
  static const gridId = 'ContentPlaceHolder1_grdStudentProfile';

  dom.Document? _document;
  Uri? _url;
  String? _owner;
  String? _identity;
  String _session = '', _class = '', _section = '';
  String? _editingNic;
  bool _saveInFlight = false;
  bool _saveAttempted = false;

  static Map<String, dynamic> fail(Format5Error error) => {
    'success': false,
    'code': error.code,
    'message': error.message,
    'submission_attempted': error.attempted,
  };

  void _guard() {
    check();
    final owner = schoolId().trim();
    final identity = sessionIdentity();
    if (owner.isEmpty || identity.isEmpty) {
      throw const Format5Error('SESSION_EXPIRED', 'School session expired.');
    }
    if (_owner != null && (_owner != owner || _identity != identity)) {
      _document = null;
      _editingNic = null;
      throw const Format5Error('SESSION_CHANGED', 'School session changed. Reopen Format 5.');
    }
    _owner ??= owner;
    _identity ??= identity;
  }

  Uri get _endpoint {
    final base = baseUrl();
    if (base.scheme != 'https' ||
        base.host.toLowerCase() != 'rajshaladarpan.rajasthan.gov.in' ||
        !RegExp(r'^/SD[1-5]/?$').hasMatch(base.path) ||
        base.hasQuery ||
        base.hasFragment) {
      throw const Format5Error('PAGE_NOT_READY', 'Invalid active School portal URL.');
    }
    return base.resolve(path);
  }

  static List<Map<String, String>> options(dom.Element? select) {
    if (select == null) return [];
    return [
      for (final o in select.querySelectorAll('option'))
        if ((o.attributes['value'] ?? o.text).trim().isNotEmpty &&
            !o.attributes.containsKey('disabled'))
          {'id': o.attributes['value'] ?? o.text, 'label': o.text.trim()},
    ];
  }

  static String selected(dom.Element? select) {
    if (select == null) return '';
    final values = select.querySelectorAll('option');
    final o = values.where((e) => e.attributes.containsKey('selected'));
    final choice = o.isNotEmpty ? o.last : (values.isEmpty ? null : values.first);
    return choice?.attributes['value'] ?? choice?.text ?? '';
  }

  static void select(dom.Document doc, String id, String choice) {
    final node = doc.getElementById(id);
    if (node == null || !options(node).any((o) => o['id'] == choice)) {
      throw Format5Error('INVALID_SELECTION', 'Portal does not offer the selected $id.');
    }
    for (final o in node.querySelectorAll('option')) {
      o.attributes.remove('selected');
      if (o.attributes['value'] == choice) o.attributes['selected'] = 'selected';
    }
  }

  static dom.Document merge(dom.Document? old, String response) {
    if (!RegExp(r'^\d+\|').hasMatch(response)) return html.parse(response);
    if (old == null) {
      throw const Format5Error('PAGE_NOT_READY', 'Missing WebForms state for an AJAX response.');
    }
    final merged = html.parse(old.outerHtml);
    final records = RankingHttp.parseDelta(response);
    bool panel = false;
    for (final record in records) {
      final (type, name, value) = record;
      if (type == 'error') throw Format5Error('PORTAL_MESSAGE', value);
      if (type == 'pageRedirect') {
        throw const Format5Error('SESSION_EXPIRED', 'School session expired.');
      }
      if (type == 'updatePanel') {
        final el = merged.getElementById(name);
        if (el == null) {
          throw const Format5Error('PAGE_NOT_READY', 'Portal UpdatePanel not found.');
        }
        el.innerHtml = value;
        panel = true;
      } else if (type == 'hiddenField') {
        final values = merged.querySelectorAll('input[name]');
        final matching = values.where((e) => e.attributes['name'] == name);
        if (matching.isEmpty) {
          // A new hidden field can appear after a postback.
          merged.querySelector('form')?.append(dom.Element.tag('input')
            ..attributes.addAll({'type': 'hidden', 'name': name, 'id': name, 'value': value}));
        } else {
          for (final el in matching) el.attributes['value'] = value;
        }
      }
    }
    if (!panel) {
      throw const Format5Error('PAGE_NOT_READY', 'Incomplete ASP.NET AJAX response.');
    }
    return merged;
  }

  static String _text(dom.Element? el) => el?.text.trim() ?? '';
  static String _cell(dom.Element row, String fragment) => _text(
    row.querySelector('[id*="grdStudentProfile_${fragment}_"]'),
  );

  static String _value(dom.Element? el) =>
      el?.attributes['value'] ?? el?.text.trim() ?? '';

  static List<Map<String, dynamic>> students(dom.Document doc) {
    final grid = doc.getElementById(gridId);
    if (grid == null) return [];
    final found = <Map<String, dynamic>>[];
    for (final row in grid.querySelectorAll('tr')) {
      final buttons = row.querySelectorAll('[id*="grdStudentProfile_btnEdit_"], [id*="grdStudentProfile_btnUpdate_"]');
      if (buttons.isEmpty) continue;
      final action = buttons.first;
      final id = action.id;
      final match = RegExp(r'_(\d+)$').firstMatch(id);
      if (match == null) continue;
      final index = int.parse(match[1]!);
      String value(String label) => _cell(row, label).isNotEmpty
          ? _cell(row, label)
          : _value(doc.getElementById('ContentPlaceHolder1_grdStudentProfile_${label}_$index'));
      final nic = value('lblSnicid').isNotEmpty ? value('lblSnicid') : value('txtSnicid_Edit');
      if (nic.isEmpty) continue;
      found.add({
        'index': index,
        'nic_id': nic,
        'sr_no': value('lblSRNO').isNotEmpty ? value('lblSRNO') : value('txtSRNO_Edit'),
        'name': value('lblName').isNotEmpty ? value('lblName') : value('txtName_Edit'),
        'father': value('lblFatherName').isNotEmpty ? value('lblFatherName') : value('txtFatherName_Edit'),
        'mother': value('lblMotherName').isNotEmpty ? value('lblMotherName') : value('txtMotherName_Edit'),
        'gender': value('lblGender').isNotEmpty ? value('lblGender') : value('ddlGender_Edit'),
        'dob': value('lblDOB').isNotEmpty ? value('lblDOB') : value('txtDOB_Edit'),
        'category': value('lblCategory').isNotEmpty ? value('lblCategory') : value('ddlCategory_Edit'),
        'mobile': value('lblMobile').isNotEmpty ? value('lblMobile') : value('txtMobile_edit'),
        'oosc': value('lblOosc').isNotEmpty ? value('lblOosc') : value('txtOosc_Edit'),
        'editing': id.contains('btnUpdate'),
      });
    }
    return found;
  }

  static Map<String, Object?> _payload(dom.Document doc, dom.Element button, {bool includeDisabled = false}) {
    final form = AttendanceForm.enclosing(button);
    if (form == null) {
      throw const Format5Error('PAGE_NOT_READY', 'Format-5 form is unavailable.');
    }
    final fields = AttendanceForm.payload(form, button);
    if (includeDisabled) {
      // Captured portal Save includes the row's disabled identity fields. They
      // must be carried unchanged, never exposed as editable app inputs.
      for (final field in form.querySelectorAll('input[name][disabled],select[name][disabled]')) {
        if (!field.id.contains('grdStudentProfile_')) continue;
        final name = field.attributes['name']!;
        fields[name] = field.localName == 'select' ? selected(field) : _value(field);
      }
    }
    if (fields['__VIEWSTATE'] is! String || fields['__EVENTVALIDATION'] is! String) {
      throw const Format5Error('PAGE_NOT_READY', 'Portal form state is missing.');
    }
    return fields;
  }

  Future<void> _send({Map<String, Object?>? payload, bool mutation = false,
      bool freshOpen = false}) async {
    _guard();
    _editPreparedAt = null;
    final endpoint = _endpoint;
    final reply = await request(
      endpoint,
      fields: payload,
      referer: payload == null ? null : (_url ?? endpoint),
      mutation: mutation,
      timeout: Duration(seconds: mutation ? 45 : 30),
    );
    // Only a new read-only page may adopt a renewed same-school session.
    // Stateful posts (especially Update) retain the strict identity guard.
    if (freshOpen && payload == null && !mutation) {
      check();
      if (schoolId().trim() != _owner || sessionIdentity().isEmpty) { _guard(); }
    } else {
      _guard();
    }
    if (reply.status != 200 ||
        reply.url.scheme != endpoint.scheme ||
        reply.url.authority != endpoint.authority ||
        reply.url.path.toLowerCase() != endpoint.path.toLowerCase()) {
      throw Format5Error(
        mutation ? 'SAVE_UNCONFIRMED' : 'PAGE_NOT_READY',
        mutation ? 'Portal update response could not be verified.' : 'Format-5 portal page was not returned.',
        attempted: mutation,
      );
    }
    if (reply.html.contains('Server Error in') || reply.html.contains('Validation of viewstate')) {
      throw Format5Error('PORTAL_MESSAGE', 'Portal rejected the WebForms state.', attempted: mutation);
    }
    try {
      _document = merge(_document, reply.html);
    } on FormatException {
      throw Format5Error('PAGE_NOT_READY', 'Portal returned an invalid AJAX response.', attempted: mutation);
    }
    _url = endpoint;
    if (_document?.getElementById(classId) == null) {
      throw Format5Error('PAGE_NOT_READY', 'Format-5 class selector missing.', attempted: mutation);
    }
    if (freshOpen) { _identity = sessionIdentity(); }
  }

  Map<String, dynamic> _snapshot() {
    final doc = _document!;
    return {
      'success': true,
      'school_id': _owner,
      'sessions': options(doc.getElementById(sessionId)),
      'classes': options(doc.getElementById(classId)),
      'sections': options(doc.getElementById(sectionId)),
      'session': selected(doc.getElementById(sessionId)),
      'class_id': selected(doc.getElementById(classId)),
      'section': selected(doc.getElementById(sectionId)),
      'students': students(doc),
    };
  }

  Future<Map<String, dynamic>> open() async {
    if (_saveInFlight) { throw const Format5Error('BUSY', 'An update is already in progress.'); }
    check();
    final owner = schoolId().trim();
    final identity = sessionIdentity();
    if (owner.isEmpty || identity.isEmpty) {
      throw const Format5Error('SESSION_EXPIRED', 'School session expired.');
    }
    // Reopening is an explicit fresh read, not reuse of the previous form.
    // A worker must never transfer to a different school.
    if (_owner != null && _owner != owner) {
      _guard();
    }
    _owner = owner;
    _identity = identity;
    _document = null;
    _url = null;
    _editingNic = null;
    _editPreparedAt = null;
    _session = _class = _section = '';
    await _send(freshOpen: true);
    _saveAttempted = false;
    return _snapshot();
  }

  Future<Map<String, dynamic>> list(String session, String klass, String section) async {
    _guard();
    // Show can preserve the grid's EditIndex. Discard unsaved edit state
    // through a clean GET before rebuilding the list with fresh form tokens.
    if (_document == null ||
        students(_document!).any((row) => row['editing'] == true)) {
      _document = null;
      await _send();
    }
    _editingNic = null;
    final doc = _document!;
    select(doc, sessionId, session);
    select(doc, classId, klass);
    select(doc, sectionId, section);
    final button = doc.getElementById(showId);
    if (button == null) throw const Format5Error('PAGE_NOT_READY', 'Portal Show control missing.');
    final fields = _payload(doc, button);
    // Non-AJAX form POST for Show: the original full page form is supported.
    await _send(payload: fields);
    if (selected(_document!.getElementById(sessionId)) != session ||
        selected(_document!.getElementById(classId)) != klass ||
        selected(_document!.getElementById(sectionId)) != section) {
      throw const Format5Error('MATCH_MISMATCH', 'Portal returned a different class/section.');
    }
    _session = session;
    _class = klass;
    _section = section;
    return _snapshot();
  }

  static dom.Element _rowButton(dom.Document doc, String nic, String action) {
    for (final row in students(doc)) {
      if (row['nic_id'] == nic && row['editing'] == (action == 'btnUpdate')) {
        final id = 'ContentPlaceHolder1_grdStudentProfile_${action}_${row['index']}';
        final element = doc.getElementById(id);
        if (element != null) return element;
      }
    }
    throw const Format5Error('MATCH_MISMATCH', 'Student row or portal action is not available.');
  }

  Future<Map<String, dynamic>> edit(String nic) async {
    _guard();
    if (_document == null) throw const Format5Error('PAGE_NOT_READY', 'Load the student list first.');
    if (_saveInFlight) throw const Format5Error('BUSY', 'An update is already in progress.');
    final age = _editPreparedAt == null ? null : now().difference(_editPreparedAt!);
    final reuse = _editingNic == nic && !_saveAttempted && age != null &&
        !age.isNegative && age < const Duration(seconds: 30) &&
        students(_document!).any((row) => row['nic_id'] == nic && row['editing'] == true);
    if (!reuse) {
      // Back/Cancel leaves the visible app list intact. Refresh WebForms state
      // lazily on the next explicit Edit, never by replaying an Update.
      if (students(_document!).any((row) => row['editing'] == true)) {
        await list(_session, _class, _section);
      }
      final button = _rowButton(_document!, nic, 'btnEdit');
      final fields = _payload(_document!, button);
      fields['__ASYNCPOST'] = 'true';
      fields[r'ctl00$ScriptManager1'] = 'ctl00\$ContentPlaceHolder1\$UpdPanel|${button.attributes['name']}';
      await _send(payload: fields);
    }
    final update = _rowButton(_document!, nic, 'btnUpdate');
    final rowIndex = RegExp(r'_(\d+)$').firstMatch(update.id)![1]!;
    Map<String, dynamic> field(String name) {
      final el = _document!.getElementById('ContentPlaceHolder1_grdStudentProfile_${name}_$rowIndex');
      if (el == null) return {'enabled': false, 'value': ''};
      return {
        'enabled': !el.attributes.containsKey('disabled'),
        'value': el.localName == 'select' ? selected(el) : _value(el),
        if (el.localName == 'select') 'options': options(el),
      };
    }
    _editingNic = nic;
    if (!reuse) _editPreparedAt = now();
    _saveAttempted = false;
    return {
      'success': true,
      'nic_id': nic,
      'sr_no': field('txtSRNO_Edit'),
      'category': field('ddlCategory_Edit'),
      'mobile': field('txtMobile_edit'),
      'name': field('txtName_Edit'),
      'father': field('txtFatherName_Edit'),
      'mother': field('txtMotherName_Edit'),
      'gender': field('ddlGender_Edit'),
      'dob': field('txtDOB_Edit'),
      'oosc': field('txtOosc_Edit'),
    };
  }

  Future<Map<String, dynamic>> save(
    String nic, {
    required String sr,
    required String category,
    required String mobile,
  }) async {
    _guard();
    _editPreparedAt = null;
    if (_editingNic != nic || _document == null) {
      throw const Format5Error('PAGE_NOT_READY', 'Reopen the student Edit form.');
    }
    if (_saveAttempted || _saveInFlight) {
      throw const Format5Error('SAVE_UNCONFIRMED', 'An update was already attempted. Refresh before trying again.');
    }
    final button = _rowButton(_document!, nic, 'btnUpdate');
    final idx = RegExp(r'_(\d+)$').firstMatch(button.id)![1]!;
    final prefix = 'ContentPlaceHolder1_grdStudentProfile_';
    final edits = {
      'txtSRNO_Edit': sr.trim(),
      'ddlCategory_Edit': category.trim(),
      'txtMobile_edit': mobile.trim(),
    };
    if (!RegExp(r'^\d{1,10}$').hasMatch(edits['txtSRNO_Edit']!) ||
        !RegExp(r'^\d{10}$').hasMatch(edits['txtMobile_edit']!)) {
      throw const Format5Error('VALIDATION_ERROR', 'Enter a valid SR number and 10-digit mobile number.');
    }
    for (final entry in edits.entries) {
      final node = _document!.getElementById('$prefix${entry.key}_$idx');
      if (node == null) throw const Format5Error('PAGE_NOT_READY', 'Portal edit field is missing.');
      final current = node.localName == 'select' ? selected(node) : _value(node);
      if (node.attributes.containsKey('disabled') && current != entry.value) {
        throw const Format5Error('VALIDATION_ERROR', 'Portal has disabled this field.');
      }
      if (node.localName == 'select') {
        if (!options(node).any((option) => option['id'] == entry.value)) {
          throw const Format5Error('INVALID_SELECTION', 'Category is not offered by the portal.');
        }
        select(_document!, node.id, entry.value);
      } else {
        node.attributes['value'] = entry.value;
      }
    }
    final fields = _payload(_document!, button, includeDisabled: true);
    fields['__ASYNCPOST'] = 'true';
    fields[r'ctl00$ScriptManager1'] = 'ctl00\$ContentPlaceHolder1\$UpdPanel|${button.attributes['name']}';
    fields['${button.attributes['name']}.x'] = '8';
    fields['${button.attributes['name']}.y'] = '4';
    _saveInFlight = true;
    _saveAttempted = true;
    try {
      await _send(payload: fields, mutation: true);
      // Dismiss controls are page chrome, not part of the portal message.
      // Clean a copy so form tokens and subsequent read-back stay untouched.
      final messageDocument = html.parse(_document!.outerHtml);
      for (final close in messageDocument.querySelectorAll(
        '[data-dismiss="alert"], [data-bs-dismiss="alert"], '
        '.alert .close, .alert .btn-close, #msgDiv .close, '
        '#msg_Success .close, #MsgPopup .close',
      )) {
        close.remove();
      }
      final notices = SchoolPortalMessages.fromDocument(messageDocument);
      final success = notices.any((m) => m.toLowerCase().contains('student profile has been updated successfully'));
      final message = notices.isNotEmpty ? notices.first : 'Update response could not be confirmed.';
      if (!success) {
        return {'success': false, 'code': 'SAVE_UNCONFIRMED', 'message': message,
          'submission_attempted': true, 'verified': false};
      }
      // The portal's success banner alone does not prove that changed values
      // persisted. Read the record again; this is a GET/Show only, never a replay.
      bool verified = false;
      try {
        final currentSession = _session;
        final currentClass = _class;
        final currentSection = _section;
        await _send(); // Fresh page and fresh ASP.NET tokens.
        if (currentSession.isNotEmpty && currentClass.isNotEmpty &&
            currentSection.isNotEmpty) {
          await list(currentSession, currentClass, currentSection);
          final row = students(_document!).where((r) => r['nic_id'] == nic).toList();
          verified = row.length == 1 && !row.single['editing'] &&
              row.single['sr_no'] == sr.trim() &&
              row.single['mobile'] == mobile.trim() &&
              row.single['category'] == _categoryLabel(category);
        }
      } catch (_) {
        // Original success is retained, but read-back verification is unknown.
      }
      _editingNic = null;
      return {
        'success': true,
        'code': verified ? 'UPDATED_VERIFIED' : 'UPDATED_UNVERIFIED',
        'message': message,
        'submission_attempted': true,
        'verified': verified,
      };
    } on Format5Error catch (e) {
      throw Format5Error(e.attempted ? e.code : 'SAVE_UNCONFIRMED', e.message, attempted: true);
    } on TimeoutException {
      throw const Format5Error('SAVE_UNCONFIRMED', 'Portal update timed out. Check current data before attempting again.', attempted: true);
    } on IOException {
      throw const Format5Error('SAVE_UNCONFIRMED', 'Network failed after update started. Refresh and verify the student.', attempted: true);
    } finally {
      _saveInFlight = false;
    }
  }

  static String _categoryLabel(String code) => const {
    '1': 'GEN', '2': 'ST', '3': 'SC', '4': 'SBC', '5': 'OBC',
  }[code] ?? code;
}
