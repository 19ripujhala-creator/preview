import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RankingStatusService {
  static final ChangeNotifier changes = ChangeNotifier();
  static final Map<String, Map<String, dynamic>> _statuses = {};
  static Map<String, dynamic>? currentDue(String school) {
    final period = duePeriod;
    final value = _statuses[_key(school, period.year, period.month)];
    return value == null ? null : Map<String, dynamic>.from(value);
  }
  static final Map<String, Map<String, dynamic>> _forms = {};
  static void rememberForm(String school, dynamic raw) {
    if (raw is! Map || raw['school_id']?.toString() != school || raw['task'] != 'ranking' || raw['editing'] == true || raw['selection'] is! Map || raw['sections'] is! List || raw['snapshot'] is! String) return;
    _forms[school] = Map<String, dynamic>.from(jsonDecode(jsonEncode(raw)));
  }
  static Map<String, dynamic>? loginForm(String school) {
    final raw = _forms[school], period = duePeriod;
    if (raw == null || '${raw['selection']['ContentPlaceHolder1_ddlyear']}' != '${period.year}' || '${raw['selection']['ContentPlaceHolder1_ddlMonth1']}' != '${period.month}') return null;
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(raw)));
  }

  static DateTime get duePeriod => DateTime(DateTime.now().year, DateTime.now().month, 0);
  static String _key(String school, int year, int month) => 'ranking_status:$school:$year-$month';
  static Future<void> store(String school, dynamic raw) async {
    if (raw is! Map || raw['school_id']?.toString() != school || raw['completed'] is! bool) return;
    final year = int.tryParse('${raw['year']}'), month = int.tryParse('${raw['month']}');
    if (year == null || month == null || month < 1 || month > 12) return;
    final value = Map<String, dynamic>.from(jsonDecode(jsonEncode(raw)));
    final key = _key(school, year, month);
    final previous = _statuses[key];
    final incomingTime = DateTime.tryParse('${value['checked_at']}');
    final previousTime = DateTime.tryParse('${previous?['checked_at']}');
    if (incomingTime != null && previousTime != null && incomingTime.isBefore(previousTime)) return;
    _statuses[key] = value;
    changes.notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      // Prefer the latest result if another operation completed while awaiting prefs.
      await prefs.setString(key, jsonEncode(_statuses[key]));
    } catch (_) { /* A cache write must not turn a verified portal action into a failure. */ }
  }
  static Future<Map<String, dynamic>?> readDue(String school) async {
    try {
      final live = currentDue(school);
      if (live != null) return live;
      final period = duePeriod, prefs = await SharedPreferences.getInstance();
      final latest = currentDue(school);
      if (latest != null) return latest;
      final raw = prefs.getString(_key(school, period.year, period.month));
      if (raw == null) return null;
      final value = jsonDecode(raw);
      if (value is! Map || value['school_id'] != school || value['year'] != period.year || value['month'] != period.month || value['completed'] is! bool) return null;
      return Map<String, dynamic>.from(value);
    } catch (_) { return null; }
  }
  static Future<void> storeForm(String school, Map<String, dynamic> result) async {
    final form = result['data'];
    // Edit opens a draft, not a newly saved record. Retain the last saved cache.
    if (form is Map && form['editing'] == true) return;
    rememberForm(school, form);
    if (form is! Map || form['task'] != 'ranking' || form['completed'] is! bool || form['selection'] is! Map) return;
    final selection = form['selection'] as Map;
    final year = int.tryParse('${selection['ContentPlaceHolder1_ddlyear']}');
    final month = int.tryParse('${selection['ContentPlaceHolder1_ddlMonth1']}');
    if (year == null || month == null) return;
    await store(school, {'school_id': school, 'year': year, 'month': month, 'completed': form['completed'], 'source': 'portal', 'checked_at': DateTime.now().toUtc().toIso8601String()});
  }
}
