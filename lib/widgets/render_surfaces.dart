import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

/// Retain tab state while isolating paints and suspending hidden animations.
class RetainedTabStack extends StatelessWidget {
  const RetainedTabStack({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IndexedStack(
    index: index,
    children: [
      for (var i = 0; i < children.length; i++)
        TickerMode(
          enabled: index == i,
          child: RepaintBoundary(child: children[i]),
        ),
    ],
  );
}

/// A static filtered decoration gets its own retained paint layer.
/// The engine remains responsible for deciding whether to raster-cache it.
class StaticBlur extends StatelessWidget {
  const StaticBlur({super.key, required this.sigma, required this.child});

  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    ),
  );
}

