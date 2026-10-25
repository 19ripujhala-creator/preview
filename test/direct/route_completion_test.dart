import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/widgets/route_completion.dart';

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('normal push completion precedes reverse transition completion', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(navigatorKey: navigator, home: const Scaffold()));
    final route = MaterialPageRoute<String>(builder: (_) => const Scaffold(body: Text('child')));
    var popped = false;
    navigator.currentState!.push(route).then((_) => popped = true);
    await t.pumpAndSettle();
    navigator.currentState!.pop('result');
    await t.pump(const Duration(milliseconds: 16));
    expect(popped, isTrue);
    expect(route.animation!.isDismissed, isFalse);
    await t.pumpAndSettle();
  });

  for (final cupertino in [false, true]) {
    testWidgets('return work waits for ${cupertino ? 'Cupertino' : 'Material'} exit and preserves result', (t) async {
      final navigator = GlobalKey<NavigatorState>();
      late BuildContext home;
      await t.pumpWidget(MaterialApp(navigatorKey: navigator, home: Builder(builder: (context) {
        home = context;
        return const Scaffold(body: Text('parent'));
      })));
      final PageRoute<String> route = cupertino
          ? CupertinoPageRoute<String>(builder: (_) => const Scaffold(body: Text('child')))
          : MaterialPageRoute<String>(builder: (_) => const Scaffold(body: Text('child')));
      var returned = false;
      String? result;
      final navigation = pushPageAndWaitForExit(home, route).then((value) { returned = true; result = value; });
      await t.pumpAndSettle();
      navigator.currentState!.pop('kept-result');
      await t.pump(const Duration(milliseconds: 16));
      expect(returned, isFalse);
      await t.pumpAndSettle();
      await navigation;
      expect(returned, isTrue);
      expect(result, 'kept-result');
      expect(find.text('parent'), findsOneWidget);
      expect(find.text('child'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('zero-duration routes finish without a fixed waiting timer', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext home;
    await t.pumpWidget(MaterialApp(navigatorKey: navigator, home: Builder(builder: (context) {
      home = context; return const Scaffold();
    })));
    final route = PageRouteBuilder<int>(pageBuilder: (_, animation, secondary) => const Scaffold(),
      transitionDuration: Duration.zero, reverseTransitionDuration: Duration.zero);
    var returned = false;
    int? result;
    final navigation = pushPageAndWaitForExit(home, route).then((value) { result = value; returned = true; });
    await t.pumpAndSettle();
    navigator.currentState!.pop(7);
    await t.pumpAndSettle(); await navigation;
    expect(returned, isTrue);
    expect(result, 7);
    expect(t.takeException(), isNull);
  });

  testWidgets('waiting for completion does not bypass a blocked back action', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext home;
    await t.pumpWidget(MaterialApp(navigatorKey: navigator, home: Builder(builder: (context) {
      home = context; return const Scaffold();
    })));
    final route = MaterialPageRoute<void>(builder: (_) => const PopScope(canPop: false,
      child: Scaffold(body: Text('protected form'))));
    var returned = false;
    final navigation = pushPageAndWaitForExit(home, route).then((_) => returned = true);
    await t.pumpAndSettle();
    await navigator.currentState!.maybePop(); await t.pumpAndSettle();
    expect(returned, isFalse); expect(find.text('protected form'), findsOneWidget);
    // Explicit pop represents the existing form's own confirmed-exit handler.
    navigator.currentState!.pop(); await t.pumpAndSettle(); await navigation;
    expect(returned, isTrue); expect(t.takeException(), isNull);
  });
}
