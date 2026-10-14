/// Operational conversion of student/study_certificate_worker.py.
/// Fresh SR lookup, exact record selection and the original print popup.
part of 'native_print_worker.dart';

class StudyCertificateWorker extends NativePrintWorker {
  StudyCertificateWorker({required super.browser, required super.check});
  static const studyPath = 'Home/School/RMSA_Student_SchoolCertificate.aspx';
  static String certificateLink(
    List<Map<String, dynamic>> rows,
    String sr, {
    String notice = '',
  }) {
    final normalized = sr.replaceFirst(RegExp(r'^0+'), '');
    final key = normalized.isEmpty ? '0' : normalized;
    final matching = rows
        .where(
          (row) => (row['cells'] as List).any(
            (cell) =>
                RegExp('^0*${RegExp.escape(key)}\$').hasMatch(cell as String),
          ),
        )
        .toList();
    if (matching.length != 1 ||
        (matching.single['links'] as List).length != 1) {
      if (rows.isEmpty)
        throw NicError(
          'NOT_FOUND',
          notice.isEmpty
              ? 'No certificate record was returned for this SR number.'
              : notice,
        );
      throw const NicError(
        'MATCH_MISMATCH',
        'Portal result does not uniquely match the requested SR number.',
      );
    }
    return (matching.single['links'] as List).single as String;
  }

  Future<Map<String, dynamic>> studyPdf(
    String school,
    String sr, {
    void Function(int, int)? progress,
  }) async {
    sr = sr.trim();
    if (!RegExp(r'^[0-9]{1,30}$').hasMatch(sr))
      throw const NicError('BAD_SR', 'Enter a valid SR number.');
    check();
    await browser.navigate(studyPath);
    await _ready();
    await _eval(
      "(() => {const e=document.getElementById('ContentPlaceHolder1_txtSR');if(!e)throw new Error('Portal SR input missing');e.value=${jsonEncode(sr)};return null;})()",
    );
    await browser.postback(
      "(() => {document.getElementById('ContentPlaceHolder1_Button4').click();return null;})()",
    );
    await _ready();
    progress?.call(1, 4);
    final rows = (await _eval(
      '''(() => Array.from(document.querySelectorAll('#ContentPlaceHolder1_grdVocSubStu tr'))
      .map(row=>({cells:Array.from(row.querySelectorAll('td')).map(td=>td.innerText.trim()),
      links:Array.from(row.querySelectorAll('a[id*="btnUpdate"]')).map(a=>a.id)})).filter(row=>row.links.length))()''',
    ) as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
    final notice = rows.isEmpty
        ? ((await _eval(
                "[Array.from(document.querySelectorAll('#ContentPlaceHolder1_upPnl,[id*=\"msg\"],[id*=\"Message\"]')).map(n=>n.innerText.trim()).filter(Boolean).join('\\n')]",
              ) as List).single
              as String)
        : '';
    final link = certificateLink(rows, sr, notice: notice);
    await browser.postback(
      '(() => {document.getElementById(${jsonEncode(link)}).click();return null;})()',
    );
    await _ready();
    await _wait(
      "!!document.getElementById('DIV_Student_Result')?.getClientRects().length && !!document.getElementById('dvReport')?.getClientRects().length",
      const Duration(seconds: 15),
    );
    final expected =
        (await _eval(
              "[document.getElementById('dvReport').innerText]",
            ) as List).single
            as String;
    if (expected.trim().length < 30)
      throw const NicError(
        'PAGE_NOT_READY',
        'Portal certificate is not ready to print.',
      );
    progress?.call(2, 4);
    await _eval(NativePrintWorker.protectPopup);
    check();
    try {
      await browser.openPopup(
        "(() => {const el=document.getElementById('ContentPlaceHolder1_ImageButton4');if(!el)throw new Error('Portal print button missing');el.addEventListener('click',e=>e.preventDefault(),{once:true});el.click();return null;})()",
      );
      await _assets(30, certificate: true);
      final actual =
          (await _eval('[document.body.innerText]', popup: true) as List).single
              as String;
      String normalize(String value) => value.replaceAll(RegExp(r'\s+'), '');
      if (!normalize(actual).contains(normalize(expected)))
        throw const NicError(
          'MATCH_MISMATCH',
          'Portal print window does not match the selected certificate.',
        );
      progress?.call(3, 4);
      check();
      final id = await browser.renderPopup();
      check();
      final bytes = await browser.merge([id]);
      check();
      progress?.call(4, 4);
      return {
        'success': true,
        'school_id': school,
        'sr_no': sr,
        'filename': 'Study_Certificate_${school}_SR_$sr.pdf',
        'pdf_base64': base64Encode(bytes),
      };
    } finally {
      try {
        await browser.closePopup();
      } catch (_) {}
    }
  }
}
