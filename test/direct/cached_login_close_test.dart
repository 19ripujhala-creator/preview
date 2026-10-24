import 'package:flutter_test/flutter_test.dart';

import 'cached_login_close_cases.dart';

void main() {
  for (final entry in cachedLoginCloseCases().entries) {
    test(entry.key, entry.value);
  }
}
