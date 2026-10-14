/// Complete viffs_mpr_worker.py: locked native four-or-more-tablet summary.
import 'monthly_tasks_worker.dart';
import 'viffs_worker.dart';

typedef ViffsReadForm = Future<Map<String, dynamic>> Function(
  Map<String, String> selection,
  String school,
);

class ViffsMprWorker {
  static const prefix = MonthlyTasksWorker.prefix;
  static Map<String, dynamic> summarizeLockedForm(
    Map<String, dynamic> form,
    String school,
    Map<String, String> selection,
  ) {
    final actual = form['selection'];
    if ('${form['school_id']}' != school ||
        actual is! Map ||
        actual.length != selection.length ||
        selection.entries.any((e) => actual[e.key] != e.value)) {
      throw const MonthlyError(
        'VIFFS school or reporting period changed.',
        'SELECTION_CHANGED',
      );
    }
    final result = <String, dynamic>{
      'success': true,
      'complete': true,
      'school_id': school,
      'selection': Map<String, String>.from(selection),
      'locked': form['locked'] == true,
      'entry_available': false,
      'boys': null,
      'girls': null,
      'total': null,
      'classes': <Map<String, dynamic>>[],
      'lock_date': null,
    };
    if (form['locked'] != true) {
      result['status'] = form['no_records'] == true ? 'no_entry' : 'unlocked';
      return result;
    }
    final sections = (form['sections'] as List?) ?? [];
    if (sections.isEmpty) {
      throw const MonthlyError(
        'Locked VIFFS entry has no class rows.',
        'VIFFS_REPORT_INCOMPLETE',
      );
    }
    final titles = <String>{}, ids = <String>{};
    for (final section in sections) {
      final title = '${section['title'] ?? ''}'.trim();
      if (title.isEmpty || !titles.add(title)) {
        throw const MonthlyError(
          'VIFFS class identity is incomplete or duplicated.',
          'VIFFS_REPORT_INCOMPLETE',
        );
      }
      final row = <String, dynamic>{'class_name': title};
      for (final gender in ['Boys', 'Girls']) {
        final pattern = RegExp(
          r'_lbl' + gender + r'_Tablet_\d+$',
          caseSensitive: false,
        );
        final fields = ((section['fields'] as List?) ?? [])
            .where((f) => pattern.hasMatch('${f['id'] ?? ''}'))
            .toList();
        if (fields.length != 1) {
          throw const MonthlyError(
            'Locked VIFFS four-tablet count is missing.',
            'VIFFS_REPORT_INCOMPLETE',
          );
        }
        final field = fields.single;
        final raw = '${field['value'] ?? ''}'.trim();
        if (!ids.add('${field['id']}') || !ViffsWorker.isDecimal(raw)) {
          throw const MonthlyError(
            'Locked VIFFS count is invalid or duplicated.',
            'VIFFS_REPORT_INCOMPLETE',
          );
        }
        row[gender.toLowerCase()] = ViffsWorker.decimalInteger(raw);
      }
      row['total'] = (row['boys'] as int) + (row['girls'] as int);
      (result['classes'] as List).add(row);
    }
    result.addAll({
      'entry_available': true,
      'status': 'locked',
      'lock_date': form['lock_date'],
    });
    for (final key in ['boys', 'girls', 'total']) {
      result[key] = (result['classes'] as List).fold<int>(
        0,
        (sum, row) => sum + (row[key] as int),
      );
    }
    return result;
  }

  /// Legacy worker contract, with the existing read_form dependency injected.
  static Future<Map<String, dynamic>> fetchSummary(
    ViffsReadForm readForm,
    String school,
    int year,
    int month, {
    String tablet = 'P',
  }) async {
    try {
      final metadata = await readForm({}, school);
      List options(String suffix) {
        final fields = (metadata['selectors'] as List)
            .where((f) => f['id'] == prefix + suffix)
            .toList();
        if (fields.length != 1) {
          throw const MonthlyError(
            'VIFFS period selectors are unavailable.',
            'VIFFS_REPORT_INCOMPLETE',
          );
        }
        return fields.single['options'] as List;
      }

      final start = month >= 5 ? year : year - 1;
      final pattern = sessionPattern(start);
      final sessions = options('ddlStudentType')
          .where((o) => pattern.hasMatch('${o['value']}'.replaceAll(' ', '')))
          .toList();
      final months = options('ddlmonth')
          .where(
            (o) =>
                ViffsWorker.isDecimal('${o['value']}') &&
                ViffsWorker.decimalInteger('${o['value']}') == month,
          )
          .toList();
      if (sessions.length != 1 || months.length != 1) {
        throw const MonthlyError(
          'Requested VIFFS session or month is unavailable.',
          'INVALID_SELECTION',
        );
      }
      if (!options('ddlClass').any((o) => o['value'] == tablet)) {
        throw const MonthlyError(
          'Requested VIFFS tablet category is unavailable.',
          'INVALID_SELECTION',
        );
      }
      final selection = <String, String>{
        '${prefix}ddlStudentType': '${sessions.single['value']}',
        '${prefix}ddlClass': tablet,
        '${prefix}ddlmonth': '${months.single['value']}',
      };
      final form = await readForm(selection, school);
      return summarizeLockedForm(form, school, selection)..addAll({
        'year': year,
        'month': month,
        'tablet': tablet,
        'metric': 'children_four_or_more_tablets',
      });
    } on MonthlyError catch (e) {
      return {
        'success': false,
        'complete': false,
        'code': e.code,
        'message': e.message,
      };
    }
  }

  static RegExp sessionPattern(int start) => RegExp(
    '^${start}[-–](?:${start + 1}|${((start + 1) % 100).toString().padLeft(2, '0')})\$',
  );
}
