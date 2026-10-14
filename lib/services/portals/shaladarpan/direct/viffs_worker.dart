/// Complete viffs_worker.py: grid identity, native totals and saved-state checks.
import 'dart:convert';

import 'package:html/dom.dart' as dom;

typedef ViffsControl = Map<String, dynamic> Function(dom.Element, String);
typedef ViffsText = String Function(dom.Element?);
typedef ViffsError = Exception Function(
  String message,
  String code, {
  Map<String, String> fieldErrors,
});

class ViffsWorker {
  static const prefix = 'ContentPlaceHolder1_';
  static final classId = RegExp(r'_lblClass_\d+$', caseSensitive: false);
  static final countId = RegExp(
    r'_lbl(?:Boys|Girls)(?:_Tablet(?:LessThen4|NoConsumption)?)?_\d+$',
    caseSensitive: false,
  );
  static List<dom.Element> _cells(dom.Element row) =>
      row.children.where((n) => ['th', 'td'].contains(n.localName)).toList();
  static dom.Element? _find(dom.Element root, RegExp pattern) {
    for (final node in root.querySelectorAll('[id]')) {
      if (pattern.hasMatch(node.id)) return node;
    }
    return null;
  }

  static Map<String, dynamic>? parseGrid(
    dom.Document soup,
    ViffsControl control,
    ViffsText text,
    ViffsError error,
  ) {
    final candidates = [
      for (final name in ['grd_Add', 'grd_Pink', 'grd_Blue'])
        soup.getElementById('$prefix$name'),
    ].whereType<dom.Element>().toList();
    if (candidates.length > 1)
      throw error(
        'Multiple VIFFS grids were returned. Refresh before continuing.',
        'STALE_FORM',
      );
    if (candidates.isEmpty) return null;
    final table = candidates.single, rows = table.querySelectorAll('tr');
    final dataRows = rows.where((r) => _find(r, classId) != null).toList();
    final headers = <(int, int), String>{};
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      if (dataRows.contains(row)) break;
      var col = 0;
      for (final cell in _cells(row)) {
        while (headers.containsKey((r, col))) {
          col++;
        }
        final span = int.parse(cell.attributes['colspan'] ?? '1'),
            height = int.parse(cell.attributes['rowspan'] ?? '1');
        if (span < 1 || height < 1 || span > 100 || height > 100)
          throw error('VIFFS table headers changed.', 'STALE_FORM');
        for (var dr = 0; dr < height; dr++) {
          for (var dc = 0; dc < span; dc++) {
            headers[(r + dr, col + dc)] = text(cell);
          }
        }
        col += span;
      }
    }
    final sections = <Map<String, dynamic>>[],
        identities = <String>{},
        allIds = <String>{};
    for (final row in dataRows) {
      final classNode = _find(row, classId)!;
      final nodeText = text(classNode),
          label = nodeText.isNotEmpty
              ? nodeText
              : classNode.attributes['value'] ?? '';
      final identity = <String, String>{
        for (final n in row.querySelectorAll('input[type="hidden"][id]'))
          if (n.id.isNotEmpty) n.id: n.attributes['value'] ?? '',
      };
      final classKeys = [
        for (final entry in identity.entries)
          if (RegExp(
            r'class.*id|id.*class',
            caseSensitive: false,
          ).hasMatch(entry.key))
            [entry.key.replaceFirst(RegExp(r'_\d+$'), ''), entry.value],
      ];
      classKeys.sort((a, b) {
        final name = a[0].compareTo(b[0]);
        return name == 0 ? a[1].compareTo(b[1]) : name;
      });
      final rowKey = jsonEncode(
        classKeys.isNotEmpty
            ? classKeys
            : ['label', label.trim().replaceAll(RegExp(r'\s+'), ' ')],
      );
      if (label.isEmpty || !identities.add(rowKey))
        throw error(
          'A unique class could not be identified in the VIFFS grid.',
          'STALE_FORM',
        );
      final fields = <Map<String, dynamic>>[],
          cells = _cells(row).where((c) => c.localName == 'td').toList();
      for (var col = 0; col < cells.length; col++) {
        final nodes = cells[col]
            .querySelectorAll('input,select')
            .where(
              (n) =>
                  n.id.isNotEmpty &&
                  ![
                    'hidden',
                    'submit',
                    'button',
                    'image',
                  ].contains((n.attributes['type'] ?? '').toLowerCase()),
            )
            .toList();
        if (nodes.length > 1)
          throw error(
            'VIFFS field mapping changed. Refresh before submitting.',
            'STALE_FORM',
          );
        if (nodes.isEmpty) continue;
        final node = nodes.single;
        if (!allIds.add(node.id))
          throw error('Duplicate VIFFS field identity.', 'STALE_FORM');
        final keys = headers.keys.toList()
          ..sort((a, b) {
            final r = a.$1.compareTo(b.$1);
            return r == 0 ? a.$2.compareTo(b.$2) : r;
          });
        final labels = <String>{
          for (final key in keys)
            if (key.$2 == col && headers[key]!.isNotEmpty) headers[key]!,
        };
        final field = control(
          node,
          labels.isNotEmpty ? labels.join(' · ') : node.id,
        );
        if (countId.hasMatch(node.id)) {
          field['numeric'] = true;
          if (field['readonly'] != true) {
            field['required'] = true;
            field['required_message'] = 'कृपया विद्यार्थियों की संख्या भरें';
          }
        }
        fields.add(field);
      }
      sections.add({
        'title': label,
        'teacher': text(
          _find(row, RegExp(r'_lblTeacher_name_\d+$', caseSensitive: false)),
        ),
        'fields': fields,
        'identity': identity,
      });
    }
    return {'grid_id': table.id, 'sections': sections};
  }

  static String _decimal(String value) => String.fromCharCodes(
    value.runes.map((rune) {
      for (final start in const <int>[
        0x30,
        0x660,
        0x6f0,
        0x7c0,
        0x966,
        0x9e6,
        0xa66,
        0xae6,
        0xb66,
        0xbe6,
        0xc66,
        0xce6,
        0xd66,
        0xde6,
        0xe50,
        0xed0,
        0xf20,
        0x1040,
        0x1090,
        0x17e0,
        0x1810,
        0x1946,
        0x19d0,
        0x1a80,
        0x1a90,
        0x1b50,
        0x1bb0,
        0x1c40,
        0x1c50,
        0xa620,
        0xa8d0,
        0xa900,
        0xa9d0,
        0xa9f0,
        0xaa50,
        0xabf0,
        0xff10,
        0x104a0,
        0x10d30,
        0x11066,
        0x110f0,
        0x11136,
        0x111d0,
        0x112f0,
        0x11450,
        0x114d0,
        0x11650,
        0x116c0,
        0x11730,
        0x118e0,
        0x11950,
        0x11c50,
        0x11d50,
        0x11da0,
        0x11f50,
        0x16a60,
        0x16ac0,
        0x16b50,
        0x1d7ce,
        0x1d7d8,
        0x1d7e2,
        0x1d7ec,
        0x1d7f6,
        0x1e140,
        0x1e2f0,
        0x1e4f0,
        0x1e950,
        0x1fbf0,
      ]) {
        if (rune >= start && rune < start + 10) return 48 + rune - start;
      }
      return rune;
    }),
  );
  static bool isDecimal(String value) => _number(value);
  static int decimalInteger(String value) => int.parse(_decimal(value));
  static bool _number(Object? value) =>
      value is String && RegExp(r'^[0-9]+$').hasMatch(_decimal(value));
  static void validateCounts(
    Map<String, dynamic> form,
    Map<String, String> values,
    ViffsError error,
  ) {
    final errors = <String, String>{};
    for (final raw in form['sections'] as List) {
      final section = raw as Map,
          fields = <String, Map>{
            for (final f in section['fields'] as List)
              (f as Map)['id'] as String: f,
          };
      for (final gender in ['Boys', 'Girls']) {
        final enrolment = fields.entries
            .where(
              (e) => RegExp(
                '_lbl${gender}_\\d+\$',
                caseSensitive: false,
              ).hasMatch(e.key),
            )
            .toList();
        final counts = fields.entries
            .where(
              (e) => RegExp(
                '_lbl${gender}_Tablet(?:LessThen4|NoConsumption)?_\\d+\$',
                caseSensitive: false,
              ).hasMatch(e.key),
            )
            .toList();
        if (enrolment.length != 1 || counts.length != 3) continue;
        final original = enrolment.single.value;
        if (original['readonly'] != true || !_number(original['value']))
          throw error(
            'The portal student strength could not be verified.',
            'STALE_FORM',
          );
        final numbers = <int>[];
        for (final entry in counts) {
          final raw = values[entry.key] ?? entry.value['value'];
          if (!_number(raw))
            errors[entry.key] = 'कृपया विद्यार्थियों की संख्या भरें';
          else
            numbers.add(int.parse(_decimal(raw as String)));
        }
        if (numbers.length == 3 &&
            numbers.fold<int>(0, (a, b) => a + b) !=
                int.parse(_decimal(original['value'] as String))) {
          for (final entry in counts) {
            if (entry.value['readonly'] != true)
              errors[entry.key] =
                  'विद्यार्थियों की कुल संख्या नामांकन के बराबर रखें';
          }
        }
      }
    }
    if (errors.isNotEmpty)
      throw error(errors.values.first, 'INVALID_PAYLOAD', fieldErrors: errors);
  }

  static bool _equal(Object? a, Object? b) {
    if (a is Map && b is Map)
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]));
    if (a is List && b is List)
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _equal(a[i], b[i]));
    return a == b;
  }

  static bool savedMatches(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
    Map<String, String> values,
  ) {
    if (before['school_id'] != after['school_id'] ||
        !_equal(before['selection'], after['selection']))
      return false;
    final oldSections = before['sections'] as List,
        newSections = after['sections'] as List;
    if (oldSections.isEmpty || oldSections.length != newSections.length)
      return false;
    final old = <String, Map>{
          for (final s in oldSections) (s as Map)['title'] as String: s,
        },
        fresh = <String, Map>{
          for (final s in newSections) (s as Map)['title'] as String: s,
        };
    if (old.length != oldSections.length ||
        old.length != fresh.length ||
        !old.keys.every(fresh.containsKey))
      return false;
    for (final entry in old.entries) {
      final current = fresh[entry.key];
      if (current == null ||
          !_equal(entry.value['identity'], current['identity']))
        return false;
      final previous = <String, Map>{
        for (final f in entry.value['fields'] as List)
          (f as Map)['id'] as String: f,
      };
      final persisted = <String, Map>{
        for (final f in current['fields'] as List)
          (f as Map)['id'] as String: f,
      };
      if (previous.length != persisted.length ||
          !previous.keys.every(persisted.containsKey))
        return false;
      for (final f in previous.entries) {
        if (persisted[f.key]!['value'] != (values[f.key] ?? f.value['value']))
          return false;
      }
    }
    return values.isNotEmpty;
  }
}
