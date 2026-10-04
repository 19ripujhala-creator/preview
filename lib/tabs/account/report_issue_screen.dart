import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';

class ReportIssueScreen extends StatefulWidget {
  final String connectionSummary;
  const ReportIssueScreen({super.key, required this.connectionSummary});
  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  static const _recipient = '19ripu.jhala@gmail.com';
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _border = Color(0xFFE2E8F0);
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final List<({XFile file, int size})> _files = [];
  bool _busy = false;
  bool _includeSummary = false;
  String? _feedback;
  bool get _nativeAttachments => !kIsWeb && [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS].contains(defaultTargetPlatform);

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  TextStyle _style(double size, [FontWeight weight = FontWeight.w400, Color color = _ink]) =>
      TextStyle(fontFamily: 'PlusJakartaSans', fontSize: size, fontWeight: weight, color: color);

  InputDecoration _input(String label, String hint) => InputDecoration(
    labelText: label, hintText: hint, alignLabelWithHint: true,
    labelStyle: _style(12, FontWeight.w400, _muted), hintStyle: _style(12, FontWeight.w400, _muted),
    filled: true, fillColor: const Color(0xFFF8FAFC),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _ink)),
    contentPadding: const EdgeInsets.all(16),
  );

  Future<void> _attach() async {
    if (_busy) return;
    setState(() { _busy = true; _feedback = null; });
    try {
      final selected = await openFiles(acceptedTypeGroups: const [XTypeGroup(
        label: 'Screenshots, PDF and text', extensions: ['png', 'jpg', 'jpeg', 'pdf', 'txt', 'log'],
        uniformTypeIdentifiers: ['public.png', 'public.jpeg', 'com.adobe.pdf', 'public.plain-text'],
        mimeTypes: ['image/png', 'image/jpeg', 'application/pdf', 'text/plain'],
      )]);
      final added = <({XFile file, int size})>[];
      var total = _files.fold<int>(0, (sum, item) => sum + item.size);
      for (final file in selected) {
        if (_files.any((item) => item.file.path == file.path) || added.any((item) => item.file.path == file.path)) continue;
        final size = await file.length();
        if (_files.length + added.length >= 5 || size > 5 * 1024 * 1024 || total + size > 10 * 1024 * 1024) {
          if (mounted) setState(() => _feedback = 'Up to 5 files, 5 MB per file and 10 MB total. Some files were not added.');
          continue;
        }
        if (size == 0 || file.path.isEmpty) continue;
        total += size;
        added.add((file: file, size: size));
      }
      if (mounted) setState(() => _files.addAll(added));
    } catch (_) {
      if (mounted) setState(() => _feedback = 'Could not read the selected files. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _body {
    const version = String.fromEnvironment('FLUTTER_BUILD_NAME');
    const build = String.fromEnvironment('FLUTTER_BUILD_NUMBER');
    return '${_description.text.trim()}\n\n'
        'App: Shaladarpan\nPlatform: ${kIsWeb ? 'Web' : defaultTargetPlatform.name}\n'
        '${version.isEmpty ? '' : 'Version: $version${build.isEmpty ? '' : ' ($build)'}\n'}'
        '${_includeSummary ? '\nConnection summary (included by user):\n${widget.connectionSummary}\n' : ''}';
  }

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _feedback = null; });
    try {
      final capability = await FlutterEmailSender.getCapabilities();
      if (!capability.canSend) {
        if (mounted) setState(() => _feedback = 'Set up an email account on this device, or copy this report and email it to $_recipient.');
        return;
      }
      if (_files.isNotEmpty && !capability.supportsAttachments) {
        if (mounted) setState(() => _feedback = 'This email client cannot accept attachments. Your files and report are kept here. Use a supported mobile email client.');
        return;
      }
      // Re-read before handing paths to the composer; missing files must never be silently dropped.
      for (final item in _files) {
        if (await item.file.length() != item.size) throw StateError('Attachment changed');
      }
      await FlutterEmailSender.send(Email(
        recipients: const [_recipient], subject: '[Shaladarpan app issue] ${_title.text.trim()}',
        body: _body, isHTML: false,
        attachmentPaths: _files.isEmpty ? null : _files.map((item) => item.file.path).toList(),
      ));
      if (mounted) setState(() => _feedback = 'Finish sending in your email app. This form is kept until you leave this screen.');
    } on FlutterEmailSenderNotAvailableException {
      if (mounted) setState(() => _feedback = 'Email is unavailable. Copy the report below and email it to $_recipient.');
    } catch (_) {
      if (mounted) setState(() => _feedback = 'Could not open the email draft. Your report is kept here. Try again or use Copy report.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    if (!_form.currentState!.validate()) return;
    try {
      await Clipboard.setData(ClipboardData(text: 'To: $_recipient\nSubject: [Shaladarpan app issue] ${_title.text.trim()}\n\n$_body'));
      if (mounted) setState(() => _feedback = 'Report copied. Paste it into your email app and attach any files there.');
    } catch (_) {
      if (mounted) setState(() => _feedback = 'Could not copy the report. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(primary: _ink, secondary: _ink),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: _ink, selectionColor: Color(0xFFCBD5E1), selectionHandleColor: _ink)),
    child: Scaffold(
    backgroundColor: const Color(0xFFF8FAFC),
    appBar: AppBar(backgroundColor: const Color(0xFFF8FAFC), surfaceTintColor: Colors.transparent,
      title: Text('Report app issue', style: _style(18, FontWeight.w600))),
    body: Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        stops: [0, .45, 1], colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9), Color(0xFFFEF3C7)])),
      child: SizedBox.expand(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680),
          child: Container(padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: _border)),
            child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tell us what happened', style: _style(18, FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Describe the issue and the steps to reproduce it.', style: _style(12, FontWeight.w400, _muted)),
              const SizedBox(height: 22),
              TextFormField(cursorColor: _ink, controller: _title, enabled: !_busy, maxLength: 120, style: _style(13),
                decoration: _input('Issue title', 'A short summary'),
                validator: (value) => (value ?? '').trim().isEmpty ? 'Enter an issue title' : null),
              const SizedBox(height: 12),
              TextFormField(cursorColor: _ink, controller: _description, enabled: !_busy, minLines: 6, maxLines: 12, maxLength: 4000,
                style: _style(13), decoration: _input('Description', 'Which screen were you using? What did you expect, and what happened?'),
                validator: (value) => (value ?? '').trim().length < 10 ? 'Describe the issue in at least 10 characters' : null),
              const SizedBox(height: 16),
              Text('Attachments', style: _style(13, FontWeight.w600)),
              const SizedBox(height: 6),
              Text(_nativeAttachments ? 'Screenshots, PDF or text · Up to 5 files, 10 MB total' :
                'On this platform, add attachments in your email app after opening the draft.', style: _style(11.5, FontWeight.w400, _muted)),
              if (_nativeAttachments) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: _busy || _files.length >= 5 ? null : _attach,
                  icon: const Icon(CupertinoIcons.paperclip, size: 17), label: const Text('Add attachments'),
                  style: OutlinedButton.styleFrom(foregroundColor: _ink, side: const BorderSide(color: _border))),
              ],
              ..._files.asMap().entries.map((entry) => Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [
                const Icon(CupertinoIcons.doc, size: 18, color: _muted), const SizedBox(width: 10),
                Expanded(child: Text('${entry.value.file.name} · ${(entry.value.size / 1024).ceil()} KB', overflow: TextOverflow.ellipsis, style: _style(12))),
                IconButton(tooltip: 'Remove attachment', onPressed: _busy ? null : () => setState(() => _files.removeAt(entry.key)), icon: const Icon(CupertinoIcons.xmark, size: 14)),
              ]))),
              const SizedBox(height: 18),
              CheckboxListTile(value: _includeSummary, onChanged: _busy ? null : (value) => setState(() => _includeSummary = value ?? false),
                contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
                title: Text('Include connection summary', style: _style(12, FontWeight.w500)),
                subtitle: Text('School and portal login IDs, session status and last checked time. No passwords or tokens.', style: _style(10.5, FontWeight.w400, _muted))),
              if (_includeSummary) Padding(padding: const EdgeInsets.only(bottom: 12), child: SelectableText(widget.connectionSummary, style: _style(11, FontWeight.w400, _muted))),
              const Divider(height: 28, color: _border),
              Text('To: $_recipient', style: _style(11.5, FontWeight.w500)),
              const SizedBox(height: 5),
              Text('Review and send from your email app. Please keep passwords out of the description and attachments.', style: _style(11, FontWeight.w400, _muted)),
              if (_feedback != null) Padding(padding: const EdgeInsets.only(top: 14), child: Semantics(liveRegion: true, child: Text(_feedback!, style: _style(12)))),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _send,
                style: FilledButton.styleFrom(backgroundColor: _ink, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: _busy ? const CupertinoActivityIndicator(color: Colors.white, radius: 8) : const Icon(CupertinoIcons.envelope, size: 18),
                label: Text(_busy ? 'Please wait…' : 'Continue to email', style: _style(12.5, FontWeight.w600, Colors.white)))),
              Center(child: TextButton(onPressed: _busy ? null : _copy, child: Text('Copy report', style: _style(11.5, FontWeight.w500)))),
            ])),
          ),
        )),
      )),
    ),
  ));
}
