import 'package:flutter_test/flutter_test.dart';

import 'staff_leave_guard_cases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final entry in staffLeaveGuardCases().entries) {
    test(entry.key, entry.value);
  }
}
