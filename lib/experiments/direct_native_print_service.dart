import 'dart:async';

import '../services/core/direct/async_primitives.dart';
import '../services/core/direct/coordinator.dart';
import '../services/core/direct/errors.dart';
import '../services/portals/shaladarpan/direct/native_print_browser.dart';
import '../services/portals/shaladarpan/direct/native_print_worker.dart';
import '../services/portals/shaladarpan/direct/nic_catalog_worker.dart';
import 'direct_portal_auth.dart';

class DirectNativePrintService {
  DirectNativePrintService(
    this.auth, {
    NativePrintBrowser Function()? browserFactory,
  }) : browserFactory = browserFactory ?? (() => PlatformNativePrintBrowser());
  final DirectPortalAuth auth;
  final NativePrintBrowser Function() browserFactory;

  Future<Map<String, dynamic>> _run(
    String school, {
    String? classId,
    String? sr,
    void Function(int, int)? progress,
  }) async {
    var identity = auth.schoolSessionIdentity;
    void check() {
      OperationCancellation.current?.check();
      if (!auth.isVerified)
        throw const NicError(
          'SESSION_EXPIRED',
          'School portal session expired.',
        );
      if (school.isEmpty || auth.authenticatedSchoolId != school)
        throw NicError(
          'ACCOUNT_CHANGED',
          sr == null
              ? 'School account changed. Open the NIC directory again.'
              : 'School account changed. Open Study Certificate again.',
        );
      if (identity.isEmpty || identity != auth.schoolSessionIdentity)
        throw NicError(
          'SESSION_CHANGED',
          sr == null
              ? 'School login session changed. Open the NIC directory again.'
              : 'School login session changed. Open Study Certificate again.',
        );
    }

    Future<Map<String, dynamic>> execute() async {
      if (auth.authenticatedSchoolId == school)
        identity = auth.schoolSessionIdentity;
      NativePrintBrowser? browser;
      void Function()? stop;
      void Function()? release;
      try {
        check();
        if (sr != null && !RegExp(r'^[0-9]{1,30}$').hasMatch(sr.trim()))
          throw const NicError('BAD_SR', 'Enter a valid SR number.');
        if (classId != null && classId.trim().isEmpty)
          throw const NicError('BAD_CLASS', 'Select a valid class.');
        release = await nativePrintLease.acquire(
          cancellation: OperationCancellation.current,
        );
        check();
        browser = browserFactory();
        stop = OperationCancellation.current?.listen(() {
          if (browser != null) unawaited(browser.close().catchError((_) {}));
        });
        final base = Uri.https(
          'rajshaladarpan.rajasthan.gov.in',
          '/${auth.verifiedNode}',
        );
        final cookies = auth.nativePrintCookies();
        if (cookies.isEmpty)
          throw const NicError(
            'SESSION_EXPIRED',
            'School portal session is unavailable.',
          );
        await browser.begin(base, cookies);
        check();
        final result = sr == null
            ? await NicSheetWorker(
                browser: browser,
                check: check,
              ).nicPdf(school, classId: classId, progress: progress)
            : await StudyCertificateWorker(
                browser: browser,
                check: check,
              ).studyPdf(school, sr, progress: progress);
        check();
        return result;
      } on NicError catch (e) {
        return NicCatalogWorker.failure(e.code, e.message);
      } finally {
        stop?.call();
        if (browser != null) {
          try {
            await browser.close();
          } catch (_) {}
        }
        release?.call();
      }
    }

    try {
      final coordinator = auth.coordinator;
      if (coordinator == null) return await execute();
      return await coordinator.run(
        resource: sr == null
            ? 'sd.student_nic'
            : 'sd.student_study_certificate',
        kind: Kind.read,
        timeout: sr == null ? 600 : 150,
        maxAttempts: 3,
        label: sr == null ? 'student_nic_pdf' : 'student_study_certificate_pdf',
        worker: (_) => execute(),
      );
    } on CoordinatorError catch (e) {
      return NicCatalogWorker.failure(e.kind.code, e.message);
    }
  }

  Future<Map<String, dynamic>> nicPdf(
    String school, {
    String? classId,
    void Function(int, int)? progress,
  }) => _run(school.trim(), classId: classId, progress: progress);
  Future<Map<String, dynamic>> studyPdf(
    String school,
    String sr, {
    void Function(int, int)? progress,
  }) => _run(school.trim(), sr: sr, progress: progress);
}
