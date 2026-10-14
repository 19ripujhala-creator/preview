/// Operational conversion of student/nic_sheet_worker.py.
/// The portal builds every original preview/CallPrint document.
part of 'native_print_worker.dart';

class NicSheetWorker extends NativePrintWorker {
  NicSheetWorker({required super.browser, required super.check});
  static const sectionId = 'ContentPlaceHolder1_ddlSection';
  static const gridId = 'ContentPlaceHolder1_grdStudentProfile';
  Future<Map<String, dynamic>> nicCatalog(String school) async {
    check();
    await browser.navigate(NicCatalogWorker.path);
    await _ready();
    final selected = NicCatalogWorker.sessionOption(
      await _options(NicCatalogWorker.sessionId),
    );
    if (selected == null)
      throw const NicError(
        'PAGE_NOT_READY',
        'Portal academic sessions are not available.',
      );
    if (selected['selected'] != true)
      await _select(NicCatalogWorker.sessionId, selected['id'] as String);
    final classes = await _options(NicCatalogWorker.classId);
    if (classes.isEmpty)
      throw const NicError(
        'PAGE_NOT_READY',
        'Portal classes are not available for the selected session.',
      );
    check();
    return {
      'success': true,
      'school_id': school,
      'classes': classes,
      'session': selected['id'],
      'session_label': selected['label'],
    };
  }

  /// Source report_fragment's identity/header checks only. The original function's
  /// transformed HTML is not used by Python for PDF generation, nor by Dart.
  static List<NicIdentity> nicIdentities(String raw) {
    final report = html.parse(raw).getElementById('dvReport');
    if (report == null)
      throw const NicError(
        'NO_STUDENT_TABLE',
        'Student profile report is not available on the portal.',
      );
    final grid = report.querySelector('#$gridId');
    if (grid == null) {
      final message = _stripped(report, ' ');
      throw NicError(
        'NO_STUDENT_TABLE',
        message.isEmpty ? 'Student profile table is not available.' : message,
      );
    }
    final identities = <NicIdentity>[];
    for (final tr in grid.querySelectorAll('tr')) {
      dom.Element? find(String pattern) => tr
          .querySelectorAll('span[id]')
          .where((n) => RegExp(pattern).hasMatch(n.id))
          .firstOrNull;
      final nic = find(r'_lblSnicid_\d+$'), name = find(r'_lblName_\d+$');
      if (nic == null && name == null) continue;
      if (nic == null || name == null || _stripped(name).isEmpty) {
        throw const NicError(
          'MATCH_MISMATCH',
          'The portal returned an incomplete student profile row.',
        );
      }
      final sr = find(r'_lblSRNO_\d+$');
      identities.add((
        _stripped(nic),
        sr == null ? '' : _stripped(sr),
        _stripped(name),
      ));
    }
    if (identities.toSet().length != identities.length) {
      throw const NicError(
        'MATCH_MISMATCH',
        'The portal returned duplicate student profile rows.',
      );
    }
    final headers = grid.querySelectorAll('th');
    final empty =
        identities.isEmpty &&
        RegExp(
          r'no\s+records?\s+found',
          caseSensitive: false,
        ).hasMatch(_stripped(grid, ' '));
    if (!empty &&
        (headers.isEmpty ||
            !headers.any((h) => _stripped(h).toUpperCase().contains('NIC')))) {
      throw const NicError(
        'NO_STUDENT_TABLE',
        'The NIC table headers could not be verified.',
      );
    }
    return identities;
  }

  static (String, String)? nextPage(String raw, int index) {
    final grid = html.parse(raw).getElementById(gridId);
    if (grid == null)
      throw const NicError(
        'NO_STUDENT_TABLE',
        'Student profile table is missing before portal print.',
      );
    final links = grid
        .querySelectorAll('a[href]')
        .map((a) => a.attributes['href']!)
        .where((href) => href.contains(r'Page$'))
        .toList();
    final next = links
        .where(
          (link) =>
              RegExp('Page\\\$(?:${index + 1}|Next)(?:[\'\"]|\\))')
                  .hasMatch(link),
        )
        .firstOrNull;
    if (next == null) {
      if (links.any((link) {
        final match = RegExp(r'Page\$(\d+)').firstMatch(link);
        return match != null && int.parse(match[1]!) > index;
      })) {
        throw const NicError(
          'PAGE_NOT_READY',
          'Portal pagination is incomplete; no partial PDF was returned.',
        );
      }
      return null;
    }
    final match = RegExp(r"__doPostBack\('([^']+)','([^']+)'\)")
        .firstMatch(next);
    if (match == null || !match[1]!.contains('grdStudentProfile'))
      throw const NicError(
        'PAGE_NOT_READY',
        'Portal student pager could not be verified.',
      );
    return (match[1]!, match[2]!);
  }

  Future<void> _show(String cls, String section, String session) async {
    await _select(NicCatalogWorker.sessionId, session);
    await _select(NicCatalogWorker.classId, cls);
    await _select(sectionId, section);
    await browser.postback(
      "(() => {document.getElementById('ContentPlaceHolder1_btnSearch').click();return null;})()",
      grid: gridId,
    );
    await _ready();
    final actual = await _eval(
      "(() => ({session:document.querySelector('#ddlSession')?.value,cls:document.querySelector('#ContentPlaceHolder1_ddlClass')?.value,section:document.querySelector('#ContentPlaceHolder1_ddlSection')?.value}))()",
    ) as Map;
    if (actual['session'] != session ||
        actual['cls'] != cls ||
        actual['section'] != section)
      throw const NicError(
        'MATCH_MISMATCH',
        'Portal class, section or session does not match the NIC request.',
      );
    await _wait(
      "!!document.getElementById('dvReport')",
      const Duration(seconds: 15),
    );
  }

  Future<String> _nicPage(
    List<String> labels,
    List<NicIdentity> expected,
  ) async {
    // Python repeats identity validation immediately before native preview.
    final before = nicIdentities(await _html());
    if (!_sameIdentities(expected, before))
      throw const NicError(
        'MATCH_MISMATCH',
        'Printed student rows changed during portal preview.',
      );
    await _eval(
      "(() => {if(typeof openPrintPreviewWindow!=='function') throw new Error('Portal print preview function missing');openPrintPreviewWindow('print');return null;})()",
    );
    await _wait(
      "!!document.querySelector('#pop_printPreview')?.getClientRects().length",
      const Duration(seconds: 12),
    );
    await _eval(NativePrintWorker.protectPopup);
    try {
      await browser.openPopup(
        '''(() => {const el=document.querySelector('#pop_printPreview input[onclick*="CallPrint"],#pop_printPreview button[onclick*="CallPrint"]');
        if(!el) throw new Error('Portal native print button missing');
        el.addEventListener('click',e=>e.preventDefault(),{once:true});el.click();return null;})()''',
      );
      await _assets(20);
      final printed = _stripped(html.parse(await _html(popup: true)), ' ');
      if (labels.any((label) => label.isNotEmpty && !printed.contains(label)))
        throw const NicError(
          'MATCH_MISMATCH',
          'Portal print window does not match the selected session, class and section.',
        );
      for (final identity in expected) {
        if (!printed.contains(identity.$1) || !printed.contains(identity.$3))
          throw const NicError(
            'MATCH_MISMATCH',
            'Portal print window is missing a student from the selected class.',
          );
      }
      check();
      return await browser.renderPopup();
    } finally {
      try {
        await browser.closePopup();
      } catch (_) {}
      try {
        await _eval(
          "(() => {if(window.jQuery)window.jQuery('#pop_printPreview').modal('hide');document.querySelectorAll('.modal-backdrop').forEach(e=>e.remove());document.body.classList.remove('modal-open');return null;})()",
        );
      } catch (_) {}
    }
  }

  static bool _sameIdentities(List<NicIdentity> a, List<NicIdentity> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);

  Future<Map<String, dynamic>> nicPdf(
    String school, {
    String? classId,
    void Function(int, int)? progress,
  }) async {
    if (classId != null && classId.trim().isEmpty)
      throw const NicError('BAD_CLASS', 'Select a valid class.');
    classId = classId?.trim();
    final catalog = await nicCatalog(school),
        session = catalog['session'] as String;
    final classes = (catalog['classes'] as List)
        .cast<Map<String, dynamic>>()
        .where((c) => classId == null || c['id'] == classId)
        .toList();
    if (classes.isEmpty)
      throw const NicError(
        'BAD_CLASS',
        'The selected class is not available for this school.',
      );
    final pages = <String>[];
    var count = 0, sectionCount = 0;
    for (var classIndex = 0; classIndex < classes.length; classIndex++) {
      final cls = classes[classIndex];
      await _select(NicCatalogWorker.classId, cls['id'] as String);
      final sections = await _options(sectionId);
      if (sections.isEmpty)
        throw NicError(
          'PAGE_NOT_READY',
          'The portal did not return sections for Class ${cls['label']}.',
        );
      for (final section in sections) {
        final labels = [
          catalog['session_label'] as String,
          cls['label'] as String,
          section['label'] as String,
        ];
        await _show(cls['id'] as String, section['id'] as String, session);
        final seen = <NicIdentity>{};
        for (var index = 1; index <= 200; index++) {
          final raw = await _html(), identities = nicIdentities(raw);
          if (identities.any(seen.contains))
            throw const NicError(
              'MATCH_MISMATCH',
              'Student profile pagination repeated a student row.',
            );
          seen.addAll(identities);
          pages.add(await _nicPage(labels, identities));
          final next = nextPage(raw, index);
          if (next == null) break;
          if (index == 200)
            throw const NicError(
              'PAGE_NOT_READY',
              'Student profile pagination exceeded the report limit.',
            );
          await browser.postback(
            '(() => {__doPostBack(${jsonEncode(next.$1)},${jsonEncode(next.$2)});return null;})()',
            grid: gridId,
          );
          await _ready();
        }
        count += seen.length;
        sectionCount++;
      }
      progress?.call(classIndex + 1, classes.length);
    }
    check();
    final bytes = await browser.merge(pages);
    check();
    return {
      'success': true,
      'school_id': school,
      'session': session,
      'class_count': classes.length,
      'section_count': sectionCount,
      'student_count': count,
      'filename':
          'NIC_Sheet_${school}_${classId == null ? 'All_Classes' : 'Class_$classId'}_$session.pdf',
      'pdf_base64': base64Encode(bytes),
    };
  }
}
