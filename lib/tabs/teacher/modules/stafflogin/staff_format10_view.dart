import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:shaladarpan/services/portals/staff_login/staff_login_service.dart';

const String kAppFont = 'PlusJakartaSans';

// ═════════════════════════════════════════════════════════════════════
// 🍏 iOS 18 Safari Style Clockwise Filling Progress Ring Widget
// ═════════════════════════════════════════════════════════════════════
class IosDownloadProgressIndicator extends StatelessWidget {
  final double size;
  final double progress;
  final Color color;
  final Color? trackColor;

  const IosDownloadProgressIndicator({
    super.key,
    this.size = 17.0,
    required this.progress,
    this.color = const Color(0xFF007AFF),
    this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _IosProgressRingPainter(
              progress: animatedValue,
              color: color,
              trackColor: trackColor ?? color.withOpacity(0.20),
            ),
          ),
        );
      },
    );
  }
}

class _IosProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _IosProgressRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.125;
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0.02) {
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;

      const double startAngle = -1.5707963267948966;
      final double sweepAngle = progress * 6.283185307179586;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }

    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth * 0.95;

    final arrowTop = center.dy - (size.height * 0.20);
    final arrowBottom = center.dy + (size.height * 0.20);
    final wingSpanX = size.width * 0.16;
    final wingSpanY = size.height * 0.14;

    final arrowPath = Path();
    arrowPath.moveTo(center.dx, arrowTop);
    arrowPath.lineTo(center.dx, arrowBottom);

    arrowPath.moveTo(center.dx - wingSpanX, arrowBottom - wingSpanY);
    arrowPath.lineTo(center.dx, arrowBottom);
    arrowPath.lineTo(center.dx + wingSpanX, arrowBottom - wingSpanY);

    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _IosProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}

// ═════════════════════════════════════════════════════════════════════
// MAIN FORMAT-10 VIEW
// ═════════════════════════════════════════════════════════════════════
class StaffFormat10View extends StatefulWidget {
  final Map<String, String> currentUser;
  const StaffFormat10View({super.key, required this.currentUser});

  @override
  State<StaffFormat10View> createState() => _StaffFormat10ViewState();
}

class _StaffFormat10ViewState extends State<StaffFormat10View> {
  bool _isDownloading = false;
  bool _isViewing = false;
  double _downloadProgress = 0.0;
  Timer? _progressTimer;

  // 🛡️ Real-time Live Verified P10 State
  String? _verifiedP10Status;
  bool? _isVerifiedLocked;
  bool _isCheckingStatus = false;

  OverlayEntry? _toastEntry;
  final ValueNotifier<String> _toastMessage = ValueNotifier<String>('');
  final ValueNotifier<bool> _toastIsProgress = ValueNotifier<bool>(false);
  final ValueNotifier<double> _toastProgressVal = ValueNotifier<double>(0.0);
  final ValueNotifier<IconData> _toastIcon = ValueNotifier<IconData>(CupertinoIcons.checkmark_alt);
  final ValueNotifier<Color> _toastIconColor = ValueNotifier<Color>(const Color(0xFF10B981));
  Timer? _toastDismissTimer;

  @override
  void initState() {
    super.initState();
    // Screen khulte hi portal se asali status verify karo
    _verifyRealPortalStatus();
  }

  Future<void> _verifyRealPortalStatus() async {
    // Agar parent ne pehle se hi verified status bhej rakha hai
    if (widget.currentUser['p10Status'] != null && widget.currentUser['p10Status']!.isNotEmpty) {
      setState(() {
        _verifiedP10Status = widget.currentUser['p10Status'];
        _isVerifiedLocked = widget.currentUser['isLocked'] == 'true';
      });
      return;
    }

    if (!mounted) return;
    setState(() => _isCheckingStatus = true);

    try {
      final res = await StaffLoginService.fetchProfile();
      if (!mounted) return;

      if (res['success'] == true && res['profile'] != null) {
        final profile = res['profile'] as Map<String, dynamic>;
        setState(() {
          _verifiedP10Status = profile['p10Status']?.toString() ?? "Status Unavailable";
          _isVerifiedLocked = profile['isLocked']?.toString().toLowerCase() == 'true';
        });
      } else {
        setState(() {
          _verifiedP10Status = "Status Unavailable";
          _isVerifiedLocked = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _verifiedP10Status = "Status Unavailable";
          _isVerifiedLocked = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isCheckingStatus = false);
    }
  }

  void _showAppleToast({
    required String message,
    bool isProgress = false,
    double progress = 0.0,
    IconData icon = CupertinoIcons.checkmark_alt,
    Color iconColor = const Color(0xFF10B981),
    int durationMs = 2200,
  }) {
    _toastDismissTimer?.cancel();

    _toastMessage.value = message;
    _toastIsProgress.value = isProgress;
    _toastProgressVal.value = progress;
    _toastIcon.value = icon;
    _toastIconColor.value = iconColor;

    if (_toastEntry != null) {
      if (!isProgress) {
        _toastDismissTimer = Timer(Duration(milliseconds: durationMs), () {
          _dismissToast();
        });
      }
      return;
    }

    HapticFeedback.lightImpact();
    final overlay = Overlay.of(context);
    final topInset = MediaQuery.of(context).padding.top;

    _toastEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: topInset + 12,
        left: 20,
        right: 20,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF000000).withOpacity(0.96),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.14), width: 0.8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: _toastIsProgress,
                        builder: (context, isProg, _) {
                          if (isProg) {
                            return ValueListenableBuilder<double>(
                              valueListenable: _toastProgressVal,
                              builder: (context, prog, _) {
                                return IosDownloadProgressIndicator(
                                  size: 16.5,
                                  progress: prog,
                                  color: const Color(0xFF007AFF),
                                  trackColor: const Color(0xFF007AFF).withOpacity(0.25),
                                );
                              },
                            );
                          }
                          return ValueListenableBuilder<IconData>(
                            valueListenable: _toastIcon,
                            builder: (context, ic, _) {
                              return ValueListenableBuilder<Color>(
                                valueListenable: _toastIconColor,
                                builder: (context, col, _) {
                                  return Icon(ic, color: col, size: 15);
                                },
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: ValueListenableBuilder<String>(
                          valueListenable: _toastMessage,
                          builder: (context, msg, _) {
                            return Text(
                              msg,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 11.8,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
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

    overlay.insert(_toastEntry!);

    if (!isProgress) {
      _toastDismissTimer = Timer(Duration(milliseconds: durationMs), () {
        _dismissToast();
      });
    }
  }

  void _dismissToast() {
    _toastDismissTimer?.cancel();
    _toastEntry?.remove();
    _toastEntry = null;
  }

  void _startSimulatedProgress() {
    _downloadProgress = 0.15;
    _showAppleToast(
      message: "Generating Format-10 PDF...",
      isProgress: true,
      progress: _downloadProgress,
    );

    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 180), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_downloadProgress < 0.88) {
          _downloadProgress += 0.04;
          _toastProgressVal.value = _downloadProgress;
        }
      });
    });
  }

  void _stopSimulatedProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _handleFormat10Action({required bool isDownloadOnly}) async {
    if (_isDownloading || _isViewing) return;

    final nicId = widget.currentUser['nicId'];
    final fileName = "Format10_${widget.currentUser['name'] ?? 'Staff'}_${nicId ?? 'Doc'}.pdf";

    setState(() {
      if (isDownloadOnly) {
        _isDownloading = true;
        _startSimulatedProgress();
      } else {
        _isViewing = true;
      }
    });

    try {
      final pdfBytes = await StaffLoginService.downloadFormat10Pdf(nicId: nicId);

      _stopSimulatedProgress();

      if (!mounted) return;

      if (pdfBytes == null || pdfBytes.isEmpty) {
        _dismissToast();
        _showAppleToast(
          message: "Failed to generate Format-10",
          icon: CupertinoIcons.exclamationmark_triangle_fill,
          iconColor: const Color(0xFFEF4444),
        );
        return;
      }

      if (isDownloadOnly) {
        setState(() => _downloadProgress = 1.0);
        _toastProgressVal.value = 1.0;

        _showAppleToast(
          message: "Format-10 PDF Ready",
          icon: CupertinoIcons.checkmark_seal_fill,
          iconColor: const Color(0xFF10B981),
        );

        await Future.delayed(const Duration(milliseconds: 400));
        _dismissToast();
        await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
      } else {
        _dismissToast();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _Format10PreviewScreen(
              pdfBytes: pdfBytes,
              employeeName: widget.currentUser['name'] ?? 'Staff User',
              nicId: nicId ?? '--',
              fileName: fileName,
            ),
          ),
        );
      }
    } catch (e) {
      _stopSimulatedProgress();
      _showAppleToast(
        message: "Error: $e",
        icon: CupertinoIcons.exclamationmark_triangle_fill,
        iconColor: const Color(0xFFEF4444),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _isViewing = false;
          _downloadProgress = 0.0;
        });
      }
    }
  }

  Widget _buildMetaCol(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: kAppFont,
            fontSize: 9.0,
            fontWeight: FontWeight.w700,
            color: Color(0xFF94A3B8),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontFamily: kAppFont,
            fontSize: 11.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _toastDismissTimer?.cancel();
    _dismissToast();
    _toastMessage.dispose();
    _toastIsProgress.dispose();
    _toastProgressVal.dispose();
    _toastIcon.dispose();
    _toastIconColor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Employee Header Badge Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(CupertinoIcons.doc_text_fill, color: Color(0xFF0F172A), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Staff Service Record (Format-10)",
                            style: TextStyle(
                              fontFamily: kAppFont,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Verified by School Head • NIC: ${widget.currentUser['nicId'] ?? '--'}",
                            style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, color: Color(0xFF64748B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // 🛡️ GENUINE PORTAL-VERIFIED STATUS BADGE (Zero False-Positives)
                    Builder(
                      builder: (context) {
                        if (_isCheckingStatus) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                CupertinoActivityIndicator(radius: 5),
                                SizedBox(width: 4),
                                Text(
                                  "Verifying...",
                                  style: TextStyle(fontFamily: kAppFont, fontSize: 9.0, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          );
                        }

                        final statusText = _verifiedP10Status ?? "Status Unavailable";
                        final isLocked = _isVerifiedLocked == true;
                        final isPending = statusText.toLowerCase().contains("pending");

                        final Color bg;
                        final Color fg;
                        final Color borderColor;

                        if (isLocked) {
                          bg = const Color(0xFFDCFCE7);
                          fg = const Color(0xFF16A34A);
                          borderColor = const Color(0xFF86EFAC);
                        } else if (isPending) {
                          bg = const Color(0xFFFEF3C7);
                          fg = const Color(0xFFD97706);
                          borderColor = const Color(0xFFFDE68A);
                        } else {
                          // Offline / Not Connected / Error
                          bg = const Color(0xFFF1F5F9);
                          fg = const Color(0xFF64748B);
                          borderColor = const Color(0xFFCBD5E1);
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: borderColor, width: 0.8),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontFamily: kAppFont,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: fg,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildMetaCol("EMPLOYEE NAME", widget.currentUser["name"] ?? "--")),
                    const SizedBox(width: 8),
                    Expanded(child: _buildMetaCol("DESIGNATION", widget.currentUser["designation"] ?? "--")),
                    const SizedBox(width: 8),
                    Expanded(child: _buildMetaCol("STAFF ID", widget.currentUser["staffLoginId"] ?? widget.currentUser["nicId"] ?? "--")),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Action Trigger Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Service Book Document",
                  style: TextStyle(fontFamily: kAppFont, fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Inspect academic qualifications, salary structure, and service records inside app or download official PDF.",
                  style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, color: Color(0xFF64748B), height: 1.4),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    // View Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_isViewing || _isDownloading) ? null : () => _handleFormat10Action(isDownloadOnly: false),
                        icon: _isViewing
                            ? const CupertinoActivityIndicator(radius: 8, color: Colors.white)
                            : const Icon(CupertinoIcons.eye_fill, size: 15, color: Colors.white),
                        label: Text(
                          _isViewing ? "Opening..." : "View Format-10",
                          style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.all(const Color(0xFF0F172A)),
                          foregroundColor: WidgetStateProperty.all(Colors.white),
                          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 11)),
                          elevation: WidgetStateProperty.all(0),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Download Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_isViewing || _isDownloading) ? null : () => _handleFormat10Action(isDownloadOnly: true),
                        icon: _isDownloading
                            ? IosDownloadProgressIndicator(
                                size: 16.5,
                                progress: _downloadProgress,
                                color: const Color(0xFF007AFF),
                              )
                            : const Icon(
                                CupertinoIcons.arrow_down_doc_fill,
                                size: 15,
                                color: Color(0xFF0F172A),
                              ),
                        label: Text(
                          "Download PDF",
                          style: TextStyle(
                            fontFamily: kAppFont,
                            fontSize: 12.0,
                            fontWeight: FontWeight.w700,
                            color: _isDownloading ? const Color(0xFF007AFF) : const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ButtonStyle(
                          side: WidgetStateProperty.all(
                            BorderSide(
                              color: _isDownloading ? const Color(0xFF007AFF) : const Color(0xFFCBD5E1),
                              width: 1.0,
                            ),
                          ),
                          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 11)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 📄 Ultra-Clean Dedicated Format-10 PDF Viewer with RepaintBoundary for Smooth Scrolling
class _Format10PreviewScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  final String employeeName;
  final String nicId;
  final String fileName;

  const _Format10PreviewScreen({
    required this.pdfBytes,
    required this.employeeName,
    required this.nicId,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leadingWidth: 54,
          leading: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Center(
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(CupertinoIcons.chevron_back, size: 18, color: Color(0xFF0F172A)),
                ),
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Format-10 • $employeeName",
                style: const TextStyle(fontFamily: kAppFont, fontSize: 14.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                "NIC: $nicId  •  Service Book Record",
                style: const TextStyle(fontFamily: kAppFont, fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
              ),
            ],
          ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, thickness: 0.8, color: Color(0xFFE2E8F0)),
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.45, 1.0],
                        colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9), Color(0xFFFEF3C7)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: -50,
                    top: -40,
                    child: Container(
                      width: 270,
                      height: 270,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [const Color(0xFFBAE6FD).withOpacity(0.35), const Color(0xFFBAE6FD).withOpacity(0.0)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -50,
                    top: 120,
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [const Color(0xFFFDE68A).withOpacity(0.35), const Color(0xFFFDE68A).withOpacity(0.0)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 74.0),
                child: RepaintBoundary(
                  child: PdfPreview(
                    build: (format) async => pdfBytes,
                    allowSharing: false,
                    allowPrinting: false,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    useActions: false,
                    initialPageFormat: PdfPageFormat.a4,
                    pdfFileName: fileName,
                    loadingWidget: const Center(
                      child: CupertinoActivityIndicator(radius: 14, color: Color(0xFF0F172A)),
                    ),
                    scrollViewDecoration: const BoxDecoration(color: Colors.transparent),
                    pdfPreviewPageDecoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 4)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          await Printing.layoutPdf(onLayout: (_) async => pdfBytes, name: fileName);
                        },
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFF000000),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 3)),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                alignment: Alignment.center,
                                child: const Icon(CupertinoIcons.printer, size: 13, color: Color(0xFF000000)),
                              ),
                              const SizedBox(width: 7),
                              const Text("Print", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
                        },
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF007AFF).withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3)),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(CupertinoIcons.share, size: 18, color: Color(0xFF007AFF)),
                              SizedBox(width: 7),
                              Text("Share", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF007AFF))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}