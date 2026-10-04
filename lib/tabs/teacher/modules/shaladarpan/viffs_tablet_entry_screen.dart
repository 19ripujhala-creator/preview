part of 'monthly_tasks_screen.dart';

class ViffsTabletEntryScreen extends MonthlyTasksScreen {
  const ViffsTabletEntryScreen({super.key, required super.schoolId, super.onStatus,
    super.initialForm, super.embedded, super.active}) : super(initialTask: 'viffs');
}

class ViffsTabletEntryScreenState extends MonthlyTasksScreenState {
  static final Map<String, Map<String, dynamic>> _selectorCache = {};
  Map<String, dynamic>? _cachedSelectors;
  String _entryGroup = 'Tablets';
  final GlobalKey _entryAnchor = GlobalKey();

  void _goToGroup(String group) {
    FocusScope.of(context).unfocus();
    setState(() { _entryGroup = group; _showAllGroups = false; });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _entryAnchor.currentContext;
      if (mounted && target != null) Scrollable.ensureVisible(target,
        duration: const Duration(milliseconds: 220), alignment: 0.05);
    });
  }

  @override
  void initState() {
    super.initState();
    ViffsStatusService.changes.addListener(_onCategoryStatusChanged);
  }
  @override
  void dispose() {
    ViffsStatusService.changes.removeListener(_onCategoryStatusChanged);
    super.dispose();
  }
  void _onCategoryStatusChanged() {
    if (!mounted) return;
    setState(() { if (!_busy) _normalizeCategory(); });
  }
  void _normalizeCategory() {
    final required = ViffsStatusService.requiredCategories(widget.schoolId);
    final current = _selection['${prefix}ddlClass'];
    if (required == null || current == null || required.contains(current)) return;
    _selectionChanged = true;
    // A draft is retained until the user explicitly discards it.
    if (_hasChanges) return;
    final fields = _periodFields.where((f) => f['id'] == '${prefix}ddlClass').toList();
    if (fields.length != 1) return;
    final available = maps(fields.single['options']).where((o) => required.contains(o['value'].toString())).toList();
    if (available.isNotEmpty) _selection['${prefix}ddlClass'] = available.first['value'].toString();
  }
  @override
  List<Map<String, dynamic>> get _periodFields {
    final fields = super._periodFields;
    final required = ViffsStatusService.requiredCategories(widget.schoolId);
    if (required == null) return fields;
    return fields.map((field) => field['id'] != '${prefix}ddlClass' ? field : {
      ...field, 'options': maps(field['options']).where((option) => required.contains(option['value'].toString())).toList(),
    }).toList();
  }

  @override
  void _initialize() {
    _showPeriodPicker = true;
    final cached = MonthlyTaskService.cachedViffsSelectors(widget.schoolId) ?? _selectorCache[widget.schoolId];
    if (cached == null) {
      _load(initial: true);
      return;
    }
    _cachedSelectors = Map<String, dynamic>.from(jsonDecode(jsonEncode(cached)));
    for (final e in Map<String, dynamic>.from(_cachedSelectors!['selection'] as Map).entries) {
      _selection[e.key] = e.value.toString();
    }
    _initialPeriodDefaults();
    _normalizeCategory();
    final loaded = ViffsStatusService.selectedForm(widget.schoolId, Map<String, dynamic>.from(_selection));
    if (loaded != null) {
      _apply(loaded);
      _rememberSelectors(loaded);
    } else {
      _selectionChanged = true;
    }
    ViffsStatusService.restore(widget.schoolId).then((_) { if (mounted) setState(() {}); });
  }

  @override
  void _initialPeriodDefaults() {
    final due = DateTime(DateTime.now().year, DateTime.now().month, 0);
    final startYear = due.month >= 5 ? due.year : due.year - 1;
    for (final field in _periodFields) {
      final id = field['id'].toString();
      final matches = maps(field['options']).where((option) {
        final value = option['value'].toString();
        if (id == '${prefix}ddlmonth') return value == '${due.month}';
        if (id == '${prefix}ddlStudentType') {
          return value.replaceAll(' ', '') == '$startYear-${startYear + 1}' ||
            value.replaceAll(' ', '') == '$startYear-${(startYear + 1).toString().substring(2)}';
        }
        return false;
      }).toList();
      if (matches.length == 1 && _selection[id] != matches.single['value'].toString()) {
        _selection[id] = matches.single['value'].toString();
        _selectionChanged = true;
      }
    }
  }

  @override
  List<Map<String, dynamic>> get _fallbackPeriodFields => _cachedSelectors != null
      ? maps(_cachedSelectors!['selectors']) : [
          {'id': '${prefix}ddlStudentType', 'label': 'सत्र', 'options': <Map<String, dynamic>>[]},
          {'id': '${prefix}ddlClass', 'label': 'गोली', 'options': <Map<String, dynamic>>[]},
          {'id': '${prefix}ddlmonth', 'label': 'माह', 'options': <Map<String, dynamic>>[]},
        ];

  @override
  void _rememberSelectors(Map<String, dynamic> data) {
    // Cache metadata only. Saved values, snapshots and completion are portal-only.
    final metadata = Map<String, dynamic>.from(jsonDecode(jsonEncode({
      'selectors': data['selectors'], 'selection': data['selection'],
    })));
    _selectorCache[widget.schoolId] = metadata;
    _cachedSelectors = metadata;
    _normalizeCategory();
  }
  @override
  Widget _periodStatus() => const SizedBox.shrink();

  Widget _selectedStatus() {
    final month = int.tryParse(_selection['${prefix}ddlmonth'] ?? '');
    final session = _selection['${prefix}ddlStudentType'] ?? '';
    final startYear = int.tryParse(session.split(RegExp(r'[-–]')).first.trim());
    final year = month != null && startYear != null ? (month >= 5 ? startYear : startYear + 1) : null;
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final tablet = _selection['${prefix}ddlClass'];
    final category = tablet == 'P' ? 'पिंक · 1–5' : tablet == 'B' ? 'ब्लू · 6–8' : '—';
    final period = month != null && month >= 1 && month <= 12 && year != null ? '${months[month - 1]} $year · $category' : '—';
    // Status always belongs to the loaded selection, never a newly selected period.
    final loaded = _data?['selection'];
    final checked = loaded is Map && !_uncertain && !_loading &&
      ['ddlStudentType', 'ddlmonth', 'ddlClass'].every((suffix) =>
        loaded['$prefix$suffix']?.toString() == _selection['$prefix$suffix']);
    final remembered = ViffsStatusService.selectionStatus(widget.schoolId, Map<String, dynamic>.from(_selection));
    final portalLocked = _data != null && _data!['locked'] == true;
    final cachedLocked = remembered != null && remembered['locked'] == true;
    final locked = checked ? portalLocked : (!_uncertain && cachedLocked);
    final noRecords = checked && _data?['no_records'] == true;
    final cachedSaved = remembered != null && remembered['saved'] == true;
    String status;
    if (locked) {
      status = 'Locked';
    } else if (noRecords) {
      status = 'No records';
    } else if (checked || (remembered != null && !_uncertain)) {
      status = cachedSaved ? 'Submitted' : 'Pending';
    } else {
      status = 'Not checked';
    }
    const green = Color(0xFF15803D);
    final success = locked || status == 'Submitted';
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Image.asset('assets/icons/leave.png', width: 16, height: 16), const SizedBox(width: 8),
          Expanded(child: Text(period, style: _text(13, FontWeight.w500))),
        ])), const SizedBox(width: 8),
        Semantics(liveRegion: true, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(color: success ? const Color(0xFF69F0AE) : const Color(0xFFF1F4F7),
            borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (success) ...[Icon(locked ? CupertinoIcons.lock_fill : CupertinoIcons.checkmark_alt, size: 12, color: green), const SizedBox(width: 4)],
            Text(status, style: _text(10.5, FontWeight.w500, success ? const Color(0xFF14532D) : muted)),
          ]))),
      ]);
  }

  @override
  Widget _reportingPeriod() {
    final fields = _periodFields;
    Widget field(String suffix) {
      final matches = fields.where((f) => f['id'] == '$prefix$suffix').toList();
      return matches.length == 1 ? _field(matches.single, selector: true) : const SizedBox.shrink();
    }
    final valid = fields.length == 3 && fields.every((f) => maps(f['options']).any((o) =>
      o['value'].toString() == _selection[f['id']] && !['', '0', '-1'].contains(_selection[f['id']])));
    Widget show() => FilledButton(
      style: FilledButton.styleFrom(backgroundColor: ink, foregroundColor: Colors.white,
        minimumSize: const Size(72, 38), padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      onPressed: _busy || !valid ? null : () async {
        if (await _discard()) await _load(refresh: _uncertain || _messageError);
      }, child: _loading ? SizedBox(width: 20, height: 20, child: Lottie.asset(
        'assets/icons/Loading (Buffering).json', errorBuilder: (_, __, ___) => const CupertinoActivityIndicator(radius: 8, color: Colors.white)))
        : Text('Show', style: _text(13, FontWeight.w600, Colors.white)));
    return Container(padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _selectedStatus(), const SizedBox(height: 8),
        LayoutBuilder(builder: (context, constraints) {
          final narrow = constraints.maxWidth < 280 || MediaQuery.textScalerOf(context).scale(12) > 18;
          if (constraints.maxWidth >= 760 && !narrow) {
            return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: field('ddlStudentType')), const SizedBox(width: 12),
              Expanded(child: field('ddlClass')), const SizedBox(width: 12),
              Expanded(child: field('ddlmonth')), const SizedBox(width: 12), show(),
            ]);
          }
          return Column(children: [
            if (narrow) ...[field('ddlStudentType'), const SizedBox(height: 10), field('ddlClass')]
            else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: field('ddlStudentType')), const SizedBox(width: 10), Expanded(child: field('ddlClass')),
            ]),
            const SizedBox(height: 8),
            if (narrow) ...[field('ddlmonth'), const SizedBox(height: 8), Align(alignment: Alignment.centerRight, child: show())]
            else Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: field('ddlmonth')), const SizedBox(width: 12), show(),
            ]),
          ]);
        }),
      ]));
  }

  bool _consumptionField(Map<String, dynamic> field) => RegExp(
    r'_lbl(?:Boys|Girls)(?:_Tablet(?:LessThen4|NoConsumption)?)?_\d+$').hasMatch(field['id'].toString());
  bool _totalField(Map<String, dynamic> field) => RegExp(r'_lblTBG_\d+$').hasMatch(field['id'].toString());
  String _nativeGroup(Map<String, dynamic> field) => field['label'].toString().split(' · ').first;
  String _groupTitle(String group) {
    if (group.contains('अध्यापक')) return 'Teacher';
    if (group.contains('प्रतिदूष') || group.contains('प्रतिकूल')) return 'Side effects';
    if (group.contains('एनीमिया') || group.contains('गंभीर')) return 'Anaemia';
    if (group.contains('शिक्षा')) return 'Health education';
    if (group.contains('हीमोग्लोबिन')) return 'Haemoglobin';
    return 'Details';
  }

  List<String> get _entryGroups {
    final groups = <String>{};
    for (final section in maps(_data?['sections'])) {
      for (final field in maps(section['fields'])) {
        if (!_consumptionField(field) && !_totalField(field)) groups.add(_nativeGroup(field));
      }
    }
    return ['Tablets', ...groups];
  }
  @override
  bool get _showFinalActions => _entryGroup == _entryGroups.last;

  @override
  Widget _sectionsView() {
    final sections = maps(_data?['sections']);
    if (sections.isEmpty) return const SizedBox.shrink();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final section in sections) {
      for (final field in maps(section['fields'])) {
        if (!_consumptionField(field) && !_totalField(field)) groups.putIfAbsent(_nativeGroup(field), () => []).add(field);
      }
    }
    var active = _entryGroup == 'Tablets' || groups.containsKey(_entryGroup) ? _entryGroup : 'Tablets';
    if (_showAllGroups && _fieldErrors.isNotEmpty) {
      final firstError = _fieldErrors.keys.first;
      if (sections.any((section) => maps(section['fields']).any((f) =>
          f['id'] == firstError && _consumptionField(f)))) {
        active = 'Tablets';
      } else {
        for (final entry in groups.entries) {
          if (entry.value.any((f) => f['id'] == firstError)) { active = entry.key; break; }
        }
      }
    }
    final locked = _data?['locked'] == true;
    final editable = !locked && _data?['can_submit'] == true && !_selectionChanged && !_uncertain;
    Map<String, dynamic>? find(List<Map<String, dynamic>> fields, String gender, String suffix) {
      final matches = fields.where((f) => RegExp('_lbl${gender}${suffix}_\\d+\$').hasMatch(f['id'].toString())).toList();
      return matches.length == 1 ? matches.single : null;
    }
    Widget number(Map<String, dynamic>? field) {
      if (field == null) return Center(child: Text('—', style: _text(14, FontWeight.w500, muted)));
      final id = field['id'].toString();
      final readonly = !editable || field['readonly'] == true;
      final error = _fieldErrors.containsKey(id);
      return Tooltip(message: field['label'].toString(), child: Container(
        key: _fieldKeys.putIfAbsent(id, () => GlobalKey()),
        constraints: const BoxConstraints(minHeight: 34),
        decoration: BoxDecoration(color: readonly ? const Color(0xFFF7F9FB) : Colors.white,
          borderRadius: BorderRadius.circular(8), border: Border.all(
            color: error ? const Color(0xFFDC2626) : const Color(0xFFE2E8F0))),
        child: readonly ? Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 7),
          child: Text(_inputs[id]?.text ?? field['value']?.toString() ?? '—', style: _text(14, FontWeight.w500))))
          : TextFormField(controller: _inputs[id], enabled: !_busy, cursorColor: ink,
              textAlign: TextAlign.center, style: _text(14, FontWeight.w500),
              keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: (field['maxlength'] as int? ?? 0) > 0 ? field['maxlength'] as int : null,
              decoration: const InputDecoration(isDense: true, counterText: '', hintText: '—',
                border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 9)),
              onChanged: (_) => setState(() { _fieldErrors.remove(id); _edited = _hasChanges; })),
      ));
    }
    final steps = ['Tablets', ...groups.keys];
    final step = steps.indexOf(active);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Tablet consumption', key: _entryAnchor, style: _text(14, FontWeight.w600)),
      const SizedBox(height: 8),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final group in ['Tablets', ...groups.keys]) Padding(padding: const EdgeInsets.only(right: 7),
          child: OutlinedButton(style: OutlinedButton.styleFrom(
            backgroundColor: active == group ? ink : Colors.white, foregroundColor: active == group ? Colors.white : ink,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            side: BorderSide(color: active == group ? ink : const Color(0xFFE2E8F0)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
            onPressed: _busy ? null : () => _goToGroup(group),
            child: Text(group == 'Tablets' ? 'Tablets' : _groupTitle(group), style: _text(12, FontWeight.w500, active == group ? Colors.white : ink)))),
      ])),
      if (active != 'Tablets') Padding(padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(active, style: _text(12, FontWeight.w500).copyWith(height: 1.5))),
      if (active == 'Tablets' && editable) Align(alignment: Alignment.centerRight,
        child: TextButton(onPressed: _busy ? null : _fillStrength,
          child: Text('Fill full strength', style: _text(12, FontWeight.w500)))),
      const SizedBox(height: 8),
      Container(margin: const EdgeInsets.only(bottom: 12), clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Column(children: [
          for (var index = 0; index < sections.length; index++) ...[
            Builder(builder: (context) {
              final section = sections[index], fields = maps(sections[index]['fields']);
              final matched = <String>{};
              final rows = <TableRow>[];
              Widget heading(String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(value, textAlign: TextAlign.center, style: _text(11, FontWeight.w600, muted)));
              rows.add(TableRow(children: [heading('Students'), heading('Enrolled'), heading('4+'), heading('<4'), heading('None')]));
              for (final gender in ['Boys', 'Girls']) {
                final items = [find(fields, gender, ''), find(fields, gender, '_Tablet'),
                  find(fields, gender, '_TabletLessThen4'), find(fields, gender, '_TabletNoConsumption')];
                for (final item in items) { if (item != null) matched.add(item['id'].toString()); }
                rows.add(TableRow(children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(gender, style: _text(12, FontWeight.w500))),
                  Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(items.first?['value']?.toString() ?? '—', style: _text(13, FontWeight.w500, muted)))),
                  for (final item in items.skip(1)) Padding(padding: const EdgeInsets.all(3), child: number(item)),
                ]));
              }
              // Unrecognized native fields are displayed with their original portal labels.
              final remainder = active == 'Tablets' ? <Map<String, dynamic>>[] : fields.where((f) =>
                !_consumptionField(f) && !_totalField(f) && _nativeGroup(f) == active).toList();
              final errors = (active == 'Tablets' ? fields.where(_consumptionField) : remainder)
                .map((f) => _fieldErrors[f['id']]).whereType<String>().toSet();
              return Padding(padding: const EdgeInsets.all(9), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Container(width: 24, height: 24,
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.school_outlined, size: 15, color: ink)), const SizedBox(width: 8),
                  Expanded(child: Text(section['title'].toString(), style: _text(13, FontWeight.w600))),
                ]),
                if (active != 'Tablets' && active.contains('अध्यापक') && (section['teacher'] ?? '').toString().isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text(section['teacher'].toString(), style: _text(12, FontWeight.w400, muted))),
                const SizedBox(height: 6),
                if (active == 'Tablets') Table(columnWidths: const {0: FlexColumnWidth(1.25), 1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1.1), 3: FlexColumnWidth(1.1), 4: FlexColumnWidth(1.1)},
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle, children: rows),
                for (final error in errors) Padding(padding: const EdgeInsets.only(top: 6),
                  child: Text(error, style: _text(12, FontWeight.w400, const Color(0xFFDC2626)))),
                if (remainder.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  LayoutBuilder(builder: (context, constraints) => Wrap(spacing: 10, runSpacing: 10,
                    children: remainder.map((field) => SizedBox(width: constraints.maxWidth >= 600
                      ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth,
                      child: _field({...field, 'readonly': locked || field['readonly'] == true,
                        'label': field['label'].toString().contains(' · ')
                          ? field['label'].toString().split(' · ').skip(1).join(' · ') : field['label']}))).toList())),
                ],
              ]));
            }),
            if (index < sections.length - 1) const Divider(height: 1, color: Color(0xFFE2E8F0)),
          ],
        ])),
      Row(children: [
        Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(backgroundColor: Colors.white,
          foregroundColor: ink, minimumSize: const Size(0, 42)),
          onPressed: _busy || step <= 0 ? null : () => _goToGroup(steps[step - 1]), child: Text('Previous', style: _text(12, FontWeight.w500)))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('${step + 1}/${steps.length}', style: _text(12, FontWeight.w500, muted))),
        Expanded(child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
          onPressed: _busy ? null : step < steps.length - 1 ? () => _goToGroup(steps[step + 1]) : editable ? _submit : null,
          child: Text(step < steps.length - 1 ? 'Next' : locked ? 'Locked' : 'Review & submit',
            style: _text(12, FontWeight.w500, Colors.white)))),
      ]), const SizedBox(height: 10),
    ]);
  }

  @override
  Map<String, String> _entryErrors() {
    final errors = <String, String>{};
    for (final section in maps(_data?['sections'])) {
      final fields = maps(section['fields']);
      for (final gender in ['Boys', 'Girls']) {
        final enrolled = fields.where((f) => RegExp('_lbl${gender}_\\d+\$').hasMatch(f['id'].toString())).toList();
        final counts = fields.where((f) => RegExp('_lbl${gender}_Tablet(?:LessThen4|NoConsumption)?_\\d+\$').hasMatch(f['id'].toString())).toList();
        if (enrolled.length != 1 || enrolled.single['readonly'] != true || counts.length != 3) continue;
        final total = int.tryParse(enrolled.single['value'].toString());
        final numbers = counts.map((f) => int.tryParse((_inputs[f['id']]?.text ?? f['value'].toString()).trim())).toList();
        if (total != null && numbers.every((n) => n != null) && numbers.fold<int>(0, (sum, n) => sum + n!) != total) {
          for (final f in counts) {
            if (f['readonly'] != true) errors[f['id'].toString()] = 'विद्यार्थियों की कुल संख्या नामांकन के बराबर रखें';
          }
        }
      }
    }
    return errors;
  }

  Future<void> _fillStrength() async {
    if (_busy || _selectionChanged || _data?['locked'] == true) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFFFAFAFC), surfaceTintColor: Colors.transparent,
      title: Text('Fill full strength?', style: _text(16, FontWeight.w600)),
      content: Text('Fill all enrolled students under 4+ tablets. Review actual consumption before saving.', style: _text(13, FontWeight.w400)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: _text(13))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Fill'))],
    )) ?? false;
    if (!confirmed || !mounted) return;
    setState(() {
      for (final section in maps(_data?['sections'])) {
        final fields = maps(section['fields']);
        for (final gender in ['Boys', 'Girls']) {
          final enrolment = fields.where((f) => RegExp('_lbl${gender}_\\d+\$').hasMatch(f['id'].toString())).toList();
          final consumption = fields.where((f) => RegExp('_lbl${gender}_Tablet(?:LessThen4|NoConsumption)?_\\d+\$').hasMatch(f['id'].toString())).toList();
          if (enrolment.length != 1 || enrolment.single['readonly'] != true || consumption.length != 3 || consumption.any((f) => f['readonly'] == true)) continue;
          final count = int.tryParse(enrolment.single['value'].toString());
          if (count == null || count < 0) continue;
          for (final f in consumption) {
            _inputs[f['id']]?.text = RegExp('_lbl${gender}_Tablet_\\d+\$').hasMatch(f['id'].toString()) ? '$count' : '0';
          }
        }
      }
      _edited = _hasChanges; _fieldErrors.clear();
    });
  }

  void _prefillViffs() {
    if (_task != 'viffs' || _selectionChanged || _data?['can_submit'] != true || _data?['locked'] == true) return;
    for (final section in maps(_data!['sections'])) {
      final fields = maps(section['fields']);
      final existingConsumption = fields.where((f) => RegExp(r'_lbl(?:Boys|Girls)_Tablet(?:LessThen4|NoConsumption)?_\d+$').hasMatch(f['id'].toString()));
      if (existingConsumption.any((f) => (_inputs[f['id']]?.text.trim() ?? '').isNotEmpty)) continue;
      for (final gender in ['Boys', 'Girls']) {
        final enrolment = fields.where((f) => RegExp('_lbl${gender}_\\d+\$').hasMatch(f['id'].toString())).toList();
        final consumption = fields.where((f) => RegExp('_lbl${gender}_Tablet(?:LessThen4|NoConsumption)?_\\d+\$').hasMatch(f['id'].toString())).toList();
        if (enrolment.length != 1 || enrolment.single['readonly'] != true || consumption.length != 3 || consumption.any((f) => f['readonly'] == true)) continue;
        final count = int.tryParse(enrolment.single['value'].toString());
        if (count == null || count < 0) continue;
        if (consumption.any((f) => (_inputs[f['id']]?.text.trim() ?? '').isNotEmpty)) continue;
        for (final f in consumption) {
          final all = RegExp('_lbl${gender}_Tablet_\\d+\$').hasMatch(f['id'].toString());
          final value = all ? '$count' : '0';
          if (_inputs[f['id']]!.text != value) { _inputs[f['id']]!.text = value; _edited = true; _prefilledViffs = true; }
        }
      }
    }
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
      backgroundColor: Colors.white, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('Review saved VIFFS entry', style: _text(18, FontWeight.w600)),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('कृपया सूचना को लॉक करने से पूर्व एक बार चेक कर ले अन्यथा लॉक करने के बाद बदलाव संभव नहीं होगा'),
          const SizedBox(height: 12), ...review]))),
      actions: [TextButton(style: TextButton.styleFrom(foregroundColor: ink), onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: ink, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))), onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm Lock'))],
    )) ?? false;
    if (mounted) setState(() => _reviewing = false);
    if (!confirmed || !mounted) return;
    setState(() { _saving = true; _message = null; });
    try {
      final result = await MonthlyTaskService.lock(widget.schoolId, Map.of(_selection), _data!['snapshot'].toString());
      if (!mounted) return;
      setState(() {
        _apply(Map<String, dynamic>.from(result['data']));
        _message = _portalMessage(result, _data!); _messageError = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _message = e.toString(); _messageError = true;
        _uncertain = e is MonthlyTaskException && e.submissionUnknown;
        _selectionChanged = true;
      });
    } finally { if (mounted) setState(() => _saving = false); }
  }
  Widget _sectionForm(Map<String, dynamic> section) {
    final fields = maps(section['fields']);
    final enrolled = fields.where((f) => RegExp(r'_lbl(?:Boys|Girls|TBG)_\d+$').hasMatch(f['id'].toString())).toList();
    final mainFields = fields.where((f) => RegExp(r'_lbl(?:Boys|Girls)_Tablet_\d+$').hasMatch(f['id'].toString())).toList();
    final extra = fields.where((f) => !enrolled.contains(f) && !mainFields.contains(f)).toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final field in extra) {
      final parts = field['label'].toString().split(' · ');
      groups.putIfAbsent(parts.length > 1 ? parts.first : 'Entry details', () => []).add(field);
    }
    Widget groupFields(List<Map<String, dynamic>> items) => LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 280 && MediaQuery.textScalerOf(context).scale(12) < 20 ? 2 : 1;
      return Wrap(spacing: 16, runSpacing: 12, children: items.map((field) {
        final parts = field['label'].toString().split(' · ');
        final displayField = groups.length > 1 && parts.length > 1 ? {...field, 'label': parts.skip(1).join(' · ')} : field;
        return SizedBox(width: (constraints.maxWidth - (columns - 1) * 16) / columns, child: _field(displayField));
      }).toList());
    });
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(width: 30, height: 30, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(11)),
        child: const Icon(Icons.school_outlined, size: 17, color: ink)), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(section['title'].toString(), style: _text(14, FontWeight.w600)),
          if ((section['teacher'] ?? '').toString().isNotEmpty) Text(section['teacher'].toString(), style: const TextStyle(fontSize: 11, color: muted)),
        ])),
      ]),
      if (enrolled.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 12, runSpacing: 4,
        children: enrolled.map((f) {
          final id = f['id'].toString();
          final label = id.contains('_lblBoys_') ? 'Boys' : id.contains('_lblGirls_') ? 'Girls' : 'Total';
          return Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(color: const Color(0xFFF4F6F8), borderRadius: BorderRadius.circular(7)),
            child: Text('$label: ${f['value']}', style: _text(12, FontWeight.w500, muted)));
        }).toList())),
      if (mainFields.isNotEmpty) ...[
        const SizedBox(height: 10), Text('4+ tablets', style: _text(12, FontWeight.w500)),
        const SizedBox(height: 8), LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 260 && MediaQuery.textScalerOf(context).scale(12) < 20 ? 2 : 1;
          return Wrap(spacing: 12, runSpacing: 10, children: mainFields.map((f) => SizedBox(
            width: (constraints.maxWidth - (columns - 1) * 12) / columns,
            child: _field({...f, 'label': f['id'].toString().contains('_lblBoys_') ? 'Boys' : 'Girls'}))).toList());
        }),
      ],
      const SizedBox(height: 8),
      if (groups.length == 1) groupFields(extra) else
        for (final entry in groups.entries) ExpansionTile(
          key: ValueKey('${section['title']}:${entry.key}:$_revision:$_showAllGroups'),
          maintainState: true, initiallyExpanded: _showAllGroups,
          tilePadding: EdgeInsets.zero, childrenPadding: const EdgeInsets.only(bottom: 12, top: 6),
          shape: const Border(), collapsedShape: const Border(),
          title: Text(entry.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink)),
          children: [groupFields(entry.value)],
        ),
    ]);
  }
}
