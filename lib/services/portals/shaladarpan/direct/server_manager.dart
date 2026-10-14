/// Conversion of portals/shaladarpan/server_manager.py.
import 'school_http.dart';

typedef SchoolProgress = void Function(int progress, String message);

const schoolServers = [
  'https://rajshaladarpan.rajasthan.gov.in/SD1',
  'https://rajshaladarpan.rajasthan.gov.in/SD2',
  'https://rajshaladarpan.rajasthan.gov.in/SD3',
  'https://rajshaladarpan.rajasthan.gov.in/SD4',
  'https://rajshaladarpan.rajasthan.gov.in/SD5',
];

Future<Map<String, dynamic>> pingServer(String url) async {
  final client = SchoolHttpClient(
    baseUrl: Uri.parse(url),
    timeout: const Duration(seconds: 1),
  );
  final clock = Stopwatch()..start();
  try {
    final response = await client.get('$url/Home/Public2/OfficeLoginNew.aspx');
    return {
      'url': url,
      'healthy': response.statusCode == 200 && response.text.runes.length > 200,
      'latency': clock.elapsedMilliseconds,
    };
  } catch (_) {
    return {'url': url, 'healthy': false, 'latency': 9999};
  } finally {
    client.retire();
  }
}

Future<(String, String, int)> selectFastestServer({
  SchoolProgress? progress,
}) async {
  progress?.call(15, 'Finding fastest server node...');
  final results = await Future.wait(schoolServers.map(pingServer));
  final healthy = results.where((r) => r['healthy'] == true).toList();
  if (healthy.isNotEmpty) {
    // Keep Python's stable tie order (SD1 first).
    var best = healthy.first;
    for (final candidate in healthy.skip(1)) {
      if ((candidate['latency'] as int) < (best['latency'] as int)) {
        best = candidate;
      }
    }
    final url = best['url'] as String;
    final name = Uri.parse(url).pathSegments.first;
    final latency = best['latency'] as int;
    progress?.call(25, 'Connected to $name (${latency}ms)');
    return (url, name, latency);
  }
  progress?.call(25, 'Fallback to default SD1 node');
  return (schoolServers.first, 'SD1', 0);
}
