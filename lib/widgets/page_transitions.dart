import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Native mobile builders, with content transitions on Windows.
final PageTransitionsTheme desktopPageTransitions = PageTransitionsTheme(
  builders: {
    ...const PageTransitionsTheme().builders,
    TargetPlatform.windows: const StableWindowsPageTransitionsBuilder(),
  },
);

/// Keep Account/Staff routes native to the actual device platform.
PageRoute<T> appPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return CupertinoPageRoute<T>(builder: builder, settings: settings);
    default:
      return MaterialPageRoute<T>(builder: builder, settings: settings);
  }
}

class StableWindowsPageTransitionsBuilder extends PageTransitionsBuilder {
  const StableWindowsPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    // Both routes use the same handoff point in opposite directions.
    // Never paint readable content from both pages at once.
    final entering = animation.drive(
      CurveTween(curve: const Interval(0.35, 1, curve: Curves.easeInOut)),
    );
    final covered = secondaryAnimation.drive(
      Tween<double>(begin: 1, end: 0).chain(
        CurveTween(curve: const Interval(0, 0.35, curve: Curves.easeInOut)),
      ),
    );
    return FadeTransition(
      opacity: entering,
      child: FadeTransition(opacity: covered, child: child),
    );
  }
}

/// Paint a stable app-colored surface while neither route is visible.
class AppNavigationBackdrop extends StatelessWidget {
  const AppNavigationBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.windows) return child;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: theme.brightness == Brightness.dark
          ? BoxDecoration(color: theme.scaffoldBackgroundColor)
          : const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .45, 1],
                colors: [
                  Color(0xFFF8FAFC),
                  Color(0xFFF1F5F9),
                  Color(0xFFFEF3C7),
                ],
              ),
            ),
      child: child,
    );
  }
}
