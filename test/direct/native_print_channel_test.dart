import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/shaladarpan/direct/native_print_browser.dart';
import '../../lib/services/portals/shaladarpan/direct/nic_catalog_worker.dart';

class PrintChannel extends MethodChannel {
  PrintChannel() : super('offline-print');
  final calls = <(String, Map<String, Object?>)>[];
  Object? value;
  Object? failure;
  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    calls.add((method, Map<String, Object?>.from(arguments as Map)));
    if (failure != null) throw failure!;
    return (method == 'begin' ? 'session' : value) as T?;
  }
}

void main() {
  final base = Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1');
  test(
    'same channel handles iOS native containers and Android encoded containers',
    () async {
      final channel = PrintChannel();
      final browser = PlatformNativePrintBrowser(channel: channel);
      await browser.begin(base, {'session': 'cookie'});
      channel.value = {
        'rows': [1, 2],
      };
      expect(await browser.evaluate('portalRead()'), {
        'rows': [1, 2],
      });
      channel.value = '{"rows":[1,2]}';
      expect(await browser.evaluate('portalRead()'), {
        'rows': [1, 2],
      });
      expect(channel.calls.last.$2['token'], 'session');
    },
  );
  test(
    'Staff scoped cookies keep path/duplicate names at native handoff',
    () async {
      final channel = PrintChannel();
      final browser = PlatformNativePrintBrowser(channel: channel);
      final cookies = [
        {
          'name': 'session',
          'value': 'one',
          'domain': base.host,
          'path': '/SD1',
        },
        {
          'name': 'session',
          'value': 'two',
          'domain': base.host,
          'path': '/SD1/Home/Staff',
        },
      ];
      await browser.beginStaff(base, cookies);
      expect(channel.calls.single.$2['portal'], 'staff');
      expect(channel.calls.single.$2['scopedCookies'], cookies);
      channel.value = cookies;
      expect(await browser.staffCookies(), cookies);
    },
  );
  test(
    'native alert message reaches existing browser error unchanged',
    () async {
      final channel = PrintChannel();
      final browser = PlatformNativePrintBrowser(channel: channel);
      await browser.begin(base, {'session': 'cookie'});
      channel.failure = PlatformException(
        code: 'PORTAL_MESSAGE',
        message: 'Portal original message',
      );
      await expectLater(
        browser.navigate('Home/School/SchoolStudentProfiles_New.aspx'),
        throwsA(
          isA<NicError>().having(
            (e) => e.message,
            'portal message',
            'Portal original message',
          ),
        ),
      );
    },
  );
  test('merge accepts only native PDF bytes', () async {
    final channel = PrintChannel();
    final browser = PlatformNativePrintBrowser(channel: channel);
    await browser.begin(base, {'session': 'cookie'});
    channel.value = Uint8List.fromList('%PDF-1.7'.codeUnits);
    expect(await browser.merge(['one', 'two']), channel.value);
    expect(channel.calls.last.$2['ids'], ['one', 'two']);
    channel.value = Uint8List.fromList('error'.codeUnits);
    await expectLater(browser.merge(['one']), throwsA(isA<NicError>()));
  });
  test('close clears session ownership even if native cleanup fails', () async {
    final channel = PrintChannel();
    final browser = PlatformNativePrintBrowser(channel: channel);
    await browser.begin(base, {'session': 'cookie'});
    channel.failure = PlatformException(
      code: 'SESSION_CHANGED',
      message: 'closed',
    );
    await expectLater(browser.close(), throwsA(isA<NicError>()));
    final count = channel.calls.length;
    await browser.close();
    expect(channel.calls.length, count);
  });
  test('unsupported Staff margin stops before the native channel', () async {
    final channel = PrintChannel();
    final browser = PlatformNativePrintBrowser(channel: channel);
    await browser.beginStaff(base, [
      {'name': 'session', 'value': 'cookie', 'domain': base.host, 'path': '/'},
    ]);
    final count = channel.calls.length;
    await expectLater(
      browser.renderStaffPopup(marginMm: 7),
      throwsArgumentError,
    );
    expect(channel.calls.length, count);
  });
}
