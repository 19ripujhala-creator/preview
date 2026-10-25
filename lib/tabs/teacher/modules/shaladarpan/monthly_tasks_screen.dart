import 'package:shaladarpan/widgets/page_content_motion.dart';
import 'package:shaladarpan/widgets/adaptive_layout.dart';
import 'package:shaladarpan/services/portals/shaladarpan/viffs_status_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/ranking_status_service.dart';
import 'package:shaladarpan/widgets/portal_calendar.dart';
import 'package:flutter/cupertino.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shaladarpan/services/portals/shaladarpan/monthly_task_service.dart';
import 'dart:convert';

part 'district_ranking_screen.dart';
part 'viffs_tablet_entry_screen.dart';

const ink = Color(0xFF0F172A), muted = Color(0xFF64748B);
const prefix = 'ContentPlaceHolder1_';
TextStyle _text(double size, [FontWeight weight = FontWeight.w500, Color color = ink]) =>
    TextStyle(fontFamily: 'PlusJakartaSans', fontSize: size, fontWeight: weight,
      color: color, height: 1.35, letterSpacing: -0.1);


class MonthlyTasksScreen extends StatefulWidget {
  final String schoolId, initialTask;
  final Map<String, dynamic>? initialForm;
  final bool embedded, active;
  final void Function(String task, bool? completed)? onStatus;
  const MonthlyTasksScreen({super.key, required this.schoolId, this.initialTask = 'ranking', this.onStatus, this.initialForm, this.embedded = false, this.active = true});
  @override
  State<MonthlyTasksScreen> createState() => initialTask == 'viffs'
      ? ViffsTabletEntryScreenState() : DistrictRankingScreenState();
}

abstract class MonthlyTasksScreenState extends State<MonthlyTasksScreen> {
  void _initialize();
  List<Map<String, dynamic>> get _fallbackPeriodFields;
  Widget _sectionForm(Map<String, dynamic> section);
  void _rememberSelectors(Map<String, dynamic> data) {}
  void _initialPeriodDefaults() {}
  void _prefillViffs() {}
  Map<String, String> _entryErrors() => {};
  bool get _rankingDraftMatchesSaved => false;
  Future<void> _rankingAction(String action) async {}
  Future<void> _lock() async {}
  Widget _periodStatus() => const SizedBox.shrink();
  bool get _showFinalActions => true;
  List<Map<String, dynamic>> get _periodFields => _data == null
      ? _fallbackPeriodFields : maps(_data!['selectors']);

  @override
  void initState() {
    super.initState();
    _task = widget.initialTask == 'viffs' ? 'viffs' : 'ranking';
    if (widget.initialForm != null) {
      _apply(Map<String, dynamic>.from(widget.initialForm!));
      _rememberSelectors(_data!);
      _prefillViffs();
    } else {
      _initialize();
    }
  }
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _inputs = {};
  final Map<String, String> _selection = {}, _choices = {};
  final Map<String, String> _fieldErrors = {};
  final Map<String, GlobalKey> _fieldKeys = {};
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _rankingStatus;
  late String _task;
  bool _reviewing = false, _loading = false, _saving = false, _selectionChanged = false, _edited = false, _uncertain = false;
  String? _message;
  String? _rankingOperation;
  bool _messageError = false;
  int _revision = 0;
  bool _showAllGroups = false;
  bool _showPeriodPicker = false;
  bool _prefilledViffs = false;
  bool get _busy => _loading || _saving || _reviewing;
  List<Map<String, dynamic>> maps(dynamic data) => data is List ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  @override
  void dispose() { for (final c in _inputs.values) { c.dispose(); } super.dispose(); }
  void _apply(Map<String, dynamic> data) {
    for (final c in _inputs.values) { c.dispose(); }
    _inputs.clear(); _choices.clear(); _selection.clear(); _fieldErrors.clear();
    _data = data;
    for (final entry in Map<String, dynamic>.from(data['selection'] as Map).entries) {
      _selection[entry.key] = entry.value.toString();
    }
    for (final section in maps(data['sections'])) {
      for (final field in maps(section['fields'])) {
        final id = field['id'].toString(), value = (field['value'] ?? '').toString();
        if (maps(field['options']).isNotEmpty) { _choices[id] = value; }
        else { _inputs[id] = TextEditingController(text: value); }
      }
    }
    _showAllGroups = false; _prefilledViffs = false;
    _showPeriodPicker = _task == 'viffs' || widget.embedded || maps(data['sections']).isEmpty;
    _revision++; _edited = false; _selectionChanged = false; _uncertain = false;
  }

  Future<void> _load({bool initial = false, bool refresh = false}) async {
    if (_busy) return;
    setState(() { _loading = true; _message = null; });
    try {
      final now = DateTime.now();
      final previous = DateTime(now.year, now.month, 0);
      final initialSelection = _task == 'ranking'
        ? {'${prefix}ddlMonth1': '${previous.month}', '${prefix}ddlyear': '${previous.year}'}
        : <String, String>{};
      final result = await MonthlyTaskService.fetch(widget.schoolId, _task, _task == 'ranking' ? (_selection.isEmpty ? initialSelection : Map.of(_selection)) : (initial ? initialSelection : Map.of(_selection)), refresh: refresh);
      if (!mounted) return;
      final data = Map<String, dynamic>.from(result['data']);
      setState(() {
        _apply(data);
        _rememberSelectors(data);
        _prefillViffs();
        if (initial && _task == 'viffs') _initialPeriodDefaults();
        _message = _portalMessage(result, data); _messageError = false;
      });
      // Use the reporting period captured at the start of this request.
      if (_task == 'ranking' && data['selection']['${prefix}ddlMonth1'] == '${previous.month}' &&
          data['selection']['${prefix}ddlyear'] == '${previous.year}') {
        widget.onStatus?.call(_task, data['completed'] as bool?);
      }
    } catch (e) {
      if (mounted) setState(() { _message = e.toString(); _messageError = true; _selectionChanged = true; });
    } finally { if (mounted) setState(() => _loading = false); }
  }
  bool get _hasChanges {
    for (final section in maps(_data?['sections'])) {
      for (final field in maps(section['fields'])) {
        final id = field['id'].toString();
        final value = _choices[id] ?? _inputs[id]?.text;
        if (value != null && value != (field['value'] ?? '').toString()) return true;
      }
    }
    return false;
  }

  Future<bool> prepareTabSwitch() async => _loading && !_saving && !_reviewing ? true : !_busy && await _discard();

  Future<void> refreshForm() async {
    if (!_busy && await _discard()) await _load(refresh: true);
  }

  Future<bool> _discard() async {
    if (_busy) return false;
    final editing = _task == 'ranking' && _data?['editing'] == true;
    if (!_hasChanges && !editing) return true;
    var confirmed = true;
    if (_hasChanges) {
      setState(() => _reviewing = true);
      try {
        confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFFFAFAFC), surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Discard changes?', style: _text(17, FontWeight.w600)),
          content: Text('Your unsaved entries will be lost.', style: _text(14).copyWith(height: 1.45)),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          actions: [Row(children: [
            Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(backgroundColor: const Color(0xFFFAFAFC),
              foregroundColor: ink, side: const BorderSide(color: Color(0xFFE2E8F0)),
              minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
              onPressed: () => Navigator.pop(ctx, false), child: Text('Keep editing', maxLines: 1, softWrap: false, style: _text(13, FontWeight.w500)))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318),
              foregroundColor: Colors.white, minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
              onPressed: () => Navigator.pop(ctx, true), child: Text('Discard', maxLines: 1, style: _text(13, FontWeight.w500, Colors.white)))),
          ])],
        )) ?? false;
      } finally { if (mounted) setState(() => _reviewing = false); }
    }
    if (!confirmed || !mounted) return false;
    if (editing) {
      setState(() => _loading = true);
      try {
        // A fresh GET ends the native edit workflow and refreshes the cached
        // signed saved form; clearing only a local flag cannot discard Edit.
        final result = await MonthlyTaskService.fetch(widget.schoolId, _task, Map.of(_selection), refresh: true);
        if (!mounted) return false;
        final restored = Map<String, dynamic>.from(result['data']);
        if (restored['editing'] == true) throw const MonthlyTaskException('The portal editing session could not be closed.');
        setState(() { _apply(restored); _message = null; _messageError = false; });
      } catch (e) {
        if (mounted) setState(() { _message = e.toString(); _messageError = true; });
        return false;
      } finally { if (mounted) setState(() => _loading = false); }
    } else {
      final restored = Map<String, dynamic>.from(_data!);
      setState(() { _apply(restored); _message = null; _messageError = false; });
    }
    return true;
  }
  Widget _periodRow() => Row(children: [
    SizedBox(width: 17, height: 17, child: Image.asset('assets/icons/leave.png', fit: BoxFit.contain)),
    const SizedBox(width: 8), Expanded(child: Text(_periodLabel, style: _text(14, FontWeight.w500))),
  ]);
  Future<void> _savedPopup() async {
    await showDialog<void>(context: context, builder: (ctx) => Dialog(
      backgroundColor: const Color(0xFFFAFAFC), surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: Padding(
        padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFE7F7EE), borderRadius: BorderRadius.circular(12)),
            child: const Icon(CupertinoIcons.checkmark_alt, color: Color(0xFF15803D), size: 22)),
            const SizedBox(width: 12), Expanded(child: Text('Data saved successfully', style: _text(15, FontWeight.w600)))]),
          const SizedBox(height: 16), _periodRow(), const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.black,
            foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
            onPressed: () => Navigator.pop(ctx), child: Text('Done', style: _text(14, FontWeight.w500, Colors.white)))),
        ]))),
    ));
  }

  void _noChangesWarning() {
    if (!mounted) return;
    setState(() { _message = null; _messageError = false; _selectionChanged = false; _uncertain = false; });
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(duration: const Duration(seconds: 3), behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFFFAFAFC), elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0))),
      content: Row(children: [const Icon(CupertinoIcons.exclamationmark_triangle, size: 19, color: Color(0xFF8A6B32)),
        const SizedBox(width: 10), Expanded(child: Text('No changes to submit.', style: _text(13)))])));
  }
  Future<void> _submit() async {
    if (_busy || _selectionChanged || _uncertain || _data?['can_submit'] != true) return;
    _fieldErrors.clear();
    for (final section in maps(_data!['sections'])) {
      for (final field in maps(section['fields'])) {
        final id = field['id'].toString();
        final required = field['required'] == true;
        if (required && field['readonly'] != true && (_inputs[id]?.text.trim() ?? _choices[id] ?? '').isEmpty) {
          _fieldErrors[id] = _portalFieldWarning((field['required_message'] ?? '').toString());
        }
      }
    }
    _fieldErrors.addAll(_entryErrors());
    if (_fieldErrors.isNotEmpty) {
      setState(() { _showAllGroups = true; _message = null; });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = _fieldKeys[_fieldErrors.keys.first]?.currentContext;
        if (target != null) Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 240), alignment: 0.25);
      });
      return;
    }
    if (!_formKey.currentState!.validate()) {
      setState(() => _showAllGroups = true);
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _formKey.currentState?.validate(); });
      return;
    }
    if (_rankingDraftMatchesSaved) { _noChangesWarning(); return; }
    final values = <String, String>{};
    final review = <Widget>[];
    for (final section in maps(_data!['sections'])) {
      review.add(Padding(padding: const EdgeInsets.only(top: 12), child: Text(section['title'].toString(), style: const TextStyle(fontWeight: FontWeight.w600))));
      for (final f in maps(section['fields'])) {
        if (f['readonly'] == true) continue;
        final id = f['id'].toString(), options = maps(f['options']);
        final value = options.isEmpty ? _inputs[id]!.text.trim() : (_choices[id] ?? '');
        values[id] = value;
        final labels = options.where((o) => o['value'] == value).map((o) => o['label'].toString()).toList();
        final display = labels.isEmpty ? null : labels.first;
        review.add(Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text('${f['label']}\n${display ?? (value.isEmpty ? '—' : value)}', style: _text(14).copyWith(height: 1.5))));
      }
    }
    setState(() => _reviewing = true);
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('Review monthly entry', style: _text(18, FontWeight.w600)),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, children: [_periodRow(), ...review]))),
      actions: [TextButton(style: TextButton.styleFrom(foregroundColor: ink), onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: ink, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))), onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit'))],
    )) ?? false;
    if (mounted) setState(() => _reviewing = false);
    if (!confirmed || !mounted) return;
    setState(() { _saving = true; _message = null; });
    try {
      final result = await MonthlyTaskService.submit(widget.schoolId, _task, Map.of(_selection), _data!['snapshot'].toString(), values, editing: _data?['editing'] == true);
      if (!mounted) return;
      setState(() {
        _apply(Map<String, dynamic>.from(result['data']));
        final portalMessage = _portalMessage(result, _data!);
        _message = result['verified'] == true && portalMessage.trim().isEmpty ? 'Data saved successfully' : portalMessage;
        _messageError = false;
      });
      if (result['verified'] == true) await _savedPopup();
      if (!mounted) return;
      final prev = DateTime(DateTime.now().year, DateTime.now().month, 0);
      if (_task == 'ranking' && _selection['${prefix}ddlMonth1'] == '${prev.month}' && _selection['${prefix}ddlyear'] == '${prev.year}') {
        widget.onStatus?.call(_task, _data!['completed'] as bool?);
      }
    } catch (e) {
      if (mounted) setState(() {
        _message = e.toString(); _messageError = true;
        _uncertain = e is MonthlyTaskException && e.submissionUnknown;
        if (e is MonthlyTaskException && e.savedForm != null) {
          _apply(e.savedForm!);
          if (e.fieldErrors.isNotEmpty && _data?['can_submit'] == true) {
            for (final entry in values.entries) {
              if (_inputs.containsKey(entry.key)) _inputs[entry.key]!.text = entry.value;
              else if (_choices.containsKey(entry.key)) _choices[entry.key] = entry.value;
            }
            _edited = _hasChanges;
          }
        } else {
          // An unknown result still needs an explicit read; never repeat the write.
          _selectionChanged = _uncertain;
        }
        if (e is MonthlyTaskException && e.fieldErrors.isNotEmpty) {
          _fieldErrors.addAll(e.fieldErrors.map((id, message) => MapEntry(id, _portalFieldWarning(message))));
          _showAllGroups = true;
          _message = null;
        }
      });
      if (mounted && e.toString() == 'No changes to submit.') _noChangesWarning();
      if (mounted && e is MonthlyTaskException && e.savedForm != null && e.fieldErrors.isEmpty) {
        setState(() { _message = null; _messageError = false; });
        await _portalRejectionPopup(e.message);
      }
      if (mounted && _fieldErrors.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _fieldErrors.isEmpty) return;
          final target = _fieldKeys[_fieldErrors.keys.first]?.currentContext;
          if (target != null) Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 240), alignment: 0.25);
        });
      }
    } finally { if (mounted) setState(() => _saving = false); }
  }
  Widget _warningSymbol() => Container(
    width: 34, height: 34,
    decoration: BoxDecoration(color: const Color(0xFFF7F2E8), borderRadius: BorderRadius.circular(11)),
    alignment: Alignment.center,
    child: const Icon(CupertinoIcons.exclamationmark_circle_fill, size: 21, color: Color(0xFF9B783E)),
  );

  Future<void> _portalRejectionPopup(String message) async {
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFFFAFAFC), surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 420),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _warningSymbol(),
          const SizedBox(width: 10),
          Expanded(child: Text('Portal message', style: _text(15, FontWeight.w600))),
        ]),
        const SizedBox(height: 14),
        Text(message, style: _text(14, FontWeight.w400)),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: ink, foregroundColor: Colors.white,
            elevation: 0, minimumSize: const Size(0, 44), textStyle: _text(14, FontWeight.w600, Colors.white),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () => Navigator.pop(ctx), child: const Text('OK'))),
      ])),
    ));
  }


  String _portalMessage(Map<String, dynamic> response, Map<String, dynamic> data) {
    final message = response['message']?.toString() ?? '';
    return message.isNotEmpty ? message : (data['message']?.toString() ?? '');
  }

  // User-requested Hindi wording for the local required-field warning.
  // Authentic portal response messages remain unchanged.
  String _portalFieldWarning(String message) {
    if (message.trim() == 'Sports participation is required') return 'कृप्या खेल गतिविधि की प्रविष्ठी करें';
    if (message.trim() == 'This field is required') return '';
    return message;
  }



  InputDecoration decoration({String? hint}) => InputDecoration(hintText: hint,
    hintStyle: _text(12, FontWeight.w400, muted), filled: true,
    fillColor: const Color(0xFFF3F5F7), isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF94A3B8))),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: ink)),
    errorStyle: _text(10.5, FontWeight.w400, muted),
  );

  Widget _field(Map<String, dynamic> f, {bool selector = false, bool showLabel = true}) {
    final id = f['id'].toString(), options = maps(f['options']);
    final isDate = f['date'] == true || (_task == 'ranking' && id.endsWith('TextBox1'));
    final disabled = _busy || f['readonly'] == true || (!selector && (_selectionChanged || _data?['can_submit'] != true));
    if (selector && options.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(f['label'].toString(), style: _text(12, FontWeight.w500, muted)),
        const SizedBox(height: 7),
        Container(height: 42, padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color(0xFFF3F5F7), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [Expanded(child: Text('—', style: _text(12, FontWeight.w400, muted))),
            const Icon(CupertinoIcons.chevron_down, size: 13, color: muted)])),
      ]);
    }
    Widget input;
    if (options.isNotEmpty) {
      final current = selector ? _selection[id] : _choices[id];
      input = DropdownButtonFormField<String>(key: ValueKey('$id:$_revision:$current'),
        value: options.any((o) => o['value'] == current) ? current : null, isExpanded: true,
        style: _text(12), dropdownColor: Colors.white, borderRadius: BorderRadius.circular(12),
        icon: const Icon(CupertinoIcons.chevron_down, size: 13, color: muted),
        decoration: decoration(), items: options.map((o) => DropdownMenuItem<String>(value: o['value'].toString(),
          child: Text(o['label'].toString(), overflow: TextOverflow.ellipsis))).toList(),
        onChanged: disabled ? null : (v) async {
          if (v == null) return;
          if (selector && !await _discard()) return;
          if (!mounted) return;
          setState(() {
            if (selector) { _selection[id] = v; _selectionChanged = true; _edited = false; }
            else { _choices[id] = v; _fieldErrors.remove(id); _edited = _hasChanges; }
          });
          if (selector && id == '${prefix}ddlStudentType') {
            _selection.remove('${prefix}ddlmonth'); _selection.remove('${prefix}ddlClass');
            await _load();
          }
        }, validator: (v) => v == null || v.isEmpty || v == '0' ? 'Select an option' : null);
    } else {
      input = TextFormField(cursorColor: ink, style: const TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 14, color: ink), controller: _inputs[id], enabled: !disabled,
        readOnly: isDate, maxLength: (f['maxlength'] as int? ?? 0) > 0 ? f['maxlength'] as int : null,
        keyboardType: f['numeric'] == true ? TextInputType.number : TextInputType.text,
        inputFormatters: f['numeric'] == true ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: decoration(hint: isDate ? 'DD-MM-YYYY' : 'Enter count').copyWith(counterText: '',
          enabledBorder: _fieldErrors.containsKey(id) ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDC2626))) : null,
          focusedBorder: _fieldErrors.containsKey(id) ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.2)) : null,
          suffixIcon: isDate ? Center(widthFactor: 1, heightFactor: 1, child: SizedBox(width: 16, height: 16, child: Image.asset('assets/icons/leave.png', fit: BoxFit.contain))) : null),
        onChanged: (_) => setState(() { _fieldErrors.remove(id); _edited = _hasChanges; }),
        onTap: !isDate ? null : () async {
          final now = DateUtils.dateOnly(DateTime.now());
          final raw = _inputs[id]?.text ?? '';
          final parts = raw.split('-');
          var initial = now;
          if (parts.length == 3) {
            final day = int.tryParse(parts[0]), month = int.tryParse(parts[1]), year = int.tryParse(parts[2]);
            if (day != null && month != null && year != null) {
              final candidate = DateTime(year, month, day);
              if (!candidate.isBefore(DateTime(2024)) && !candidate.isAfter(now)) initial = candidate;
            }
          }
          final chosen = await showPortalCalendar(context, initial, DateTime(2024), now);
          if (chosen != null && mounted) setState(() {
            _inputs[id]!.text = '${chosen.day.toString().padLeft(2, '0')}-${chosen.month.toString().padLeft(2, '0')}-${chosen.year}'; _fieldErrors.remove(id); _edited = _hasChanges;
          });
        },
        validator: (v) => f['numeric'] == true && (v ?? '').isNotEmpty && !RegExp(r'^\d+$').hasMatch(v!) ? 'Enter a whole number' : null);
    }
    if (!selector && f['readonly'] == true) {
      final value = options.isEmpty ? (_inputs[id]?.text ?? '') : options.where((o) => o['value'] == _choices[id]).map((o) => o['label'].toString()).join();
      if (!showLabel) return Container(
        width: double.infinity, constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: const Color(0xFFF7F9FB), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE8EDF2))),
        alignment: Alignment.centerRight,
        child: SelectableText(value.isEmpty ? '—' : value, textAlign: TextAlign.right,
          style: _text(15, FontWeight.w500).copyWith(height: 1.35)));

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(f['label'].toString(), style: const TextStyle(fontSize: 11, color: muted)),
        const SizedBox(height: 8), SelectableText(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ]);
    }
    input = Column(key: _fieldKeys.putIfAbsent(id, () => GlobalKey()), crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if ((_fieldErrors[id] ?? '').trim().isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_fieldErrors[id]!, style: _text(12, FontWeight.w400, const Color(0xFFDC2626)))),
      input,
    ]);
    if (!showLabel) return input;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(f['label'].toString(), style: const TextStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w500, color: ink)),
      const SizedBox(height: 7), input,
    ]);
  }
  Widget _sectionsView() => Column(children: [
    for (final section in maps(_data?['sections'])) _sectionForm(section),
  ]);

  Widget _reportingPeriod() => _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Reporting period', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), const SizedBox(height: 12),
                  LayoutBuilder(builder: (context, constraints) {
                    final fields = _periodFields;
                    final columns = constraints.maxWidth >= 650 ? fields.length.clamp(1, 3) : constraints.maxWidth >= 280 ? 2 : 1;
                    return Wrap(spacing: 12, runSpacing: 14, children: fields.map((field) => SizedBox(width: (constraints.maxWidth - (columns - 1) * 12) / columns,
                      child: _field(field, selector: true))).toList());
                  }),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: ink, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
                    onPressed: _busy || _periodFields.any((f) => maps(f['options']).isEmpty) ? null : () async {
                      if (_periodFields.any((f) => (_selection[f['id']] ?? '0') == '0')) {
                        _formKey.currentState?.validate(); return;
                      }
                      if (await _discard()) _load(refresh: _uncertain || _messageError || _data?['editing'] == true);
                    }, child: _task == 'viffs' && _loading && _data == null
                        ? SizedBox(width: 18, height: 18, child: Lottie.asset('assets/icons/Loading (Buffering).json', errorBuilder: (_, __, ___) => const CupertinoActivityIndicator(radius: 7)))
                        : const Text('Show', style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 12, fontWeight: FontWeight.w600)))),
                ]));

  Widget _card(Widget child) => Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE2E8F0).withValues(alpha: 0.65)),
      boxShadow: [BoxShadow(color: ink.withValues(alpha: 0.025), blurRadius: 18, offset: const Offset(0, 5))]), child: child);



  IconData _rankingIcon(String id) {
    if (id.endsWith('txtaward')) return Icons.emoji_events_outlined;
    if (id.endsWith('txtlibbooks')) return CupertinoIcons.book;
    if (id.endsWith('txtsports')) return Icons.sports_basketball_outlined;
    return CupertinoIcons.calendar;
  }







  String get _periodLabel {
    return _periodFields.map((f) {
      final selected = _selection[f['id']];
      final options = maps(f['options']).where((o) => o['value'].toString() == selected);
      return options.isEmpty ? '' : options.first['label'].toString();
    }).where((v) => v.isNotEmpty).join(' · ');
  }



  Widget _initialForm() => _card(Row(children: [
    SizedBox(width: 25, height: 25, child: Lottie.asset('assets/icons/Loading (Buffering).json',
      errorBuilder: (_, __, ___) => const CupertinoActivityIndicator(radius: 8))),
    const SizedBox(width: 10), Expanded(child: Text('Loading portal form…', style: _text(12, FontWeight.w400, muted))),
  ]));




  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.active || (!_busy && !_hasChanges && _data?['editing'] != true),
    onPopInvokedWithResult: (didPop, result) async {
      if (widget.active && !didPop && !_busy && await _discard() && context.mounted) {
        await WidgetsBinding.instance.endOfFrame;
        if (context.mounted) Navigator.of(context).pop();
      }
    },
    child: Theme(data: Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(fontFamily: 'PlusJakartaSans'),
      colorScheme: Theme.of(context).colorScheme.copyWith(primary: ink, secondary: ink, surface: Colors.white),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: ink, selectionColor: Color(0xFFCBD5E1), selectionHandleColor: ink),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: ink, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)))),
    ), child: Scaffold(backgroundColor: const Color(0xFFF8FAFC),
      appBar: widget.embedded ? null : AppBar(backgroundColor: const Color(0xFFF8FAFC), surfaceTintColor: Colors.transparent,
        title: Text(_task == 'ranking' ? 'District Ranking' : 'VIFFS Tablet Entry', style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 16, fontWeight: FontWeight.w500)),
        actions: [IconButton(tooltip: 'Read latest portal form', onPressed: _busy ? null : () async { if (await _discard()) _load(refresh: true); }, icon: const Icon(CupertinoIcons.arrow_clockwise, size: 18))]),
      body: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        stops: [0, .45, 1], colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9), Color(0xFFFEF3C7)])),
        child: PageContentMotion(child: SizedBox.expand(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: AppAdaptive.contentWidth(MediaQuery.sizeOf(context).width) - 32),
            child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: _task == 'ranking' ? const Icon(Icons.leaderboard_outlined, size: 21, color: ink)
                    : Padding(padding: const EdgeInsets.all(9), child: Image.asset('assets/icons/viffs.png', fit: BoxFit.contain))),
                const SizedBox(width: 11),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_task == 'ranking' ? 'District Ranking' : 'VIFFS tablet entry', style: _text(17, FontWeight.w600)),
                  const SizedBox(height: 3), Text('School NIC : ${widget.schoolId}', style: _text(11, FontWeight.w400, muted)),
                ])),
              ]), const SizedBox(height: 14),
              _periodStatus(),
              if (!widget.embedded && _task == 'ranking') Align(alignment: Alignment.centerRight, child: TextButton(
                onPressed: _busy ? null : () async {
                  if (!await _discard() || !mounted) return;
                  setState(() {
                    if (_showPeriodPicker && _data != null && _selectionChanged) {
                      _selection.clear();
                      for (final e in Map<String, dynamic>.from(_data!['selection'] as Map).entries) {
                        _selection[e.key] = e.value.toString();
                      }
                      _selectionChanged = false;
                    }
                    _showPeriodPicker = !_showPeriodPicker;
                  });
                },
                child: Text(_showPeriodPicker ? 'Hide period' : 'Change period', style: _text(12, FontWeight.w500, muted)))),
              if (_showPeriodPicker) _reportingPeriod(),
              if (_task == 'ranking' && _data == null && _loading) _initialForm(),
              if ((_loading || _saving) && _rankingOperation == null && _data != null) _card(Row(children: [
                SizedBox(width: 28, height: 28, child: Lottie.asset('assets/icons/Loading (Buffering).json',
                  errorBuilder: (context, error, stack) => const CupertinoActivityIndicator(radius: 9))),
                const SizedBox(width: 12), Expanded(child: Text(_saving ? 'Verifying submission…' : 'Reading portal form…', style: const TextStyle(fontSize: 12, color: muted))),
              ])),
              if (_message?.isNotEmpty == true) _card(Semantics(liveRegion: true,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(_messageError ? CupertinoIcons.exclamationmark_triangle : _message == 'Data saved successfully' ? CupertinoIcons.checkmark_circle : CupertinoIcons.info_circle, size: 20, color: _messageError ? const Color(0xFFB7791F) : ink),
                  const SizedBox(width: 12), Expanded(child: SelectableText(_message!, style: _text(14, FontWeight.w400).copyWith(height: 1.5))),
                ]))),
              if (_data == null && !_loading && _messageError)
                Align(alignment: Alignment.centerRight, child: FilledButton.icon(
                  onPressed: _busy ? null : () => _load(initial: true),
                  icon: const Icon(CupertinoIcons.arrow_clockwise, size: 15),
                  label: const Text('Retry', style: TextStyle(fontSize: 12)))),
              if (_data != null) ...[
                if (_selectionChanged && _task == 'ranking') const Padding(padding: EdgeInsets.only(bottom: 16), child: Text('Press Show to read the selected period.', style: TextStyle(fontSize: 12, color: muted))),
                ...[
                  if (_data!['note'] != null && (_task != 'viffs' || maps(_data!['sections']).isNotEmpty)) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(_data!['note'].toString(), style: const TextStyle(fontSize: 11.5, height: 1.5, color: muted))),
                  if (_task == 'viffs' && _prefilledViffs)
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(
                      'Draft: full student count is filled for 4+ tablets in empty rows. Adjust actual consumption before submitting.',
                      style: _text(11, FontWeight.w400, muted))),
                  if (!_selectionChanged) _sectionsView(),
                  if (_task == 'ranking' && _data!['editing'] != true &&
                      (_data!['can_edit'] == true || _data!['can_delete'] == true))
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
                      if (_data!['can_edit'] == true) Expanded(child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: ink, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0)))),
                        onPressed: _busy || _uncertain || _selectionChanged ? null : () => _rankingAction('edit'),
                        child: _rankingOperation == 'edit' ? SizedBox(width: 20, height: 20, child: Lottie.asset('assets/icons/Loading (Buffering).json', errorBuilder: (_, __, ___) => const CupertinoActivityIndicator(radius: 8))) : const Text('Edit'))),
                      if (_data!['can_edit'] == true && _data!['can_delete'] == true) const SizedBox(width: 10),
                      if (_data!['can_delete'] == true) Expanded(child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: _busy || _uncertain || _selectionChanged ? null : () => _rankingAction('delete'),
                        child: _rankingOperation == 'delete' ? const CupertinoActivityIndicator(radius: 8, color: Colors.white) : const Text('Delete'))),
                    ])),
                  if (_task == 'ranking' && _data!['can_submit'] == true)
                    SizedBox(width: double.infinity, child: FilledButton.icon(
                      onPressed: _busy || _uncertain || _selectionChanged ? null : _submit,
                      style: FilledButton.styleFrom(backgroundColor: ink, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
                      icon: const Icon(CupertinoIcons.doc_text_search, size: 17),
                      label: Text(_data!['editing'] == true ? 'Review & update' : 'Review & submit', style: _text(12.5, FontWeight.w600, Colors.white)),
                    )),
                  if (_task != 'ranking' && _task != 'viffs' && _data!['can_submit'] == true && !_selectionChanged) _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Review your entry', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), const SizedBox(height: 6),
                    Text(_task == 'viffs' ? 'Submit saves all classes. Final Lock stays a separate reviewed action.' : 'Check the period and values before sending to the portal.', style: const TextStyle(fontSize: 11.5, color: muted)),
                    const SizedBox(height: 16), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy || _uncertain || _selectionChanged ? null : _submit,
                      icon: const Icon(CupertinoIcons.doc_text_search, size: 17), label: const Text('Review & submit', style: TextStyle(fontSize: 12)))),
                  ])),
                  if (_task == 'viffs' && _showFinalActions && _data!['can_lock'] == true) Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed: _busy || _edited || _uncertain ? null : _lock,
                    icon: const Icon(CupertinoIcons.lock, size: 16), label: const Text('Review & Lock', style: TextStyle(fontSize: 12)))),
                  if (_task == 'viffs' && _showFinalActions && _edited && _data!['can_lock'] == true) const Text('Submit your changes before Lock.', style: TextStyle(fontSize: 11, color: muted)),
                ],
              ],
            ])),
          )),
        ))),
      ),
    )),
  );
}
