import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shaladarpan/services/portals/shaladarpan/monthly_task_service.dart';

class MonthlyTasksScreen extends StatefulWidget {
  final String schoolId, initialTask;
  final void Function(String task, bool? completed)? onStatus;
  const MonthlyTasksScreen({super.key, required this.schoolId, this.initialTask = 'ranking', this.onStatus});
  @override
  State<MonthlyTasksScreen> createState() => _MonthlyTasksScreenState();
}

class _MonthlyTasksScreenState extends State<MonthlyTasksScreen> {
  static const ink = Color(0xFF0F172A), muted = Color(0xFF64748B);
  static const prefix = 'ContentPlaceHolder1_';
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _inputs = {};
  final Map<String, String> _selection = {}, _choices = {};
  Map<String, dynamic>? _data;
  late String _task;
  bool _reviewing = false, _loading = false, _saving = false, _selectionChanged = false, _edited = false, _uncertain = false;
  String? _message;
  bool _messageError = false;
  int _revision = 0;
  bool get _busy => _loading || _saving || _reviewing;
  List<Map<String, dynamic>> maps(dynamic data) => data is List ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  @override
  void initState() { super.initState(); _task = widget.initialTask == 'viffs' ? 'viffs' : 'ranking'; _load(initial: true); }
  @override
  void dispose() { for (final c in _inputs.values) { c.dispose(); } super.dispose(); }
  void _apply(Map<String, dynamic> data) {
    for (final c in _inputs.values) { c.dispose(); }
    _inputs.clear(); _choices.clear(); _selection.clear();
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
    _revision++; _edited = false; _selectionChanged = false; _uncertain = false;
  }
  Future<void> _load({bool initial = false}) async {
    if (_busy) return;
    setState(() { _loading = true; _message = null; });
    try {
      final result = await MonthlyTaskService.fetch(widget.schoolId, _task, initial ? {} : Map.of(_selection));
      if (!mounted) return;
      final data = Map<String, dynamic>.from(result['data']);
      setState(() {
        _apply(data);
        if (initial) {
          final now = DateTime.now();
          final previous = DateTime(now.year, now.month, 0);
          final defaults = _task == 'ranking'
            ? {'${prefix}ddlMonth1': '${previous.month}', '${prefix}ddlyear': '${previous.year}'}
            : {'${prefix}ddlmonth': '${previous.month}'};
          for (final f in maps(data['selectors'])) {
            final id = f['id'].toString(), wanted = defaults[f['id']];
            if (wanted != null && maps(f['options']).any((o) => o['value'] == wanted) && _selection[id] != wanted) {
              _selection[id] = wanted; _selectionChanged = true;
            }
          }
        }
        _message = (data['message'] ?? '').toString(); _messageError = false;
      });
      // Completion belongs to a period; do not mark another month's dashboard.
      final previous = DateTime(DateTime.now().year, DateTime.now().month, 0);
      if (_task == 'ranking' && data['selection']['${prefix}ddlMonth1'] == '${previous.month}' &&
          data['selection']['${prefix}ddlyear'] == '${previous.year}') {
        widget.onStatus?.call(_task, data['completed'] as bool?);
      }
    } catch (e) {
      if (mounted) setState(() { _message = e.toString(); _messageError = true; _selectionChanged = true; });
    } finally { if (mounted) setState(() => _loading = false); }
  }
  Future<bool> _discard() async {
    if (!_edited) return true;
    return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Discard changes?'), content: const Text('Your unsaved entries will be lost.'), actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
      ])) ?? false;
  }
  Future<void> _switch(String value) async {
    if (_busy || value == _task || !await _discard() || !mounted) return;
    setState(() { _task = value; _data = null; _edited = false; });
    await _load(initial: true);
  }
  Future<void> _submit() async {
    if (_busy || _selectionChanged || _uncertain || _data?['can_submit'] != true || !_formKey.currentState!.validate()) return;
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
        review.add(Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text('${f['label']}\n${display ?? (value.isEmpty ? '—' : value)}', style: const TextStyle(fontSize: 12))));
      }
    }
    setState(() => _reviewing = true);
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Review monthly entry'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, children: [Text(_selection.values.join(' · ')), ...review]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit'))],
    )) ?? false;
    if (mounted) setState(() => _reviewing = false);
    if (!confirmed || !mounted) return;
    setState(() { _saving = true; _message = null; });
    try {
      final result = await MonthlyTaskService.submit(widget.schoolId, _task, Map.of(_selection), _data!['snapshot'].toString(), values);
      if (!mounted) return;
      setState(() {
        _apply(Map<String, dynamic>.from(result['data']));
        final portalMessage = (result['message'] ?? '').toString();
        _message = portalMessage.isNotEmpty ? portalMessage : 'Saved values verified on the portal.';
        _messageError = false;
      });
      final prev = DateTime(DateTime.now().year, DateTime.now().month, 0);
      if (_task == 'ranking' && _selection['${prefix}ddlMonth1'] == '${prev.month}' && _selection['${prefix}ddlyear'] == '${prev.year}') {
        widget.onStatus?.call(_task, _data!['completed'] as bool?);
      }
    } catch (e) {
      if (mounted) setState(() {
        _message = e.toString(); _messageError = true;
        _uncertain = e is MonthlyTaskException && e.submissionUnknown;
        // Force a read after any rejection; never silently replay a mutation.
        _selectionChanged = true;
      });
    } finally { if (mounted) setState(() => _saving = false); }
  }
  Future<void> _lock() async {
    if (_busy || _edited || _selectionChanged || _uncertain || _data?['can_lock'] != true) return;
    final review = <Widget>[];
    for (final field in maps(_data!['selectors'])) {
      final options = maps(field['options']).where((o) => o['value'] == _selection[field['id']]).toList();
      review.add(Text('${field['label']}: ${options.isEmpty ? field['value'] : options.first['label']}'));
    }
    for (final section in maps(_data!['sections'])) {
      review.add(Padding(padding: const EdgeInsets.only(top: 12), child: Text(section['title'].toString(), style: const TextStyle(fontWeight: FontWeight.w600))));
      for (final field in maps(section['fields'])) {
        final options = maps(field['options']).where((o) => o['value'] == field['value']).toList();
        review.add(Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(
          '${field['label']}: ${options.isEmpty ? field['value'] : options.first['label']}', style: const TextStyle(fontSize: 12))));
      }
    }
    setState(() => _reviewing = true);
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Review saved VIFFS entry'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('कृपया सूचना को लॉक करने से पूर्व एक बार चेक कर ले अन्यथा लॉक करने के बाद बदलाव संभव नहीं होगा'),
          const SizedBox(height: 12), ...review]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm Lock'))],
    )) ?? false;
    if (mounted) setState(() => _reviewing = false);
    if (!confirmed || !mounted) return;
    setState(() { _saving = true; _message = null; });
    try {
      final result = await MonthlyTaskService.lock(widget.schoolId, Map.of(_selection), _data!['snapshot'].toString());
      if (!mounted) return;
      setState(() {
        _apply(Map<String, dynamic>.from(result['data']));
        _message = result['message'].toString(); _messageError = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _message = e.toString(); _messageError = true;
        _uncertain = e is MonthlyTaskException && e.submissionUnknown;
        _selectionChanged = true;
      });
    } finally { if (mounted) setState(() => _saving = false); }
  }
  InputDecoration decoration({String? hint}) => InputDecoration(hintText: hint, filled: true,
    fillColor: const Color(0xFFF8FAFC), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE2E8F0))));
  Widget _field(Map<String, dynamic> f, {bool selector = false}) {
    final id = f['id'].toString(), options = maps(f['options']);
    final disabled = _busy || f['readonly'] == true || (!selector && (_selectionChanged || _data?['can_submit'] != true));
    Widget input;
    if (options.isNotEmpty) {
      final current = selector ? _selection[id] : _choices[id];
      input = DropdownButtonFormField<String>(key: ValueKey('$id:$_revision:$current'),
        value: options.any((o) => o['value'] == current) ? current : null, isExpanded: true,
        decoration: decoration(), items: options.map((o) => DropdownMenuItem<String>(value: o['value'].toString(),
          child: Text(o['label'].toString(), overflow: TextOverflow.ellipsis))).toList(),
        onChanged: disabled ? null : (v) async {
          if (v == null) return;
          if (selector && !await _discard()) return;
          if (!mounted) return;
          setState(() {
            if (selector) { _selection[id] = v; _selectionChanged = true; _edited = false; }
            else { _choices[id] = v; _edited = true; }
          });
          if (selector && id == '${prefix}ddlStudentType') {
            _selection.remove('${prefix}ddlmonth'); _selection.remove('${prefix}ddlClass');
            await _load();
          }
        }, validator: (v) => v == null || v.isEmpty || v == '0' ? 'Select an option' : null);
    } else {
      input = TextFormField(controller: _inputs[id], enabled: !disabled,
        readOnly: f['date'] == true, maxLength: (f['maxlength'] as int? ?? 0) > 0 ? f['maxlength'] as int : null,
        keyboardType: f['numeric'] == true ? TextInputType.number : TextInputType.text,
        inputFormatters: f['numeric'] == true ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: decoration(hint: f['date'] == true ? 'DD-MM-YYYY' : null).copyWith(counterText: '',
          suffixIcon: f['date'] == true ? const Icon(CupertinoIcons.calendar, size: 18) : null),
        onChanged: (_) => setState(() => _edited = true),
        onTap: f['date'] != true ? null : () async {
          final now = DateUtils.dateOnly(DateTime.now());
          final chosen = await showDatePicker(context: context, initialDate: now, firstDate: DateTime(2024), lastDate: now);
          if (chosen != null && mounted) setState(() {
            _inputs[id]!.text = '${chosen.day.toString().padLeft(2, '0')}-${chosen.month.toString().padLeft(2, '0')}-${chosen.year}'; _edited = true;
          });
        },
        validator: (v) => f['numeric'] == true && (v ?? '').isNotEmpty && !RegExp(r'^\d+$').hasMatch(v!) ? 'Enter a whole number' : null);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(f['label'].toString(), style: const TextStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w500, color: ink)),
      const SizedBox(height: 7), input,
    ]);
  }
  Widget _card(Widget child) => Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE2E8F0))), child: child);
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && !_edited,
    onPopInvokedWithResult: (didPop, result) async {
      if (!didPop && !_saving && await _discard() && context.mounted) {
        setState(() => _edited = false); Navigator.of(context).pop();
      }
    },
    child: Theme(data: Theme.of(context).copyWith(textTheme: Theme.of(context).textTheme.apply(fontFamily: 'PlusJakartaSans')),
      child: Scaffold(backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(backgroundColor: const Color(0xFFF8FAFC), surfaceTintColor: Colors.transparent,
          title: const Text('Monthly Tasks', style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 18, fontWeight: FontWeight.w600)),
          actions: [IconButton(tooltip: 'Refresh', onPressed: _busy ? null : () async { if (await _discard()) _load(); }, icon: const Icon(CupertinoIcons.arrow_clockwise, size: 19))]),
        body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Form(key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: double.infinity, child: CupertinoSlidingSegmentedControl<String>(groupValue: _task,
              children: const {'ranking': Padding(padding: EdgeInsets.all(10), child: Text('District Ranking')),
                'viffs': Padding(padding: EdgeInsets.all(10), child: Text('VIFFS'))},
              onValueChanged: (String? value) {
                if (_busy || value == null) return;
                _switch(value);
              })),
            const SizedBox(height: 16),
            if (_loading || _saving) Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Row(children: [
              const CupertinoActivityIndicator(radius: 9), const SizedBox(width: 10),
              Text(_saving ? 'Verifying submission…' : 'Reading portal form…', style: const TextStyle(fontSize: 12, color: muted))])),
            if (_message?.isNotEmpty == true) _card(Semantics(liveRegion: true, child: Text(_message!,
              style: TextStyle(fontSize: 12, height: 1.5, color: _messageError ? const Color(0xFFB91C1C) : ink)))),
            if (_data != null) ...[
              _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_data!['note'] != null) Padding(padding: const EdgeInsets.only(bottom: 14),
                  child: Text(_data!['note'].toString(), style: const TextStyle(fontSize: 12, height: 1.5, color: muted))),
                LayoutBuilder(builder: (context, c) {
                  final fields = maps(_data!['selectors']); final n = c.maxWidth >= 650 ? fields.length : 1;
                  return Wrap(spacing: 14, runSpacing: 14, children: fields.map((f) => SizedBox(width: (c.maxWidth - (n-1)*14)/n,
                    child: _field(f, selector: true))).toList());
                }), const SizedBox(height: 14),
                Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _busy ? null : () async {
                  if (maps(_data!['selectors']).any((f) => (_selection[f['id']] ?? '0') == '0')) {
                    setState(() { _message = 'Select the reporting period and tablet.'; _messageError = true; }); return;
                  }
                  if (await _discard()) _load();
                }, child: const Text('Show'))),
              ])),
              if (_selectionChanged) const Padding(padding: EdgeInsets.only(bottom: 16),
                child: Text('Press Show to read the selected period.', style: TextStyle(fontSize: 12, color: muted))),
              if (!_selectionChanged) ...[
                if (_data!['completed'] == true) Padding(padding: EdgeInsets.only(bottom: 14),
                  child: Text(_data!['locked'] == true ? 'Lock on : ${_data!["lock_date"]}' : 'Entry exists on the portal', style: TextStyle(fontSize: 12, color: Color(0xFF15803D)))),
                ...maps(_data!['sections']).map((section) => _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(section['title'].toString(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  if ((section['teacher'] ?? '').toString().isNotEmpty) Text(section['teacher'].toString(), style: const TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(height: 16),
                  LayoutBuilder(builder: (context, c) {
                    final cols = _task == 'viffs' && c.maxWidth >= 650 ? 2 : 1;
                    return Wrap(spacing: 16, runSpacing: 16, children: maps(section['fields']).map((f) => SizedBox(
                      width: (c.maxWidth - (cols-1)*16)/cols, child: _field(f))).toList());
                  }),
                ]))),
                if (_data!['can_submit'] == true) ...[
                  if (_task == 'viffs') const Padding(padding: EdgeInsets.only(bottom: 12), child: Text(
                    'Submit saves changes. Review the saved entry before final Lock.', style: TextStyle(fontSize: 12, color: muted))),
                  Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _busy || _uncertain ? null : _submit,
                    icon: const Icon(CupertinoIcons.checkmark_alt, size: 16), label: const Text('Review & Submit'))),
                ],
                if (_task == 'viffs' && _data!['can_lock'] == true) Padding(
                  padding: const EdgeInsets.only(top: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (_edited) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text(
                      'Submit your changes before Lock.', style: TextStyle(fontSize: 12, color: muted))),
                    OutlinedButton.icon(onPressed: _busy || _edited || _uncertain ? null : _lock,
                      icon: const Icon(CupertinoIcons.lock, size: 16), label: const Text('Review & Lock')),
                  ])),
              ],
            ],
            const SizedBox(height: 24),
          ]))),
      )),
  );
}
