import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shaladarpan/experiments/direct_school_session.dart';
import 'package:shaladarpan/experiments/direct_working_days_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/working_days_worker.dart';
import 'package:shaladarpan/widgets/adaptive_layout.dart';
import 'package:shaladarpan/widgets/page_content_motion.dart';
import 'package:shaladarpan/widgets/page_transitions.dart';

import 'monthly_student_attendance_screen.dart';

class MonthlyAttendanceScreen extends StatefulWidget {
  const MonthlyAttendanceScreen({super.key});
  @override
  State<MonthlyAttendanceScreen> createState() =>
      _MonthlyAttendanceScreenState();
}

class _MonthlyAttendanceScreenState extends State<MonthlyAttendanceScreen> {
  static const ink = Color(0xFF18212F), line = Color(0xFFE5E9EF);
  final _scroll = ScrollController();
  final _inputs = <String, TextEditingController>{};
  DirectWorkingDaysService? _service;
  String _school = '', _session = '', _month = '';
  Map<String, dynamic>? _data;
  String? _error, _notice;
  bool _loading = true,
      _saving = false,
      _confirming = false,
      _submitted = false;
  Timer? _noticeTimer;
  int _selectionEpoch = 0;
  bool get _busy => _loading || _saving || _confirming;
  bool get _current =>
      identical(_service, DirectSchoolSession.workingDays) &&
      _school == DirectSchoolSession.schoolId;
  List<Map<String, dynamic>> get _rows =>
      ((_data?['rows'] as List?) ?? []).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _sessions =>
      ((_data?['sessions'] as List?) ?? []).cast<Map<String, dynamic>>();
  Map _cell(Map row) => (row['cells'] as Map)[_month] as Map;
  Map<String, String> get _changes => {
    for (final row in _rows)
      if (_cell(row)['enabled'] == true &&
          _inputs[row['id']]!.text.trim() != _cell(row)['value'])
        row['id'] as String: _inputs[row['id']]!.text.trim(),
  };
  TextStyle _text(
    double size, {
    Color color = ink,
    FontWeight weight = FontWeight.w500,
  }) => TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: size,
    color: color,
    fontWeight: weight,
  );
  Widget _neutral(Widget child) => Theme(
    data: Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(
        primary: ink,
        secondary: ink,
        surface: Colors.white,
        surfaceTint: Colors.transparent,
      ),
    ),
    child: child,
  );

  @override
  void initState() {
    super.initState();
    _month = const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][DateTime.now().month - 1];
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _scroll.dispose();
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _accept(Map<String, dynamic> data) {
    _data = data;
    _session = '${data['session'] ?? _session}';
    for (final c in _inputs.values) {
      c.dispose();
    }
    _inputs.clear();
    for (final row in _rows) {
      _inputs[row['id'] as String] = TextEditingController(
        text: '${_cell(row)['value']}',
      );
    }
  }

  void _feedback(String message, {bool error = true}) {
    if (!mounted) return;
    setState(() {
      if (error) {
        _error = message;
        _notice = null;
        _noticeTimer?.cancel();
      } else {
        _notice = message;
        _error = null;
      }
    });
    if (!error) {
      _noticeTimer?.cancel();
      _noticeTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _notice = null);
      });
    }
  }

  Future<void> _open() async {
    if (_saving || _confirming) return;
    final service = DirectSchoolSession.workingDays;
    _service = service;
    _school = DirectSchoolSession.schoolId;
    if (service == null) {
      setState(() {
        _loading = false;
        _error = 'School login is required.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
      _data = null;
    });
    try {
      final result = await service.open();
      if (!mounted) return;
      if (!_current) {
        _feedback('School login has changed. Reopen Monthly Attendance.');
        return;
      }
      if (result['success'] == true) {
        setState(() => _accept(result));
      } else {
        _feedback('${result['message']}');
      }
    } catch (e) {
      _feedback('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reload() async {
    if (_busy || !await _discard() || !mounted) return;
    if (_session.isEmpty || _data == null) {
      await _open();
    } else {
      await _load();
    }
  }

  Future<void> _load() async {
    if (_busy || !_current || _session.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await _service!.load(_session);
      if (!mounted) return;
      if (!_current) {
        setState(() => _data = null);
        _feedback('School login has changed. Reopen Monthly Attendance.');
        return;
      }
      if (result['success'] == true) {
        setState(() {
          _accept(result);
          _submitted = false;
        });
        final messages = (result['messages'] as List?) ?? [];
        if (messages.isNotEmpty) _feedback(messages.join('\n'));
      } else {
        _feedback('${result['message']}');
      }
    } catch (e) {
      _feedback('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _discard() async {
    if (_changes.isEmpty) return true;
    setState(() => _confirming = true);
    try {
      return await showDialog<bool>(
            context: context,
            builder: (ctx) => _neutral(
              AlertDialog(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                title: Text(
                  'Discard unsaved changes?',
                  style: _text(19, weight: FontWeight.w700),
                ),
                content: const Text(
                  'Your unsaved working-days entries will be cleared.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Keep Editing'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Discard'),
                  ),
                ],
              ),
            ),
          ) ==
          true;
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _monthChanged(String? value) async {
    if (value == null || _busy || value == _month) return;
    if (!await _discard()) {
      if (mounted) setState(() => _selectionEpoch++);
      return;
    }
    if (!mounted) return;
    setState(() {
      _month = value;
      if (_data != null) _accept(_data!);
    });
  }

  Future<void> _sessionChanged(String? value) async {
    if (value == null || _busy || value == _session) return;
    if (!await _discard()) {
      if (mounted) setState(() => _selectionEpoch++);
      return;
    }
    if (!mounted) return;
    setState(() {
      _session = value;
      _data = {...?_data, 'rows': <Map<String, dynamic>>[], 'loaded': false};
      _error = null;
      _notice = null;
    });
  }

  Future<void> _save() async {
    if (_busy || _submitted || !_current || _changes.isEmpty) return;
    final changes = Map<String, String>.from(_changes);
    final expected = <String, String>{};
    for (final row in _rows) {
      if (!changes.containsKey(row['id'])) continue;
      final cell = _cell(row), value = changes[row['id']]!;
      final number = int.tryParse(value);
      if (!RegExp(r'^\d+$').hasMatch(value) ||
          number == null ||
          value.length > (cell['max_length'] as int) ||
          number < (cell['min'] as int) ||
          number > (cell['max'] as int)) {
        _feedback(
          cell['validation_message'] as String? ??
              'Enter valid whole working days for Class ${row['label']}.',
        );
        return;
      }
      expected[row['id'] as String] = '${cell['value']}';
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final session = _session, month = _month;
    setState(() => _confirming = true);
    bool approved = false;
    try {
      approved =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => _neutral(
              AlertDialog(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                scrollable: true,
                title: Text(
                  'Confirm Working Days',
                  style: _text(19, weight: FontWeight.w700),
                ),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$session · $month',
                        style: _text(13, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      for (final row in _rows)
                        if (changes.containsKey(row['id']))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Class ${row['label']}: ${expected[row['id']]} → ${changes[row['id']]}',
                              style: _text(13),
                            ),
                          ),
                      const SizedBox(height: 6),
                      const Text(
                        'Only these changes will be applied. Other months retain their current portal values.',
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Keep Editing'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Submit'),
                  ),
                ],
              ),
            ),
          ) ==
          true;
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
    if (!approved || !mounted) return;
    if (!_current) {
      _feedback('School login has changed. Reopen Monthly Attendance.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await _service!.save(session, month, changes, expected);
      if (!mounted) return;
      if (!_current) {
        setState(() => _data = null);
        _feedback('School login has changed. Reopen Monthly Attendance.');
        return;
      }
      setState(() {
        _submitted =
            result['submission_attempted'] != false &&
            result['verified'] != true;
        if (result['snapshot'] is Map) {
          _accept(Map<String, dynamic>.from(result['snapshot'] as Map));
        }
      });
      _feedback('${result['message']}', error: result['success'] != true);
    } catch (e) {
      if (mounted) setState(() => _submitted = true);
      _feedback('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _students() async {
    if (_busy || !await _discard() || !mounted) return;
    if (!_current) {
      _feedback('School login has changed. Reopen Monthly Attendance.');
      return;
    }
    setState(() {
      for (final row in _rows) {
        _inputs[row['id']]!.text = '${_cell(row)['value']}';
      }
    });
    // Stay in this module; returning preserves the Working Days page and avoids
    // an automatic network refresh after the accepted route transition.
    final route = appPageRoute<void>(
      builder: (_) => MonthlyStudentAttendanceScreen(
        initialSession: _session,
        initialMonth:
            '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'].indexOf(_month) + 1}',
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
  }

  Widget _steps() => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '1 of 2 · Set working days',
          style: _text(
            12,
            color: const Color(0xFF697586),
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Save each class’s total working days first. Then enter how many days each student attended.',
          style: _text(13),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _students,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: ink,
              side: const BorderSide(color: line),
            ),
            icon: const Icon(CupertinoIcons.person_2, size: 18),
            label: const Text('Student Attendance'),
          ),
        ),
      ],
    ),
  );

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: const BorderSide(color: line),
    ),
  );
  Widget _message(String message, bool error) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: error ? Colors.red.shade100 : Colors.green.shade100,
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!error)
          Image.asset(
            'assets/icons/check.png',
            width: 26,
            height: 26,
            cacheWidth: 104,
            errorBuilder: (_, _, _) => const Icon(
              CupertinoIcons.checkmark_alt,
              color: Color(0xFF16A34A),
            ),
          )
        else
          const Icon(
            CupertinoIcons.exclamationmark_triangle,
            color: Color(0xFFB42318),
            size: 24,
          ),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: _text(12))),
        IconButton(
          tooltip: 'Dismiss message',
          onPressed: () => setState(() {
            if (error) {
              _error = null;
            } else {
              _notice = null;
              _noticeTimer?.cancel();
            }
          }),
          icon: const Icon(CupertinoIcons.xmark, size: 14),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gutter =
        [
          TargetPlatform.windows,
          TargetPlatform.macOS,
          TargetPlatform.linux,
        ].contains(defaultTargetPlatform)
        ? 14.0
        : 0.0;
    return PopScope(
      canPop: !_saving && !_confirming,
      child: Theme(
        data: theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(
            primary: ink,
            secondary: ink,
            surface: Colors.white,
            surfaceTint: Colors.transparent,
          ),
        ),
        child: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: SafeArea(
              bottom: false,
              child: AdaptiveWorkspace(
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    const BackButton(color: ink),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Monthly Attendance',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(16, weight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Reload working days',
                      onPressed: _busy || _service == null ? null : _reload,
                      icon: const Icon(CupertinoIcons.refresh, size: 20),
                    ),
                    SizedBox(width: 8 + gutter),
                  ],
                ),
              ),
            ),
          ),
          body: AdaptiveWorkspace(
            background: true,
            child: PageContentMotion(
              child: Column(
                children: [
                  if (_notice != null || _error != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16 + gutter, 0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_notice != null) _message(_notice!, false),
                              if (_error != null) _message(_error!, true),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false, overscroll: false),
                      child: Scrollbar(
                        controller: _scroll,
                        thumbVisibility: gutter > 0,
                        child: Padding(
                          padding: EdgeInsets.only(right: gutter),
                          child: ListView(
                            controller: _scroll,
                            padding: const EdgeInsets.all(16),
                            children: [
                              _steps(),
                              Text(
                                'Total Working Days',
                                style: _text(19, weight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Set the total days for each class and month',
                                style: _text(
                                  12,
                                  color: const Color(0xFF788292),
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (_sessions.isNotEmpty)
                                LayoutBuilder(
                                  builder: (context, box) {
                                    final selector =
                                        DropdownButtonFormField<String>(
                                          key: ValueKey(
                                            'session/$_session/$_selectionEpoch',
                                          ),
                                          initialValue:
                                              _sessions.any(
                                                (s) => s['id'] == _session,
                                              )
                                              ? _session
                                              : null,
                                          dropdownColor: Colors.white,
                                          isExpanded: true,
                                          decoration: _decoration('Session'),
                                          style: _text(13),
                                          items: [
                                            for (final s in _sessions)
                                              DropdownMenuItem(
                                                value: s['id'] as String,
                                                child: Text('${s['label']}'),
                                              ),
                                          ],
                                          onChanged: _busy
                                              ? null
                                              : _sessionChanged,
                                        );
                                    final show = FilledButton(
                                      onPressed: _busy || _session.isEmpty
                                          ? null
                                          : _load,
                                      child: const Text('Show Working Days'),
                                    );
                                    if (box.maxWidth < 420) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          selector,
                                          const SizedBox(height: 10),
                                          show,
                                        ],
                                      );
                                    }
                                    return Row(
                                      children: [
                                        Expanded(child: selector),
                                        const SizedBox(width: 12),
                                        show,
                                      ],
                                    );
                                  },
                                ),
                              if (_loading)
                                const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: CupertinoActivityIndicator(),
                                ),
                              if (_rows.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    'month/$_month/$_selectionEpoch',
                                  ),
                                  initialValue: _month,
                                  isExpanded: true,
                                  dropdownColor: Colors.white,
                                  decoration: _decoration('Month'),
                                  style: _text(13),
                                  items: [
                                    for (final m in WorkingDaysWorker.months)
                                      DropdownMenuItem(
                                        value: m,
                                        child: Text(m),
                                      ),
                                  ],
                                  onChanged: _busy ? null : _monthChanged,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'मीटिंग की संख्या नहीं भरें  कार्य दिवस भरें , आधे दिन/ एक पारी को भी पूर्ण दिवस मानें ।',
                                  style: _text(
                                    12,
                                    color: const Color(0xFF788292),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: line),
                                  ),
                                  child: Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          14,
                                          12,
                                          14,
                                          0,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                'Class',
                                                style: _text(
                                                  12,
                                                  color: const Color(
                                                    0xFF697586,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 90,
                                              child: Text(
                                                'Working days',
                                                textAlign: TextAlign.center,
                                                style: _text(
                                                  12,
                                                  color: const Color(
                                                    0xFF697586,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      for (final row in _rows)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Class ${row['label']}',
                                                  style: _text(
                                                    14,
                                                    weight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              SizedBox(
                                                width: 90,
                                                child: TextField(
                                                  key: ValueKey(
                                                    'working-days/${row['id']}',
                                                  ),
                                                  controller:
                                                      _inputs[row['id']],
                                                  enabled:
                                                      !_busy &&
                                                      !_submitted &&
                                                      _cell(row)['enabled'] ==
                                                          true,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter
                                                        .digitsOnly,
                                                    LengthLimitingTextInputFormatter(
                                                      _cell(row)['max_length']
                                                          as int,
                                                    ),
                                                  ],
                                                  textAlign: TextAlign.center,
                                                  style: _text(14),
                                                  decoration: _decoration(
                                                    'Days',
                                                  ),
                                                  onChanged: (_) => setState(
                                                    () => _error = null,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                              if (_data?['loaded'] == true && _rows.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'No classes returned by the portal.',
                                  ),
                                ),
                              if (_submitted)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    'Submission was attempted. Reload and verify the portal values before making another update.',
                                    style: _text(
                                      12,
                                      color: const Color(0xFF788292),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed:
                              _busy ||
                                  _submitted ||
                                  _data?['can_save'] != true ||
                                  _changes.isEmpty
                              ? null
                              : _save,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          child: _saving
                              ? const CupertinoActivityIndicator(
                                  color: Colors.white,
                                )
                              : Text('Save $_month Working Days'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
