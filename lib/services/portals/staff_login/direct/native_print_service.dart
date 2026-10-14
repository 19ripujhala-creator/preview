/// Staff print_browser.py handoff and /leave/pdf, /format10/pdf integration.
import 'dart:async';

import '../../../core/direct/async_primitives.dart';
import '../../../core/direct/coordinator.dart';
import '../../../core/direct/errors.dart';
import '../../shaladarpan/direct/native_print_browser.dart';
import '../../shaladarpan/direct/nic_catalog_worker.dart' show NicError;
import 'auth_manager.dart';
import 'format10_worker.dart';
import 'http_auth.dart';
import 'http_login.dart' show staffLower;
import 'http_session.dart';
import 'leave_pdf_worker.dart';
import 'portal_state.dart';

class StaffNativePrintService {
  StaffNativePrintService({
    required this.registry,
    required this.coordinator,
    StaffPrintBrowser Function()? browserFactory,
  }) : browserFactory = browserFactory ?? (() => PlatformNativePrintBrowser());
  final StaffHttpAuth registry;
  final PortalCoordinator coordinator;
  final StaffPrintBrowser Function() browserFactory;

  Future<Map<String, dynamic>> _run(
    String user, {
    bool format10 = false,
    String? nicId,
    String? sNo,
    String? fromDate,
    String? toDate,
    String? leaveType,
  }) async {
    bool owned() =>
        user.isNotEmpty &&
        staffLower(registry.current()?.user ?? '') == staffLower(user);
    try {
      if (!owned())
        throw const StaffPortalError('ACCOUNT_CHANGED', 'Staff login changed.');
      return await coordinator.run(
        resource: format10 ? 'staff.format10' : 'staff.leave.pdf',
        kind: Kind.read,
        timeout: format10 ? 75 : 60,
        label: format10 ? 'format10_pdf' : 'leave_pdf',
        worker: (_) async {
          final generation = coordinator.generation;
          try {
            final session = registry.current();
            if (!owned())
              throw const StaffPortalError(
                'ACCOUNT_CHANGED',
                'Staff login changed.',
              );
            if (session == null ||
                !session.authenticated ||
                session.base == null) {
              throw const StaffPortalError(
                'SESSION_EXPIRED',
                'Staff session expired.',
              );
            }
            void check() {
              OperationCancellation.current?.check();
              if (!identical(session, registry.current()) || !owned()) {
                throw const StaffPortalError(
                  'ACCOUNT_CHANGED',
                  'Staff login changed.',
                );
              }
              if (!session.authenticated ||
                  generation != coordinator.generation) {
                throw const StaffPortalError(
                  'SESSION_CHANGED',
                  'Staff login session changed.',
                );
              }
            }

            return await session.exclusive(() async {
              final release = await nativePrintLease.acquire(
                cancellation: OperationCancellation.current,
              );
              StaffPrintBrowser? browser;
              void Function()? stop;
              var handedOff = false;
              try {
                check();
                browser = browserFactory();
                stop = OperationCancellation.current?.listen(() {
                  if (browser != null)
                    unawaited(browser.abort().catchError((_) {}));
                });
                final cookies = registry.browserCookies(session);
                if (cookies.isEmpty)
                  throw const StaffPortalError(
                    'SESSION_EXPIRED',
                    'Staff session expired.',
                  );
                await browser.beginStaff(Uri.parse(session.base!), cookies);
                check();
                // Fresh StaffHome, positive evidence only. The adapter never logs in.
                await browser.navigate('Home/Staff/StaffHome.aspx');
                final state = await browser.evaluate(
                  '({url:location.href,text:document.documentElement.outerHTML})',
                ) as Map;
                check();
                final home = (
                  url: state['url'] as String,
                  status: 200,
                  text: state['text'] as String,
                );
                final verdict = StaffAuthManager.classifyHome(home);
                if (verdict == Probe.dead) {
                  registry.invalidate(session);
                  throw const StaffPortalError(
                    'SESSION_EXPIRED',
                    'Staff session expired.',
                  );
                }
                if (verdict != Probe.alive ||
                    !staffSameNode(session.base!, home.url)) {
                  throw const StaffPortalError(
                    'PAGE_NOT_READY',
                    'The Staff portal page is not ready. Please try again.',
                  );
                }
                handedOff = true;
                final result = format10
                    ? await Format10Worker(
                        browser: browser,
                        check: check,
                      ).generate(nicId: nicId)
                    : await LeavePdfWorker(
                        browser: browser,
                        check: check,
                      ).generate(
                        sNo: sNo,
                        fromDate: fromDate,
                        toDate: toDate,
                        leaveType: leaveType,
                      );
                check();
                return result;
              } finally {
                stop?.call();
                if (browser != null) {
                  try {
                    if (handedOff && identical(registry.current(), session)) {
                      final cookies = await browser.staffCookies().timeout(
                        const Duration(seconds: 3),
                      );
                      if (identical(registry.current(), session) &&
                          session.authenticated &&
                          registry.syncFromBrowser(session, cookies))
                        await registry.persist(session);
                    }
                  } catch (_) {}
                  try {
                    await browser.close();
                  } catch (_) {}
                }
                release();
              }
            });
          } on StaffHttpError catch (e) {
            return {
              'success': false,
              'code': e.code,
              'message': e.message,
              if (e is Format10StageError) 'stage': e.stage,
            };
          } on NicError catch (e) {
            return {'success': false, 'code': e.code, 'message': e.message};
          }
        },
      );
    } on StaffHttpError catch (e) {
      return {'success': false, 'code': e.code, 'message': e.message};
    } on NicError catch (e) {
      return {'success': false, 'code': e.code, 'message': e.message};
    } on CoordinatorError catch (e) {
      return {'success': false, 'code': e.kind.code, 'message': e.message};
    }
  }

  Future<Map<String, dynamic>> format10Pdf(String user, {String? nicId}) =>
      _run(user, format10: true, nicId: nicId);
  Future<Map<String, dynamic>> leavePdf(
    String user, {
    String? sNo,
    String? fromDate,
    String? toDate,
    String? leaveType,
  }) => _run(
    user,
    sNo: sNo,
    fromDate: fromDate,
    toDate: toDate,
    leaveType: leaveType,
  );
}
