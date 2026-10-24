import 'package:flutter_test/flutter_test.dart';

import 'staff_cookie_ownership_cases.dart';

void main() {
  for (final entry in staffCookieOwnershipCases().entries) {
    test(entry.key, entry.value);
  }
}
