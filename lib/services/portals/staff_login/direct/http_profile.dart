/// File equivalent of Staff http_profile.py; authenticated, read-only requests.
import 'dart:async';
import 'dart:io';

import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';

import 'http_session.dart';

const staffP10Path = '/Home/Staff/Staff_P10_DetailsV2.aspx';
Map<String, String> staffProfileFields(String text, String fallbackUser) {
  final doc = html.parse(text);
  final name =
      doc.querySelector('div.widget-heading') ??
      doc.querySelector('#ContentPlaceHolder1_lblStaffName') ??
      doc.querySelector('#ContentPlaceHolder1_lblEmployeeName');
  final designation =
      doc.querySelector('div.widget-subheading') ??
      doc.querySelector('#ContentPlaceHolder1_lblStaffDesignation') ??
      doc.querySelector('#ContentPlaceHolder1_lblEmployeePostName');
  final value = name == null ? '' : staffText(name, ' ');
  if (value.isEmpty)
    throw const StaffHttpError(
      'INVALID_RESULT',
      'Staff profile name could not be read.',
    );
  var nic = fallbackUser;
  final id = doc
      .querySelectorAll('span[id]')
      .where((e) => RegExp('grd_NMMSApplicationFilled_lblName').hasMatch(e.id))
      .firstOrNull;
  if (id != null)
    nic = RegExp(r'\((\d+)\)').firstMatch(staffText(id, ' '))?.group(1) ?? nic;
  return {
    'name': value,
    'designation': designation == null
        ? 'Unknown'
        : staffText(designation, ' '),
    'nicId': nic.isEmpty ? '--' : nic,
    'staffLoginId': fallbackUser.isNotEmpty
        ? fallbackUser
        : (nic.isEmpty ? '--' : nic),
  };
}

Map<String, String> staffP10Fields(String text) {
  final Element? status = html
      .parse(text)
      .querySelectorAll('span[id]')
      .where((e) => e.id.contains('spn_StatusPercen'))
      .firstOrNull;
  if (status == null)
    return {
      'p10Status': 'Unknown',
      'isLocked': 'false',
      'p10StatusKnown': 'false',
    };
  final value = staffText(status, ' '), locked = value.contains('100%');
  return {
    'p10Status': locked ? 'Active / Locked' : 'Pending ($value)',
    'isLocked': '$locked',
    'p10StatusKnown': 'true',
  };
}

Future<Map<String, dynamic>> fetchStaffHttpProfile(StaffHttpSession session) =>
    session.exclusive(() async {
      if (!session.authenticated ||
          session.base == null ||
          (session.user ?? '').isEmpty)
        throw const StaffHttpError(
          'SESSION_EXPIRED',
          'Staff session is not authenticated.',
        );
      final base = session.base!;
      final home = await session.client.get('$base$staffHomePath');
      if (!staffSameNode(base, home.url.toString()) ||
          !authenticatedStaffHome(home))
        throw const StaffHttpError(
          'SESSION_NOT_VERIFIED',
          'Staff Home did not verify the active session.',
        );
      final profile = staffProfileFields(home.text, session.user!);
      // Only a transport failure is recoverable. Portal errors remain authoritative.
      try {
        final p10 = await session.client.get('$base$staffP10Path');
        if (!staffSameNode(base, p10.url.toString()))
          throw const StaffHttpError(
            'INVALID_REDIRECT',
            'P10 redirected outside the Staff Portal node.',
          );
        if (p10.statusCode != 200)
          throw StaffHttpError(
            'PORTAL_RESPONSE_ERROR',
            'P10 returned HTTP ${p10.statusCode}.',
          );
        if (html
                .parse(p10.text)
                .querySelector('#txt_Username, #txtUPNswd, #btn_StaffLogin') !=
            null)
          throw const StaffHttpError(
            'SESSION_NOT_VERIFIED',
            'P10 returned the Staff login form.',
          );
        if (p10.text.toLowerCase().contains('server error in'))
          throw const StaffHttpError(
            'PORTAL_RESPONSE_ERROR',
            'P10 returned a server error.',
          );
        profile.addAll(staffP10Fields(p10.text));
      } on StaffHttpError {
        rethrow;
      } on IOException {
        profile.addAll(staffP10Fields(''));
      } on TimeoutException {
        profile.addAll(staffP10Fields(''));
      }
      return {'success': true, 'profile': profile};
    });
