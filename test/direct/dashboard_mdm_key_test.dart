import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/services/portals/shaladarpan/dashboard_mdm_key.dart';

void main() {
  test('MDM producer/listener identity includes the portal mode', () {
    expect(
      dashboardMdmDayKey('123', DateTime(2026, 10, 29), direct: true),
      'direct/123/2026-10-29',
    );
    expect(
      dashboardMdmDayKey('123', DateTime(2026, 10, 29), direct: false),
      'backend/123/2026-10-29',
    );
  });
  test('school and day changes cannot reuse the old notification identity', () {
    final old = dashboardMdmDayKey('123', DateTime(2026, 10, 29), direct: true);
    expect(
      dashboardMdmDayKey('456', DateTime(2026, 10, 29), direct: true),
      isNot(old),
    );
    expect(
      dashboardMdmDayKey('123', DateTime(2026, 10, 30), direct: true),
      isNot(old),
    );
  });
}
