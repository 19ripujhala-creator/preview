/// ReportLab overlay and pypdf vector-page merge equivalents for mpr_pdf.py.
/// Uses only the original bundled fonts, exact metrics and original PDF page.
library;

import 'dart:ffi' as ffi;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdf/pdf.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart' as pdfium;

import 'mpr_pdf.dart';

class MprPdfAssets {
  MprPdfAssets({
    required this.template,
    required this.latin,
    required this.hindi,
    required this.metrics,
    this.bold,
  });
  final Uint8List template, latin, hindi;
  final Uint8List? bold;
  final Map<String, dynamic> metrics;
}

class MprPdfRenderer {
  MprPdfRenderer({pdfium.PDFium? bindings})
    : _pdfium = bindings ?? pdfium.getPdfium() {
    _pdfium.FPDF_InitLibrary();
  }
  final pdfium.PDFium _pdfium;
  bool _closed = false;
  Future<Uint8List> render(
    MprPdfPlan plan,
    MprPdfAssets assets, {
    List<Map<String, dynamic>>? trace,
  }) async {
    if (_closed) throw const MprPdfError('MPR PDF renderer is closed.');
    final document = PdfDocument();
    // Each overlay has the same Legal page as the original Python canvas.
    final overlayPage = PdfPage(
      document,
      pageFormat: const PdfPageFormat(612, 1008),
    );
    final canvas = overlayPage.getGraphics(),
        latin = PdfTtfFont(
          document,
          ByteData.sublistView(assets.bold ?? assets.latin),
        ),
        hindiPdf = PdfTtfFont(document, ByteData.sublistView(assets.hindi));
    for (final command in plan.commands) {
      double n(String key) => (command[key] as num).toDouble();
      switch (command['type']) {
        case 'cell':
          final text = command['text'] as String,
              x = n('x'),
              y = n('y'),
              w = n('width'),
              h = n('height'),
              isHindi = text.runes.any((c) => c >= 0x900 && c <= 0x97f),
              meta = Map<String, dynamic>.from(
                assets.metrics[isHindi
                        ? 'hindi'
                        : assets.bold != null
                        ? 'bold'
                        : 'latin']
                    as Map,
              );
          final widths = Map<String, dynamic>.from(meta['widths'] as Map);
          double measure(double size) =>
              text.runes.fold<double>(
                0,
                (sum, r) =>
                    sum +
                    ((widths[r.toString()] ?? meta['default_width']) as num)
                        .toDouble(),
              ) *
              size *
              .001;
          if (command['erase'] == true) {
            canvas.setColor(PdfColors.white);
            canvas.drawRect(x + .6, 1008 - y - h + .6, w - 1.2, h - 1.2);
            canvas.fillPath();
          }
          var size = math.min(10.2, h * .84), usable = math.max(1.0, w - 4.8);
          while (size > 7.8 && measure(size) > usable) {
            size -= .15;
          }
          if (measure(size) > usable) {
            while (size > 4.8 && measure(size) > usable) {
              size -= .1;
            }
          }
          if (measure(size) > usable)
            throw const MprPdfError(
              'A report field is too long to fit the original PDF.',
            );
          final ascent = (meta['ascent'] as num).toDouble() * size * .001,
              descent = (meta['descent'] as num).toDouble() * size * .001,
              baseline = 1008 - y - h / 2 - (ascent + descent) / 2 + .34;
          canvas.setColor(PdfColors.black);
          final textWidth = measure(size);
          final left = command['align'] == 'left'
              ? x + 2.4
              : x + w / 2 - textWidth / 2;
          final offsets = isHindi || assets.bold == null
              ? [-.175, .175]
              : [0.0];
          trace?.add({
            'type': 'text',
            'text': text,
            'font': isHindi
                ? 'MPRHindi'
                : assets.bold != null
                ? 'MPRRobotoBold'
                : 'MPRRoboto',
            'size': size,
            'baseline': baseline,
            'left': left,
            'advance': textWidth,
            'offsets': offsets,
          });
          for (final dx in offsets) {
            canvas.drawString(
              isHindi ? hindiPdf : latin,
              size,
              text,
              left + dx,
              baseline,
            );
          }
        case 'rect':
          canvas.saveContext();
          final color = (command['color'] as List).cast<num>();
          canvas.setColor(
            PdfColor(
              color[0].toDouble(),
              color[1].toDouble(),
              color[2].toDouble(),
            ),
          );
          canvas.setLineWidth(n('line_width'));
          canvas.setLineDashPattern(
            (command['dash'] as List).cast<num>(),
            command['dash_phase'] as int,
          );
          canvas.drawRect(n('x'), n('y'), n('width'), n('height'));
          if (command['fill'] == true && command['stroke'] == true) {
            canvas.fillAndStrokePath();
          } else if (command['fill'] == true) {
            canvas.fillPath();
          } else if (command['stroke'] == true) {
            canvas.strokePath();
          }
          canvas.restoreContext();
        case 'line':
          canvas.saveContext();
          canvas.setColor(PdfColors.black);
          canvas.setLineWidth(n('line_width'));
          if (command['round'] == true) {
            canvas.setLineCap(PdfLineCap.round);
            canvas.setLineJoin(PdfLineJoin.round);
          }
          canvas.moveTo(n('x1'), n('y1'));
          canvas.lineTo(n('x2'), n('y2'));
          canvas.strokePath();
          canvas.restoreContext();
        default:
          throw const MprPdfError('Invalid MPR drawing operation.');
      }
    }
    final overlay = await document.save();
    return _merge(assets.template, overlay);
  }

  Uint8List _merge(Uint8List original, Uint8List overlay) {
    final sourceBuffer = calloc<ffi.Uint8>(original.length),
        overlayBuffer = calloc<ffi.Uint8>(overlay.length);
    sourceBuffer.asTypedList(original.length).setAll(0, original);
    overlayBuffer.asTypedList(overlay.length).setAll(0, overlay);
    var source = ffi.nullptr.cast<pdfium.fpdf_document_t__>(),
        over = ffi.nullptr.cast<pdfium.fpdf_document_t__>(),
        output = ffi.nullptr.cast<pdfium.fpdf_document_t__>(),
        page = ffi.nullptr.cast<pdfium.fpdf_page_t__>();
    try {
      source = _pdfium.FPDF_LoadMemDocument64(
        sourceBuffer.cast(),
        original.length,
        ffi.nullptr,
      );
      over = _pdfium.FPDF_LoadMemDocument64(
        overlayBuffer.cast(),
        overlay.length,
        ffi.nullptr,
      );
      if (source == ffi.nullptr ||
          over == ffi.nullptr ||
          _pdfium.FPDF_GetPageCount(source) < 1 ||
          _pdfium.FPDF_GetPageCount(over) != 1)
        throw const MprPdfError(
          'The original MPR PDF or overlay could not be opened.',
        );
      output = _pdfium.FPDF_CreateNewDocument();
      if (output == ffi.nullptr)
        throw const MprPdfError('MPR PDF document could not be created.');
      const a4w = 595.275590551, a4h = 841.88976378;
      page = _pdfium.FPDFPage_New(output, 0, a4w, a4h);
      if (page == ffi.nullptr)
        throw const MprPdfError('MPR PDF page could not be created.');
      final sourcePage = _pdfium.FPDF_LoadPage(source, 0);
      if (sourcePage == ffi.nullptr)
        throw const MprPdfError('The original MPR PDF page is unavailable.');
      final sourceWidth = _pdfium.FPDF_GetPageWidthF(sourcePage);
      _pdfium.FPDF_ClosePage(sourcePage);
      final scale = math.min(a4w / sourceWidth, (a4h - 20) / 955),
          tx = (a4w - sourceWidth * scale) / 2,
          ty = 10 - 40 * scale;
      for (final doc in [source, over]) {
        final xobject = _pdfium.FPDF_NewXObjectFromPage(output, doc, 0);
        if (xobject == ffi.nullptr)
          throw const MprPdfError(
            'The original vector MPR page could not be imported.',
          );
        try {
          final object = _pdfium.FPDF_NewFormObjectFromXObject(xobject);
          if (object == ffi.nullptr)
            throw const MprPdfError('MPR PDF content could not be imported.');
          _pdfium.FPDFPageObj_Transform(object, scale, 0, 0, scale, tx, ty);
          _pdfium.FPDFPage_InsertObject(page, object);
        } finally {
          _pdfium.FPDF_CloseXObject(xobject);
        }
      }
      _pdfium.FPDFPage_SetMediaBox(page, 0, 0, a4w, a4h);
      _pdfium.FPDFPage_SetCropBox(page, 0, 0, a4w, a4h);
      _pdfium.FPDFPage_SetTrimBox(page, 0, 0, a4w, a4h);
      _pdfium.FPDFPage_SetBleedBox(page, 0, 0, a4w, a4h);
      if (_pdfium.FPDFPage_GenerateContent(page) == 0)
        throw const MprPdfError('MPR PDF content could not be finalized.');
      final bytes = BytesBuilder(), writer = calloc<pdfium.FPDF_FILEWRITE>();
      final callback =
          ffi.NativeCallable<
            ffi.Int Function(
              ffi.Pointer<pdfium.FPDF_FILEWRITE_>,
              ffi.Pointer<ffi.Void>,
              ffi.UnsignedLong,
            )
          >.isolateLocal((
            ffi.Pointer<pdfium.FPDF_FILEWRITE_> self,
            ffi.Pointer<ffi.Void> data,
            int size,
          ) {
            try {
              bytes.add(data.cast<ffi.Uint8>().asTypedList(size));
              return 1;
            } catch (_) {
              return 0;
            }
          }, exceptionalReturn: 0);
      try {
        writer.ref.version = 1;
        writer.ref.WriteBlock = callback.nativeFunction;
        if (_pdfium.FPDF_SaveAsCopy(output, writer, 0) == 0)
          throw const MprPdfError('MPR PDF could not be saved.');
        return bytes.takeBytes();
      } finally {
        callback.close();
        calloc.free(writer);
      }
    } finally {
      if (page != ffi.nullptr) _pdfium.FPDF_ClosePage(page);
      if (output != ffi.nullptr) _pdfium.FPDF_CloseDocument(output);
      if (over != ffi.nullptr) _pdfium.FPDF_CloseDocument(over);
      if (source != ffi.nullptr) _pdfium.FPDF_CloseDocument(source);
      calloc.free(overlayBuffer);
      calloc.free(sourceBuffer);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _pdfium.FPDF_DestroyLibrary();
  }
}
