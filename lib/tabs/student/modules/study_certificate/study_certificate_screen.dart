import 'package:shaladarpan/widgets/page_content_motion.dart';
import 'package:shaladarpan/widgets/route_completion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shaladarpan/widgets/adaptive_layout.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/student_study_certificate_service.dart';
import '../student_nic/nic_download_indicator.dart';
import 'study_certificate_pdf_preview_screen.dart';

class StudyCertificateScreen extends StatefulWidget {
  const StudyCertificateScreen({super.key});
  @override
  State<StudyCertificateScreen> createState() => _StudyCertificateScreenState();
}

class _StudyCertificateScreenState extends State<StudyCertificateScreen> {
  final _sr = TextEditingController();
  bool _busy = false;
  double _progress = 0;
  String? _error;
  static const _ink = Color(0xFF18212F);
  static const _blue = Color(0xFF007AFF);
  TextStyle _text(double size, {Color color = _ink, FontWeight weight = FontWeight.w500}) =>
      TextStyle(fontFamily: 'PlusJakartaSans', fontSize: size, color: color, fontWeight: weight);

  @override
  void dispose() { _sr.dispose(); super.dispose(); }

  Future<void> _download() async {
    if (_busy) return;
    final sr = _sr.text.trim();
    if (!RegExp(r'^[0-9]{1,30}$').hasMatch(sr)) {
      setState(() => _error = 'Enter a valid SR number.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _progress = .08; _error = null; });
    try {
      final creds = await SecureStorageService.getShaladarpanCreds();
      final school = creds['id']?.trim() ?? '';
      final file = await StudentStudyCertificateService.download(srNo: sr, expectedSchool: school,
        onProgress: (value) { if (mounted) setState(() => _progress = value); });
      if (!mounted) return;
      await pushPageAndWaitForExit<void>(context, MaterialPageRoute<void>(builder: (_) =>
        StudyCertificatePdfPreviewScreen(bytes: file.bytes, filename: file.filename, srLabel: 'SR : $sr')));
    } catch (error) {
      if (mounted) setState(() => _error = error is FormatException ? error.message : '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, viewport) => Scaffold(
    backgroundColor: const Color(0xFFF8FAFC),
    appBar: PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: SafeArea(bottom: false, child: Center(child: SizedBox(
        width: AppAdaptive.contentWidth(viewport.maxWidth), height: kToolbarHeight,
        child: Row(children: [
          const SizedBox(width: 8),
          const BackButton(color: _ink),
          const SizedBox(width: 6),
          Expanded(child: Text('Study Certificate', style: _text(16, weight: FontWeight.w600))),
        ]),
      ))),
    ),
    body: AdaptiveWorkspace(background: true, child: PageContentMotion(child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE5E9EF)),
              boxShadow: const [BoxShadow(color: Color(0x060F172A), blurRadius: 20, offset: Offset(0, 6))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(width: 42, height: 42,
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(CupertinoIcons.doc_text, size: 22, color: _ink)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Student certificate', style: _text(15, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Download from Shaladarpan', style: _text(12, color: const Color(0xFF64748B))),
                ])),
              ]),
              const Padding(padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1, color: Color(0xFFEDF0F4))),
              Text('SR Number', style: _text(13, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _sr, enabled: !_busy, cursorColor: _blue, maxLength: 30,
                keyboardType: TextInputType.number, textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _download(),
                onChanged: (_) { if (_error != null) setState(() => _error = null); },
                style: _text(15, weight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Enter SR number', counterText: '',
                  hintStyle: _text(14, color: const Color(0xFF7C8797)),
                  isDense: true, filled: true, fillColor: const Color(0xFFF7F8FA),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E9EF))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E9EF))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _blue)),
                  disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E9EF))),
                ),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 9),
                child: SelectableText(_error!, style: _text(13, color: const Color(0xFFB42318)))),
              const SizedBox(height: 14),
              SizedBox(height: 44, child: FilledButton(
                onPressed: _busy ? null : _download,
                style: FilledButton.styleFrom(backgroundColor: _ink, foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFF1F5F9), disabledForegroundColor: _ink,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (_busy) NicDownloadIndicator(size: 21, progress: _progress)
                  else const Icon(CupertinoIcons.arrow_down_doc, size: 18),
                  const SizedBox(width: 9),
                  Flexible(child: Text(_busy ? 'Downloading…' : 'Download PDF',
                    style: _text(14, color: _busy ? _ink : Colors.white, weight: FontWeight.w600))),
                ]),
              )),
            ]),
          ),
        ]),
      )),
    ))),
  ));
}
