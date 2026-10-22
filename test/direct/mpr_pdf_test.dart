import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/rajsims/direct/mpr_pdf.dart';

void main() {
  final fixture = jsonDecode(
    File('test/direct/fixtures/python_mpr_pdf.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final item in fixture['cases'] as List) {
    test('original Python MPR commands: ${item['name']}', () {
      final plan = buildMprPdfPlan(
        Map<String, dynamic>.from(item['payload'] as Map),
      );
      expect(plan.commands, equals(item['commands']));
    });
  }
  for (final item in fixture['errors'] as List) {
    test('original Python MPR validation: ${item['name']}', () {
      expect(
        () =>
            buildMprPdfPlan(Map<String, dynamic>.from(item['payload'] as Map)),
        throwsA(
          isA<MprPdfError>().having(
            (e) => e.message,
            'source message',
            item['message'],
          ),
        ),
      );
    });
  }
  for (final item in fixture['amount_cases'] as List) {
    test('original Python half-up amount: ${item[0]}', () {
      expect(mprAmount(item[0]), item[1]);
    });
  }
  for (final item in fixture['name_cases'] as List) {
    test('original Python name: ${item[0]}', () {
      expect(mprPersonName(item[0]), item[1]);
    });
  }
}
