import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/school_http.dart';
import 'package:shaladarpan/services/portals/staff_login/direct/http_session.dart';
import 'package:shaladarpan/services/portals/staff_login/direct/http_profile.dart';

class _Transport implements StaffTransport {
  final urls = <String>[];
  bool redirect = false;
  @override
  final jar = SchoolCookieJar();
  @override
  Future<SchoolHttpReply> get(
    String url, {
    Map<String, String> headers = const {},
    Duration? timeout,
    bool followRedirects = true,
  }) async {
    urls.add(url);
    final text = url.endsWith(staffHomePath)
        ? '<a id="lnkLogout"></a><div class="widget-heading">Teacher Name</div><div class="widget-subheading">Teacher L1</div>'
        : '<span id="spn_StatusPercen">100%</span>';
    return SchoolHttpReply(
      Uri.parse(redirect ? 'https://example.com/other' : url),
      200,
      Uint8List.fromList(utf8.encode(text)),
      {},
    );
  }

  @override
  Future<SchoolHttpReply> post(
    String url, {
    Map<String, String>? data,
    String? content,
    Map<String, String> headers = const {},
    bool followRedirects = true,
  }) => throw StateError('Identity must never POST');
  @override
  void close() {}
}

StaffHttpSession _session(_Transport t) => StaffHttpSession(client: t)
  ..authenticated = true
  ..base = 'https://rajshaladarpan.rajasthan.gov.in/SD4'
  ..user = '99';
void main() {
  test(
    'identity returns designation after one verified Home GET without P10',
    () async {
      final t = _Transport();
      final r = await fetchStaffHttpProfile(_session(t), includeP10: false);
      expect(r['success'], true);
      expect((r['profile'] as Map)['designation'], 'Teacher L1');
      expect(t.urls.length, 1);
      expect(t.urls.single.endsWith(staffHomePath), true);
    },
  );
  test('default full profile still reads P10', () async {
    final t = _Transport();
    final r = await fetchStaffHttpProfile(_session(t));
    expect(r['success'], true);
    expect(t.urls.length, 2);
    expect(t.urls.last.endsWith(staffP10Path), true);
  });
  test('identity cannot return profile from another node', () async {
    final t = _Transport()..redirect = true;
    await expectLater(
      fetchStaffHttpProfile(_session(t), includeP10: false),
      throwsA(isA<StaffHttpError>()),
    );
  });
  test('identity rejects unauthenticated session before network', () async {
    final t = _Transport();
    final session = _session(t)..authenticated = false;
    await expectLater(
      fetchStaffHttpProfile(session, includeP10: false),
      throwsA(isA<StaffHttpError>()),
    );
    expect(t.urls, isEmpty);
  });
}
