import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:shaladarpan/widgets/adaptive_layout.dart';

/// Matches Format 5's shared canvas, toolbar height, spacing and typography.
class AttendancePageHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const AttendancePageHeader({
    super.key,
    required this.title,
    required this.foreground,
    this.actions = const [],
  });

  final String title;
  final Color foreground;
  final List<Widget> actions;

  static double get _trailingGutter =>
      [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ].contains(defaultTargetPlatform)
      ? 14
      : 0;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    child: SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, viewport) => Center(
          child: SizedBox(
            key: const ValueKey('attendance-page-header-canvas'),
            width: AppAdaptive.contentWidth(viewport.maxWidth),
            height: kToolbarHeight,
            child: Row(
              children: [
                const SizedBox(width: 8),
                BackButton(color: foreground),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
                ...actions,
                SizedBox(width: 8 + _trailingGutter),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
