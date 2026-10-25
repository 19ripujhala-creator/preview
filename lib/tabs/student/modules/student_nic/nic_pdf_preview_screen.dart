import 'package:shaladarpan/widgets/page_content_motion.dart';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:shaladarpan/widgets/adaptive_layout.dart';

class NicPdfPreviewScreen extends StatelessWidget {
  final Uint8List bytes;
  final String filename;
  final String classLabel;
  const NicPdfPreviewScreen({super.key, required this.bytes, required this.filename, required this.classLabel});

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
    appBar: AppBar(backgroundColor: const Color(0xFFF8FAFC), foregroundColor: const Color(0xFF0F172A),
      surfaceTintColor: Colors.transparent, elevation: 0,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Student NIC sheet', style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 15, fontWeight: FontWeight.w600)),
        Text(classLabel, style: const TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 11, color: Color(0xFF64748B))),
      ]),
      actions: [
        Padding(
          padding: EdgeInsets.only(right: AppAdaptive.gutter(constraints.maxWidth) + 10),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xDBFFFFFF),
              border: Border.all(color: Colors.white),
              boxShadow: const [
                BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: IconButton(
              tooltip: 'Share PDF',
              onPressed: () => _share(context),
              padding: EdgeInsets.zero,
              icon: const Icon(CupertinoIcons.share, size: 20, color: Color(0xFF007AFF)),
            ),
          ),
        ),
      ]),
    body: AdaptiveWorkspace(background: true,
      child: PageContentMotion(child: PdfPreview(build: (_) async => bytes, pdfFileName: filename,
          initialPageFormat: PdfPageFormat.a4.landscape, canChangeOrientation: false, canChangePageFormat: false,
          allowSharing: false, allowPrinting: false, useActions: false,
          loadingWidget: const Center(child: CupertinoActivityIndicator(radius: 13)),
          scrollViewDecoration: const BoxDecoration(color: Colors.transparent),
          pdfPreviewPageDecoration: const BoxDecoration(color: Colors.white,
            boxShadow: [BoxShadow(color: Color(0x150F172A), blurRadius: 12, offset: Offset(0, 3))]))),
    ),
    ),
  );
}
