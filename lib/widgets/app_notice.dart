import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared app message surface optimized for both iOS (Notch/Dynamic Island) and Android.
class AppNotice {
  static OverlayEntry? _entry;
  static Timer? _timer;

  /// Extracts clean portal or HTTP message from String or Map response.
  static String? message(dynamic response) {
    if (response is String) return response.trim().isEmpty ? null : response;
    if (response is! Map) return null;
    final native = response['portal_message'];
    if (native is String && native.trim().isNotEmpty) return native;
    final detail = response['detail'];
    if (detail is Map) {
      final value = message(detail);
      if (value != null) return value;
    }
    final value = response['message'];
    if (value is String && value.trim().isNotEmpty) return value;
    return detail is String && detail.trim().isNotEmpty ? detail : null;
  }

  /// Extracts HTTP status code if present in a Map response.
  static int? statusCodeOf(dynamic response) {
    if (response is! Map) return null;
    final code = response['status_code'] ?? response['statusCode'] ?? response['status'] ?? response['code'];
    if (code is int) return code;
    if (code is String) return int.tryParse(code);
    return null;
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  /// Automatically picks icon and color based on HTTP status or message text if defaults are used.
  static ({IconData icon, Color color, String? badge}) _resolveStyle(
    String? rawText,
    IconData icon,
    Color iconColor,
    int? statusCode,
  ) {
    final isDefaultStyle = icon == Icons.info_outline_rounded && iconColor == const Color(0xFF93C5FD);

    if (statusCode != null) {
      if (statusCode >= 200 && statusCode < 300) {
        return (icon: Icons.check_circle_rounded, color: const Color(0xFF4ADE80), badge: 'HTTP $statusCode');
      } else if (statusCode >= 400) {
        return (icon: Icons.error_rounded, color: const Color(0xFFF87171), badge: 'HTTP $statusCode');
      }
    }

    if (!isDefaultStyle || rawText == null) {
      return (icon: icon, color: iconColor, badge: statusCode != null ? 'HTTP $statusCode' : null);
    }

    final lower = rawText.toLowerCase();
    if (lower.contains('error') ||
        lower.contains('failed') ||
        lower.contains('invalid') ||
        lower.contains('required') ||
        lower.contains('denied') ||
        lower.contains('expired') ||
        lower.contains('exception')) {
      return (icon: Icons.error_outline_rounded, color: const Color(0xFFF87171), badge: null);
    }

    if (lower.contains('success') ||
        lower.contains('verified') ||
        lower.contains('saved') ||
        lower.contains('completed') ||
        lower.contains('generated') ||
        lower.contains('updated')) {
      return (icon: Icons.check_circle_outline_rounded, color: const Color(0xFF4ADE80), badge: null);
    }

    if (lower.contains('warning') || lower.contains('wait') || lower.contains('pending')) {
      return (icon: Icons.warning_amber_rounded, color: const Color(0xFFFBBF24), badge: null);
    }

    return (icon: icon, color: iconColor, badge: null);
  }

  static void show(
    BuildContext context,
    String message, {
    IconData icon = Icons.info_outline_rounded,
    Color iconColor = const Color(0xFF93C5FD),
    int? statusCode,
  }) {
    if (message.trim().isEmpty || !context.mounted) return;
    showContent(
      context,
      Text(message.trim()),
      icon: icon,
      iconColor: iconColor,
      statusCode: statusCode,
    );
  }

  static void showContent(
    BuildContext context,
    Widget content, {
    IconData icon = Icons.info_outline_rounded,
    Color iconColor = const Color(0xFF93C5FD),
    int? statusCode,
  }) {
    if (!context.mounted) return;
    final overlay = Navigator.maybeOf(context, rootNavigator: true)?.overlay ??
        Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    dismiss();

    String? rawText;
    if (content is Text && content.data != null) {
      rawText = content.data!.trim();
      content = Text(rawText);
    }

    final resolved = _resolveStyle(rawText, icon, iconColor, statusCode);
    final displayedContent = content;

    _entry = OverlayEntry(builder: (overlayContext) {
      final media = MediaQuery.of(overlayContext);
      final viewPaddingTop = MediaQueryData.fromView(View.of(overlayContext)).padding.top;
      final safeTop = math.max(media.padding.top, viewPaddingTop);
      final availableHeight = math.max(
        48.0,
        media.size.height - safeTop - media.padding.bottom - media.viewInsets.bottom - 24,
      );

      return Positioned(
        top: safeTop + 8,
        left: 12,
        right: 12,
        child: Align(
          alignment: Alignment.topCenter,
          child: Dismissible(
            key: UniqueKey(),
            direction: DismissDirection.up,
            onDismissed: (_) => dismiss(),
            child: Semantics(
              liveRegion: true,
              container: true,
              child: Material(
                color: const Color(0xFF0F172A),
                elevation: 8,
                shadowColor: Colors.black.withValues(alpha: 0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: resolved.color.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    maxHeight: math.min(availableHeight, 220),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: resolved.color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(resolved.icon, color: resolved.color, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (resolved.badge != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Text(
                                      resolved.badge!,
                                      style: TextStyle(
                                        fontFamily: 'PlusJakartaSans',
                                        color: resolved.color,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                DefaultTextStyle(
                                  style: const TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                  child: displayedContent,
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: dismiss,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });

    overlay.insert(_entry!);
    if (!MediaQuery.of(context).accessibleNavigation) {
      final longMessage = (rawText?.length ?? 0) > 100;
      _timer = Timer(Duration(seconds: longMessage ? 10 : 4), dismiss);
    }
  }
}

extension AppNoticeMessenger on ScaffoldMessengerState {
  void showAppNotice(SnackBar notice) => AppNotice.showContent(context, notice.content);
}