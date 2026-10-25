import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A small content entrance; the page background and toolbar keep their bounds.
/// Native mobile transitions own their motion and bypass this wrapper.
class PageContentMotion extends StatelessWidget {
  const PageContentMotion({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.windows ||
        MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (route == null || route.isFirst || animation == null) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          0,
          12 * (1 - Curves.easeInOut.transform(animation.value)),
        ),
        child: child,
      ),
    );
  }
}
