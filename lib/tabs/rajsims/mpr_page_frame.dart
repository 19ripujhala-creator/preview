import 'package:flutter/material.dart';
import 'package:shaladarpan/widgets/adaptive_layout.dart';

/// Reserves footer height while painting one background behind the whole page.
class MprPageFrame extends StatelessWidget {
  const MprPageFrame({
    super.key,
    required this.appBar,
    required this.background,
    required this.body,
    this.footer,
  });
  final PreferredSizeWidget appBar;
  final Widget background;
  final Widget body;
  final Widget? footer;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      background,
      Scaffold(
        extendBody: false,
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.transparent,
        appBar: appBar,
        body: body,
        bottomNavigationBar: footer == null
            ? null
            : Padding(
                // Scaffold resizes its body for the keyboard, but does not lift the
                // bottom navigation bar. Reserve the obscured region explicitly.
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: footer,
              ),
      ),
    ],
  );
}

/// Keep MPR messages inside the same responsive canvas as the form.
SnackBar mprPageNotice(BuildContext context, String message) {
  final width = MediaQuery.sizeOf(context).width;
  final side = width >= 900
      ? 20.0
      : width < 600
      ? 10.0
      : 14.0;
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    width: AppAdaptive.contentWidth(width) - 2 * side,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    content: Text(message),
  );
}
