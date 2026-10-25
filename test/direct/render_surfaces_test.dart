import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/widgets/render_surfaces.dart';

class _AnimatedTab extends StatefulWidget {
  const _AnimatedTab(this.id, this.ticks);
  final String id;
  final Map<String, int> ticks;
  @override
  State<_AnimatedTab> createState() => _AnimatedTabState();
}
class _AnimatedTabState extends State<_AnimatedTab> with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  int edits = 0;
  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(() { widget.ticks.update(widget.id, (v) => v + 1, ifAbsent: () => 1); });
    controller.repeat();
  }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => edits++), child: Text('${widget.id}:$edits'));
}
void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('hidden tab stops ticking and resumes with retained edits', (t) async {
    final ticks = <String, int>{};
    Widget app(int index) => MaterialApp(home: RetainedTabStack(index: index,
      children: [_AnimatedTab('a', ticks), _AnimatedTab('b', ticks)]));
    await t.pumpWidget(app(0));
    await t.pump(const Duration(milliseconds: 20));
    expect(ticks['a'], greaterThan(0));
    expect(ticks['b'] ?? 0, 0);
    final first = t.state(find.byType(_AnimatedTab).first);
    await t.tap(find.text('a:0')); await t.pump();
    await t.pumpWidget(app(1)); final before = ticks['a'];
    await t.pump(const Duration(milliseconds: 40));
    expect(ticks['a'], before); expect(ticks['b'], greaterThan(0));
    await t.pumpWidget(app(0)); await t.pump(const Duration(milliseconds: 40));
    expect(t.state(find.byType(_AnimatedTab).first), same(first));
    expect(find.text('a:1'), findsOneWidget); expect(ticks['a'], greaterThan(before!));
    await t.pumpWidget(const SizedBox()); expect(t.takeException(), isNull);
  });
  testWidgets('hidden parent suppresses active nested child animations', (t) async {
    final ticks = <String, int>{};
    Widget app(int outer) => MaterialApp(home: RetainedTabStack(index: outer, children: [
      RetainedTabStack(index: 0, children: [_AnimatedTab('nested', ticks)]), const Text('other')]));
    await t.pumpWidget(app(0)); await t.pump(const Duration(milliseconds: 20));
    await t.pumpWidget(app(1)); final before = ticks['nested'];
    await t.pump(const Duration(milliseconds: 100)); expect(ticks['nested'], before);
    await t.pumpWidget(app(0)); await t.pump(const Duration(milliseconds: 20));
    expect(ticks['nested'], greaterThan(before!)); await t.pumpWidget(const SizedBox());
  });
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('retained tabs keep IndexedStack geometry at width $width', (t) async {
      t.view.devicePixelRatio = 1; t.view.physicalSize = Size(width, 720);
      addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
      const visible = ValueKey('visible'); const hidden = ValueKey('hidden');
      const children = [SizedBox(key: visible, width: 100, height: 40), SizedBox(key: hidden, width: 200, height: 60)];
      Widget app(Widget stack) => Directionality(textDirection: TextDirection.ltr, child: Center(child: stack));
      await t.pumpWidget(app(const IndexedStack(index: 0, children: children)));
      final rect = t.getRect(find.byKey(visible));
      await t.pumpWidget(app(const RetainedTabStack(index: 0, children: children)));
      expect(t.getRect(find.byKey(visible)), rect);
      expect(find.byKey(hidden).hitTestable(), findsNothing); expect(t.takeException(), isNull);
    });
  }
  testWidgets('static decoration retains blur settings and child paint layer', (t) async {
    const child = SizedBox(width: 80, height: 80, child: ColoredBox(color: Colors.red));
    await t.pumpWidget(const Directionality(textDirection: TextDirection.ltr,
      child: Center(child: StaticBlur(sigma: 85, child: child))));
    final filter = t.widget<ImageFiltered>(find.byType(ImageFiltered));
    expect(filter.imageFilter, ImageFilter.blur(sigmaX: 85, sigmaY: 85)); expect(filter.child, same(child));
    expect(find.ancestor(of: find.byType(ImageFiltered), matching: find.byType(RepaintBoundary)), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
