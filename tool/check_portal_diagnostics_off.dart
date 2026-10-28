import 'dart:convert';
import 'dart:io';

import '../lib/services/core/direct/portal_diagnostics.dart';
import '../lib/services/portals/shaladarpan/direct/school_http.dart';

/// Run with -DPORTAL_DIAGNOSTICS=false; no Flutter/device dependencies.
Future<void> main() async {
  if (PortalDiagnostics.enabled)
    throw StateError('Expected diagnostics disabled');
  PortalDiagnostics.clear();
  var calls = 0;
  final value = await PortalDiagnostics.withAction(
    'SUBMIT',
    () => PortalDiagnostics.measure(PortalPhase.studentSubmit, () async {
      calls++;
      return 7;
    }),
  );
  if (value != 7 || calls != 1)
    throw StateError('Operation result/count changed');
  final error = StateError('synthetic');
  Object? observedError;
  try {
    await PortalDiagnostics.measure(
      PortalPhase.studentRead,
      () async => throw error,
    );
  } catch (caught) {
    observedError = caught;
  }
  if (!identical(observedError, error))
    throw StateError('Exception propagation changed');
  PortalDiagnostics.recordStudentView(
    startedMs: 0,
    cache: 'hit',
    outcome: 'rendered',
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = Uri.parse('http://127.0.0.1:${server.port}');
  final client = SchoolHttpClient(
    baseUrl: base,
    allowUrl: (u) => u.origin == base.origin,
  );
  var requests = 0;
  final subscription = server.listen((request) async {
    requests++;
    await request.drain<void>();
    request.response.write('unchanged');
    await request.response.close();
  });
  try {
    if ((await client.get('/test')).text != 'unchanged' || requests != 1) {
      throw StateError('Disabled transport behavior changed');
    }
  } finally {
    client.retire();
    await subscription.cancel();
    await server.close(force: true);
  }
  final report = jsonDecode(PortalDiagnostics.export());
  if (report['enabled'] != false || (report['events'] as List).isNotEmpty) {
    throw StateError('Disabled mode collected events');
  }
  stdout.writeln(
    'PASS: disabled diagnostics records no events; operations, exceptions and HTTP still work.',
  );
}
