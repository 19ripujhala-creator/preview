/// Complete Staff server_manager.py node order, ping policy and cooldown.
import 'http_session.dart';

typedef StaffProgress = void Function(int progress, String message);
const staffServers = [
  'https://rajshaladarpan.rajasthan.gov.in/SD4',
  'https://rajshaladarpan.rajasthan.gov.in/SD1',
  'https://rajshaladarpan.rajasthan.gov.in/SD3',
  'https://rajshaladarpan.rajasthan.gov.in/SD2',
  'https://rajshaladarpan.rajasthan.gov.in/SD5',
];

class StaffServerManager {
  StaffServerManager({
    DateTime Function()? now,
    StaffTransport Function()? clientFactory,
    this.progress,
  }) : now = now ?? DateTime.now,
       clientFactory =
           clientFactory ??
           (() =>
               DartStaffTransport(timeout: const Duration(milliseconds: 1200)));
  final DateTime Function() now;
  final StaffTransport Function() clientFactory;
  final StaffProgress? progress;
  final Map<String, DateTime> _penalties = {};
  void penalizeNode(String url) => _penalties[url] = now();
  Future<Map<String, dynamic>> pingAndVerifyNode(
    StaffTransport client,
    String url,
  ) async {
    final penalized = _penalties[url];
    if (penalized != null) {
      if (now().difference(penalized) < const Duration(minutes: 5))
        return {'url': url, 'healthy': false, 'latency': 99999};
      _penalties.remove(url);
    }
    final watch = Stopwatch()..start();
    try {
      final response = await client.get('$url$staffLoginPath');
      return {
        'url': url,
        'healthy':
            response.statusCode == 200 &&
            response.text.runes.length > 3000 &&
            response.text.contains('txt_Username'),
        'latency': watch.elapsedMilliseconds,
      };
    } catch (_) {
      return {'url': url, 'healthy': false, 'latency': 99999};
    }
  }

  Future<(String, String, int)> selectFastestServer() async {
    progress?.call(15, 'Finding fastest server node for Staff Login...');
    final client = clientFactory();
    late List<Map<String, dynamic>> results;
    try {
      results = await Future.wait(
        staffServers.map((s) => pingAndVerifyNode(client, s)),
      );
    } finally {
      client.close();
    }
    final healthy = results.where((r) => r['healthy'] == true).toList();
    if (healthy.isNotEmpty) {
      var best = healthy.first;
      for (final candidate in healthy.skip(1)) {
        if ((candidate['latency'] as int) < (best['latency'] as int))
          best = candidate;
      }
      final url = best['url'] as String,
          name = best['url'].toString().split('/').last,
          latency = best['latency'] as int;
      progress?.call(25, 'Staff connected to $name (${latency}ms)');
      return (url, name, latency);
    }
    progress?.call(25, 'Fallback to default SD4 node');
    return (staffServers.first, 'SD4', 0);
  }

  Future<(String, String, int)> selectFastestStaffServer() =>
      selectFastestServer();
}
