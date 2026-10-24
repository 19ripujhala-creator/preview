import 'package:flutter_test/flutter_test.dart';

import 'school_reuse_cases.dart';

void main() {
  for (final entry in schoolReuseCases().entries) {
    test(entry.key, entry.value);
  }
}
