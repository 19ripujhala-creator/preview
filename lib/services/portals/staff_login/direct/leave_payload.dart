/// Pure validation/parsing equivalents from leave_apply_worker.py.
/// No network requests or portal mutations are performed by this file.
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

Iterable<String> _strippedStrings(dom.Node node) sync* {
  if (node is dom.Text) {
    final value = node.data.trim();
    if (value.isNotEmpty) yield value;
  } else {
    if (node is dom.Element &&
        {'script', 'style', 'template'}.contains(node.localName))
      return;
    for (final child in node.nodes) {
      yield* _strippedStrings(child);
    }
  }
}

String _string(Object? value) => switch (value) {
  null => 'None',
  true => 'True',
  false => 'False',
  _ => value.toString(),
};

bool _truth(Object? value) =>
    value != null && value != false && value != '' && value != 0;
Object? _or(Object? a, Object? b) => _truth(a) ? a : b;

String normalizeStaffLeaveDate(Object? value) {
  var text = _string(_or(value, '')).trim();
  if (text.isEmpty) return text;
  text = text.split('T').first.split(' ').first.trim();
  final dash = RegExp(r'^\d{2}-\d{2}-\d{4}').firstMatch(text);
  if (dash != null) return dash[0]!;
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
  if (iso != null) return '${iso[3]}-${iso[2]}-${iso[1]}';
  final slash = RegExp(r'^(\d{2})/(\d{2})/(\d{4})').firstMatch(text);
  if (slash != null) return '${slash[1]}-${slash[2]}-${slash[3]}';
  return text;
}

class StaffLeavePayloadError implements Exception {
  const StaffLeavePayloadError(this.code, this.message);
  final String code, message;
}

/// Validation/defaults from LeaveApplyPayload and api_apply_leave.
Map<String, dynamic> prepareStaffLeavePayload(Map<String, dynamic> input) {
  final data = <String, dynamic>{
    'from_duration': 'Full',
    'to_duration': 'Full',
    'day_type': null,
    'from_day_type': null,
    'to_day_type': null,
    'station_leave': 'N',
    'address': 'At Home',
    'remark': 'Leave Application',
    'confirmed': false,
    ...input,
  };
  String date(Object? value) {
    final raw = value is String ? value.trim() : '';
    if (raw.isEmpty)
      throw const StaffLeavePayloadError(
        'BAD_DATE',
        'A valid date is required.',
      );
    final local = RegExp(r'^(\d{1,2})([/-])(\d{1,2})\2(\d{4})$')
        .firstMatch(raw);
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(raw);
    if (local == null && iso == null) {
      throw const StaffLeavePayloadError(
        'BAD_DATE',
        'Invalid calendar date. Use DD/MM/YYYY.',
      );
    }
    final normalized = local != null
        ? '${local[1]}-${local[3]}-${local[4]}'
        : '${iso![3]}-${iso[2]}-${iso[1]}';
    try {
      final parsed = _date(normalized);
      return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year.toString().padLeft(4, '0')}';
    } on FormatException {
      throw const StaffLeavePayloadError(
        'BAD_DATE',
        'Invalid calendar date. Use DD/MM/YYYY.',
      );
    }
  }

  data['from_date'] = date(data['from_date']);
  data['to_date'] = date(data['to_date']);
  if (_date((data['to_date'] as String).replaceAll('/', '-'))
      .isBefore(_date((data['from_date'] as String).replaceAll('/', '-')))) {
    throw const StaffLeavePayloadError(
      'BAD_DATE',
      'Leave end date must not precede start date.',
    );
  }
  for (final entry in {
    'reason_id': 'Reason ID',
    'leave_type_id': 'Leave type ID',
  }.entries) {
    final value = data[entry.key];
    if (value is! String ||
        value.trim().isEmpty ||
        value.trim().length > 200 ||
        value.trim().runes.any((c) => c < 32)) {
      throw StaffLeavePayloadError(
        'INVALID_PAYLOAD',
        '${entry.value} is required and must be valid.',
      );
    }
  }
  try {
    final timing = staffLeaveTiming(data);
    countStaffLeaveDays(
      (data['from_date'] as String).replaceAll('/', '-'),
      (data['to_date'] as String).replaceAll('/', '-'),
      timing,
      data['leave_type_id'] as String,
    );
    data['from_duration'] = timing['from_duration'];
    data['to_duration'] = timing['to_duration'];
  } on FormatException catch (e) {
    throw StaffLeavePayloadError('INVALID_PAYLOAD', e.message);
  }
  if (!{'Y', 'N'}.contains(data['station_leave']))
    throw const StaffLeavePayloadError(
      'INVALID_PAYLOAD',
      'Station leave must be Y or N.',
    );
  if (_truth(data['record_id']) || _truth(data['sNo'])) {
    final serial = data['sNo'];
    if (serial is! String ||
        !RegExp(r'^\d+$').hasMatch(serial) ||
        !_truth(data['original_from_date']) ||
        !_truth(data['original_to_date'])) {
      throw const StaffLeavePayloadError(
        'INVALID_PAYLOAD',
        'Leave edit requires serial number and original date range.',
      );
    }
    data['original_from_date'] = date(data['original_from_date']);
    data['original_to_date'] = date(data['original_to_date']);
  }
  if (data['confirmed'] is! bool)
    throw const StaffLeavePayloadError(
      'INVALID_PAYLOAD',
      'Confirmation must be true or false.',
    );
  return data;
}

DateTime _date(String text) {
  final match = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})$').firstMatch(text);
  if (match == null) throw const FormatException('Invalid date');
  final day = int.parse(match[1]!),
      month = int.parse(match[2]!),
      year = int.parse(match[3]!);
  if (year < 1) throw const FormatException('Invalid date');
  final result = DateTime.utc(year, month, day);
  if (result.year != year || result.month != month || result.day != day) {
    throw const FormatException('Invalid date');
  }
  return result;
}

Map<String, dynamic> staffLeaveTiming(Map<String, dynamic> data) {
  const durations = {
    '1': 'Full',
    'full': 'Full',
    'full day': 'Full',
    '2': 'Half',
    'half': 'Half',
    'half day': 'Half',
  };
  var from =
      durations[_string(_or(data['from_duration'], 'Full'))
          .trim()
          .toLowerCase()];
  var to =
      durations[_string(
        _or(data['to_duration'], _or(data['from_duration'], 'Full')),
      ).trim().toLowerCase()];
  if (from == null || to == null)
    throw const FormatException(
      'Duration must be Full or Half for each endpoint.',
    );
  if (_string(data['leave_type_id']) == '12') from = to = 'Half';
  const periods = {
    '1': 'Forenoon',
    'forenoon': 'Forenoon',
    'fn': 'Forenoon',
    'before noon': 'Forenoon',
    '2': 'Afternoon',
    'afternoon': 'Afternoon',
    'an': 'Afternoon',
    'after noon': 'Afternoon',
  };
  String? period(String key, String duration) {
    var raw = data[key];
    if (raw == null)
      raw = duration == 'Half'
          ? (data.containsKey('day_type') ? data['day_type'] : data['dayType'])
          : null;
    final nonempty = raw != null && _string(raw).trim().isNotEmpty;
    final value = nonempty ? periods[_string(raw).trim().toLowerCase()] : null;
    if (nonempty && value == null)
      throw const FormatException(
        'Day type must be Before Noon or After Noon.',
      );
    if (duration == 'Half' && value == null)
      throw const FormatException(
        'Select Before Noon or After Noon for each half-day endpoint.',
      );
    if (duration == 'Full' && value != null)
      throw const FormatException(
        'Day type applies only to a half-day endpoint.',
      );
    return value;
  }

  final fp = period('from_day_type', from), tp = period('to_day_type', to);
  return {
    'duration': from,
    'period': fp == tp ? fp : null,
    'from_duration': from,
    'to_duration': to,
    'from_period': fp,
    'to_period': tp,
  };
}

double countStaffLeaveDays(
  String fromDate,
  String toDate,
  Map<String, dynamic> timing,
  String leaveType,
) {
  final days = _date(toDate).difference(_date(fromDate)).inDays + 1;
  if (days <= 0)
    throw const FormatException('To date cannot precede From date.');
  final fd = timing['from_duration'],
      td = timing['to_duration'],
      fp = timing['from_period'],
      tp = timing['to_period'];
  if (days == 1) {
    if (fd != td || (fd == 'Half' && fp != tp))
      throw const FormatException(
        'For one date, use matching durations and the same half-day period.',
      );
    return fd == 'Half' ? 0.5 : 1.0;
  }
  if (leaveType == '12')
    throw const FormatException(
      'HCL must use one date. Select CL for a multi-day request.',
    );
  if (fd == 'Half' && fp != 'Afternoon')
    throw const FormatException(
      'A multi-day half-day start must be After Noon.',
    );
  if (td == 'Half' && tp != 'Forenoon')
    throw const FormatException(
      'A multi-day half-day end must be Before Noon.',
    );
  return days.toDouble() - (fd == 'Half' ? 0.5 : 0) - (td == 'Half' ? 0.5 : 0);
}

Map<String, dynamic> previewStaffLeave(Map<String, dynamic> data) {
  final from = normalizeStaffLeaveDate(data['from_date']);
  final to = normalizeStaffLeaveDate(
    data.containsKey('to_date') ? data['to_date'] : from,
  );
  if (from.isEmpty || to.isEmpty)
    return {'success': false, 'message': 'From and To dates are required.'};
  DateTime start, end;
  try {
    start = _date(from);
    end = _date(to);
  } on FormatException {
    return {
      'success': false,
      'message': 'Invalid date format. Use DD-MM-YYYY.',
    };
  }
  if (end.isBefore(start))
    return {
      'success': false,
      'message': 'To date cannot be earlier than From date.',
    };
  Map<String, dynamic> timing;
  try {
    timing = staffLeaveTiming(data);
  } on FormatException catch (e) {
    return {'success': false, 'code': 'BAD_DURATION', 'message': e.message};
  }
  double days;
  try {
    days = countStaffLeaveDays(
      from,
      to,
      timing,
      _string(data['leave_type_id']),
    );
  } on FormatException catch (e) {
    return {'success': false, 'code': 'BAD_DATE', 'message': e.message};
  }
  Object? defaulted(String key, Object value) =>
      data.containsKey(key) ? data[key] : value;
  return {
    'success': true,
    'message': 'Leave verification ready',
    'preview': {
      'reason_id': _string(defaulted('reason_id', '1')),
      'leave_type_id': _string(defaulted('leave_type_id', '1')),
      'from_date': from,
      'to_date': to,
      'total_days': days,
      'from_duration': timing['from_duration'],
      'to_duration': timing['to_duration'],
      'day_type': timing['period'],
      'from_day_type': timing['from_period'],
      'to_day_type': timing['to_period'],
      'station_leave':
          {
            'Y',
            'YES',
            'TRUE',
          }.contains(_string(data['station_leave']).toUpperCase())
          ? 'Y'
          : 'N',
      'address': defaulted('address', 'At Home'),
      'remark': defaulted('remark', 'Leave Application'),
    },
  };
}

/// Mirrors apply_leave's pre-confirmation branch, including its nested preview.
Map<String, dynamic> staffLeaveConfirmation(Map<String, dynamic> data) {
  final record = _string(_or(data['record_id'], _or(data['sNo'], ''))).trim();
  return {
    'success': false,
    'confirmation_required': true,
    'message': 'User confirmation required before final submission.',
    'preview': previewStaffLeave(data),
    'mode': record.isNotEmpty && !record.startsWith('LR-') ? 'edit' : 'new',
  };
}

Map<String, String>? findStaffLeaveEditTarget(
  String text,
  String originalFrom,
  String originalTo, {
  String? serialNumber,
}) {
  final table = html
      .parse(text)
      .getElementById('ContentPlaceHolder1_grdLeaveDetails');
  if (table == null) return null;
  final matches = <Map<String, String>>[];
  final digit = RegExp(r'^\d+$'), date = RegExp(r'^\d{2}-\d{2}-\d{4}$');
  final edit = RegExp(r'(?:^|_)btnEdit(?:_|$)', caseSensitive: false);
  for (final row in table.querySelectorAll('tr')) {
    final cells = row.querySelectorAll('td');
    if (cells.isEmpty) continue;
    // BeautifulSoup get_text(strip=True) joins stripped text nodes without separators.
    String strippedText(dom.Node element) => _strippedStrings(element).join();
    final serial = strippedText(cells.first);
    if (!digit.hasMatch(serial)) continue;
    final buttons = row
        .querySelectorAll('input[type="image"]')
        .where((e) => edit.hasMatch(e.id));
    if (buttons.isEmpty || buttons.first.id.isEmpty) continue;
    final dates = cells
        .map((c) => normalizeStaffLeaveDate(strippedText(c)))
        .where(date.hasMatch)
        .toList();
    if (dates.length >= 2 &&
        dates[0] == normalizeStaffLeaveDate(originalFrom) &&
        dates[1] == normalizeStaffLeaveDate(originalTo)) {
      matches.add({'button_id': buttons.first.id, 's_no': serial});
    }
  }
  final exact = serialNumber == null
      ? matches
      : matches.where((e) => e['s_no'] == serialNumber.trim()).toList();
  return exact.length == 1 ? exact.first : null;
}

bool? classifyStaffLeaveMessage(String text) {
  if (text.isEmpty) return null;
  if (RegExp(
    r'\b(?:not|never)\s+(?:(?:yet|been|be|being)\s+)*(?:applied|updated|modified|successful|approved)|unsuccess|unable|cannot|could not|नहीं|असफल|pehle se|already|पहले से|duplicate|invalid|error|त्रुटि|please enter|required|फेल|failed',
    caseSensitive: false,
  ).hasMatch(text))
    return false;
  if (RegExp(
    r'applied|success|safalta|स्वीकार|update|उपडेट|अपडेट|संशोधित|modified|modifi',
    caseSensitive: false,
  ).hasMatch(text))
    return true;
  return null;
}

/// Original server message extraction; no replacement success messages.
String? extractStaffLeaveMessage(String text) {
  final doc = html.parse(text);
  for (final id in ['msgDiv', 'msg_Success', 'MsgPopup']) {
    final element = doc.getElementById(id);
    if (element == null) continue;
    final message = _strippedStrings(element).join(' ');
    if (message.isEmpty) continue;
    final cleaned = message
        .replaceAll(RegExp(r'\bClose\b|\bबंद करें\b', caseSensitive: false), '')
        .trim();
    if (cleaned.isNotEmpty) return cleaned;
  }
  final popup = doc
      .querySelectorAll('[id]')
      .where(
        (e) => RegExp('AlreadyApplyPopup', caseSensitive: false).hasMatch(e.id),
      );
  if (popup.isNotEmpty) {
    final message = _strippedStrings(popup.first).join(' ');
    if (message.isNotEmpty) return message;
  }
  final phrase = RegExp(
    r'Leave Request (?:Applied|Modified)',
    caseSensitive: false,
  );
  // BeautifulSoup find(string=...) matches one text node, not joined parent text.
  for (final value in _strippedStrings(doc)) {
    if (phrase.hasMatch(value)) return value;
  }
  return null;
}
