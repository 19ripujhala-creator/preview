/// Complete ranking_status_cache.py conversion; native preferences replace files.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RankingStatusCache {
  RankingStatusCache({this.read, this.write, this.remove});
  final Future<String?> Function(String)? read;
  final Future<void> Function(String, String)? write;
  final Future<void> Function(String)? remove;
  final _memory = <(String, int, int), Map<String, dynamic>>{};
  Future<void> _writes = Future.value();
  static DateTime indiaNow([DateTime? instant]) => (instant ?? DateTime.now())
      .toUtc()
      .add(const Duration(hours: 5, minutes: 30));

  /// Explicit [indiaDate] is already an IST calendar date, matching Python's now.
  static ({int year, int month}) duePeriod([DateTime? indiaDate]) {
    final date = indiaDate ?? indiaNow();
    return (
      year: date.month == 1 ? date.year - 1 : date.year,
      month: date.month == 1 ? 12 : date.month - 1,
    );
  }

  static String storageKey(String school, int year, int month) {
    // Python's json.dumps(tuple) uses a JSON array with comma-space separators.
    final schoolJson = jsonEncode(school);
    final escaped = StringBuffer();
    for (final rune in schoolJson.runes) {
      if (rune < 128)
        escaped.writeCharCode(rune);
      else if (rune <= 0xffff)
        escaped.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
      else {
        final offset = rune - 0x10000;
        for (final part in [
          0xd800 + (offset >> 10),
          0xdc00 + (offset & 1023),
        ]) {
          escaped.write('\\u${part.toRadixString(16).padLeft(4, '0')}');
        }
      }
    }
    return 'rajshala.direct.sd.ranking_cache.${sha256.convert(utf8.encode('[$escaped, $year, $month]'))}';
  }

  static bool valid(Object? raw, String school, int year, int month) {
    if (raw is! Map ||
        raw['school_id'] != school ||
        raw['year'] != year ||
        raw['month'] != month ||
        raw['completed'] is! bool)
      return false;
    if (raw['checked_at'] is! String ||
        DateTime.tryParse(raw['checked_at']) == null ||
        raw['checked_date'] is! String)
      return false;
    final iso = RegExp(r'^([0-9]{4})-?([0-9]{2})-?([0-9]{2})')
        .firstMatch(raw['checked_at']);
    if (iso != null) {
      final y = int.parse(iso.group(1)!),
          m = int.parse(iso.group(2)!),
          d = int.parse(iso.group(3)!);
      final date = DateTime.utc(y, m, d);
      if (y < 1 || date.year != y || date.month != m || date.day != d)
        return false;
    }
    final time = RegExp(
      r'^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ]([0-9]{2}):([0-9]{2})(?::([0-9]{2}))?',
    ).firstMatch(raw['checked_at']);
    if (time != null &&
        (int.parse(time.group(1)!) > 23 ||
            int.parse(time.group(2)!) > 59 ||
            int.parse(time.group(3) ?? '0') > 59))
      return false;
    final match = RegExp(r'^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})$')
        .firstMatch(raw['checked_date']);
    if (match == null) return false;
    final y = int.parse(match.group(1)!),
        m = int.parse(match.group(2)!),
        d = int.parse(match.group(3)!);
    final date = DateTime.utc(y, m, d);
    return y >= 1 && date.year == y && date.month == m && date.day == d;
  }

  Future<Map<String, dynamic>?> readStatus(
    String school,
    int year,
    int month,
  ) async {
    final key = (school, year, month);
    try {
      Map<String, dynamic>? value = _memory[key];
      if (value == null) {
        final stored = read != null
            ? await read!(storageKey(school, year, month))
            : (await SharedPreferences.getInstance()).getString(
                storageKey(school, year, month),
              );
        if (stored == null) return null;
        // A concurrent invalidate/store wins over an earlier asynchronous disk read.
        final current = _memory[key];
        final raw = current ?? jsonDecode(stored);
        if (raw is! Map) return null;
        value = Map<String, dynamic>.from(raw);
      }
      if (!valid(value, school, year, month)) return null;
      return Map<String, dynamic>.from(value);
    } catch (_) {
      return null;
    }
  }

  static String _date(DateTime now) =>
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  static String _iso(DateTime now) {
    final seconds =
        '${_date(now)}T${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final micros = now.millisecond * 1000 + now.microsecond;
    return '$seconds${micros == 0 ? '' : '.${micros.toString().padLeft(6, '0')}'}+05:30';
  }

  Future<void> _persist(Future<void> Function() action) {
    final pending = _writes.then((_) async {
      try {
        await action();
      } catch (_) {
        /* Retain memory cache as the Python source does. */
      }
    });
    _writes = pending;
    return pending;
  }

  Future<Map<String, dynamic>?> storeStatus(
    String school,
    int year,
    int month,
    Object? completed, {
    DateTime? indiaDate,
    Map<String, dynamic>? form,
  }) async {
    if (completed is! bool) return null;
    final now = indiaDate ?? indiaNow(), key = (school, year, month);
    final value = <String, dynamic>{
      'school_id': school,
      'year': year,
      'month': month,
      'completed': completed,
      'checked_at': _iso(now),
      'checked_date': _date(now),
      'source': 'portal',
      if (form != null) 'form': form,
    };
    _memory[key] = value;
    final stored = jsonEncode(value), name = storageKey(school, year, month);
    await _persist(() async {
      if (write != null)
        await write!(name, stored);
      else
        await (await SharedPreferences.getInstance()).setString(name, stored);
    });
    return Map<String, dynamic>.from(value);
  }

  static bool needsLoginCheck(
    Map<String, dynamic>? cached, {
    DateTime? indiaDate,
  }) {
    if (cached?['completed'] == true) return false;
    return (indiaDate ?? indiaNow()).day <= 5;
  }

  Future<void> invalidateStatus(String school, int year, int month) async {
    _memory[(school, year, month)] = {};
    final name = storageKey(school, year, month);
    await _persist(() async {
      if (remove != null)
        await remove!(name);
      else
        await (await SharedPreferences.getInstance()).remove(name);
    });
  }
}
