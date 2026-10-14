// Pure Dart parity layer for Python student_attendance_worker.py.
// NO HTTP, cookies, portal mutations, or personal-data logging.
class AttendanceParityException implements Exception {
  const AttendanceParityException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

class StudentAttendanceParity {
  static const statuses = <String>['Present', 'Absent', 'OnLeave', 'OnMedical'];

  static String normalizeSr(Object? raw) {
    final s = (raw?.toString() ?? '').replaceAll(RegExp(r'\s+'), '');
    if (s.isEmpty || s == '-') return '';
    final stripped = s.replaceFirst(RegExp(r'^0+'), '');
    return stripped.isEmpty ? '0' : stripped;
  }

  static String normalizeDate(String input) {
    final match = RegExp(r'^\s*(\d{1,2})[/-](\d{1,2})[/-](\d{4})\s*$').firstMatch(input);
    if (match == null) throw const AttendanceParityException('BAD_DATE', 'Expected DD/MM/YYYY');
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final date = DateTime.utc(year, month, day);
    if (date.day != day || date.month != month || date.year != year) {
      throw const AttendanceParityException('BAD_DATE', 'Invalid attendance date');
    }
    return '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year';
  }

  static String? normalizeStatus(String label, int index) {
    final value = label.toLowerCase().replaceAll(' ', '');
    if (value.contains('medical') || value.contains('चिकित्सा')) return 'OnMedical';
    if (value.contains('leave') || value.contains('अवकाश')) return 'OnLeave';
    if (value.contains('absent') || value.contains('अनुपस्थित')) return 'Absent';
    if (value.contains('present') || value.contains('उपस्थित')) return 'Present';
    return index >= 0 && index < statuses.length ? statuses[index] : null;
  }

  static String identity(Map<String, Object?> student) {
    final sr = normalizeSr(student['srNo']);
    if (sr.isNotEmpty) return 'sr:$sr';
    final serial = (student['serialNo'] ?? student['rollNo'] ?? '').toString().trim();
    final name = (student['name'] ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    return 'row:$serial:$name';
  }

  static String requestedStatus(Map<String, Object?> row) {
    final explicit = row['status']?.toString() ?? '';
    if (explicit.isNotEmpty) {
      if (!statuses.contains(explicit)) {
        throw const AttendanceParityException('MATCH_MISMATCH', 'Unknown attendance status');
      }
      return explicit;
    }
    return row['present'] == false ? 'Absent' : 'Present';
  }

  // Mirrors _apply_updates matching, minus HTML radio selection.
  // Does not infer portal save success from these validations.
  static AttendanceChangePlan plan({
    required List<Map<String, Object?>> current,
    required List<Map<String, Object?>> requested,
  }) {
    if (requested.isEmpty || current.length != requested.length) {
      throw const AttendanceParityException('MATCH_MISMATCH', 'Student count mismatch');
    }
    final updates = <String, String>{};
    for (final row in requested) {
      final key = identity(row);
      if (updates.containsKey(key)) {
        throw const AttendanceParityException('MATCH_MISMATCH', 'Duplicate student identity');
      }
      updates[key] = requestedStatus(row);
    }
    final expected = <String, String>{};
    var changed = 0;
    for (final row in current) {
      final key = identity(row);
      final wanted = updates[key];
      if (wanted == null || expected.containsKey(key)) {
        throw const AttendanceParityException('MATCH_MISMATCH', 'Student identity mismatch');
      }
      expected[key] = wanted;
      if (row['status'] != wanted) changed++;
    }
    if (expected.length != updates.length) {
      throw const AttendanceParityException('MATCH_MISMATCH', 'Incomplete attendance roster');
    }
    return AttendanceChangePlan(expected, changed);
  }

  static bool readBackMatches(AttendanceChangePlan plan, List<Map<String, Object?>> actual) {
    if (plan.expected.length != actual.length) return false;
    final found = <String, String>{};
    for (final row in actual) {
      final key = identity(row);
      final status = row['status'];
      if (found.containsKey(key) || status is! String || !statuses.contains(status)) {
        return false;
      }
      found[key] = status;
    }
    if (found.length != plan.expected.length) return false;
    for (final entry in plan.expected.entries) {
      if (found[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool canCorrectMarkedAttendance({
    required String portalDate,
    required DateTime indiaToday,
  }) => normalizeDate(portalDate) ==
      '${indiaToday.day.toString().padLeft(2, '0')}/${indiaToday.month.toString().padLeft(2, '0')}/${indiaToday.year}';
}

class AttendanceChangePlan {
  AttendanceChangePlan(Map<String, String> expected, this.changedCount)
      : expected = Map.unmodifiable(expected);
  final Map<String, String> expected;
  final int changedCount;
}
