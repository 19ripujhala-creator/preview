import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shaladarpan/experiments/direct_school_session.dart';
import 'package:shaladarpan/experiments/direct_monthly_attendance_service.dart';
import 'package:shaladarpan/widgets/adaptive_layout.dart';
import 'package:shaladarpan/widgets/page_content_motion.dart';

/// Student register, opened from the Working Days step of Monthly Attendance.
class MonthlyStudentAttendanceScreen extends StatefulWidget {
  const MonthlyStudentAttendanceScreen({
    super.key,
    this.initialSession = '',
    this.initialMonth = '',
  });
  final String initialSession, initialMonth;
  @override
  State<MonthlyStudentAttendanceScreen> createState() =>
      _MonthlyStudentAttendanceScreenState();
}

class _MonthlyStudentAttendanceScreenState
    extends State<MonthlyStudentAttendanceScreen> {
  static const ink = Color(0xFF18212F), line = Color(0xFFE5E9EF);
  final _scroll = ScrollController();
  final _inputs = <String, TextEditingController>{};
  DirectMonthlyAttendanceService? _service;
  Map<String, dynamic>? _data;
  String _school = '', _session = '', _class = '', _section = '', _month = '';
  String? _message;
  bool _error = false,
      _loading = true,
      _saving = false,
      _confirming = false,
      _blocked = false;
  int _epoch = 0;
  Timer? _timer;
  bool get _busy => _loading || _saving || _confirming;
  bool get _current =>
      identical(_service, DirectSchoolSession.monthlyAttendance) &&
      _school == DirectSchoolSession.schoolId;
  List<Map<String, dynamic>> get _rows =>
      ((_data?['rows'] as List?) ?? []).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> _options(String key) =>
      ((_data?[key] as List?) ?? []).cast<Map<String, dynamic>>();
  Map<String, String> get _changes => {
    for (final r in _rows)
      if (r['enabled'] == true && _inputs[r['id']]!.text.trim() != r['value'])
        r['id'] as String: _inputs[r['id']]!.text.trim(),
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _accept(Map<String, dynamic> result) {
    _data = result;
    _session = '${result['session'] ?? ''}';
    _class = '${result['class_id'] ?? ''}';
    _section = '${result['section'] ?? ''}';
    _month = '${result['month'] ?? ''}';
    for (final c in _inputs.values) {
      c.dispose();
    }
    _inputs.clear();
    for (final r in _rows) {
      _inputs[r['id'] as String] = TextEditingController(text: '${r['value']}');
    }
    _epoch++;
  }

  void _feedback(String message, {bool error = true}) {
    if (!mounted) return;
    _timer?.cancel();
    setState(() {
      _message = message;
      _error = error;
    });
    if (!error) {
      _timer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _message = null);
      });
    }
  }

  void _checkCurrent() {
    if (!_current) {
      throw StateError('School login has changed. Reopen Monthly Attendance.');
    }
  }

  Future<void> _open() async {
    _service = DirectSchoolSession.monthlyAttendance;
    _school = DirectSchoolSession.schoolId;
    if (_service == null) {
      setState(() => _loading = false);
      _feedback('School login is required.');
      return;
    }
    try {
      final result = await _service!.open();
      if (!mounted) return;
      _checkCurrent();
      if (result['success'] != true) {
        _feedback('${result['message']}');
        return;
      }
      setState(() {
        _accept(result);
        if (widget.initialSession.isNotEmpty) {
          _session =
              _options('sessions').any((o) => o['id'] == widget.initialSession)
              ? widget.initialSession
              : '';
        }
        if (widget.initialMonth.isNotEmpty) {
          _month = _options('months').any((o) => o['id'] == widget.initialMonth)
              ? widget.initialMonth
              : '';
        }
        _blocked = false;
      });
      final messages = (result['messages'] as List?) ?? [];
      if (messages.isNotEmpty) _feedback(messages.join('\n'));
    } catch (e) {
      _feedback('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _discard() async {
    if (_changes.isEmpty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => _neutral(
            AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              title: const Text('Discard attendance changes?'),
              content: const Text('Your unsaved entries will be lost.'),
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
  }

  Future<void> _select(String key, String? value) async {
    if (value == null || _busy) return;
    if (!await _discard() || !mounted) {
      if (mounted) setState(() => _epoch++);
      return;
    }
    setState(() {
      if (key == 'session') _session = value;
      if (key == 'class_id') _class = value;
      if (key == 'section') _section = value;
      if (key == 'month') _month = value;
      _data = {...?_data, 'rows': <Map<String, dynamic>>[], 'loaded': false};
      for (final c in _inputs.values) {
        c.dispose();
      }
      _inputs.clear();
      _message = null;
      _epoch++;
    });
  }

  Future<void> _load({bool reload = false}) async {
    if (_busy) return;
    if (!await _discard() || !mounted) return;
    if ([_session, _class, _section, _month].any((s) => s.isEmpty)) {
      if (reload) {
        setState(() => _loading = true);
        await _open();
      } else {
        _feedback('Select session, class, section and month.');
      }
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      _checkCurrent();
      final result = await _service!.load(_session, _class, _section, _month);
      if (!mounted) return;
      _checkCurrent();
      if (result['success'] == true) {
        setState(() {
          _accept(result);
          _blocked = false;
        });
        final messages = (result['messages'] as List?) ?? [];
        if (messages.isNotEmpty) _feedback(messages.join('\n'));
      } else {
        setState(
          () => _data = {
            ...?_data,
            'rows': <Map<String, dynamic>>[],
            'loaded': false,
          },
        );
        _feedback('${result['message']}');
      }
    } catch (e) {
      if (mounted) setState(() => _data = null);
      _feedback('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _blocked || _changes.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final changes = Map<String, String>.from(_changes);
    final expected = [for (final r in _rows) Map<String, dynamic>.from(r)];
    for (final r in expected.where((r) => changes.containsKey(r['id']))) {
      final text = changes[r['id']]!, number = int.tryParse(text);
      if (!RegExp(r'^\d+$').hasMatch(text) ||
          number == null ||
          number < 0 ||
          number > (r['working_days'] as int) ||
          text.length > (r['max_length'] as int)) {
        _feedback(
          'Enter attendance from 0 to ${r['working_days']} for ${r['name']}.',
        );
        return;
      }
    }
    final session = _session,
        klass = _class,
        section = _section,
        month = _month;
    bool approved = false;
    setState(() => _confirming = true);
    try {
      approved =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => _neutral(
              AlertDialog(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                title: const Text('Confirm Monthly Attendance'),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$session • Class $klass / ${_label('sections', section)} • ${_label('months', month)}',
                        ),
                        const SizedBox(height: 12),
                        for (final r in expected.where(
                          (r) => changes.containsKey(r['id']),
                        ))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              '${r['name']} (SR ${r['sr_no']})\n${r['value']} → ${changes[r['id']]} / ${r['working_days']} days',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Keep Editing'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save Attendance'),
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
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      _checkCurrent();
      final result = await _service!.save(
        session,
        klass,
        section,
        month,
        changes,
        expected,
      );
      if (!mounted) return;
      _checkCurrent();
      setState(() {
        _blocked =
            result['submission_attempted'] != false &&
            result['verified'] != true;
        if (result['snapshot'] is Map) {
          _accept(Map<String, dynamic>.from(result['snapshot'] as Map));
        }
      });
      _feedback('${result['message']}', error: result['success'] != true);
    } catch (e) {
      if (mounted) setState(() => _blocked = true);
      _feedback('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _label(String key, String value) =>
      '${_options(key).where((o) => o['id'] == value).firstOrNull?['label'] ?? value}';
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
  Widget _dropdown(String key, String source, String label, String value) =>
      DropdownButtonFormField<String>(
        key: ValueKey('attendance/$key/$value/$_epoch'),
        initialValue: _options(source).any((o) => o['id'] == value)
            ? value
            : null,
        isExpanded: true,
        dropdownColor: Colors.white,
        decoration: _decoration(label),
        style: _text(13),
        items: [
          for (final o in _options(source))
            DropdownMenuItem(
              value: o['id'] as String,
              child: Text('${o['label']}'),
            ),
        ],
        onChanged: _busy ? null : (value) => _select(key, value),
      );
  Widget _notice() => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: _error ? Colors.red.shade100 : Colors.green.shade100,
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_error)
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
            size: 22,
          ),
        const SizedBox(width: 10),
        Expanded(child: Text(_message!, style: _text(12))),
        IconButton(
          tooltip: 'Dismiss message',
          onPressed: () => setState(() => _message = null),
          icon: const Icon(CupertinoIcons.xmark, size: 14),
        ),
      ],
    ),
  );
  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Student Attendance', style: _text(19, weight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(
        '2 of 2 · Enter days attended for each student.',
        style: _text(12, color: const Color(0xFF697586)),
      ),
      const SizedBox(height: 16),
      if (_data != null)
        LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth >= 850
                ? (box.maxWidth - 36) / 4
                : box.maxWidth >= 540
                ? (box.maxWidth - 12) / 2
                : box.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: width,
                  child: _dropdown('session', 'sessions', 'Session', _session),
                ),
                SizedBox(
                  width: width,
                  child: _dropdown('class_id', 'classes', 'Class', _class),
                ),
                SizedBox(
                  width: width,
                  child: _dropdown('section', 'sections', 'Section', _section),
                ),
                SizedBox(
                  width: width,
                  child: _dropdown('month', 'months', 'Month', _month),
                ),
              ],
            );
          },
        ),
      const SizedBox(height: 12),
      if (_data != null)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _busy ? null : _load,
            icon: const Icon(CupertinoIcons.person_2, size: 18),
            label: const Text('Show Students'),
          ),
        ),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(24),
          child: CupertinoActivityIndicator(),
        ),
      if (_data?['loaded'] == true && !_loading) ...[
        const SizedBox(height: 16),
        Text(
          '${_rows.length} students · ${_changes.length} changed',
          style: _text(13, weight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          _rows.isEmpty ? 'No students returned for this selection.' : 'Attendance cannot exceed the working days shown by the portal.',
          style: _text(12, color: const Color(0xFF697586)),
        ),
        if (_rows.any((r) => r['working_days'] == 0))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Working days are 0 for some students. Go back to Working Days, save the correct days, then reload this list.',
              style: _text(12, color: const Color(0xFFB45309)),
            ),
          ),
        const SizedBox(height: 12),
      ],
    ],
  );
  Widget _student(Map<String, dynamic> row) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: line),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${row['name']}', style: _text(14, weight: FontWeight.w600)),
              const SizedBox(height: 5),
              Text(
                'SR ${row['sr_no']} · ${row['working_days']} working days',
                style: _text(12, color: const Color(0xFF697586)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 96,
          child: TextField(
            key: ValueKey('monthly-attendance/${row['id']}'),
            controller: _inputs[row['id']],
            enabled:
                !_busy &&
                !_blocked &&
                row['enabled'] == true &&
                _data?['can_save'] == true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: _text(15, weight: FontWeight.w600),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(row['max_length'] as int),
            ],
            decoration: _decoration('Attended'),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context),
        desktop = [
          TargetPlatform.windows,
          TargetPlatform.linux,
          TargetPlatform.macOS,
        ].contains(defaultTargetPlatform);
    final gutter = desktop ? 14.0 : 0.0;
    return PopScope(
      canPop: !_saving && !_confirming && _changes.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _busy) return;
        if (await _discard() && mounted) {
          setState(() {
            for (final r in _rows) {
              _inputs[r['id']]!.text = '${r['value']}';
            }
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
        }
      },
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
                      tooltip: 'Reload attendance',
                      onPressed: _busy ? null : () => _load(reload: true),
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
                  if (_message != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16 + gutter, 0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: SingleChildScrollView(child: _notice()),
                      ),
                    ),
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false, overscroll: false),
                      child: Scrollbar(
                        controller: _scroll,
                        thumbVisibility: desktop,
                        child: Padding(
                          padding: EdgeInsets.only(right: gutter),
                          child: CustomScrollView(
                            controller: _scroll,
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  0,
                                ),
                                sliver: SliverToBoxAdapter(child: _header()),
                              ),
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                sliver: SliverList.builder(
                                  itemCount: _rows.length,
                                  itemBuilder: (context, index) =>
                                      _student(_rows[index]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_rows.isNotEmpty)
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 10, 16 + gutter, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_blocked)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Reload and check portal attendance before another save.',
                                  style: _text(
                                    12,
                                    color: const Color(0xFFB45309),
                                  ),
                                ),
                              ),
                            FilledButton(
                              onPressed:
                                  _busy ||
                                      _blocked ||
                                      _changes.isEmpty ||
                                      _data?['can_save'] != true
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
                                  : Text(
                                      'Save Attendance (${_changes.length})',
                                    ),
                            ),
                          ],
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
