import 'dart:async';

import 'package:shaladarpan/widgets/page_content_motion.dart';
import 'package:shaladarpan/widgets/page_transitions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shaladarpan/widgets/adaptive_layout.dart';
import 'package:shaladarpan/widgets/route_completion.dart';

import '../../../../experiments/direct_format5_service.dart';
import '../../../../experiments/direct_school_session.dart';

// Match Student Desk's compact Plus Jakarta Sans / neutral-card language.
// Only this screen is changed; the shared session and other student modules
// continue to own their existing UI/state.
class _F5Style {
  static const ink = Color(0xFF18212F);
  static const muted = Color(0xFF788292);
  static const line = Color(0xFFE5E9EF);
  static const page = Color(0xFFF8FAFC);
  static const fill = Color(0xFFF4F6F9);
  static const danger = Color(0xFFB42318);
  static TextStyle text(
    double size, {
    Color color = ink,
    FontWeight weight = FontWeight.w500,
  }) => TextStyle(
    fontFamily: 'PlusJakartaSans',
    fontSize: size,
    color: color,
    fontWeight: weight,
  );
  static InputDecoration input(String hint, {IconData? icon}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: text(12, color: muted),
        prefixIcon: icon == null ? null : Icon(icon, size: 18, color: muted),
        isDense: true,
        filled: true,
        fillColor: fill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: line),
          borderRadius: BorderRadius.circular(11),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: line),
          borderRadius: BorderRadius.circular(11),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: ink),
          borderRadius: BorderRadius.circular(11),
        ),
        disabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: line),
          borderRadius: BorderRadius.circular(11),
        ),
      );
  static BoxDecoration card() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: line),
    boxShadow: const [
      BoxShadow(color: Color(0x060F172A), blurRadius: 12, offset: Offset(0, 3)),
    ],
  );
  static ButtonStyle button() => FilledButton.styleFrom(
    backgroundColor: ink,
    foregroundColor: Colors.white,
    disabledBackgroundColor: const Color(0xFFD9DEE5),
    disabledForegroundColor: muted,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    minimumSize: const Size(0, 44),
  );
}

class _F5Theme extends StatelessWidget {
  const _F5Theme({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: _F5Style.ink,
          secondary: _F5Style.ink,
          surface: Colors.white,
          onSurface: _F5Style.ink,
          surfaceTint: Colors.transparent,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: _F5Style.ink,
          selectionColor: Color(0xFFDDE3EB),
          selectionHandleColor: _F5Style.ink,
        ),
      ),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context)
            .copyWith(overscroll: false, scrollbars: false),
        child: child,
      ),
    );
  }
}

class _F5Header extends StatelessWidget implements PreferredSizeWidget {
  const _F5Header({required this.title, this.actions = const []});
  final String title;
  final List<Widget> actions;
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: LayoutBuilder(
      builder: (context, viewport) => Center(
        child: SizedBox(
          width: AppAdaptive.contentWidth(viewport.maxWidth),
          height: kToolbarHeight,
          child: Row(
            children: [
              const SizedBox(width: 8),
              const BackButton(color: _F5Style.ink),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _F5Style.text(16, weight: FontWeight.w600),
                ),
              ),
              ...actions,
              SizedBox(width: 8 + _F5ScrollSurface.trailingGutter),
            ],
          ),
        ),
      ),
    ),
  );
}

class _F5ScrollSurface extends StatelessWidget {
  const _F5ScrollSurface({required this.controller, required this.child});
  final ScrollController controller;
  final Widget child;
  // Header actions and scroll content reserve the same desktop gutter.
  static double get trailingGutter =>
      [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ].contains(defaultTargetPlatform)
      ? 14
      : 0;

  @override
  Widget build(BuildContext context) {
    final gutter = trailingGutter;
    if (gutter == 0) return child;
    return Scrollbar(
      key: const ValueKey('format5-scrollbar'),
      controller: controller,
      thumbVisibility: true,
      interactive: true,
      thickness: 6,
      radius: const Radius.circular(4),
      child: Padding(
        padding: EdgeInsets.only(right: gutter),
        child: child,
      ),
    );
  }
}

class _F5EqualPanels extends StatelessWidget {
  const _F5EqualPanels({
    required this.first,
    required this.second,
    this.breakpoint = 900,
    this.gap = 16,
    this.stackedGap = 12,
    this.firstFlex = 1,
    this.secondFlex = 2,
  });
  final Widget first, second;
  final double breakpoint, gap, stackedGap;
  final int firstFlex, secondFlex;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
        1.0,
        1.5,
      );
      if (box.maxWidth < breakpoint * scale) {
        return Column(
          children: [
            first,
            SizedBox(height: stackedGap),
            second,
          ],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: firstFlex, child: first),
            SizedBox(width: gap),
            Expanded(flex: secondFlex, child: second),
          ],
        ),
      );
    },
  );
}

class _F5Notice extends StatelessWidget {
  const _F5Notice({
    required this.message,
    required this.error,
    required this.onDismiss,
  });
  final String message;
  final bool error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Container(
      key: ValueKey(error ? 'format5-error-notice' : 'format5-success-notice'),
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFFF8F7) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: error ? const Color(0xFFF1D4D0) : const Color(0xFFD9EAE0),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x050F172A),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: error
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(
                      CupertinoIcons.exclamationmark_triangle_fill,
                      size: 22,
                      color: _F5Style.danger,
                    ),
                  )
                : Image.asset(
                    'assets/icons/check.png',
                    key: const ValueKey('format5-success-badge'),
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                    cacheWidth: 104,
                    excludeFromSemantics: true,
                    errorBuilder: (_, __, ___) => const Icon(
                      CupertinoIcons.checkmark_alt,
                      size: 24,
                      color: Color(0xFF16A34A),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(
                message,
                style: _F5Style.text(
                  12,
                  color: error ? _F5Style.danger : _F5Style.ink,
                ).copyWith(height: 1.5),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: error
                ? 'Dismiss error message'
                : 'Dismiss success message',
            onPressed: onDismiss,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: const EdgeInsets.all(10),
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              backgroundColor: _F5Style.fill,
              foregroundColor: _F5Style.muted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(CupertinoIcons.xmark, size: 14),
          ),
        ],
      ),
    ),
  );
}

class Format5Screen extends StatefulWidget {
  const Format5Screen({super.key});

  @override
  State<Format5Screen> createState() => _Format5ScreenState();
}

class _Format5ScreenState extends State<Format5Screen> {
  DirectFormat5Service? _service;
  final _search = TextEditingController();
  final _listScroll = ScrollController();
  final _messageAnchor = GlobalKey();
  bool _messageScrollScheduled = false;
  bool _loading = true;
  bool _working = false;
  bool _listLoaded = false;
  String? _error;
  String? _notice;
  Timer? _noticeTimer;
  String? _school;
  String? _editingNic;
  String _session = '', _classId = '', _section = '';
  List<Map<String, String>> _sessions = [], _classes = [], _sections = [];
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _search.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  static List<Map<String, String>> _options(Object? raw) => [
    if (raw is List)
      for (final item in raw)
        if (item is Map)
          {
            'id': '${item['id'] ?? ''}',
            'label': '${item['label'] ?? item['id'] ?? ''}',
          },
  ];

  static List<Map<String, dynamic>> _rows(Object? raw) => [
    if (raw is List)
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
  ];

  bool get _sameSession =>
      _service != null &&
      identical(_service, DirectSchoolSession.format5) &&
      _school == DirectSchoolSession.schoolId;

  void _accept(Map<String, dynamic> result, {required bool loaded}) {
    _sessions = _options(result['sessions']);
    _classes = _options(result['classes']);
    _sections = _options(result['sections']);
    String choice(String key, String old, List<Map<String, String>> options) {
      final portal = '${result[key] ?? ''}';
      if (options.any((option) => option['id'] == portal)) return portal;
      if (options.any((option) => option['id'] == old)) return old;
      return options.isEmpty ? '' : options.first['id']!;
    }

    _session = choice('session', _session, _sessions);
    _classId = choice('class_id', _classId, _classes);
    _section = choice('section', _section, _sections);
    _students = _rows(result['students']);
    _listLoaded = loaded;
  }

  void _clearNotice() {
    _noticeTimer?.cancel();
    _noticeTimer = null;
    _notice = null;
  }

  void _scheduleNoticeDismiss() {
    _noticeTimer?.cancel();
    final notice = _notice;
    if (notice == null) return;
    _noticeTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _notice == notice) setState(_clearNotice);
    });
  }

  void _report(String message, {bool error = true}) {
    if (!mounted) return;
    setState(() {
      if (error) {
        _error = message;
        if (_notice == message) _clearNotice();
      } else {
        _error = null;
        _notice = message;
      }
    });
    if (!error) _scheduleNoticeDismiss();
    if (!_messageScrollScheduled) {
      _messageScrollScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _messageScrollScheduled = false;
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        final anchor = _messageAnchor.currentContext;
        if (anchor != null) {
          Scrollable.ensureVisible(
            anchor,
            duration: const Duration(milliseconds: 180),
          );
        }
      });
    }
  }

  Future<void> _open() async {
    if (!mounted || _working || (_loading && _service != null)) return;
    final service = DirectSchoolSession.format5;
    if (service == null) {
      setState(() {
        _loading = false;
        _error = 'Direct School login is required.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _service = service;
      _school = DirectSchoolSession.schoolId;
      _error = null;
      _clearNotice();
      _listLoaded = false;
      _students = [];
    });
    try {
      final result = await service.open();
      if (!mounted) return;
      if (!_sameSession) {
        setState(() {
          _students = [];
          _listLoaded = false;
        });
        _report('School login has changed. Reopen Format 5.');
        return;
      }
      if (result['success'] == true) {
        setState(() => _accept(result, loaded: false));
      } else {
        _report('${result['message'] ?? 'Format-5 could not load.'}');
      }
    } catch (error) {
      _report('$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _show({bool keepNotice = false}) async {
    if (_loading ||
        _working ||
        !_sameSession ||
        _session.isEmpty ||
        _classId.isEmpty ||
        _section.isEmpty) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (keepNotice) _noticeTimer?.cancel();
    setState(() {
      _working = true;
      _listLoaded = false;
      if (!keepNotice) {
        _error = null;
        _clearNotice();
      }
    });
    try {
      final result = await _service!.list(_session, _classId, _section);
      if (!mounted) return;
      if (!_sameSession) {
        setState(() {
          _students = [];
          _listLoaded = false;
        });
        _report('School login has changed. Reopen Format 5.');
        return;
      }
      if (result['success'] == true) {
        setState(() => _accept(result, loaded: true));
      } else {
        _report('${result['message'] ?? 'Format-5 list unavailable.'}');
      }
    } catch (error) {
      _report('$error');
    } finally {
      if (mounted) {
        setState(() => _working = false);
        if (keepNotice) _scheduleNoticeDismiss();
      }
    }
  }

  Future<void> _edit(Map<String, dynamic> student) async {
    if (_loading || _working || !_sameSession || _editingNic != null) return;
    final nic = '${student['nic_id'] ?? ''}'.trim();
    if (nic.isEmpty) {
      _report('The student record has no NIC ID. Refresh the list.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.selectionClick();
    setState(() {
      _working = true;
      _editingNic = nic;
      _error = null;
      _clearNotice();
    });
    Future<Map<String, dynamic>>? preparing;
    try {
      final service = _service!;
      preparing = service
          .edit(nic)
          .then<Map<String, dynamic>>(
            (result) => result,
            onError: (Object error, StackTrace stack) => <String, dynamic>{
              'success': false,
              'message': '$error',
            },
          );

      var updateAttempted = false;
      final outcome = await pushPageAndWaitForExit<Map<String, dynamic>>(
        context,
        appPageRoute<Map<String, dynamic>>(
          builder: (_) => _Format5EditScreen(
            service: service,
            expectedSchool: _school ?? '',
            student: student,
            fields: preparing!,
            onUpdateAttempted: () => updateAttempted = true,
          ),
        ),
      );
      await preparing;
      if (!mounted) return;
      setState(() {
        _working = false;
        _editingNic = null;
      });
      if (!_sameSession) {
        setState(() {
          _students = [];
          _listLoaded = false;
        });
        _report('School login has changed. Reopen Format 5.');
        return;
      }
      if (outcome != null) {
        final message = '${outcome['message'] ?? ''}'.trim();
        // Read-only refresh. Saving is NEVER retried automatically.
        if (message.isNotEmpty) {
          _report(message, error: outcome['success'] != true);
        }
        await _show(keepNotice: true);
      } else if (updateAttempted) {
        // An uncertain Update may have reached the portal. Read current data
        // after leaving that form; this must never replay the submission.
        await _show();
      }
      // Back/Cancel without an Update attempt keeps the displayed list and
      // scroll/search state. The worker reuses only a fresh, untouched Edit form.
    } catch (error) {
      if (mounted) setState(() => _listLoaded = false);
      _report('$error');
    } finally {
      await preparing;
      if (mounted) {
        setState(() {
          _working = false;
          _editingNic = null;
        });
      }
    }
  }

  Widget _picker(
    String title,
    List<Map<String, String>> options,
    String selected,
    ValueChanged<String?> callback,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: _F5Style.text(
          11,
          color: _F5Style.muted,
          weight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(12),
        key: ValueKey('$title/$selected/${options.length}'),
        initialValue: options.any((e) => e['id'] == selected) ? selected : null,
        isExpanded: true,
        style: _F5Style.text(12, weight: FontWeight.w600),
        decoration: _F5Style.input('Select $title'),
        items: [
          for (final option in options)
            DropdownMenuItem(
              value: option['id'],
              child: Text(option['label']!, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: _loading || _working ? null : callback,
      ),
    ],
  );

  Widget _studentTile(Map<String, dynamic> student, int number) {
    final nic = '${student['nic_id'] ?? ''}';
    final busy = _editingNic == nic;
    return Container(
      key: ValueKey('format5-student-$nic'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: _F5Style.card(),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _working ? null : () => _edit(student),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _F5Style.fill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$number',
                  style: _F5Style.text(11, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${student['name'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _F5Style.text(13, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SR ${student['sr_no'] ?? '-'}  ·  ${student['father'] ?? '-'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _F5Style.text(11, color: _F5Style.muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${student['category'] ?? '-'}  ·  ${student['mobile'] ?? '-'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _F5Style.text(10, color: _F5Style.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: _F5Style.fill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: busy
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CupertinoActivityIndicator(radius: 8),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            CupertinoIcons.pencil,
                            color: _F5Style.ink,
                            size: 15,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Edit',
                            style: _F5Style.text(11, weight: FontWeight.w700),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final visible = _students
        .where(
          (student) =>
              q.isEmpty ||
              [
                'name',
                'sr_no',
                'nic_id',
                'father',
                'mother',
              ].any((key) => '${student[key] ?? ''}'.toLowerCase().contains(q)),
        )
        .toList();
    return _F5Theme(
      child: Scaffold(
        backgroundColor: _F5Style.page,
        appBar: _F5Header(
          title: 'Format 5',
          actions: [
            IconButton(
              tooltip: 'Refresh portal',
              onPressed: _loading || _working ? null : _open,
              icon: const Icon(CupertinoIcons.refresh, size: 20),
            ),
          ],
        ),
        body: AdaptiveWorkspace(
          background: true,
          child: PageContentMotion(
            child: Center(
              child: SizedBox.expand(
                key: const ValueKey('format5-list-workspace'),
                child: _loading
                    ? const Center(child: CupertinoActivityIndicator())
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                        child: _F5ScrollSurface(
                          controller: _listScroll,
                          child: CustomScrollView(
                            controller: _listScroll,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            slivers: [
                              SliverToBoxAdapter(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (MediaQuery.viewInsetsOf(context)
                                            .bottom ==
                                        0)
                                      Container(
                                        decoration: _F5Style.card(),
                                        padding: const EdgeInsets.all(14),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(
                                                  CupertinoIcons.person_2,
                                                  size: 18,
                                                  color: _F5Style.ink,
                                                ),
                                                const SizedBox(width: 9),
                                                Expanded(
                                                  child: Text(
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    'Student Profiles',
                                                    style: _F5Style.text(
                                                      13,
                                                      weight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Portal data',
                                                  style: _F5Style.text(
                                                    10,
                                                    color: _F5Style.muted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 13),
                                            _picker(
                                              'Session',
                                              _sessions,
                                              _session,
                                              (value) => setState(() {
                                                _session = value ?? '';
                                                _students = [];
                                                _listLoaded = false;
                                                _error = null;
                                                _clearNotice();
                                              }),
                                            ),
                                            const SizedBox(height: 10),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: _picker(
                                                    'Class',
                                                    _classes,
                                                    _classId,
                                                    (value) => setState(() {
                                                      _classId = value ?? '';
                                                      _students = [];
                                                      _listLoaded = false;
                                                      _error = null;
                                                      _clearNotice();
                                                    }),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: _picker(
                                                    'Section',
                                                    _sections,
                                                    _section,
                                                    (value) => setState(() {
                                                      _section = value ?? '';
                                                      _students = [];
                                                      _listLoaded = false;
                                                      _error = null;
                                                      _clearNotice();
                                                    }),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            SizedBox(
                                              height: 43,
                                              child: FilledButton.icon(
                                                style: _F5Style.button(),
                                                onPressed:
                                                    _working ||
                                                        !_sameSession ||
                                                        _session.isEmpty ||
                                                        _classId.isEmpty ||
                                                        _section.isEmpty
                                                    ? null
                                                    : _show,
                                                icon: _working
                                                    ? const SizedBox(
                                                        width: 17,
                                                        height: 17,
                                                        child:
                                                            CupertinoActivityIndicator(
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      )
                                                    : const Icon(
                                                        CupertinoIcons.search,
                                                        size: 17,
                                                      ),
                                                label: Text(
                                                  _working
                                                      ? 'Loading from portal…'
                                                      : 'Show Students',
                                                  style: _F5Style.text(
                                                    12,
                                                    color: Colors.white,
                                                    weight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (_notice != null || _error != null)
                                      Column(
                                        key: _messageAnchor,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          for (final message in [
                                            if (_notice != null)
                                              (_notice!, false),
                                            if (_error != null) (_error!, true),
                                          ])
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 10,
                                              ),
                                              child: _F5Notice(
                                                message: message.$1,
                                                error: message.$2,
                                                onDismiss: () => setState(() {
                                                  if (message.$2) {
                                                    _error = null;
                                                  } else {
                                                    _clearNotice();
                                                  }
                                                }),
                                              ),
                                            ),
                                        ],
                                      ),
                                    const SizedBox(height: 13),
                                    TextField(
                                      key: const ValueKey('format5-search'),
                                      controller: _search,
                                      onChanged: (_) => setState(() {}),
                                      style: _F5Style.text(12),
                                      decoration: _F5Style.input(
                                        'Search name, SR number or NIC ID',
                                        icon: CupertinoIcons.search,
                                      ),
                                    ),
                                    const SizedBox(height: 11),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            'STUDENT LIST',
                                            style: _F5Style.text(
                                              11,
                                              weight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _listLoaded
                                              ? '${visible.length} of ${_students.length}'
                                              : 'Select a class',
                                          style: _F5Style.text(
                                            11,
                                            color: _F5Style.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 9),
                                  ],
                                ),
                              ),
                              if (!_listLoaded || visible.isEmpty)
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Center(
                                    child: Text(
                                      !_listLoaded
                                          ? 'Choose a class and tap Show Students'
                                          : _students.isEmpty
                                          ? 'No students found for this class'
                                          : 'No matching students',
                                      textAlign: TextAlign.center,
                                      style: _F5Style.text(
                                        12,
                                        color: _F5Style.muted,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                SliverList.builder(
                                  itemCount: visible.length,
                                  itemBuilder: (_, index) =>
                                      _studentTile(visible[index], index + 1),
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dedicated edit page: a tap always opens a visible screen or shows a visible
/// portal error on the list. No modal constrained by keyboard/sheet height.
class _Format5EditScreen extends StatefulWidget {
  const _Format5EditScreen({
    required this.service,
    required this.expectedSchool,
    required this.student,
    required this.fields,
    required this.onUpdateAttempted,
  });
  final DirectFormat5Service service;
  final String expectedSchool;
  final Map<String, dynamic> student;
  final Future<Map<String, dynamic>> fields;
  final VoidCallback onUpdateAttempted;

  @override
  State<_Format5EditScreen> createState() => _Format5EditScreenState();
}

class _Format5EditScreenState extends State<_Format5EditScreen> {
  late final TextEditingController _sr, _mobile;
  final _editScroll = ScrollController();
  late String _category;
  Map<String, dynamic> _fields = {};
  bool _preparing = true, _ready = false;
  bool _saving = false;
  bool _confirming = false;
  bool get _busy => _saving || _confirming;
  bool get _sessionCurrent =>
      identical(widget.service, DirectSchoolSession.format5) &&
      widget.expectedSchool == DirectSchoolSession.schoolId;
  bool _submitted = false;
  String? _error;

  Map<String, dynamic> _field(String key) {
    final value = _fields[key];
    if (value is Map) return Map<String, dynamic>.from(value);
    final cached = '${widget.student[key] ?? ''}';
    return {
      'enabled': false,
      'value': cached,
      if (key == 'category' && cached.isNotEmpty)
        'options': [
          {'id': cached, 'label': cached},
        ],
    };
  }

  List<Map<String, String>> get _categories =>
      _Format5ScreenState._options(_field('category')['options']);

  @override
  void initState() {
    super.initState();
    _sr = TextEditingController(text: '${_field('sr_no')['value'] ?? ''}');
    _mobile = TextEditingController(text: '${_field('mobile')['value'] ?? ''}');
    _category = '${_field('category')['value'] ?? ''}';
    _loadFields();
  }

  Future<void> _loadFields() async {
    final result = await widget.fields;
    if (!mounted) return;
    setState(() {
      _preparing = false;
      if (!_sessionCurrent) {
        _error = 'School login has changed. Reopen Format 5.';
      } else if (result['success'] != true) {
        _error =
            '${result['message'] ?? 'The portal did not open this student for editing.'}';
      } else {
        _fields = result;
        _ready = true;
        _sr.text = '${_field('sr_no')['value'] ?? ''}';
        _mobile.text = '${_field('mobile')['value'] ?? ''}';
        _category = '${_field('category')['value'] ?? ''}';
      }
    });
  }

  @override
  void dispose() {
    _editScroll.dispose();
    _sr.dispose();
    _mobile.dispose();
    super.dispose();
  }

  String _detail(String key) {
    final value = '${_field(key)['value'] ?? ''}'.trim();
    return value.isEmpty ? '${widget.student[key] ?? ''}' : value;
  }

  String _categoryLabel(String id) =>
      _categories
          .where((option) => option['id'] == id)
          .map((option) => option['label']!)
          .firstOrNull ??
      id;

  List<({String label, String before, String after})> get _changes => [
    if (_field('sr_no')['enabled'] == true &&
        _sr.text.trim() != '${_field('sr_no')['value'] ?? ''}'.trim())
      (
        label: 'SR Number',
        before: '${_field('sr_no')['value'] ?? ''}',
        after: _sr.text.trim(),
      ),
    if (_field('category')['enabled'] == true &&
        _category != '${_field('category')['value'] ?? ''}')
      (
        label: 'Caste Category',
        before: _categoryLabel('${_field('category')['value'] ?? ''}'),
        after: _categoryLabel(_category),
      ),
    if (_field('mobile')['enabled'] == true &&
        _mobile.text.trim() != '${_field('mobile')['value'] ?? ''}'.trim())
      (
        label: 'Parent / Guardian Mobile',
        before: '${_field('mobile')['value'] ?? ''}',
        after: _mobile.text.trim(),
      ),
  ];
  bool get _changed => _changes.isNotEmpty;

  Widget _reviewValue(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: _F5Style.text(10, color: _F5Style.muted)),
      const SizedBox(height: 4),
      Text(
        value.isEmpty ? '—' : value,
        style: _F5Style.text(13, weight: FontWeight.w600),
      ),
    ],
  );

  Widget _label(String name, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 106,
          child: Text(name, style: _F5Style.text(12, color: _F5Style.muted)),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: _F5Style.text(13, weight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Future<void> _save() async {
    if (!_ready || _busy || _submitted || !_changed) return;
    if (!_sessionCurrent) {
      setState(() => _error = 'School login has changed. Reopen Format 5.');
      return;
    }
    if (_field('sr_no')['enabled'] == true &&
        !RegExp(r'^\d{1,10}$').hasMatch(_sr.text.trim())) {
      setState(() => _error = 'Enter a valid SR Number.');
      return;
    }
    if (_field('mobile')['enabled'] == true &&
        !RegExp(r'^\d{10}$').hasMatch(_mobile.text.trim())) {
      setState(() => _error = 'Enter a valid 10-digit mobile number.');
      return;
    }
    final sr = _sr.text.trim(),
        mobile = _mobile.text.trim(),
        category = _category;
    final changes = _changes;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _confirming = true);
    bool? approved;
    try {
      approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => _F5Theme(
          child: AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            scrollable: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Confirm Update',
              style: _F5Style.text(16, weight: FontWeight.w700),
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${widget.student['name'] ?? 'Student'}',
                    style: _F5Style.text(14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'NIC ID: ${widget.student['nic_id'] ?? ''}',
                    style: _F5Style.text(11, color: _F5Style.muted),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Review these changes before updating the student in ShalaDarpan.',
                    style: _F5Style.text(12, color: _F5Style.muted),
                  ),
                  for (final change in changes)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _F5Style.fill,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              change.label,
                              style: _F5Style.text(11, weight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _reviewValue('Current', change.before),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  child: Icon(
                                    CupertinoIcons.arrow_right,
                                    size: 16,
                                    color: _F5Style.muted,
                                  ),
                                ),
                                Expanded(
                                  child: _reviewValue('New', change.after),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(
                  foregroundColor: _F5Style.ink,
                  overlayColor: _F5Style.ink,
                  surfaceTintColor: Colors.transparent,
                ),
                child: Text(
                  'Keep Editing',
                  style: _F5Style.text(12, weight: FontWeight.w600),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: _F5Style.button().copyWith(
                  surfaceTintColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  overlayColor: const WidgetStatePropertyAll(Color(0x1AFFFFFF)),
                ),
                child: Text(
                  'Update',
                  style: _F5Style.text(
                    12,
                    color: Colors.white,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
    if (approved != true || !mounted) return;
    if (!_sessionCurrent) {
      setState(() => _error = 'School login has changed. Reopen Format 5.');
      return;
    }
    setState(() {
      _saving = true;
      _submitted = true;
      _error = null;
    });
    widget.onUpdateAttempted();
    try {
      final result = await widget.service.save(
        '${widget.student['nic_id'] ?? ''}',
        srNo: sr,
        category: category,
        mobile: mobile,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        Navigator.pop(context, result);
        return;
      }
      setState(() {
        _error = '${result['message'] ?? 'Portal update was not confirmed.'}';
        // Release button only for a definitive pre-submit validation failure;
        // never resubmit when the portal may already have processed the update.
        if (result['submission_attempted'] == false) _submitted = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _footer() {
    final cancel = OutlinedButton(
      onPressed: _busy ? null : () => Navigator.pop(context),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        disabledBackgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        overlayColor: _F5Style.ink,
        minimumSize: const Size(0, 44),
        foregroundColor: _F5Style.ink,
        side: const BorderSide(color: _F5Style.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      child: Text('Cancel', style: _F5Style.text(12, weight: FontWeight.w700)),
    );
    final update = FilledButton.icon(
      onPressed: !_ready || _busy || _submitted || !_changed ? null : _save,
      style: _F5Style.button(),
      icon: _saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CupertinoActivityIndicator(color: Colors.white),
            )
          : const Icon(CupertinoIcons.check_mark, size: 17),
      label: Text(
        _saving ? 'Updating…' : 'Update on Portal',
        style: _F5Style.text(12, color: Colors.white, weight: FontWeight.w700),
      ),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 11, 15, 10),
        child: LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(12) > 16) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [update, const SizedBox(height: 8), cancel],
              );
            }
            return Row(
              children: [
                Expanded(child: cancel),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: update),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: _F5Theme(
      child: Scaffold(
        backgroundColor: _F5Style.page,
        appBar: _F5Header(
          title: 'Edit Student Profile',
          actions: [
            if (_preparing)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: CupertinoActivityIndicator(radius: 8),
              ),
          ],
        ),
        body: AdaptiveWorkspace(
          background: true,
          child: PageContentMotion(
            child: Center(
              child: SizedBox.expand(
                key: const ValueKey('format5-edit-workspace'),
                child: Column(
                  children: [
                    Expanded(
                      child: _F5ScrollSurface(
                        controller: _editScroll,
                        child: ListView(
                          controller: _editScroll,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(15, 9, 15, 16),
                          children: [
                            _F5EqualPanels(
                              breakpoint: 900,
                              gap: 16,
                              stackedGap: 12,
                              firstFlex: 1,
                              secondFlex: 2,
                              first: Container(
                                key: const ValueKey('format5-details-card'),
                                decoration: _F5Style.card(),
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${widget.student['name'] ?? ''}',
                                      style: _F5Style.text(
                                        16,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Student details · ShalaDarpan',
                                      style: _F5Style.text(
                                        11,
                                        color: _F5Style.muted,
                                      ),
                                    ),
                                    const Divider(
                                      height: 25,
                                      color: _F5Style.line,
                                    ),
                                    _label(
                                      'NIC ID',
                                      '${widget.student['nic_id'] ?? ''}',
                                    ),
                                    _label('Father', _detail('father')),
                                    _label('Mother', _detail('mother')),
                                    _label(
                                      'Gender',
                                      '${widget.student['gender'] ?? ''}',
                                    ),
                                    _label('Date of Birth', _detail('dob')),
                                  ],
                                ),
                              ),
                              second: Container(
                                key: const ValueKey('format5-fields-card'),
                                decoration: _F5Style.card(),
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'EDITABLE DETAILS',
                                      style: _F5Style.text(
                                        11,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _preparing
                                          ? 'Loading editable fields from the portal…'
                                          : 'Fields locked by the portal cannot be changed.',
                                      style: _F5Style.text(
                                        11,
                                        color: _F5Style.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'SR Number',
                                      style: _F5Style.text(
                                        12,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _sr,
                                      enabled:
                                          !_busy &&
                                          !_submitted &&
                                          _field('sr_no')['enabled'] == true,
                                      keyboardType: TextInputType.number,
                                      maxLength: 10,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      onChanged: (_) =>
                                          setState(() => _error = null),
                                      style: _F5Style.text(13),
                                      decoration: _F5Style.input('SR Number')
                                          .copyWith(counterText: ''),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Caste Category',
                                      style: _F5Style.text(
                                        12,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey('format5-category/$_ready'),
                                      dropdownColor: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      initialValue:
                                          _categories.any(
                                            (c) => c['id'] == _category,
                                          )
                                          ? _category
                                          : null,
                                      isExpanded: true,
                                      decoration: _F5Style.input(
                                        'Caste Category',
                                      ),
                                      style: _F5Style.text(13),
                                      items: [
                                        for (final option in _categories)
                                          DropdownMenuItem(
                                            value: option['id'],
                                            child: Text(
                                              option['label']!,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                      onChanged:
                                          _busy ||
                                              _submitted ||
                                              _field('category')['enabled'] !=
                                                  true
                                          ? null
                                          : (value) => setState(() {
                                              _category = value ?? _category;
                                              _error = null;
                                            }),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Parent / Guardian Mobile',
                                      style: _F5Style.text(
                                        12,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _mobile,
                                      enabled:
                                          !_busy &&
                                          !_submitted &&
                                          _field('mobile')['enabled'] == true,
                                      keyboardType: TextInputType.phone,
                                      maxLength: 10,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      onChanged: (_) =>
                                          setState(() => _error = null),
                                      style: _F5Style.text(13),
                                      decoration: _F5Style.input(
                                        'Mobile Number',
                                      ).copyWith(counterText: ''),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF1F0),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Text(
                                    _error!,
                                    style: _F5Style.text(
                                      12,
                                      color: _F5Style.danger,
                                    ),
                                  ),
                                ),
                              ),
                            if (_submitted && !_saving)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  'Update was attempted. Reopen the profile to verify before trying again.',
                                  style: _F5Style.text(
                                    11,
                                    color: _F5Style.muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    _footer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
