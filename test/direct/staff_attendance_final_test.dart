import 'package:flutter_test/flutter_test.dart';

import 'staff_attendance_final_cases.dart';

void main() {
  for (final entry in staffFinalRegressionCases().entries) {
    test(entry.key, entry.value);
  }
}
