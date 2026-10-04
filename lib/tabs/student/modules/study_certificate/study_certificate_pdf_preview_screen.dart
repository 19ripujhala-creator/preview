import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:shaladarpan/widgets/adaptive_layout.dart';

class StudyCertificatePdfPreviewScreen extends StatelessWidget {
  final Uint8List bytes;
  final String filename;
  final String srLabel;
  const StudyCertificatePdfPreviewScreen({super.key, required this.bytes, required this.filename, required this.srLabel});

  Future<void> _share(BuildContext context) async {
    try {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Scaffold(
    backgroundColor: const Color(0xFFF8FAFC),
    appBar: PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: SafeArea(bottom: false, child: Center(
        child: SizedBox(
          width: AppAdaptive.contentWidth(constraints.maxWidth),
          height: kToolbarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              BackButton(color: const Color(0xFF0F172A)),
              const SizedBox(width: 8),
              Expanded(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Study Certificate', style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(srLabel, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 11, color: Color(0xFF64748B))),
                ],
              )),
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xDBFFFFFF),
                  border: Border.all(color: Colors.white),
                  boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: IconButton(
                  tooltip: 'Share PDF', onPressed: () => _share(context),
                  padding: EdgeInsets.zero,
                  icon: const Icon(CupertinoIcons.share, size: 20, color: Color(0xFF007AFF)),
                ),
              ),
              const SizedBox(width: 8),
            ]),
          ),
        ),
      )),
    ),
    body: AdaptiveWorkspace(background: true,
      child: LayoutBuilder(builder: (context, viewport) {
        // Fit a complete portrait page on larger screens; phones retain
        // their readable full-width preview. Only display sizing changes.
        final pageRatio = PdfPageFormat.a4.width / PdfPageFormat.a4.height;
        final availableWidth = (viewport.maxWidth - 32).clamp(1.0, double.infinity).toDouble();
        final availableHeight = (viewport.maxHeight - 48).clamp(1.0, double.infinity).toDouble();
        final fitWidth = availableHeight * pageRatio;
        final pageWidth = viewport.maxWidth >= 600 && fitWidth < availableWidth
            ? fitWidth : availableWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: pageWidth + 32,
            height: viewport.maxHeight,
            child: PdfPreviewCustom(
          build: (_) async => bytes,
          pageFormat: PdfPageFormat.a4,
          maxPageWidth: pageWidth,
          padding: const EdgeInsets.all(16),
          previewPageMargin: const EdgeInsets.only(bottom: 16),
          scrollPhysics: const ClampingScrollPhysics(),
          loadingWidget: const Center(child: CupertinoActivityIndicator(radius: 13)),
          scrollViewDecoration: const BoxDecoration(color: Colors.transparent),
          pdfPreviewPageDecoration: const BoxDecoration(color: Colors.white,
            boxShadow: [BoxShadow(color: Color(0x150F172A), blurRadius: 12, offset: Offset(0, 3))]),
            ),
          ),
        );
      }),
    ),
    ),
  );
}
