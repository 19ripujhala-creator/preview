import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/core/direct/latest_read_queue.dart';

void main() {
  test('rapid class changes execute active and final selection only', () async {
    final queue = LatestReadQueue(), release = Completer<void>();
    final calls = <int>[];
    final first = queue.request(() async {
      calls.add(1);
      await release.future;
    });
    final futures = [first];
    for (var i = 2; i <= 5; i++) {
      final selected = i;
      futures.add(
        queue.request(() async {
          calls.add(selected);
        }),
      );
    }
    expect(calls, [1]);
    release.complete();
    await Future.wait(futures);
    expect(calls, [1, 5]);
  });
  test('discard pending selection never cancels active portal read', () async {
    final queue = LatestReadQueue(), release = Completer<void>();
    final calls = <String>[];
    final task = queue.request(() async {
      calls.add('active');
      await release.future;
      calls.add('settled');
    });
    queue.request(() async {
      calls.add('pending');
    });
    queue.discardPending();
    release.complete();
    await task;
    expect(calls, ['active', 'settled']);
  });
  test(
    'failed read releases queue and next explicit request can proceed',
    () async {
      final queue = LatestReadQueue(), error = StateError('offline');
      await expectLater(
        queue.request(() async => throw error),
        throwsA(same(error)),
      );
      var ran = false;
      await queue.request(() async {
        ran = true;
      });
      expect(ran, true);
    },
  );
  test('latest request arriving during second read is drained once', () async {
    final queue = LatestReadQueue(),
        first = Completer<void>(),
        second = Completer<void>();
    final calls = <int>[];
    final task = queue.request(() async {
      calls.add(1);
      await first.future;
    });
    queue.request(() async {
      calls.add(2);
      await second.future;
    });
    first.complete();
    await Future<void>.delayed(Duration.zero);
    queue.request(() async {
      calls.add(3);
    });
    queue.request(() async {
      calls.add(4);
    });
    second.complete();
    await task;
    expect(calls, [1, 2, 4]);
  });
}
