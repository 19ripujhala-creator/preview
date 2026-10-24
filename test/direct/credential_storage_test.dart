import 'package:flutter_test/flutter_test.dart';

import 'credential_storage_cases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final entry in credentialStorageCases().entries) {
    test(entry.key, entry.value);
  }
}
