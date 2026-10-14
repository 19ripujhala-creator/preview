import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verified category states. Saved and finally locked are separate states.
class ViffsStatusService {
  static final ChangeNotifier changes = ChangeNotifier();
  static final Map<String, Map<String, dynamic>> _records = {};
  static final Map<String, Map<String, dynamic>> _forms = {};
  static final Map<String, Set<String>> _required = {};
  static final Set<String> _invalidated = {};
  static DateTime get duePeriod => DateTime(DateTime.now().year, DateTime.now().month, 0);
  static String _key(String school, String session, String month, String tablet) => 'viffs_status:$school:$session:$month:$tablet';

  static String _selectionKey(String school, Map<String, dynamic> selection) => _key(school,
    '${selection['ContentPlaceHolder1_ddlStudentType']}', '${selection['ContentPlaceHolder1_ddlmonth']}',
    '${selection['ContentPlaceHolder1_ddlClass']}');
  static Map<String, dynamic>? selectionStatus(String school, Map<String, dynamic> selection) {
    final value = _records[_selectionKey(school, selection)];
    return value == null ? null : Map<String, dynamic>.from(value);
  }
  static Map<String, dynamic>? selectedForm(String school, Map<String, dynamic> selection) {
    final form = _forms[_selectionKey(school, selection)];
    return form == null ? null : Map<String, dynamic>.from(jsonDecode(jsonEncode(form)));
  }

  static Map<String, dynamic>? periodTabletStatus(
    String school,
    int year,
    int month,
    String tablet,
  ) {
    Map<String, dynamic>? latest;
    DateTime? latestAt;
    for (final record in _records.values) {
      if (record['school_id'] != school ||
          record['year'] != year ||
          record['month'] != month ||
          record['tablet']?.toString() != tablet) {
        continue;
      }
      final checkedAt = DateTime.tryParse('${record['checked_at'] ?? ''}');
      if (latest == null ||
          (checkedAt != null && (latestAt == null || checkedAt.isAfter(latestAt)))) {
        latest = record;
        latestAt = checkedAt;
      }
    }
    return latest == null ? null : Map<String, dynamic>.from(latest);
  }

  static Map<String, int>? _lockedTotals(Map<dynamic, dynamic> form) {
    if (form['locked'] != true || form['sections'] is! List) return null;

    int boys = 0;
    int girls = 0;
    bool foundClass = false;
    final ids = <String>{};
    final boysId = RegExp(r'_lblBoys_Tablet_\d+$', caseSensitive: false);
    final girlsId = RegExp(r'_lblGirls_Tablet_\d+$', caseSensitive: false);

    for (final section in (form['sections'] as List).whereType<Map>()) {
      final fields = (section['fields'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
      int? rowBoys;
      int? rowGirls;

      for (final field in fields) {
        final id = '${field['id'] ?? ''}';
        if (!ids.add(id)) return null;
        final raw = '${field['value'] ?? ''}'.trim();
        final value = int.tryParse(raw);
        if (boysId.hasMatch(id)) rowBoys = value;
        if (girlsId.hasMatch(id)) rowGirls = value;
      }

      if (rowBoys == null || rowGirls == null || rowBoys < 0 || rowGirls < 0) {
        return null;
      }
      boys += rowBoys;
      girls += rowGirls;
      foundClass = true;
    }

    if (!foundClass) return null;
    return {'boys': boys, 'girls': girls, 'total': boys + girls};
  }

  static int? _year(String session, int month) {
    final match = RegExp(r'^(\d{4})\s*[-–]\s*(?:\d{2}|\d{4})$').firstMatch(session.trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    return month >= 5 ? year : year + 1; // Portal note: session begins in May.
  }

  static void setEligibility(String school, {required bool? primary, required bool? upper}) {
    if (primary == null || upper == null) return;
    final required = <String>{if (primary || upper) 'P', if (upper) 'B'};
    if (required.isEmpty || setEquals(_required[school], required)) return;
    _required[school] = required;
    changes.notifyListeners();
  }

  static List<String>? requiredCategories(String school) {
    final types = _required[school];
    return types == null ? null : [for (final type in ['P', 'B']) if (types.contains(type)) type];
  }
  static bool? applicable(String school, String tablet) => _required[school]?.contains(tablet);

  static Map<String, Map<String, dynamic>> _dueRecords(String school) {
    final due = duePeriod;
    return {for (final record in _records.values)
      if (record['school_id'] == school && record['year'] == due.year && record['month'] == due.month)
        record['tablet'].toString(): record};
  }

  static bool? currentDue(String school) {
    final records = _dueRecords(school);
    final required = _required[school];
    if (required != null && required.every((type) => records[type]?['locked'] == true)) return true;
    if (records['P']?['locked'] == true && records['B']?['locked'] == true) return true;
    if (records.entries.any((entry) => (required == null || required.contains(entry.key)) && entry.value['locked'] == false)) return false;
    return null;
  }

  static String dueLabel(String school) {
    final done = currentDue(school);
    if (done == true) return 'Locked';
    final records = _dueRecords(school);
    final required = _required[school];
    final relevant = records.entries.where((e) => required == null || required.contains(e.key)).map((e) => e.value).toList();
    if (relevant.any((record) => record['saved'] == true && record['locked'] != true)) return 'Saved';
    if (relevant.any((record) => record['locked'] == true)) return 'Partial';
    if (done == false) return 'Pending';
    return '—';
  }

  static Future<void> storeForm(String school, Map<String, dynamic> response, {bool saved = false}) async {
    final form = response['data'];
    if (form is! Map ||
        form['task'] != 'viffs' ||
        form['school_id']?.toString() != school ||
        form['selection'] is! Map) {
      return;
    }

    final selection = form['selection'] as Map;
    final session = '${selection['ContentPlaceHolder1_ddlStudentType']}';
    final month = int.tryParse('${selection['ContentPlaceHolder1_ddlmonth']}');
    final tablet = '${selection['ContentPlaceHolder1_ddlClass']}';
    if (month == null ||
        month < 1 ||
        month > 12 ||
        !['P', 'B'].contains(tablet)) {
      return;
    }

    final year = _year(session, month);
    if (year == null || form['locked'] is! bool) return;

    final key = _key(school, session, '$month', tablet);
    final sections = form['sections'] is List ? form['sections'] as List : const [];
    if (form['locked'] == true && sections.isEmpty) return;

    final fingerprint = jsonEncode(sections.whereType<Map>().map((section) => {
      'title': section['title'],
      'identity': section['identity'],
      'values': (section['fields'] is List ? section['fields'] as List : const [])
          .whereType<Map>()
          .map((field) => {'id': field['id'], 'value': field['value']})
          .toList(),
    }).toList());

    final totals = form['locked'] == true ? _lockedTotals(form) : null;
    if (form['locked'] == true && totals == null) return;

    final value = <String, dynamic>{
      'school_id': school,
      'session': session,
      'year': year,
      'month': month,
      'tablet': tablet,
      'locked': form['locked'],
      'saved': form['locked'] == true ||
          (saved && response['verified'] == true) ||
          (_records[key]?['saved'] == true &&
              _records[key]?['fingerprint'] == fingerprint),
      'boys': totals?['boys'],
      'girls': totals?['girls'],
      'total': totals?['total'],
      'no_records': form['no_records'] == true,
      'fingerprint': fingerprint,
      'checked_at': DateTime.now().toUtc().toIso8601String(),
    };

    _invalidated.remove(key);
    _forms[key] = Map<String, dynamic>.from(jsonDecode(jsonEncode(form)));
    _records[key] = value;
    changes.notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(value));
    } catch (_) {
      // Cache persistence cannot invalidate a verified portal result.
    }
  }

  static Future<void> restore(String school) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where((key) => key.startsWith('viffs_status:$school:'))) {
        if (_records.containsKey(key) || _invalidated.contains(key)) continue;
        final value = jsonDecode(prefs.getString(key) ?? 'null');
        if (value is! Map || value['school_id'] != school || value['locked'] is! bool) continue;
        if (value['locked'] == true && (value['boys'] is! num || value['girls'] is! num)) {
          await prefs.remove(key);
          continue;
        }
        _records.putIfAbsent(key, () => Map<String, dynamic>.from(value));
      }
      changes.notifyListeners();
    } catch (_) { /* Unknown remains unknown when local cache cannot be read. */ }
  }

  static Future<void> invalidate(String school, Map<String, dynamic> selection) async {
    final key = _key(school, '${selection['ContentPlaceHolder1_ddlStudentType']}',
      '${selection['ContentPlaceHolder1_ddlmonth']}', '${selection['ContentPlaceHolder1_ddlClass']}');
    _invalidated.add(key);
    _forms.remove(key);
    _records.remove(key);
    changes.notifyListeners();
    try { final prefs = await SharedPreferences.getInstance(); await prefs.remove(key); } catch (_) {}
  }
}
