import 'package:flutter_test/flutter_test.dart';

import 'staff_restore_cases.dart';

void main() {
  for (final entry in staffRestoreCases().entries) {
    test(entry.key, entry.value);
  }
}
