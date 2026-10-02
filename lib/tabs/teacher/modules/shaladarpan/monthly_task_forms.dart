import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Values use the portal's control IDs. The caller supplies live dropdown
/// options and connects submission to its authenticated backend service.
typedef MonthlyFormAction = Future<void> Function(Map<String, String> values);
typedef MonthlyDatePicker = Future<DateTime?> Function(BuildContext context, DateTime? selected);

class DistrictRankingForm extends StatelessWidget {
  final Map<String, String> months, years, initialValues;
  final MonthlyFormAction? onSubmit;
  final MonthlyDatePicker? pickDate;
  final bool readOnly;
  const DistrictRankingForm({super.key, required this.months, required this.years,
    this.initialValues = const {}, this.onSubmit, this.pickDate, this.readOnly = false});

  @override
  Widget build(BuildContext context) => _MonthlyForm(
    title: 'District Ranking', subtitle: 'District Entry Data Ranking',
    actionLabel: 'Submit', onAction: onSubmit, pickDate: pickDate,
    readOnly: readOnly, initialValues: initialValues,
    fields: [
      _Field('ddlMonth1', 'Month', options: months),
      _Field('ddlyear', 'Year', options: years),
      const _Field('txtaward', 'गत सत्र में इंस्पायर्ड अवार्ड/STSE/NTSE/NMMS/गार्गी पुरूस्कार/इंदिरा प्रियदर्शनी/विज्ञान प्रदर्शनी/कला एवं संस्कृति उत्सव में भाग लेन वाले विद्यार्थियों की संख्या', numeric: true),
      const _Field('txtlibbooks', 'इस माह में कितने विद्यार्थियों को पुस्तकालय से पुस्तक वितरित की गई', numeric: true),
      const _Field('txtsports', 'इस सत्र में राष्ट्रिय/राज्य स्तरीय खेल गतिविधि में चयन होने वाले विद्यार्थियों की संख्या', numeric: true),
      const _Field('TextBox1', 'एसडीएमसी/एसएमसी बैठक आयोजित करने की दिनांक', date: true),
    ],
  );
}

/// Selection form only: the supplied VIFFS HTML contains no entry grid.
/// Reload portal month options after changing session via onSelectionChanged.
class ViffsSelectionForm extends StatelessWidget {
  final Map<String, String> sessions, tablets, months, initialValues;
  final MonthlyFormAction? onShow;
  final void Function(String field, String value)? onSelectionChanged;
  final bool readOnly;
  const ViffsSelectionForm({super.key, required this.sessions, required this.tablets,
    required this.months, this.initialValues = const {}, this.onShow,
    this.onSelectionChanged, this.readOnly = false});

  @override
  Widget build(BuildContext context) => _MonthlyForm(
    title: 'VIFFS Tablets', subtitle: 'विद्यालय मासिक सूचना प्रपत्र - विफ्स(पिंक और ब्ल्यू)',
    note: 'नोट :- सत्र का प्रारंभ मई माह से मानते हुए, इस प्रपत्र में एंट्रीज़ करनी है',
    actionLabel: 'Show', onAction: onShow, readOnly: readOnly,
    initialValues: initialValues, onSelectionChanged: onSelectionChanged,
    fields: [
      _Field('ddlStudentType', 'सत्र', options: sessions),
      _Field('ddlClass', 'गोली', options: tablets),
      _Field('ddlmonth', 'माह', options: months),
    ],
  );
}

class _Field {
  final String id, label;
  final Map<String, String>? options;
  final bool numeric, date, readOnly;
  const _Field(this.id, this.label, {this.options, this.numeric = false, this.date = false, this.readOnly = false});
}

class _MonthlyForm extends StatefulWidget {
  final String title, subtitle, actionLabel;
  final String? note;
  final List<_Field> fields;
  final Map<String, String> initialValues;
  final MonthlyFormAction? onAction;
  final MonthlyDatePicker? pickDate;
  final void Function(String field, String value)? onSelectionChanged;
  final bool readOnly;
  const _MonthlyForm({required this.title, required this.subtitle, required this.actionLabel,
    required this.fields, required this.initialValues, this.note, this.onAction,
    this.pickDate, this.onSelectionChanged, this.readOnly = false});
  @override
  State<_MonthlyForm> createState() => _MonthlyFormState();
}

class _MonthlyFormState extends State<_MonthlyForm> {
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _selected = {};
  bool _busy = false;
  String? _error;
  bool get _enabled => !_busy && !widget.readOnly;
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final value = widget.initialValues[f.id] ?? '';
      if (f.options != null) {
        if (f.options!.containsKey(value) && value != '0') _selected[f.id] = value;
      } else {
        _controllers[f.id] = TextEditingController(text: value);
      }
    }
  }
  @override
  void dispose() {
    for (final c in _controllers.values) { c.dispose(); }
    super.dispose();
  }
  Future<void> _act() async {
    if (!_enabled || widget.onAction == null || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    final values = <String, String>{};
    for (final f in widget.fields) {
      values[f.id] = f.options != null ? (_selected[f.id] ?? '') : _controllers[f.id]!.text.trim();
    }
    try {
      await widget.onAction!(Map.unmodifiable(values));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst(RegExp(r'^Exception: '), ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  InputDecoration _decoration() => InputDecoration(
    filled: true, fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _ink)),
  );
  Widget _input(_Field f) {
    final options = f.options;
    Widget control;
    if (options != null) {
      final validOptions = Map<String, String>.fromEntries(options.entries.where((e) => e.key.isNotEmpty && e.key != '0'));
      final selected = validOptions.containsKey(_selected[f.id]) ? _selected[f.id] : null;
      control = DropdownButtonFormField<String>(
        key: ValueKey('${f.id}:${validOptions.keys.join(',')}:$selected'),
        value: selected, isExpanded: true, decoration: _decoration(),
        hint: const Text('Select', style: TextStyle(fontSize: 12, color: _muted)),
        items: validOptions.entries.map((e) => DropdownMenuItem(value: e.key,
          child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: !_enabled ? null : (value) {
          if (value == null) return;
          setState(() {
            _selected[f.id] = value;
            if (f.id == 'ddlStudentType') _selected.remove('ddlmonth');
          });
          widget.onSelectionChanged?.call(f.id, value);
        },
        validator: (value) => value == null || !validOptions.containsKey(value) ? 'Please select ${f.label}' : null,
      );
    } else {
      control = TextFormField(
        controller: _controllers[f.id], enabled: _enabled && !f.readOnly,
        readOnly: f.date && widget.pickDate != null,
        keyboardType: f.numeric ? TextInputType.number : f.date ? TextInputType.datetime : TextInputType.text,
        inputFormatters: f.numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: _decoration().copyWith(hintText: f.date ? 'DD-MM-YYYY' : null,
          suffixIcon: f.date ? const Icon(CupertinoIcons.calendar, size: 18, color: _muted) : null),
        onTap: !f.date || widget.pickDate == null ? null : () async {
          final parts = _controllers[f.id]!.text.split('-');
          DateTime? selected;
          if (parts.length == 3) selected = DateTime.tryParse('${parts[2]}-${parts[1]}-${parts[0]}');
          final date = await widget.pickDate!(context, selected);
          if (!mounted || date == null) return;
          _controllers[f.id]!.text = '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
        },
        validator: (raw) {
          final value = (raw ?? '').trim();
          // Do not replace missing values with zero or invent required portal fields.
          if (value.isEmpty) return null;
          if (f.numeric && !RegExp(r'^\d+$').hasMatch(value)) return 'Enter a non-negative whole number';
          if (f.date) {
            final match = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(value);
            if (match == null) return 'Use DD-MM-YYYY';
            final d = int.parse(match[1]!), m = int.parse(match[2]!), y = int.parse(match[3]!);
            final date = DateTime(y, m, d), today = DateUtils.dateOnly(DateTime.now());
            if (date.year != y || date.month != m || date.day != d || date.isBefore(DateTime(2024)) || date.isAfter(today)) return 'Select a valid date from 01-01-2024 to today';
          }
          return null;
        },
      );
    }
    return Padding(padding: const EdgeInsets.only(bottom: 18), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(f.label, style: const TextStyle(fontSize: 12, height: 1.6, fontWeight: FontWeight.w500, color: _ink)),
        const SizedBox(height: 7), control,
      ]));
  }
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(textTheme: Theme.of(context).textTheme.apply(fontFamily: 'PlusJakartaSans')),
    child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.title, style: const TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 18, fontWeight: FontWeight.w600, color: _ink)),
        const SizedBox(height: 5), Text(widget.subtitle, style: const TextStyle(fontSize: 12, color: _muted)),
        const SizedBox(height: 18),
        Container(width: double.infinity, padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.note != null) Padding(padding: const EdgeInsets.only(bottom: 18),
              child: Text(widget.note!, style: const TextStyle(fontSize: 12, height: 1.6, color: _muted))),
            LayoutBuilder(builder: (context, constraints) {
              final selectors = widget.fields.takeWhile((f) => f.options != null).toList();
              if (selectors.isEmpty) return const SizedBox.shrink();
              final columns = constraints.maxWidth >= 720 ? selectors.length : constraints.maxWidth >= 440 ? 2 : 1;
              final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(spacing: 16, children: selectors.map((f) => SizedBox(width: width, child: _input(f))).toList());
            }),
            ...widget.fields.skipWhile((f) => f.options != null).map(_input),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(liveRegion: true, child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12)))),
            Align(alignment: Alignment.centerRight, child: FilledButton(
              onPressed: _enabled && widget.onAction != null ? _act : null,
              style: FilledButton.styleFrom(backgroundColor: _ink, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_busy) ...[const CupertinoActivityIndicator(radius: 8, color: Colors.white), const SizedBox(width: 9)],
                Text(widget.actionLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ]))),
          ])),
        ),
      ])),
  );
}

/// One row from the live Pink grid. rowKey is the portal row suffix, never
/// assumed to be a class ID. initialValues use full live control IDs.
class ViffsPinkClassData {
  final String rowKey, classLabel;
  final Map<String, String> initialValues;
  const ViffsPinkClassData({required this.rowKey, required this.classLabel,
    required this.initialValues});
}

/// All classes submit together. Submit does not imply Lock or completion.
/// Lock is deliberately not exposed until its confirmation/result is mapped.
class ViffsPinkEntryForm extends StatelessWidget {
  final List<ViffsPinkClassData> rows;
  final String periodLabel;
  final bool locked;
  final MonthlyFormAction? onSubmit;
  const ViffsPinkEntryForm({super.key, required this.rows, required this.periodLabel,
    required this.locked, this.onSubmit});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(18),
      child: Text('No class data available.'));
    final values = <String, String>{};
    final fields = <_Field>[];
    for (final row in rows) {
      values.addAll(row.initialValues);
      String id(String name) => 'ContentPlaceHolder1_grd_Pink_${name}_${row.rowKey}';
      String label(String text) => '${row.classLabel} · $text';
      fields.addAll([
        _Field(id('lblBoys'), label('कक्षा विवरण — छात्र'), numeric: true, readOnly: true),
        _Field(id('lblGirls'), label('कक्षा विवरण — छात्रा'), numeric: true, readOnly: true),
        _Field(id('lblTBG'), label('कुल'), numeric: true, readOnly: true),
        _Field(id('lblBoys_Tablet'), label('कम से कम चार गोली — छात्र'), numeric: true),
        _Field(id('lblGirls_Tablet'), label('कम से कम चार गोली — छात्रा'), numeric: true),
        _Field(id('lblBoys_TabletLessThen4'), label('चार से कम गोली — छात्र'), numeric: true),
        _Field(id('lblGirls_TabletLessThen4'), label('चार से कम गोली — छात्रा'), numeric: true),
        _Field(id('lblBoys_TabletNoConsumption'), label('एक भी गोली नहीं — छात्र'), numeric: true),
        _Field(id('lblGirls_TabletNoConsumption'), label('एक भी गोली नहीं — छात्रा'), numeric: true),
        _Field(id('lblTabletRecation_Student'), label('गोली सेवन के बाद प्रतिकूल प्रभाव वाले विद्यार्थियों की संख्या'), numeric: true),
        _Field(id('lblHospitalRafer_Student'), label('प्रतिकूल प्रभाव के प्रबंधन हेतु स्वास्थ्य केंद्र रेफर विद्यार्थियों की संख्या'), numeric: true),
        _Field(id('lblIdentify_Student'), label('मध्यम / गंभीर एनीमिया लक्षण — पहचान किये गये विद्यार्थी'), numeric: true),
        _Field(id('lblRefer_student'), label('मध्यम / गंभीर एनीमिया लक्षण — रेफर किये गये विद्यार्थी'), numeric: true),
        _Field(id('lblPlanSession_Count'), label('पोषण एवं स्वास्थ्य शिक्षा — प्लान सत्रों की संख्या'), numeric: true),
        _Field(id('lblOrganizeSession_Count'), label('पोषण एवं स्वास्थ्य शिक्षा — आयोजित सत्रों की संख्या'), numeric: true),
        _Field(id('lblLessthan7'), label('हिमोग्लोबिन स्तर 7 से कम — विद्यार्थियों की संख्या'), numeric: true),
        _Field(id('lbl7to9'), label('हिमोग्लोबिन स्तर 7 से 9.9 — विद्यार्थियों की संख्या'), numeric: true),
        _Field(id('lbl10to10_9'), label('हिमोग्लोबिन स्तर 10 से 10.9 — विद्यार्थियों की संख्या'), numeric: true),
        _Field(id('lblGreaterthan_11'), label('हिमोग्लोबिन स्तर 11 से अधिक — विद्यार्थियों की संख्या'), numeric: true),
        _Field(id('lblTeacher_name'), label('कक्षा अध्यापक का नाम'), readOnly: true),
        _Field(id('ddl_Teach_PinkTablet1'), label('क्या कक्षा अध्यापक गोली लेते हैं?'), options: const {'1': 'हाँ', '2': 'नहीं'}),
        _Field(id('ddl_Teach_PinkTablet2'), label('इस माह में 4 या अधिक गोली का उपयोग किया गया?'), options: const {'1': 'हाँ', '2': 'नहीं'}),
      ]);
    }
    return _MonthlyForm(title: 'VIFFS · पिंक', subtitle: periodLabel,
      note: locked ? 'Locked' : null, actionLabel: 'Submit', readOnly: locked,
      initialValues: values, fields: fields, onAction: onSubmit);
  }
}
