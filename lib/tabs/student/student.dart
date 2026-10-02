// lib/tabs/student/student.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'modules/student_attendance/screens/daily_attendance_sheet_screen.dart';
import 'modules/student_attendance/screens/school_report_screen.dart';

const String kAppFont = 'PlusJakartaSans';

class StudentDashboardView extends StatefulWidget {
  const StudentDashboardView({super.key});

  @override
  State<StudentDashboardView> createState() => _StudentDashboardViewState();
}

class _StudentDashboardViewState extends State<StudentDashboardView> {
  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _ink => _dark ? const Color(0xFFF0F3F8) : const Color(0xFF18212F);
  Color get _muted => _dark ? const Color(0xFFA4ADBA) : const Color(0xFF788292);
  double get _textScale => MediaQuery.textScalerOf(context).scale(12) / 12;
  Color get _line => _dark ? const Color(0xFF343B46) : const Color(0xFFE5E9EF);
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final List<String> _classList = ['All Classes', 'Class 1', 'Class 2', 'Class 3', 'Class 4', 'Class 5', 'Class 6', 'Class 7', 'Class 8'];
  DateTime _reportDate = DateUtils.dateOnly(DateTime.now());
  int _selectedClassIndex = 0;
  bool _nicExpanded = false;
  bool _reportOpening = false;
  bool _attendanceOpening = false;
  bool _calendarOpening = false;

  TextStyle _text(double size, {FontWeight weight = FontWeight.w500, Color? color}) =>
      TextStyle(fontFamily: kAppFont, fontSize: size, fontWeight: weight, color: color ?? _ink);

  void _haptic() => HapticFeedback.selectionClick();

  void _showNotice(String message) {
    _haptic();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, style: _text(12, color: Colors.white)),
        backgroundColor: const Color(0xFF18212F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
  }

  void _planned(String name) => _showNotice('$name is not connected yet.');

  void _downloadNicSheet() => _showNotice(
      'NIC sheet download is not connected yet (${_classList[_selectedClassIndex]}).');

  Future<void> _openAttendance() async {
    if (_attendanceOpening) return;
    _haptic();
    setState(() => _attendanceOpening = true);
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (_) => const DailyAttendanceSheetScreen(),
      ));
    } finally {
      if (mounted) setState(() => _attendanceOpening = false);
    }
  }

  Future<void> _viewReport() async {
    if (_reportOpening) return;
    _haptic();
    setState(() => _reportOpening = true);
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (_) => SchoolReportScreen(
          date: _reportDate,
          backgroundColor: Scaffold.maybeOf(context)?.widget.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
        ),
      ));
    } finally {
      if (mounted) setState(() => _reportOpening = false);
    }
  }

  Future<void> _pickReportDate() async {
    if (_calendarOpening) return;
    _calendarOpening = true;
    _haptic();
    try {
      final today = DateUtils.dateOnly(DateTime.now());
      final picked = await _pickMinimalDate(context,
        _reportDate.isAfter(today) ? today : _reportDate, DateTime(2015), today);
      if (!mounted || picked == null) return;
      setState(() => _reportDate = DateUtils.dateOnly(picked));
    } finally {
      _calendarOpening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // The parent tab owns the background; this dashboard paints no canvas.
    return SafeArea(top: false, bottom: false, child: LayoutBuilder(builder: (context, constraints) {
      final padding = constraints.maxWidth < 360 ? 12.0 : 18.0;
      return SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: SizedBox(
          width: constraints.maxWidth,
          child: Padding(
            padding: EdgeInsets.fromLTRB(padding, 12, padding, 88),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Student Desk', style: _text(16, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Attendance & student services', style: _text(11, color: _muted)),
              const SizedBox(height: 17),
              _attendanceCard(),
              const SizedBox(height: 12),
              _dailyRegister(),
              const SizedBox(height: 12),
              _surface(child: _moduleRow(title: 'Monthly attendance', subtitle: 'Monthly register • Planned',
                icon: CupertinoIcons.calendar, iconAsset: 'assets/icons/leave.png',
                onTap: () => _planned('Monthly Attendance'))),
              const SizedBox(height: 22),
              _sectionHeader('STUDENT RECORDS', 'Directories & enrollment'),
              const SizedBox(height: 10),
              _nicCard(),
              const SizedBox(height: 10),
              LayoutBuilder(builder: (context, box) {
                final cards = [
                  _actionCard('New Admission', 'Enrollment • Planned', CupertinoIcons.person_badge_plus,
                    () => _planned('New Admission')),
                  _actionCard('Transfer Cert. (TC)', 'School leaving • Planned', CupertinoIcons.arrow_up_doc,
                    () => _planned('Transfer Certificate')),
                ];
                if (box.maxWidth < 310 * _textScale.clamp(1.0, 1.5)) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [cards[0], const SizedBox(height: 10), cards[1]]);
                }
                return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: cards[0]), const SizedBox(width: 10), Expanded(child: cards[1]),
                ]));
              }),
              const SizedBox(height: 22),
              _sectionHeader('CERTIFICATES & FORMATS', 'Additional modules • Planned'),
              const SizedBox(height: 10),
              _surface(child: Column(children: [
                _moduleRow(title: 'Study Certificate', subtitle: 'Academic validation',
                  icon: CupertinoIcons.doc_checkmark, onTap: () => _planned('Study Certificate')),
                _rowDivider(),
                _moduleRow(title: 'Character Certificate', subtitle: 'Conduct & behavior',
                  icon: CupertinoIcons.shield_lefthalf_fill, onTap: () => _planned('Character Certificate')),
                _rowDivider(),
                _moduleRow(title: 'Format 5', subtitle: 'Student profile ledger',
                  icon: CupertinoIcons.doc_plaintext, onTap: () => _planned('Format 5')),
                _rowDivider(),
                _moduleRow(title: 'Format 9', subtitle: 'Cumulative academic record',
                  icon: CupertinoIcons.folder, onTap: () => _planned('Format 9')),
              ])),
            ]),
          ),
        ),
      );
    }));
  }

  Widget _sectionHeader(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: _text(10, weight: FontWeight.w700, color: _muted)),
      const SizedBox(height: 3),
      Text(subtitle, style: _text(10.5, color: _muted)),
    ],
  );

  Widget _surface({required Widget child}) => Material(
    color: Theme.of(context).cardColor.withOpacity(0.65),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: _line)),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _iconBox(IconData icon, {double size = 19, String? asset}) => Container(
    width: 40, height: 40,
    decoration: BoxDecoration(color: _dark ? const Color(0xFF2C333E) : const Color(0xFFEDEFF3), borderRadius: BorderRadius.circular(11)),
    child: Center(child: asset == null ? Icon(icon, size: size, color: _ink)
      : Image.asset(asset, width: size + 2, height: size + 2, fit: BoxFit.contain,
          color: _ink, colorBlendMode: BlendMode.srcIn,
          errorBuilder: (_, __, ___) => Icon(icon, size: size, color: _ink))),
  );

  Widget _attendanceCard() => Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF212834), Color(0xFF10151D)]),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF333D4C)),
    ),
    child: Padding(padding: const EdgeInsets.all(18), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 42, height: 42,
            decoration: BoxDecoration(color: const Color(0xFF303B4B), borderRadius: BorderRadius.circular(12)),
            child: const Icon(CupertinoIcons.person_2, size: 22, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Student Attendance', style: _text(16, weight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 5),
            Text('Class-wise attendance & daily roll call', style: _text(10.5, color: const Color(0xFFB8C3D2))),
          ])),
        ]),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _attendanceOpening ? null : _openAttendance,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF4F6F9), foregroundColor: const Color(0xFF152031),
            disabledBackgroundColor: const Color(0xFFDCE2EA), disabledForegroundColor: const Color(0xFF64748B),
            elevation: 0, minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
          child: Row(children: [
            Expanded(child: Text('Open Attendance Register', style: _text(12,
              weight: FontWeight.w700, color: const Color(0xFF152031)))),
            const SizedBox(width: 8),
            const Icon(CupertinoIcons.arrow_right, size: 16),
          ]),
        )),
      ],
    )),
  );

  Widget _dailyRegister() {
    final dateLabel = '${_reportDate.day} ${_months[_reportDate.month - 1]} ${_reportDate.year}';
    final monthLabel = '${_months[_reportDate.month - 1]} ${_reportDate.year}';
    // Only the calendar widget opens the picker; this panel has no tap handler.
    return _surface(child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      child: LayoutBuilder(builder: (context, box) {
        final stacked = box.maxWidth < 240 * _textScale.clamp(1.0, 2.0);
        final dateInfo = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(monthLabel, style: _text(10.5, weight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text('Attendance report', style: _text(9, color: _muted)),
        ]);
        final calendarAndInfo = Row(children: [
          _iosCalendar(dateLabel),
          const SizedBox(width: 11),
          Expanded(child: dateInfo),
        ]);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Image.asset('assets/icons/report.png', width: 17, height: 17,
              color: _muted, colorBlendMode: BlendMode.srcIn,
              errorBuilder: (_, __, ___) => Icon(CupertinoIcons.doc_chart, size: 17, color: _muted)),
            const SizedBox(width: 7),
            Expanded(child: Text('Daily Register', style: _text(11.5, weight: FontWeight.w600))),
            if (box.maxWidth > 280 * _textScale) ...[
              const SizedBox(width: 6),
              Text('PDF report', style: _text(8.5, color: _muted)),
            ],
          ]),
          const SizedBox(height: 9),
          if (stacked) ...[
            calendarAndInfo,
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: _viewButton()),
          ] else Row(children: [
            Expanded(child: calendarAndInfo),
            const SizedBox(width: 10),
            _viewButton(),
          ]),
        ]);
      }),
    ));
  }

  Widget _iosCalendar(String dateLabel) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
    child: Tooltip(
      message: 'Choose date: $dateLabel',
      child: Semantics(button: true, label: 'Choose report date, $dateLabel',
        child: GestureDetector(onTap: _pickReportDate, behavior: HitTestBehavior.opaque,
          child: Container(
            width: 42, height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Colors.white, Color(0xFFF6F6F7), Color(0xFFD8DBDF)], stops: [0, 0.55, 1]),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white, width: 1.1),
              boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_weekdays[_reportDate.weekday - 1], style: _text(9.5, weight: FontWeight.w700, color: const Color(0xFFFF3B42))),
              Text('${_reportDate.day}', style: const TextStyle(fontFamily: kAppFont, fontSize: 24, height: 1.05,
                fontWeight: FontWeight.w600, color: Color(0xFF161719),
                shadows: [Shadow(color: Colors.white, offset: Offset(0, 1))])),
            ]),
          ),
        ),
      ),
    ),
  );

  Widget _viewButton() => OutlinedButton(
    onPressed: _reportOpening ? null : _viewReport,
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF152031),
      backgroundColor: const Color(0xFFFFFFFF),
      disabledBackgroundColor: const Color(0xFFF1F2F4),
      disabledForegroundColor: _muted,
      side: BorderSide(color: _dark ? const Color(0xFF566171) : const Color(0xFFCDD5DF)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      minimumSize: const Size(75, 38),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('View', style: _text(11, weight: FontWeight.w600, color: _reportOpening ? _muted : const Color(0xFF152031))),
      const SizedBox(width: 7),
      const Icon(CupertinoIcons.arrow_right, size: 13),
    ]),
  );

  Widget _navigationArrow() => Container(
    width: 25, height: 25,
    decoration: BoxDecoration(color: _dark ? const Color(0xFF303846) : const Color(0xFFEBEFF4),
      borderRadius: BorderRadius.circular(8)),
    child: Icon(CupertinoIcons.chevron_forward, size: 10, color: _muted),
  );

  Widget _moduleRow({required String title, required String subtitle, required IconData icon, String? iconAsset, required VoidCallback onTap}) =>
      InkWell(onTap: onTap, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          _iconBox(icon, asset: iconAsset),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: _text(12.5, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(subtitle, style: _text(10, color: _muted)),
          ])),
          const SizedBox(width: 7),
          _navigationArrow(),
        ]),
      ));

  Widget _rowDivider() => Divider(height: 1, thickness: 0.6, color: _line, indent: 65, endIndent: 14);

  Widget _actionCard(String title, String subtitle, IconData icon, VoidCallback onTap) => _surface(
    child: InkWell(onTap: onTap, child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [_iconBox(icon), const Spacer(), _navigationArrow()]),
        const SizedBox(height: 12),
        Text(title, style: _text(12.5, weight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text(subtitle, style: _text(10, color: _muted)),
      ]),
    )),
  );

  Widget _nicCard() => _surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    InkWell(onTap: () {
      _haptic();
      setState(() => _nicExpanded = !_nicExpanded);
    }, child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        _iconBox(CupertinoIcons.barcode_viewfinder),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Student NIC directory', style: _text(12.5, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(_nicExpanded ? 'Select a class below' : 'Class-wise NIC sheets', style: _text(10, color: _muted)),
        ])),
        Icon(_nicExpanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down, size: 14, color: _muted),
      ]),
    )),
    if (_nicExpanded) Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Divider(height: 1, color: _line),
        const SizedBox(height: 13),
        SizedBox(height: 34 * _textScale.clamp(1.0, 3.0), child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _classList.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final selected = index == _selectedClassIndex;
            return Material(color: selected ? const Color(0xFF18212F) : (_dark ? const Color(0xFF2C333E) : const Color(0xFFF2F5F8)),
              borderRadius: BorderRadius.circular(9), clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: () {
                _haptic();
                setState(() => _selectedClassIndex = index);
              }, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(child: Text(_classList[index], style: _text(10.5,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : _muted))),
              )),
            );
          },
        )),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: TextButton(
          onPressed: _downloadNicSheet,
          style: TextButton.styleFrom(
            foregroundColor: _ink,
            backgroundColor: _dark ? const Color(0xFF303846) : const Color(0xFFE9EEF4),
            minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Row(children: [
            const Icon(CupertinoIcons.arrow_down_to_line, size: 15),
            const SizedBox(width: 8),
            Expanded(child: Text('Download NIC sheet', style: _text(11, weight: FontWeight.w600))),
            const Icon(CupertinoIcons.arrow_right, size: 13),
          ]),
        )),
        const SizedBox(height: 6),
        Text('Download integration is planned.', style: _text(9, color: _muted)),
      ]),
    ),
  ]));

  Future<DateTime?> _pickMinimalDate(BuildContext ctx, DateTime initial, DateTime first, DateTime last) async {
    DateTime displayedMonth = DateTime(initial.year, initial.month);
    DateTime selectedDate = initial;

    return await showDialog<DateTime>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) {
        return Theme(
          data: ThemeData.light(useMaterial3: true).copyWith(
            splashFactory: NoSplash.splashFactory,
            colorScheme: const ColorScheme(
              brightness: Brightness.light,
              primary: Color(0xFF0F172A),
              onPrimary: Colors.white,
              secondary: Color(0xFF0F172A),
              onSecondary: Colors.white,
              error: Color(0xFFDC2626),
              onError: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF0F172A),
              surfaceTint: Colors.transparent,
            ),
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final int year = displayedMonth.year;
              final int month = displayedMonth.month;
              final int daysInMonth = DateUtils.getDaysInMonth(year, month);
              final int firstWeekday = DateTime(year, month, 1).weekday;
              const List<String> monthNames = [
                "",
                "January",
                "February",
                "March",
                "April",
                "May",
                "June",
                "July",
                "August",
                "September",
                "October",
                "November",
                "December",
              ];
              final List<int> yearsList = List.generate(last.year - first.year + 1, (i) => first.year + i);

              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: 285,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            PopupMenuButton<int>(
                              initialValue: month,
                              color: Colors.white,
                              elevation: 3,
                              offset: const Offset(0, 30),
                              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 130),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              itemBuilder: (context) => [
                                for (int i = 1; i <= 12; i++)
                                  PopupMenuItem<int>(
                                    value: i,
                                    height: 35,
                                    child: Text(
                                      monthNames[i],
                                      style: TextStyle(
                                        fontFamily: kAppFont,
                                        fontSize: 12.5,
                                        fontWeight: i == month ? FontWeight.w700 : FontWeight.w500,
                                        color: i == month ? const Color(0xFFEF4444) : const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                              ],
                              onSelected: (val) => setDialogState(() => displayedMonth = DateTime(year, val)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    monthNames[month],
                                    style: const TextStyle(
                                      fontFamily: kAppFont,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(Icons.arrow_drop_down_rounded, size: 21, color: Color(0xFFEF4444)),
                                ],
                              ),
                            ),
                            PopupMenuButton<int>(
                              initialValue: year,
                              color: Colors.white,
                              elevation: 3,
                              offset: const Offset(0, 30),
                              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 95),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              itemBuilder: (context) => [
                                for (final y in yearsList)
                                  PopupMenuItem<int>(
                                    value: y,
                                    height: 35,
                                    child: Text(
                                      "$y",
                                      style: TextStyle(
                                        fontFamily: kAppFont,
                                        fontSize: 12.5,
                                        fontWeight: y == year ? FontWeight.w700 : FontWeight.w500,
                                        color: y == year ? const Color(0xFFEF4444) : const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                              ],
                              onSelected: (val) => setDialogState(() => displayedMonth = DateTime(val, month)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "$year",
                                    style: const TextStyle(
                                      fontFamily: kAppFont,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(Icons.arrow_drop_down_rounded, size: 21, color: Color(0xFFEF4444)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: const [
                          Text(
                            "Mo",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Tu",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "We",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Th",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Fr",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Sa",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Su",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 2.5,
                          crossAxisSpacing: 2.5,
                        ),
                        itemCount: daysInMonth + (firstWeekday - 1),
                        itemBuilder: (context, index) {
                          if (index < firstWeekday - 1) return const SizedBox.shrink();
                          final int day = index - (firstWeekday - 2);
                          final DateTime currentCellDate = DateTime(year, month, day);
                          final bool isDisabled =
                              currentCellDate.isBefore(DateTime(first.year, first.month, first.day)) ||
                              currentCellDate.isAfter(DateTime(last.year, last.month, last.day));
                          final bool isSelected =
                              currentCellDate.year == selectedDate.year &&
                              currentCellDate.month == selectedDate.month &&
                              currentCellDate.day == selectedDate.day;

                          return GestureDetector(
                            onTap: isDisabled ? null : () => setDialogState(() => selectedDate = currentCellDate),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFEF4444) : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                "$day",
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 11.0,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isDisabled
                                      ? const Color(0xFFCBD5E1)
                                      : isSelected
                                      ? Colors.white
                                      : const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(context, null),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: const Size(48, 28),
                            ),
                            child: const Text(
                              "Cancel",
                              style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, color: Color(0xFF64748B)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, selectedDate),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              minimumSize: const Size(38, 28),
                              elevation: 0,
                            ),
                            child: const Text(
                              "OK",
                              style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

}
