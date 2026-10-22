import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/shaladarpan/direct/viffs_worker.dart';
import '../../lib/services/portals/shaladarpan/direct/ranking_status_cache.dart';

String fixture(String name) =>
    File('test/direct/fixtures/$name').readAsStringSync();
dynamic golden(String name) => jsonDecode(fixture(name));

class DependencyError implements Exception {
  DependencyError(this.message, this.code, {this.fieldErrors = const {}});
  final String message, code;
  final Map<String, String> fieldErrors;
  Map<String, dynamic> result() => {
    'success': false,
    'code': code,
    'message': message,
    'field_errors': fieldErrors,
  };
}

String text(dom.Element? e) => e == null
    ? ''
    : e.nodes
          .expand(
            (n) => n is dom.Text
                ? [n.text.trim()]
                : n is dom.Element
                ? [text(n)]
                : <String>[],
          )
          .where((s) => s.isNotEmpty)
          .join(' ');
Map<String, dynamic> control(dom.Element n, String label) => {
  'id': n.id,
  'label': label,
  'value': n.attributes['value'] ?? '',
  'options': [],
  'required':
      n.attributes.containsKey('required') ||
      n.attributes['aria-required'] == 'true',
  'readonly':
      n.attributes.containsKey('disabled') ||
      n.attributes.containsKey('readonly'),
  'numeric':
      n.attributes['type'] == 'number' ||
      RegExp(r'CheckNumeric|onlyNumber')
          .hasMatch(n.attributes['onkeypress'] ?? ''),
  'maxlength': int.parse(n.attributes['maxlength'] ?? '0'),
  'date': n.classes.contains('datepicker'),
};
Map<String, dynamic> copy(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));
void main() {
  for (final mode in [
    'normal',
    'pink',
    'blue',
    'unicode',
    'headers',
    'label',
    'duplicate_class',
    'duplicate_field',
    'multiple',
    'two',
    'absent',
  ]) {
    test('complete VIFFS source parser parity: $mode', () {
      Map<String, dynamic> result;
      try {
        result = {
          'success': true,
          'data': ViffsWorker.parseGrid(
            html.parse(fixture('viffs_dependency_$mode.html')),
            control,
            text,
            DependencyError.new,
          ),
        };
      } on DependencyError catch (e) {
        result = e.result();
      }
      expect(result, golden('python_viffs_dependency_$mode.json'));
    });
  }
  for (final mode in [
    'valid',
    'mismatch',
    'invalid',
    'strength',
    'incomplete',
  ]) {
    test(
      'source enrolment/count validation and field warning parity: $mode',
      () {
        final g = golden('python_viffs_counts_$mode.json');
        Map<String, dynamic> r;
        try {
          ViffsWorker.validateCounts(
            Map<String, dynamic>.from(g['form']),
            Map<String, String>.from(g['values']),
            DependencyError.new,
          );
          r = {'success': true};
        } on DependencyError catch (e) {
          r = e.result();
        }
        expect(r, g['result']);
      },
    );
  }
  test(
    'saved readback validates all fields, complete roster, school and period',
    () {
      final g = golden('python_viffs_counts_valid.json'),
          before = Map<String, dynamic>.from(g['form']);
      final values = Map<String, String>.from(g['values']);
      expect(ViffsWorker.savedMatches(before, copy(before), values), true);
      for (final change in <void Function(Map<String, dynamic>)>[
        (f) => f['school_id'] = 'other',
        (f) => f['selection'] = {'period': '10'},
        (f) => (f['sections'] as List).removeLast(),
        (f) => f['sections'][0]['identity'] = {'wrong': 'id'},
        (f) => f['sections'][0]['fields'][0]['value'] = '11',
        (f) => f['sections'][1]['title'] = f['sections'][0]['title'],
      ]) {
        final after = copy(before);
        change(after);
        expect(ViffsWorker.savedMatches(before, after, values), false);
      }
      expect(ViffsWorker.savedMatches(before, copy(before), {}), false);
    },
  );
  test(
    'readback remains valid when sections reorder with unchanged identities',
    () {
      final g = golden('python_viffs_counts_valid.json'),
          before = Map<String, dynamic>.from(g['form']),
          after = copy(before);
      after['sections'] = (after['sections'] as List).reversed.toList();
      expect(
        ViffsWorker.savedMatches(
          before,
          after,
          Map<String, String>.from(g['values']),
        ),
        true,
      );
    },
  );
  test('complete ranking cache store output equals original source', () async {
    for (final g in golden('python_ranking_cache_store.json') as List) {
      final disk = <String, String>{},
          cache = RankingStatusCache(
            read: (k) async => disk[k],
            write: (k, v) async {
              disk[k] = v;
            },
            remove: (k) async {
              disk.remove(k);
            },
          );
      final result = await cache.storeStatus(
        '123456',
        2026,
        9,
        g['completed'],
        indiaDate: DateTime.utc(2026, 10, 11, 0, 54, 21),
        form: {'task': 'ranking', 'completed': g['completed']},
      );
      expect(result, g['result']);
      if (result == null)
        expect(disk, isEmpty);
      else
        expect(await cache.readStatus('123456', 2026, 9), result);
    }
  });
  test('January rollover, fifth-day deadline and completed cache follow original source', () {
    for (final g in golden('python_ranking_cache_policy.json') as List) {
      final date = DateTime.parse(g['date']),
          period = RankingStatusCache.duePeriod(date);
      expect({'year': period.year, 'month': period.month}, g['due']);
      expect(
        RankingStatusCache.needsLoginCheck(
          g['cached'] == null ? null : Map<String, dynamic>.from(g['cached']),
          indiaDate: date,
        ),
        g['check'],
      );
    }
    expect(
      RankingStatusCache.indiaNow(DateTime.utc(2026, 9, 30, 20)).month,
      10,
    );
  });
  test('cache school/period key matches original Python digest', () {
    expect(
      RankingStatusCache.storageKey('123456', 2026, 9).split('.').last,
      golden('python_ranking_cache_key.json')['key'],
    );
  });
  test('unavailable storage cannot discard a verified memory cache', () async {
    final cache = RankingStatusCache(
      write: (k, v) async {
        throw const FileSystemException('offline');
      },
    );
    final saved = await cache.storeStatus('123456', 2026, 9, true);
    expect(await cache.readStatus('123456', 2026, 9), saved);
    expect(await cache.readStatus('999999', 2026, 9), null);
  });
  test(
    'invalidation tombstone prevents old data even when storage delete fails',
    () async {
      final disk = <String, String>{},
          cache = RankingStatusCache(
            read: (k) async => disk[k],
            write: (k, v) async {
              disk[k] = v;
            },
            remove: (k) async {
              throw const FileSystemException('offline');
            },
          );
      await cache.storeStatus('123456', 2026, 9, true);
      await cache.invalidateStatus('123456', 2026, 9);
      expect(disk, isNotEmpty);
      expect(await cache.readStatus('123456', 2026, 9), null);
    },
  );
  test('invalid cache identity, completion and dates cannot become pending/completed', () {
    final good = golden('python_ranking_cache_store.json')[0]['result'] as Map;
    expect(RankingStatusCache.valid(good, '123456', 2026, 9), true);
    for (final change in [
      {'completed': 0},
      {'school_id': 'other'},
      {'year': 2025},
      {'checked_at': 'broken'},
      {'checked_at': '2026-02-30T12:00:00+05:30'},
      {'checked_at': '2026-10-10T24:00:00+05:30'},
      {'checked_date': '2026-02-30'},
    ]) {
      expect(
        RankingStatusCache.valid({...good, ...change}, '123456', 2026, 9),
        false,
      );
    }
  });
  test('parallel writes persist the newest result without resurrecting invalidation', () async {
    final disk = <String, String>{},
        cache = RankingStatusCache(
          read: (k) async => disk[k],
          write: (k, v) async {
            disk[k] = v;
          },
          remove: (k) async {
            disk.remove(k);
          },
        );
    await Future.wait([
      cache.storeStatus('123456', 2026, 9, false),
      cache.storeStatus('123456', 2026, 9, true),
    ]);
    final fresh = RankingStatusCache(read: (k) async => disk[k]);
    expect((await fresh.readStatus('123456', 2026, 9))!['completed'], true);
    await cache.invalidateStatus('123456', 2026, 9);
    expect(await fresh.readStatus('123456', 2026, 9), null);
  });
}
