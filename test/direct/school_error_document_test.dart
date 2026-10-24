import 'package:flutter_test/flutter_test.dart';

import 'school_error_document_cases.dart';

void main() {
  for (final entry in schoolErrorDocumentCases().entries) {
    test(entry.key, entry.value);
  }
}
