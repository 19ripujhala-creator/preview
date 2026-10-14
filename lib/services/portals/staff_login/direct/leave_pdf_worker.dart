/// Native PDF section of leave_apply_worker.py. Apply/Update remain unconverted.
import 'package:html/parser.dart' as html;

import 'http_session.dart';
import 'http_login.dart' show staffLower;
import 'native_print_worker.dart';
import 'portal_state.dart';

const nonLeaveModalIds = ['MsgPopup', 'AlreadyApplyPopup', 'selectPopup4'];
const leaveModalRequiredStrings = <String, List<String>>{
  'divCLLeaveApplication': [
    'स्कूल शिक्षा विभाग',
    'आकस्मिक अवकाश के लिए आवेदन प्रपत्र',
    'आवेदक का नाम',
    'पद नाम',
  ],
  'divAllLeaveApplication': [
    'स्कूल शिक्षा विभाग',
    'राजस्थान सेवा नियमों के अन्तर्गत अवकाश के लिए आवेदन प्रपत्र',
    'आवेदक का नाम',
    'पद नाम',
  ],
  'divCCLApplication': [
    'APPLICATION FOR CHILD CARE LEAVE',
    'Name of the Applicant',
    'Designation',
  ],
};
const openModalFunctionToId = {
  'OpenPrintPopAllLeave': 'divAllLeaveApplication',
  'OpenPrintPopClLeave': 'divCLLeaveApplication',
  'OpenPrintPopCClLeave': 'divCCLApplication',
  'OpenPrintPopApplicationStatus': 'divApplicationStatus',
};

String normalizeStaffLeaveDate(String? value) {
  var text = (value ?? '').trim().split('T').first.split(' ').first.trim();
  final dash = RegExp(r'^\d{2}-\d{2}-\d{4}').firstMatch(text);
  if (dash != null) return dash[0]!;
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
  if (iso != null) return '${iso[3]}-${iso[2]}-${iso[1]}';
  final slash = RegExp(r'^(\d{2})/(\d{2})/(\d{4})').firstMatch(text);
  if (slash != null) return '${slash[1]}-${slash[2]}-${slash[3]}';
  return text;
}

String? leaveResponseModal(String response) {
  final match = RegExp(
    r'scriptStartupBlock\|ScriptContentNoTags\|(Open\w+)\(\);',
  ).firstMatch(response);
  return match == null ? null : openModalFunctionToId[match[1]];
}

({String? button, List<int> pages}) findLeaveViewOnPage(
  String source, {
  String? sNo,
  String? fromDate,
  String? toDate,
  String? leaveType,
}) {
  final doc = html.parse(source);
  final tables = doc
      .querySelectorAll('table')
      .where((e) => e.id.contains('grdLeaveDetails'));
  if (tables.isEmpty)
    throw const StaffPortalError(
      'PRINT_CAPTURE_FAILED',
      'Leave grid not found on Applied Leaves page.',
    );
  final sno = (sNo ?? '').trim();
  final from = normalizeStaffLeaveDate(fromDate),
      to = normalizeStaffLeaveDate(toDate);
  final type = staffLower(leaveType ?? '').split('/').first.trim();
  for (final row in tables.first.querySelectorAll('tr')) {
    final cols = row.querySelectorAll('td');
    if (cols.isEmpty) continue;
    final rowNo = staffText(cols.first);
    if (!RegExp(r'^\d+$').hasMatch(rowNo)) continue;
    final dates = cols
        .map((e) => normalizeStaffLeaveDate(staffText(e, ' ')))
        .where((value) => RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(value))
        .toList();
    final snoOk = sno.isEmpty || rowNo == sno;
    final datesOk =
        (from.isEmpty || (dates.isNotEmpty && dates[0] == from)) &&
        (to.isEmpty || (dates.length >= 2 && dates[1] == to));
    final strongMatch =
        (sno.isNotEmpty && snoOk) ||
        (from.isNotEmpty && to.isNotEmpty && datesOk);
    final rowType = cols.length > 1 ? staffLower(staffText(cols[1], ' ')) : '';
    final typeOk =
        strongMatch ||
        type.runes.length <= 2 ||
        type.contains(rowType) ||
        rowType.contains(type);
    if (snoOk && datesOk && typeOk && (sno.isNotEmpty || from.isNotEmpty)) {
      final buttons = row
          .querySelectorAll('input[id]')
          .where((e) => e.id.toLowerCase().contains('imgview'));
      if (buttons.isNotEmpty) return (button: buttons.first.id, pages: <int>[]);
    }
  }
  final pages = <int>{};
  for (final link in doc.querySelectorAll('a[href]')) {
    final match = RegExp(r'Page\$(\d+)').firstMatch(link.attributes['href']!);
    if (match != null) pages.add(int.parse(match[1]!));
  }
  return (button: null, pages: pages.toList()..sort());
}

void validateStaffLeavePopup(
  String source,
  String modal,
  String fromDate,
  String toDate,
) {
  final missing = (leaveModalRequiredStrings[modal] ?? [])
      .where((text) => !source.contains(text))
      .toList();
  if (missing.isNotEmpty) {
    throw StaffPortalError(
      'PRINT_CAPTURE_FAILED',
      'Captured popup ($modal) is missing expected official portal text $missing — refusing to generate a PDF from unverified content.',
    );
  }
  final from = normalizeStaffLeaveDate(fromDate),
      to = normalizeStaffLeaveDate(toDate);
  if (from.isNotEmpty && !source.contains(from)) {
    throw StaffPortalError(
      'PRINT_CAPTURE_FAILED',
      'Captured popup does not contain the selected From date ($from) — possible wrong-row capture.',
    );
  }
  if (to.isNotEmpty && !source.contains(to)) {
    throw StaffPortalError(
      'PRINT_CAPTURE_FAILED',
      'Captured popup does not contain the selected To date ($to) — possible wrong-row capture.',
    );
  }
}

class LeavePdfWorker extends StaffNativePrintWorker {
  LeavePdfWorker({required super.browser, required super.check});
  static const modalExpression = '''(() => {
    const excluded=['MsgPopup','AlreadyApplyPopup','selectPopup4'];
    const m=Array.from(document.querySelectorAll('.modal')).find(m => {
      if(excluded.includes(m.id)) return false;
      return getComputedStyle(m).display==='block' || m.classList.contains('in') || m.classList.contains('show');
    });
    if(!m) return null;
    const b=m.querySelector('input[type="image"],input[id*="ImageButton"],input[id*="Printer"],input[id*="img"],button[onclick*="CallPrint"]');
    return {modal_id:m.id,button_id:b ? b.id : null,text_length:(m.innerText || '').trim().length};
  })()''';

  Future<void> dismissPopups() async {
    await evaluate('''(() => {
      for(const selector of ['#MsgPopup button','#MsgPopup .close','#AlreadyApplyPopup button','#AlreadyApplyPopup .close']) {
        const b=document.querySelector(selector);
        if(b && b.getClientRects().length) { b.click(); break; }
      }
      document.querySelectorAll('#MsgPopup,#AlreadyApplyPopup').forEach(p=>{
        p.style.display='none';p.classList.remove('in','show');p.setAttribute('aria-hidden','true');
      });
      document.querySelectorAll('.modal-backdrop').forEach(b=>{if(!b.classList.contains('leave-modal-backdrop'))b.remove()});
      return true;
    })()''');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  Future<void> selectAll() async {
    await waitFor(
      "!window.Sys || !Sys.WebForms || !Sys.WebForms.PageRequestManager || !Sys.WebForms.PageRequestManager.getInstance().get_isInAsyncPostBack()",
      const Duration(seconds: 8),
      'The leave history filter is still busy.',
    );
    const id = 'ContentPlaceHolder1_rdoLeaveApplicationType_1';
    if (await evaluate("!!document.getElementById('$id')?.checked") == true)
      return;
    await dismissPopups();
    await waitFor(
      "!!document.getElementById('$id')",
      const Duration(seconds: 5),
      'The leave history filter is unavailable.',
    );
    await browser.postback('''(() => {
      const el=document.getElementById('$id');
      if(el.tagName!=='INPUT' || el.type!=='radio' || !el.name) throw new Error('Leave history filter is not a named radio input.');
      if(el.disabled || el.matches(':disabled')) throw new Error('Leave history filter is disabled.');
      el.click();return true;
    })()''');
    await waitFor(
      "!!document.getElementById('$id')?.checked",
      const Duration(seconds: 12),
      'The Staff portal did not retain the requested leave history filter.',
    );
    await waitFor(
      "!!document.querySelector(\"table[id*='grdLeaveDetails']\")?.getClientRects().length",
      const Duration(seconds: 6),
      'Leave grid not found on Applied Leaves page.',
    );
  }

  Future<String> findView({
    String? sNo,
    String? fromDate,
    String? toDate,
    String? leaveType,
  }) async {
    final visited = <int>{}, queue = <int>[1];
    while (queue.isNotEmpty && visited.length < 200) {
      final page = queue.removeAt(0);
      if (!visited.add(page)) continue;
      if (page > 1) {
        await browser.postback('''(() => {
          const link=document.querySelector("a[href*='Page\$$page']");
          if(link) link.click();
          else __doPostBack('ctl00\$ContentPlaceHolder1\$grdLeaveDetails','Page\$$page');
          return true;
        })()''');
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      final current = await document();
      if (staffDocumentFailure(current.url, current.text) ==
          'SESSION_EXPIRED') {
        throw const StaffPortalError(
          'SESSION_EXPIRED',
          'Session expired while locating the leave row.',
        );
      }
      final found = findLeaveViewOnPage(
        current.text,
        sNo: sNo,
        fromDate: fromDate,
        toDate: toDate,
        leaveType: leaveType,
      );
      if (found.button != null) return found.button!;
      for (final number in found.pages) {
        if (!visited.contains(number) && !queue.contains(number))
          queue.add(number);
      }
    }
    throw StaffPortalError(
      'PRINT_CAPTURE_FAILED',
      "Requested leave (S.No=$sNo, $fromDate to $toDate, Type=$leaveType) not found in the portal's grid.",
    );
  }

  Future<Map<String, dynamic>> generate({
    String? sNo,
    String? fromDate,
    String? toDate,
    String? leaveType,
  }) async {
    final from = normalizeStaffLeaveDate(fromDate);
    final to = normalizeStaffLeaveDate(
      toDate == null || toDate.isEmpty ? from : toDate,
    );
    if ((sNo ?? '').trim().isEmpty && from.isEmpty) {
      throw const StaffPortalError(
        'INVALID_PAYLOAD',
        'Provide the leave S.No or From date.',
      );
    }
    await browser.navigate('Home/Staff/Staff_LeaveApplication_Applied.aspx');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await requireDocument(
      'Applied Leaves',
      path: 'Staff_LeaveApplication_Applied.aspx',
    );
    await protectPopup();
    await dismissPopups();
    await selectAll();
    final view = await findView(
      sNo: sNo,
      fromDate: from,
      toDate: to,
      leaveType: leaveType,
    );
    await evaluate(
      "(() => {try {if(window.\$) {\$('.modal').modal('hide');\$('.modal-backdrop').remove();}}catch(_){} return true;})()",
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Exactly one View dispatch. A failed response must never re-click the row.
    await browser.postback(clickId(view, 'Leave View control is disabled.'));
    final response =
        await evaluate('[window.__rajPrintPost?.text || ""]') as List;
    final expected = leaveResponseModal(response.first as String);
    if (expected == 'divApplicationStatus') {
      throw const StaffPortalError(
        'PRINT_CAPTURE_FAILED',
        "The portal's own response shows this leave only triggers the status view (OpenPrintPopApplicationStatus), which has no Print button — not printable this way.",
      );
    }
    await waitFor(
      '!!($modalExpression)',
      const Duration(seconds: 12),
      'No leave modal became visible after clicking View.',
    );
    await waitFor(
      '(($modalExpression)?.text_length || 0) > 100',
      const Duration(seconds: 8),
      'The leave modal did not finish loading.',
    );
    final active = await evaluate(modalExpression) as Map;
    final modal = active['modal_id'] as String;
    if (expected != null && modal != expected) {
      throw StaffPortalError(
        'PRINT_CAPTURE_FAILED',
        "Mismatch between the portal's own trigger response ($expected) and the modal that actually became visible ($modal) — refusing to proceed.",
      );
    }
    final printId = active['button_id'];
    if (printId is! String || printId.isEmpty) {
      throw StaffPortalError(
        'PRINT_CAPTURE_FAILED',
        modal == 'divApplicationStatus'
            ? "This leave record only opened the status view (divApplicationStatus), which the portal never gives a Print button for — it isn't printable this way."
            : 'Active leave modal (#$modal) opened but no print button could be located inside it.',
      );
    }
    await browser.openPopup(
      clickId(printId, 'Leave print control is disabled.'),
    );
    try {
      await waitFor(
        "document.readyState === 'complete'",
        const Duration(seconds: 5),
        'Could not intercept native print window.',
        popup: true,
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      validateStaffLeavePopup(
        (await document(popup: true)).text,
        modal,
        from,
        to,
      );
      return {
        ...result(await capture(10), 'leave.pdf'),
        'source': 'native_$modal',
        'leave_format': modal,
      };
    } finally {
      await browser.closePopup();
      await dismissPopups();
    }
  }
}
