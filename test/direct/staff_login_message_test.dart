import 'package:flutter_test/flutter_test.dart';

import 'staff_login_message_cases.dart';

void main() {
  for (final entry in staffLoginMessageCases().entries) {
    test(entry.key, entry.value);
  }
}
