import 'package:flutter/material.dart';

/// Keep controls at their natural size; adapt the surrounding layout instead.
class AppAdaptive {
  static const double twoPane = 900;
  static double gutter(double width) {
    if (width < 600) return 0;
    final spacing = ((width - 600) * .06 + 16).clamp(16.0, 80.0).toDouble();
    final canvasMargin = (width - 1280) / 2;
    return canvasMargin > spacing ? canvasMargin : spacing;
  }
  static double contentWidth(double width) {
    final available = width - 2 * gutter(width);
    return available > 1280 ? 1280 : available;
  }
}

/// Side-by-side panels when both have room, otherwise a single readable column.
class AdaptivePanels extends StatelessWidget {
  final Widget first, second;
  final double breakpoint, gap, stackedGap;
  final int firstFlex, secondFlex;
  const AdaptivePanels({super.key, required this.first, required this.second,
    this.breakpoint = AppAdaptive.twoPane, this.gap = 20, this.stackedGap = 0,
    this.firstFlex = 1, this.secondFlex = 1});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (box.maxWidth < breakpoint * scale.clamp(1.0, 1.5)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, if (stackedGap > 0) SizedBox(height: stackedGap), second]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: firstFlex, child: first), SizedBox(width: gap),
      Expanded(flex: secondFlex, child: second),
    ]);
  });
}

/// Fields keep useful input widths and reflow without changing controllers.
class AdaptiveFieldGrid extends StatelessWidget {
  final List<Widget> children;
  final double minFieldWidth, gap;
  const AdaptiveFieldGrid({super.key, required this.children,
    this.minFieldWidth = 280, this.gap = 12});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.5);
    final columns = box.maxWidth >= minFieldWidth * 2 * scale + gap ? 2 : 1;
    final width = (box.maxWidth - (columns - 1) * gap) / columns;
    return Wrap(spacing: gap, runSpacing: 10, children: [
      for (final field in children) SizedBox(width: width, child: field),
    ]);
  });
}

/// A readable workspace inside the available viewport, including nested routes.
/// Forms and documents can choose a smaller limit than tables. The viewport
/// remains full height, so scrolling, pinned headers and footers keep working.
class AdaptiveWorkspace extends StatelessWidget {
  final Widget child;
  final bool background;
  const AdaptiveWorkspace({super.key, required this.child,
    this.background = false});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final width = AppAdaptive.contentWidth(box.maxWidth);
    final workspace = Align(alignment: Alignment.topCenter,
      child: SizedBox(width: width,
        height: box.hasBoundedHeight ? box.maxHeight : null, child: child));
    if (!background) return workspace;
    return DecoratedBox(decoration: Theme.of(context).brightness == Brightness.dark
      ? BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor)
      : const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          stops: [0, .45, 1],
          colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9), Color(0xFFFEF3C7)])),
      child: workspace);
  });
}
