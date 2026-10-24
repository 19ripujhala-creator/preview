import 'package:flutter_test/flutter_test.dart';

import 'school_session_snapshot_cases.dart';

void main() {
  for (final entry in schoolSessionSnapshotCases().entries) {
    test(entry.key, entry.value);
  }
}
