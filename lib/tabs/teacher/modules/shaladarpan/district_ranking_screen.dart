part of 'monthly_tasks_screen.dart';

class DistrictRankingScreen extends MonthlyTasksScreen {
  const DistrictRankingScreen({super.key, required super.schoolId, super.onStatus,
    super.initialForm, super.embedded, super.active}) : super(initialTask: 'ranking');
}

class DistrictRankingScreenState extends MonthlyTasksScreenState {
  @override
  void _initialize() {
    final previous = DateTime(DateTime.now().year, DateTime.now().month, 0);
    _selection.addAll({'${prefix}ddlMonth1': '${previous.month}', '${prefix}ddlyear': '${previous.year}'});
    _showPeriodPicker = widget.embedded;
    _restoreRankingStatus();
  }
  @override
  Widget _sectionForm(Map<String, dynamic> section) => _rankingSection(section);
  Future<void> _restoreRankingStatus() async {
    final status = await RankingStatusService.readDue(widget.schoolId);
    if (!mounted) return;
    final form = RankingStatusService.loginForm(widget.schoolId);
    setState(() {
      _rankingStatus = status;
      if (form != null) _apply(form);
    });
    // Opening this screen is an explicit read. Recover a missing login form
    // automatically; never require a manual Show just to open the entry.
    if (form == null) await _load();
  }
  bool get _rankingDraftMatchesSaved {
    if (_task != 'ranking' || _data?['editing'] != true) return false;
    final records = maps(_data?['history']).where((row) =>
      row['year'].toString() == _selection['${prefix}ddlyear'] &&
      row['month'].toString() == _selection['${prefix}ddlMonth1']).toList();
    if (records.length != 1 || records.single['values'] is! List) return false;
    final saved = records.single['values'] as List;
    const fields = ['txtaward', 'txtlibbooks', 'txtsports', 'TextBox1'];
    if (saved.length != fields.length) return false;
    for (var index = 0; index < fields.length; index++) {
      if ((_inputs['$prefix${fields[index]}']?.text.trim() ?? '') != saved[index].toString()) return false;
    }
    return true;
  }
  String _rankingTitle(String id) {
    if (id.endsWith('txtaward')) return 'Awards & participation';
    if (id.endsWith('txtlibbooks')) return 'Library books';
    if (id.endsWith('txtsports')) return 'Sports participation';
    if (id.endsWith('TextBox1')) return 'SDMC / SMC meeting';
    return 'Entry details';
  }
  Widget _rankingSection(Map<String, dynamic> section) {
    final fields = maps(section['fields']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text('Entry details', style: _text(12, FontWeight.w600, muted))),
      Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: ink.withValues(alpha: 0.025), blurRadius: 18, offset: const Offset(0, 5))]),
        child: LayoutBuilder(builder: (context, box) {
          Widget fieldView(MapEntry<int, Map<String, dynamic>> entry) => Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: LayoutBuilder(builder: (context, constraints) {
                final field = entry.value;
                final id = field['id'].toString();
                final isDate = field['date'] == true || id.endsWith('TextBox1');
                const valueWidth = 190.0;
                final narrow = constraints.maxWidth < 600 || MediaQuery.textScalerOf(context).scale(14) > 20;
                final title = Row(children: [
                  Container(width: 32, height: 32,
                    decoration: BoxDecoration(color: const Color(0xFFF1F4F7), borderRadius: BorderRadius.circular(10)),
                    child: id.endsWith('TextBox1')
                      ? Center(child: SizedBox(width: 18, height: 18, child: Image.asset('assets/icons/leave.png', fit: BoxFit.contain)))
                      : Icon(_rankingIcon(id), size: 18, color: ink)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_rankingTitle(id), style: _text(14, FontWeight.w500))),
                ]);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (narrow) ...[
                    title, const SizedBox(height: 8),
                    Text(field['label'].toString(), style: _text(13, FontWeight.w400, muted).copyWith(height: 1.5)),
                    const SizedBox(height: 12), _field(field, showLabel: false),
                  ] else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title,
                      const SizedBox(height: 8), Text(field['label'].toString(), style: _text(13, FontWeight.w400, muted).copyWith(height: 1.5))])), const SizedBox(width: 24),
                    SizedBox(width: valueWidth, child: _field(field, showLabel: false)),
                  ]),

                ]);
              }));
          return Column(children: [
              for (final entry in fields.asMap().entries) ...[
                fieldView(entry),
                if (entry.key < fields.length - 1)
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFE2E8F0)),
              ],
            ]);
        }),
      ),
    ]);
  }
  Future<void> _rankingAction(String action) async {
    if (_busy || _selectionChanged || _uncertain || _data == null) return;
    final nativeAction = action == 'edit' ? 'Edit' : 'Delete';
    if (_data!['confirmations'] is! Map || (_data!['confirmations'][nativeAction] ?? '').toString().isEmpty) {
      await _load();
      if (!mounted || _selectionChanged || _data == null) return;
    }
    final portalConfirmation = _data!['confirmations'] is Map
      ? (_data!['confirmations'][nativeAction] ?? '').toString() : '';
    if (portalConfirmation.isEmpty) {
      setState(() { _message = 'The portal confirmation is unavailable. Please refresh.'; _messageError = true; });
      return;
    }
    final confirmed = (await showDialog<bool>(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: const Color(0xFFFAFAFC),
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: SizedBox(width: 360, child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    _warningSymbol(),
                    const SizedBox(width: 10),
                    Expanded(child: Text(action == 'edit' ? 'Edit entry' : 'Delete entry', style: _text(15, FontWeight.w600))),
                  ]),
                  const SizedBox(height: 12), _periodRow(),
                  const SizedBox(height: 8),
                  Text(portalConfirmation, style: _text(14, FontWeight.w400)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFFFAFAFC), foregroundColor: ink,
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: _text(14, FontWeight.w500)),
                      onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: _text(14, FontWeight.w500)),
                      onPressed: () => Navigator.pop(ctx, true), child: const Text('OK'))),
                  ]),
                ]),
              )),
            ),
          ),
        ) ?? false);
    if (!confirmed || !mounted) return;
    setState(() { _saving = true; _rankingOperation = action; _message = null; });
    try {
      final result = await MonthlyTaskService.rankingAction(widget.schoolId, action, Map.of(_selection), _data!['snapshot'].toString());
      if (!mounted) return;
      setState(() { _apply(Map<String, dynamic>.from(result['data'])); _message = _portalMessage(result, _data!); _messageError = false; });
      final previous = DateTime(DateTime.now().year, DateTime.now().month, 0);
      if (action == 'delete' && _selection['${prefix}ddlMonth1'] == '${previous.month}' && _selection['${prefix}ddlyear'] == '${previous.year}') {
        widget.onStatus?.call('ranking', _data!['completed'] as bool?);
      }
    } catch (e) {
      if (mounted) setState(() {
        _message = e.toString(); _messageError = true; _selectionChanged = true;
        _uncertain = e is MonthlyTaskException && e.submissionUnknown;
      });
    } finally { if (mounted) setState(() { _saving = false; _rankingOperation = null; }); }
  }
  Widget _periodStatus() {
    final checking = _loading || _saving;
    final confirmed = !checking && !_selectionChanged && !_uncertain && _data != null;
    final editing = confirmed && _data?['editing'] == true;
    final cachedPeriod = _rankingStatus != null &&
      _selection['${prefix}ddlMonth1'] == '${_rankingStatus!['month']}' &&
      _selection['${prefix}ddlyear'] == '${_rankingStatus!['year']}';
    final completed = confirmed ? !editing && _data!['completed'] == true : !checking && _data == null && cachedPeriod && _rankingStatus!['completed'] == true;
    final pending = confirmed ? _data!['completed'] == false : !checking && _data == null && cachedPeriod && _rankingStatus!['completed'] == false;
    final label = checking ? (_rankingOperation == 'edit' ? 'Opening' : _rankingOperation == 'delete' ? 'Deleting' : _saving ? 'Saving' : 'Checking') : editing ? 'Editing' : completed ? (_data?['locked'] == true ? 'Locked' : 'Submitted')
      : pending ? 'Pending' : _selectionChanged ? 'Check period' : 'Not confirmed';
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(children: [
      SizedBox(width: 16, height: 16, child: Image.asset('assets/icons/leave.png', fit: BoxFit.contain)),
      const SizedBox(width: 7),
      Expanded(child: Text(_periodLabel, style: _text(13, FontWeight.w500, ink))),
      const SizedBox(width: 8),
      Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: completed ? const Color(0xFF69F0AE) : editing ? const Color(0xFFFFF3D6) : const Color(0xFFF1F4F7),
          borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (checking) ...[SizedBox(width: 14, height: 14, child: Lottie.asset('assets/icons/Loading (Buffering).json',
            errorBuilder: (_, __, ___) => const CupertinoActivityIndicator(radius: 6))), const SizedBox(width: 5)],
          if (completed) ...[const Icon(CupertinoIcons.checkmark_alt, size: 12, color: Color(0xFF15803D)), const SizedBox(width: 4)],
          Text(label, style: _text(10.5, FontWeight.w500, completed ? const Color(0xFF14532D) : editing ? const Color(0xFF865B16) : muted)),
        ]),
      ),
    ]));
  }
  List<Map<String, dynamic>> get _fallbackPeriodFields {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final year = DateTime.now().year;
    return [
      {'id': '${prefix}ddlMonth1', 'label': 'Month', 'options': [
        for (var i = 0; i < months.length; i++) {'value': '${i + 1}', 'label': months[i]}]},
      {'id': '${prefix}ddlyear', 'label': 'Year', 'options': [
        for (var y = year - 1; y <= year; y++) {'value': '$y', 'label': '$y'}]},
    ];
  }
}
