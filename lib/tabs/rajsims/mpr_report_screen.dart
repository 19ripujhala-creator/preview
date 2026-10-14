import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/portals/rajsims/rajsims_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/viffs_status_service.dart';
import 'package:shaladarpan/widgets/adaptive_layout.dart';

class MprReportScreen extends StatefulWidget {
  const MprReportScreen({super.key});
  @override
  State<MprReportScreen> createState() => _MprReportScreenState();
}

class _MprReportScreenState extends State<MprReportScreen> {
  static const groups = ['pre_primary', 'primary', 'upper_primary'];
  static const labels = {
    'pre_primary': 'Pre-primary',
    'primary': 'Primary (1–5)',
    'upper_primary': 'Upper primary (6–8)',
  };

  // ───────── Steps ─────────
  static const stepLabels = ['Meals', 'Milk & gas', 'Staff', 'Health'];
  static const stepTitles = [
    'Meals & cooking cost',
    'Milk, sugar & gas',
    'Staff details',
    'Health & inspection',
  ];
  static const stepSubs = [
    'Check portal data and enter the cooking rate.',
    'Milk powder, sugar, milk helper and gas accounts.',
    'Cooks, helper and MDM incharge. Saved per school.',
    'Children health, inspection, CCH / MME and bank.',
  ];
  static const _lastStep = 3;

  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _fields = {};
  Map<String, dynamic>? _school, _monthly, _viffs;
  Map<String, dynamic> _mealGroups = {};
  final Map<String, String> _errors = {};
  int _year = DateTime.now().month == 1
      ? DateTime.now().year - 1
      : DateTime.now().year;
  int _month = DateTime.now().month == 1 ? 12 : DateTime.now().month - 1;
  bool _loading = false, _generating = false;
  double _pdfProgress = 0.0;
  String _inspection = '', _settingsSchool = '';
  int _revision = 0;

  TextEditingController f(String key) =>
      _fields.putIfAbsent(key, () => TextEditingController());

  @override
  void initState() {
    super.initState();
    f('cooking_rate_primary').text = '6.78';
    f('powder_rate_primary').text = '15';
    for (final prefix in ['cook1', 'cook2', 'cook3']) {
      f('${prefix}_honorarium').text = '2467';
    }
    f('milk_helper_consumption').text = '500';
    f('helper_honorarium').text = '500';
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> maps(dynamic value) => value is List
      ? value.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : [];
  Map<String, dynamic> map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  int enrolled(String g) =>
      (map(map(map(_school?['groups'])[g])['total'])['total'] as num?)
          ?.toInt() ??
      0;
  List<String> get active => groups.where((g) => enrolled(g) > 0).toList();
  List<String> get visible => active.isEmpty ? ['primary'] : active;

  Future<Map<String, dynamic>?> getData(String label, String path) async {
    final result = await RajsimsService.fetchMprJson(path);
    if (result['success'] != true) {
      _errors[label] = result['message']?.toString() ?? 'Data unavailable';
      return null;
    }
    return result;
  }

  Future<void> _load() async {
    if (_loading || _generating) return;
    final rev = ++_revision;

    setState(() {
      _loading = true; // Spinner on
      _errors.clear();
      _school = null;
      _monthly = null;
      _viffs = null;
      _mealGroups = {};
    });

    try {
      // 🔥 5 alag API calls ke bajaye sirf 1 Single Bundle Call
      final res = await RajsimsService.fetchMprJson(
        '/api/rajsims/mdm/mpr-bundle?year=$_year&month=$_month',
      );

      if (!mounted || rev != _revision) return;

      if (res['success'] != true) {
        _errors['Report'] = res['message']?.toString() ?? 'Data unavailable';
        return;
      }

      _school = res['school'];
      _monthly = res['monthly'];
      final profile = res['profile'];

      if (_monthly != null && _monthly!['complete'] != true) {
        _errors['Meals / stock'] = 'Monthly report is incomplete.';
        _monthly = null;
      }

      // School Settings restore
      if (_school != null) {
        final id = '${_school!['school_id']}';
        if (_settingsSchool.isNotEmpty && _settingsSchool != id) {
          for (final c in _fields.values) {
            c.clear();
          }
          f('cooking_rate_primary').text = '6.78';
          f('powder_rate_primary').text = '15';
          for (final prefix in ['cook1', 'cook2', 'cook3']) {
            f('${prefix}_honorarium').text = '2467';
          }
          f('helper_honorarium').text = '500';
          f('milk_helper_consumption').text = '500';
        }
        await _restoreSettings();
      }

      if (!mounted || rev != _revision) return;

      // Incharge pre-fill
      if (profile != null) {
        if (f('incharge_name').text.isEmpty) {
          f('incharge_name').text = profile['incharge_name']?.toString() ?? '';
        }
        if (f('incharge_mobile').text.isEmpty) {
          f('incharge_mobile').text = profile['incharge_mobile']?.toString() ?? '';
        }
      }

      if (_school != null && _monthly != null) _mapMeals();

      // VIFFS: reuse the Monthly Tasks verified status/cache.
      // Pending/unlocked means manual entry; MPR itself never replays VIFFS portal tabs.
      if (_school != null) {
        final schoolId = '${_school!['school_id']}';
        await ViffsStatusService.restore(schoolId);
        ViffsStatusService.setEligibility(
          schoolId,
          primary: enrolled('primary') > 0,
          upper: enrolled('upper_primary') > 0,
        );

        final tablets = ViffsStatusService.requiredCategories(schoolId) ?? const <String>[];
        final statuses = <Map<String, dynamic>>[];
        for (final tablet in tablets) {
          final status = ViffsStatusService.periodTabletStatus(
            schoolId,
            _year,
            _month,
            tablet,
          );
          if (status != null) statuses.add(status);
        }

        final available = tablets.isNotEmpty &&
            statuses.length == tablets.length &&
            statuses.every((r) =>
                r['locked'] == true &&
                r['boys'] is num &&
                r['girls'] is num);

        final boys = available
            ? statuses.fold<int>(0, (sum, r) => sum + (r['boys'] as num).toInt())
            : 0;
        final girls = available
            ? statuses.fold<int>(0, (sum, r) => sum + (r['girls'] as num).toInt())
            : 0;

        _viffs = {
          'locked': available,
          'entry_available': available,
          'manual_required': !available,
          'boys': available ? boys : null,
          'girls': available ? girls : null,
          'source': 'monthly_task_status',
        };

        if (available) {
          f('viffs_boys').text = '$boys';
          f('viffs_girls').text = '$girls';
        }
      }

      // Default working days & report date
      if (f('working_days').text.isEmpty && _monthly?['served_days'] != null) {
        f('working_days').text = '${_monthly!['served_days']}';
      }
      if (f('report_date').text.isEmpty) {
        f('report_date').text = _formatReportDate(DateUtils.dateOnly(DateTime.now()));
      }
    } catch (e) {
      _errors['Report'] = '$e';
    } finally {
      if (mounted && rev == _revision) {
        setState(() => _loading = false); // Data aate hi spinner stop
      }
    }
  }

  void _mapMeals() {
    for (final r in maps(_monthly?['groups'])) {
      final name = '${r['group_name']}'.toLowerCase();
      String? group;
      if (name.contains('pre-primary to 5')) {
        if (enrolled('pre_primary') > 0 && enrolled('primary') > 0) {
          _errors['Meal categories'] =
              'Portal combines Pre-primary and Primary meals. Separate verified totals are required.';
          continue;
        }
        group = enrolled('pre_primary') > 0 ? 'pre_primary' : 'primary';
      } else if (name.contains('upper') ||
          name.contains('6 to 8') ||
          name.contains('6-8')) {
        group = 'upper_primary';
      } else if (name.contains('pre-primary')) {
        group = 'pre_primary';
      } else if (name.contains('primary')) {
        group = 'primary';
      }
      if (group == null || _mealGroups.containsKey(group)) {
        _errors['Meal categories'] =
            'Portal meal category could not be mapped uniquely.';
        continue;
      }
      _mealGroups[group] = r;
    }
  }

  // Ye fields school ke hisaab se save hote hain.
  bool savedKey(String key) =>
      key.startsWith('cook') ||
      key.startsWith('helper_') ||
      key.startsWith('cooking_rate_') ||
      key.startsWith('powder_rate_') ||
      key.startsWith('checked_') ||
      key.startsWith('incharge_') ||
      key.startsWith('school_detail_');

  Future<void> _restoreSettings() async {
    final id = '${_school!['school_id']}';
    if (_settingsSchool == id) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final stored = prefs.getString('mpr_settings_$id');
    if (stored != null) {
      final values = map(jsonDecode(stored));
      for (final entry in values.entries) {
        if (savedKey(entry.key)) f(entry.key).text = '${entry.value}';
      }
    }
    _settingsSchool = id;
  }

  Future<void> _saveSettings() async {
    if (_school == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'mpr_settings_${_school!['school_id']}',
      jsonEncode({
        for (final e in _fields.entries)
          if (savedKey(e.key)) e.key: e.value.text.trim(),
      }),
    );
  }

  double? n(String key) => double.tryParse(f(key).text.trim());

  String calc(String g) {
    final meals = (map(_mealGroups[g])['total_meals'] as num?)?.toInt();
    final rate = n('cooking_rate_$g');
    if (meals == null ||
        rate == null ||
        !RegExp(r'^\d+(\.\d+)?$').hasMatch(f('cooking_rate_$g').text.trim())) {
      return '—';
    }
    // Decimal rate ko scale karke multiply; final amount round hota hai, har meal nahi.
    final raw = f('cooking_rate_$g').text.trim().split('.');
    final fraction = raw.length > 1 ? raw[1] : '';
    int scale = 1;
    for (int i = 0; i < fraction.length; i++) {
      scale *= 10;
    }
    final units = int.parse(raw[0]) * scale + (int.tryParse(fraction) ?? 0);
    final total = meals * units;
    return '${(total + scale ~/ 2) ~/ scale}';
  }

  // Milk powder: consumption aur closing apne aap (preview; PDF bhi yahi nikalta hai).
  List<String> _powder(String g) {
    final opening = n('powder_${g}_opening');
    final received = n('powder_${g}_received');
    final count = n('milk_count_$g');
    final grams = n('powder_rate_$g');
    if (count == null || grams == null) return ['—', '—'];
    String fmt(double v) {
      final t = v.toStringAsFixed(3);
      return t.contains('.') ? t.replaceFirst(RegExp(r'\.?0+$'), '') : t;
    }

    final consumption = count * grams / 1000;
    if (opening == null || received == null) return [fmt(consumption), '—'];
    final closing = opening + received - consumption;
    return [fmt(consumption), closing < 0 ? 'Exceeds stock' : fmt(closing)];
  }

  int get _totalCooking =>
      visible.fold<int>(0, (s, g) => s + (int.tryParse(calc(g)) ?? 0));

  bool get _hasTotal => visible.any((g) => calc(g) != '—');

  Future<void> _generate() async {
    if (_loading || _generating) return;
    if (_school == null ||
        _monthly == null ||
        _errors.containsKey('Meal categories')) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _generating = true;
      _pdfProgress = 0.06;
    });

    try {
      // Actual milestone 1: local/school-specific settings persisted.
      await _saveSettings();
      if (!mounted) return;
      setState(() => _pdfProgress = 0.22);

      final values = {
        for (final e in _fields.entries) e.key: e.value.text.trim(),
        'inspection': _inspection,
      };

      // Actual milestone 2: payload is completely prepared and backend request
      // is about to start. No fake timer is used.
      if (!mounted) return;
      setState(() => _pdfProgress = 0.34);

      final rawBytes = await RajsimsService.generateMprPdf({
        'school': _school,
        'monthly': _monthly,
        'viffs': _viffs,
        'meal_groups': _mealGroups,
        'values': values,
      });

      // Actual milestone 3: backend finished PDF creation and bytes arrived.
      if (!mounted) return;
      setState(() => _pdfProgress = 0.90);

      final bytes = Uint8List.fromList(rawBytes);

      // Actual milestone 4: bytes are ready for preview.
      if (!mounted) return;
      setState(() => _pdfProgress = 1.0);

      // Let the 100% ring become visible before opening the preview.
      await Future<void>.delayed(const Duration(milliseconds: 140));
      if (!mounted) return;

      setState(() {
        _generating = false;
        _pdfProgress = 0.0;
      });

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.transparent,
            appBar: _alignedTopBar(
              title: 'MPR PDF',
              onBack: () => Navigator.maybePop(context),
              action: _circleTopAction(
                tooltip: 'Share PDF',
                icon: CupertinoIcons.share,
                iconColor: const Color(0xFF007AFF),
                onPressed: () async {
                  try {
                    await Printing.sharePdf(
                      bytes: bytes,
                      filename:
                          'MPR_$_year-${_month.toString().padLeft(2, '0')}.pdf',
                    );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e')),
                      );
                    }
                  }
                },
              ),
            ),
            body: Stack(
              fit: StackFit.expand,
              children: [
                _appBackground(),
                SafeArea(
                  top: false,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final isPhone = box.maxWidth < 600;
                      final previewWidth = isPhone
                          ? box.maxWidth
                          : box.maxWidth < 900
                              ? 720.0
                              : 820.0;

                      return Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: previewWidth,
                          height: box.maxHeight,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              isPhone ? 8 : 12,
                              0,
                              isPhone ? 8 : 12,
                              isPhone ? 8 : 12,
                            ),
                            child: PdfPreview(
                              build: (_) async => bytes,
                              useActions: false,
                              allowPrinting: false,
                              allowSharing: false,
                              canChangeOrientation: false,
                              canChangePageFormat: false,
                              pdfFileName:
                                  'MPR_$_year-${_month.toString().padLeft(2, '0')}.pdf',
                              loadingWidget: const Center(
                                child: CupertinoActivityIndicator(radius: 13),
                              ),
                              scrollViewDecoration: const BoxDecoration(
                                color: Colors.transparent,
                              ),
                              pdfPreviewPageDecoration: const BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x180F172A),
                                    blurRadius: 14,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _generating = false;
          _pdfProgress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted && _generating) {
        setState(() {
          _generating = false;
          _pdfProgress = 0.0;
        });
      }
    }
  }

  // ───────── Design tokens ─────────
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const line = Color(0xFFE2E8F0);
  static const paper = Color(0xFFF8FAFC);
  static const accent = Color(0xFF111827);
  static const danger = Color(0xFFFF3B30);
  static const TextStyle _valueStyle = TextStyle(
    fontSize: 13.0,
    height: 1.0,
    letterSpacing: 0,
    fontWeight: FontWeight.w500,
    color: ink,
  );
  static const double _h = 38; // compact mobile-first input/dropdown/date height
  static const monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  int _page = 0;
  String? _invalidKey;
  final Set<String> _manualInvalid = <String>{};
  String? invalid(String key, String message) {
    _invalidKey ??= key;
    return message;
  }

  int pageFor(String key) {
    if ((key.startsWith('cook') && !key.startsWith('cooking_rate_')) ||
        key.startsWith('helper_') ||
        key.startsWith('incharge_')) {
      return 2;
    }
    if (key.startsWith('powder_') ||
        key.startsWith('sugar_') ||
        key.startsWith('milk_helper_') ||
        key.startsWith('gas_')) {
      return 1;
    }
    if (key.startsWith('viffs_') ||
        key.startsWith('checked_') ||
        key.startsWith('inspection_') ||
        key.startsWith('bank_') ||
        key.startsWith('cch_') ||
        key.startsWith('mme_')) {
      return 3;
    }
    return 0;
  }

  final _scroll = ScrollController();
  bool get _ready =>
      !_loading &&
      _school != null &&
      _monthly != null &&
      !_errors.containsKey('Meal categories');

  InputDecoration _inputDecoration({
    String? hint,
    bool readonly = false,
    bool invalidField = false,
  }) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 13,
          height: 1.15,
          letterSpacing: 0,
          color: Color(0xFF94A3B8),
        ),
        filled: true,
        fillColor: readonly ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
        focusColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        constraints: const BoxConstraints.tightFor(height: _h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: invalidField ? danger : line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: invalidField ? danger : line,
            width: invalidField ? 1.25 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: invalidField ? danger : ink,
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: danger, width: 1.25),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: danger, width: 1.25),
        ),
        // Error text hidden: red border + red label hi dikhta hai (layout nahi hilta).
        errorStyle: const TextStyle(color: danger, fontSize: 0, height: 0),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 34,
          minHeight: _h,
          maxHeight: _h,
        ),
        suffixIcon: readonly
            ? const Icon(Icons.lock_outline_rounded, size: 14, color: muted)
            : null,
      );

  Widget _fieldLabel(String label, {bool invalid = false}) => SizedBox(
    height: 15,
    child: Align(
      alignment: Alignment.topLeft,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.0,
          fontWeight: FontWeight.w600,
          color: invalid ? danger : muted,
        ),
      ),
    ),
  );

  // Label ke saath same height ka read-only box (calculated values ke liye).
  Widget readonlyBox(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      _fieldLabel(label),
      Container(
        height: _h,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: line),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _valueStyle,
        ),
      ),
    ],
  );

  Widget field(
    String key,
    String label, {
    bool numeric = false,
    bool integer = false,
    bool readonly = false,
    bool required = false,
  }) {
    final invalidField = _manualInvalid.contains(key);
    final isNameField = key.contains('name'); // 👈 Name field check

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _fieldLabel(label, invalid: invalidField),
        SizedBox(
          height: _h,
          child: TextFormField(
            controller: f(key),
            readOnly: readonly,
            enabled: !_generating,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.center,
            textInputAction: TextInputAction.next,
            // 👇 Har word ka pehla letter auto-capital banega (Cook, Incharge, Checked by etc.)
            textCapitalization: isNameField
                ? TextCapitalization.words
                : TextCapitalization.none,
            style: _valueStyle,
            strutStyle: const StrutStyle(
              fontSize: 13.5,
              height: 1.0,
              forceStrutHeight: true,
            ),
            keyboardType: numeric
                ? TextInputType.numberWithOptions(decimal: !integer)
                : (isNameField ? TextInputType.name : TextInputType.text),
            inputFormatters: numeric
                ? [
                    FilteringTextInputFormatter.allow(
                      RegExp(integer ? r'[0-9]' : r'[0-9.]'),
                    ),
                  ]
                : null,
            scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
            decoration: _inputDecoration(
              readonly: readonly,
              invalidField: invalidField,
            ),
            onChanged: (_) {
              if (_manualInvalid.remove(key) ||
                  key.startsWith('cooking_rate_') ||
                  key.startsWith('powder_') ||
                  key.startsWith('milk_count_')) {
                setState(() {});
              }
            },
            validator: (v) {
              final value = (v ?? '').trim();
              if (required && value.isEmpty) return invalid(key, 'Required');
              if (value.isEmpty) return null;
              if (numeric &&
                  (!RegExp(integer ? r'^\d+$' : r'^\d+(\.\d+)?$')
                          .hasMatch(value) ||
                      double.tryParse(value)?.isFinite != true)) {
                return invalid(key, 'Enter a valid number');
              }
              if (!numeric &&
                  value.runes.any(
                    (c) => c > 127 && !(c >= 0x0900 && c <= 0x097F),
                  )) {
                return invalid(key, 'Use English or Hindi text');
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  String _choiceText(String value) {
    if (value.isEmpty) return 'Select';
    if (value == 'M') return 'Male';
    if (value == 'F') return 'Female';
    if (value == 'Y') return 'Yes';
    if (value == 'N') return 'No';
    return value;
  }

  Widget _popupField<T>({
    required String label,
    required T value,
    required List<MapEntry<T, String>> items,
    required ValueChanged<T> onSelected,
    bool invalidField = false,
    bool enabled = true,
    bool showLabel = true,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showLabel) _fieldLabel(label, invalid: invalidField),
          LayoutBuilder(
            builder: (context, box) => PopupMenuButton<T>(
              enabled: enabled,
              tooltip: '',
              position: PopupMenuPosition.under,
              color: Colors.white,
              elevation: 8,
              surfaceTintColor: Colors.transparent,
              offset: const Offset(0, 4),
              constraints: BoxConstraints(
                minWidth: box.maxWidth,
                maxWidth: box.maxWidth,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: line),
              ),
              onSelected: onSelected,
              itemBuilder: (context) => [
                for (final item in items)
                  PopupMenuItem<T>(
                    value: item.key,
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.value,
                            style: TextStyle(
                              letterSpacing: 0,
                              fontSize: 13.5,
                              fontWeight: item.key == value
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: ink,
                            ),
                          ),
                        ),
                        if (item.key == value)
                          const Icon(
                            CupertinoIcons.checkmark,
                            size: 14,
                            color: ink,
                          ),
                      ],
                    ),
                  ),
              ],
              child: Container(
                height: _h,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: enabled ? const Color(0xFFF8FAFC) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: invalidField ? danger : line,
                    width: invalidField ? 1.25 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (() {
                          for (final item in items) {
                            if (item.key == value) return item.value;
                          }
                          return 'Select';
                        })(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _valueStyle.copyWith(
                          color: items.any((e) => e.key == value)
                              ? ink
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      CupertinoIcons.chevron_down,
                      size: 12,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );

  Widget choice(String key, String label, List<String> options) {
    final current = f(key).text;

    return FormField<String>(
      initialValue: current,
      validator: (_) =>
          key.startsWith('cook') &&
                  key.endsWith('_gender') &&
                  (key.startsWith('cook1_') ||
                      f('${key.split('_').first}_name').text.trim().isNotEmpty) &&
                  f(key).text.isEmpty
              ? invalid(key, 'Required')
              : null,
      builder: (state) {
        final invalidField = state.hasError || _manualInvalid.contains(key);

        return _popupField<String>(
          label: label,
          value: current,
          invalidField: invalidField,
          enabled: !_generating,
          items: [
            const MapEntry('', 'Select'),
            for (final option in options) MapEntry(option, _choiceText(option)),
          ],
          onSelected: (selected) {
            f(key).text = selected;
            _manualInvalid.remove(key);
            state.didChange(selected);
            setState(() {});
          },
        );
      },
    );
  }

  // Predictable responsive grid:
  // phone: 1/2 cols, tablet: 2 cols, desktop: 3 cols, wide: up to maxColumns.
  Widget grid(
    List<Widget> children, {
    double minWidth = 160,
    bool preferTwoOnMobile = true,
    int maxColumns = 4,
  }) =>
      LayoutBuilder(
        builder: (_, constraints) {
          final width = constraints.maxWidth;
          final gap = width < 600 ? 8.0 : 10.0;

          int availableColumns;
          if (width < 350) {
            availableColumns = 1;
          } else if (width < 600) {
            availableColumns = preferTwoOnMobile ? 2 : 1;
          } else if (width < 820) {
            availableColumns = 2;
          } else if (width < 1120) {
            availableColumns = 3;
          } else {
            availableColumns = 4;
          }

          var columns = availableColumns.clamp(1, maxColumns).toInt();
          if (children.length < columns) columns = children.length;
          if (columns < 1) columns = 1;

          final cellWidth = (width - gap * (columns - 1)) / columns;

          return Wrap(
            spacing: gap,
            runSpacing: 8,
            children: [
              for (final child in children)
                SizedBox(width: cellWidth, child: child),
            ],
          );
        },
      );

  // Name jaise lambe fields ko zyada jagah (flex), chhote fields ko kam.
  Widget flexFields(
    List<Widget> children, {
    required List<int> flexes,
    double stackBelow = 600,
    bool compactPhone = false,
  }) =>
      LayoutBuilder(
        builder: (_, constraints) {
          assert(children.length == flexes.length);

          if (constraints.maxWidth < stackBelow) {
            if (compactPhone &&
                children.length == 3 &&
                constraints.maxWidth >= 350) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  children.first,
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: children[1]),
                      const SizedBox(width: 8),
                      Expanded(child: children[2]),
                    ],
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  children[i],
                ],
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(flex: flexes[i], child: children[i]),
              ],
            ],
          );
        },
      );

  Widget hint(String text) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11, height: 1.5, color: muted),
    ),
  );

  Widget iconBadge(IconData icon) => Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      color: const Color(0xFFF1F4F7),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, size: 15, color: ink),
  );

  Widget section(
    String title,
    List<Widget> children, {
    String? note,
    bool fold = false,
    bool expanded = false,
    bool nested = false,
    IconData? icon,
  }) {
    final verified = note != null && note.toLowerCase().contains('verified');
    final compact = MediaQuery.sizeOf(context).width < 600;
    final side = nested
        ? 10.0
        : compact
            ? 11.0
            : 14.0;
    final top = nested
        ? 9.0
        : compact
            ? 10.0
            : 12.0;
    final bottom = nested
        ? 10.0
        : compact
            ? 11.0
            : 13.0;

    final body = Padding(
      padding: EdgeInsets.fromLTRB(side, 0, side, bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

    final head = Row(
      children: [
        if (icon != null) ...[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F4F7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: ink),
          ),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: nested ? 12 : 13.25,
                        height: 1.15,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ),
                  // "Verified" ab title ke aage hi dikhta hai (neeche alag line nahi).
                  if (verified) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      CupertinoIcons.checkmark_seal_fill,
                      size: 13,
                      color: Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 3),
                    const Text(
                      'Verified',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.0,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ],
                ],
              ),
              if (note != null && !verified) ...[
                const SizedBox(height: 3),
                Text(
                  note,
                  style: const TextStyle(
                    fontSize: 10.25,
                    height: 1.15,
                    fontWeight: FontWeight.w400,
                    color: muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: nested ? const Color(0xFFF8FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(nested ? 12 : 16),
        border: Border.all(color: const Color(0xFFE9EEF4)),
        boxShadow: nested
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0C0F172A),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: fold
          ? Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: ValueKey('$title|$expanded'),
                initiallyExpanded: expanded,
                maintainState: true,
                dense: true,
                visualDensity: VisualDensity.compact,
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: EdgeInsets.symmetric(horizontal: side),
                childrenPadding: EdgeInsets.zero,
                title: head,
                children: [body],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(side, top, side, 9),
                  child: head,
                ),
                body,
              ],
            ),
    );
  }

  Widget subLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        Container(
          width: 2,
          height: 11,
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget groupFields(
    String title,
    List<Widget> Function(String) builder, {
    IconData? icon,
    String? note,
  }) => section(
    title,
    [
      for (final g in visible) ...[
        if (visible.length > 1) subLabel(labels[g]!),
        ...builder(g),
        if (g != visible.last)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: line),
          ),
      ],
    ],
    icon: icon,
    note: note,
  );

  Widget moneyRow(String prefix, {String expenditure = 'consumption'}) => grid(
    [
      for (final h in ['opening', 'received', expenditure, 'closing'])
        field(
          '${prefix}_$h',
          h == 'consumption'
              ? 'Expenditure ₹'
              : '${h[0].toUpperCase()}${h.substring(1)} ₹',
          numeric: true,
        ),
    ],
    minWidth: 150,
    preferTwoOnMobile: true,
    maxColumns: 4,
  );

  Widget personPrimaryFields(String prefix, {bool required = false}) =>
      flexFields(
        [
          field(
            '${prefix}_name',
            'Name${required ? ' *' : ''}',
            required: required,
          ),
          choice(
            '${prefix}_gender',
            'Gender${required ? ' *' : ''}',
            ['M', 'F'],
          ),
          field('${prefix}_honorarium', 'Honorarium ₹', numeric: true),
        ],
        flexes: const [2, 1, 1],
        stackBelow: 600,
        compactPhone: true,
      );

  // Yes / No chips: chuna hua option par ✓ tick dikhta hai (dobara tap = clear).
  Widget tickChoice({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _fieldLabel(label),
          SizedBox(
            height: _h,
            child: Row(
              children: [
                for (final o in const ['Yes', 'No']) ...[
                  if (o == 'No') const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _generating
                          ? null
                          : () => onChanged(value == o ? '' : o),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: value == o
                              ? const Color(0xFFE8EDF4)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: value == o ? ink : line,
                            width: value == o ? 1.4 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (value == o) ...[
                              const Icon(
                                CupertinoIcons.checkmark_alt,
                                size: 15,
                                color: ink,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              o,
                              style: _valueStyle.copyWith(
                                fontWeight: value == o
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: value == o ? ink : muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );

  // Data me 'Y' / 'N' save hota hai (PDF isi ko padhta hai).
  Widget yesNoField(String key, String label) => tickChoice(
    label: label,
    value: f(key).text == 'Y'
        ? 'Yes'
        : f(key).text == 'N'
            ? 'No'
            : '',
    onChanged: (v) => setState(() {
      f(key).text = v == 'Yes'
          ? 'Y'
          : v == 'No'
              ? 'N'
              : '';
    }),
  );

  Widget personMoreDetails(String prefix) => grid(
    [
      choice('${prefix}_social', 'Social group', [
        'SC',
        'ST',
        'OBC',
        'MIN',
        'GEN',
      ]),
      yesNoField('${prefix}_bpl', 'BPL'),
      yesNoField('${prefix}_eshram', 'E-Shram'),
      choice('${prefix}_payment', 'Payment', ['Bank', 'Cash']),
      field('${prefix}_from', 'Joining date'),
      field('${prefix}_till', 'Till date'),
    ],
    minWidth: 170,
    preferTwoOnMobile: true,
    maxColumns: 3,
  );

  int get _totalEnrolled => visible.fold<int>(0, (a, g) => a + enrolled(g));
  bool get _cook2Needed => _totalEnrolled >= 60; // 60+ enrolment => 2 cooks

  // Cook 1 hamesha khula + More details khula. Enrolment 60+ ho to Cook 2 bhi waisa hi.
  // Milk helper hamesha dikhta hai; sirf optional Cook 2 (<60) aur Cook 3 fold hote hain.
  Widget cook(String prefix, String title, {bool required = false}) {
    final open = prefix == 'cook1' || (prefix == 'cook2' && _cook2Needed);
    return section(
      title,
      [
        personPrimaryFields(prefix, required: required),
        const SizedBox(height: 9),
        section(
          'More details',
          [personMoreDetails(prefix)],
          fold: true,
          expanded: open,
          nested: true,
        ),
      ],
      note: required
          ? 'Required · saved per school'
          : prefix == 'cook2' && _cook2Needed
              ? 'Needed for 60+ enrolment · saved per school'
              : 'Optional · saved per school',
      fold: (prefix == 'cook2' && !_cook2Needed) || prefix == 'cook3',
      expanded: prefix == 'cook2' && _cook2Needed,
      icon: Icons.person_outline_rounded,
    );
  }

  Widget metric(String label, Object? value, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: line),
    ),
    child: Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F4F7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: ink),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value ?? '—'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.05,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.05,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _tc(
    String text, {
    bool head = false,
    bool bold = false,
    bool left = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Text(
      text,
      textAlign: left ? TextAlign.left : TextAlign.right,
      style: TextStyle(
        fontSize: head ? 10.5 : 12,
        letterSpacing: 0,
        fontWeight: head
            ? FontWeight.w600
            : bold
                ? FontWeight.w700
                : FontWeight.w500,
        color: head ? muted : ink,
      ),
    ),
  );

  // Chhoti saaf table: header row + rows (last row bold ho sakti hai).
  Widget _dataTable(
    List<String> headers,
    List<List<String>> rows, {
    bool boldLast = false,
  }) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(2.2)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
            children: [
              for (int i = 0; i < headers.length; i++)
                _tc(headers[i], head: true, left: i == 0),
            ],
          ),
          for (int r = 0; r < rows.length; r++)
            TableRow(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: line)),
              ),
              children: [
                for (int i = 0; i < rows[r].length; i++)
                  _tc(
                    rows[r][i],
                    left: i == 0,
                    bold: boldLast && r == rows.length - 1,
                  ),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Text(k, style: const TextStyle(fontSize: 11, color: muted)),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(
              fontSize: 12,
              letterSpacing: 0,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ),
      ],
    ),
  );

  // PDF jaisa hi: OBC + SBC ek saath (SBC alag nahi jodte).
  String _enrol(String g, String cat, String k) {
    final grp = map(map(_school?['groups'])[g]);
    final num v;
    if (cat == 'obc_sbc') {
      final a = map(grp['obc'])[k];
      final b = map(grp['sbc'])[k];
      if (a is! num && b is! num) return '—';
      v = (a is num ? a : 0) + (b is num ? b : 0);
    } else {
      final x = map(grp[cat])[k];
      if (x is! num) return '—';
      v = x;
    }
    return '${v.toInt()}';
  }

  Widget verifiedSummary() => section(
    'Portal data',
    [
      grid(
        [
          metric(
            'Enrolled',
            visible.fold<int>(0, (n, g) => n + enrolled(g)),
            Icons.groups_2_outlined,
          ),
          metric(
            'Meals served',
            _monthly?['total_meals'],
            Icons.restaurant_outlined,
          ),
          metric('Meal days', _monthly?['served_days'], Icons.event_available),
          metric(
            'VIFFS · boys / girls',
            _viffs?['entry_available'] == true
                ? '${_viffs!['boys']} / ${_viffs!['girls']}'
                : '—',
            Icons.medication_outlined,
          ),
        ],
        minWidth: 150,
        preferTwoOnMobile: true,
        maxColumns: 4,
      ),
      const SizedBox(height: 8),
      section(
        'Enrolment',
        [
          for (final g in visible) ...[
            if (visible.length > 1) subLabel(labels[g]!),
            _dataTable(
              ['Category', 'Boys', 'Girls', 'Total'],
              [
                for (final c in const [
                  ['sc', 'SC'],
                  ['st', 'ST'],
                  ['obc_sbc', 'OBC + SBC'],
                  ['general', 'General'],
                  ['total', 'Total'],
                ])
                  [
                    c[1],
                    _enrol(g, c[0], 'boys'),
                    _enrol(g, c[0], 'girls'),
                    _enrol(g, c[0], 'total'),
                  ],
              ],
              boldLast: true,
            ),
            if (g != visible.last) const SizedBox(height: 8),
          ],
        ],
        fold: true,
        nested: true,
      ),
      section(
        'Foodgrain stock · kg',
        [
          _dataTable(
            ['Grain', 'Opening', 'Received', 'Used', 'Closing'],
            [
              for (final st in maps(_monthly?['stock']))
                [
                  '${st['product_name']}',
                  '${st['opening']}',
                  '${st['received']}',
                  '${st['outward']}',
                  '${st['closing']}',
                ],
            ],
          ),
          hint('Foodgrain stock is school-wide.'),
        ],
        fold: true,
        nested: true,
      ),
    ],
    note: 'Verified from portal',
    icon: Icons.verified_outlined,
  );

  DateTime? _parseReportDate(String raw) {
    final parts = raw.trim().split(RegExp(r'[-/]'));
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    try {
      return DateUtils.dateOnly(DateTime(y, m, d));
    } catch (_) {
      return null;
    }
  }

  String _formatReportDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.year.toString().padLeft(4, '0')}';

  Future<DateTime?> _pickMinimalDate(
    DateTime initial,
    DateTime firstDate,
    DateTime lastDate,
  ) async {
    DateTime selected = DateUtils.dateOnly(initial);
    int month = selected.month;
    int year = selected.year;

    return showDialog<DateTime>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.36),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final firstOfMonth = DateTime(year, month, 1);
          final daysInMonth = DateUtils.getDaysInMonth(year, month);
          final leading = firstOfMonth.weekday - DateTime.monday;

          bool enabled(DateTime d) {
            final day = DateUtils.dateOnly(d);
            return !day.isBefore(DateUtils.dateOnly(firstDate)) &&
                !day.isAfter(DateUtils.dateOnly(lastDate));
          }

          Widget picker<V>({
            required V current,
            required String text,
            required List<V> values,
            required String Function(V) labelOf,
            required ValueChanged<V> onPick,
          }) =>
              PopupMenuButton<V>(
                tooltip: '',
                initialValue: current,
                position: PopupMenuPosition.under,
                surfaceTintColor: Colors.transparent,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                onSelected: onPick,
                itemBuilder: (_) => [
                  for (final v in values)
                    PopupMenuItem<V>(
                      value: v,
                      height: 36,
                      child: Text(
                        labelOf(v),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              v == current ? FontWeight.w700 : FontWeight.w500,
                          color: v == current
                              ? const Color(0xFFEF4444)
                              : ink,
                        ),
                      ),
                    ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      text,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(
                      CupertinoIcons.chevron_down,
                      size: 11,
                      color: Color(0xFFEF4444),
                    ),
                  ],
                ),
              );

          void clampDay() {
            final maxDay = DateUtils.getDaysInMonth(year, month);
            if (selected.day > maxDay) {
              selected = DateTime(year, month, maxDay);
            }
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              width: 285,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.14),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      picker<int>(
                        current: month,
                        text: monthNames[month - 1],
                        values: [for (int m = 1; m <= 12; m++) m],
                        labelOf: (m) => monthNames[m - 1],
                        onPick: (v) => setLocal(() {
                          month = v;
                          clampDay();
                        }),
                      ),
                      const SizedBox(width: 12),
                      picker<int>(
                        current: year,
                        text: '$year',
                        values: [
                          for (int y = firstDate.year; y <= lastDate.year; y++)
                            y,
                        ],
                        labelOf: (y) => '$y',
                        onPick: (v) => setLocal(() {
                          year = v;
                          clampDay();
                        }),
                      ),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          final prev = DateTime(year, month - 1, 1);
                          if (!prev.isBefore(
                            DateTime(firstDate.year, firstDate.month, 1),
                          )) {
                            setLocal(() {
                              year = prev.year;
                              month = prev.month;
                              clampDay();
                            });
                          }
                        },
                        icon: const Icon(CupertinoIcons.chevron_left, size: 16),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          final next = DateTime(year, month + 1, 1);
                          if (!next.isAfter(
                            DateTime(lastDate.year, lastDate.month, 1),
                          )) {
                            setLocal(() {
                              year = next.year;
                              month = next.month;
                              clampDay();
                            });
                          }
                        },
                        icon:
                            const Icon(CupertinoIcons.chevron_right, size: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final day in const [
                        'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su',
                      ])
                        Expanded(
                          child: Center(
                            child: Text(
                              day,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: muted,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: leading + daysInMonth,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 3,
                      crossAxisSpacing: 3,
                    ),
                    itemBuilder: (_, index) {
                      if (index < leading) return const SizedBox.shrink();
                      final day = index - leading + 1;
                      final date = DateTime(year, month, day);
                      final isEnabled = enabled(date);
                      final isSelected = selected.year == year &&
                          selected.month == month &&
                          selected.day == day;

                      return InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: isEnabled
                            ? () => setLocal(() => selected = date)
                            : null,
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFEF4444)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: !isEnabled
                                  ? const Color(0xFFCBD5E1)
                                  : isSelected
                                      ? Colors.white
                                      : ink,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: enabled(selected)
                            ? () => Navigator.pop(
                                  ctx,
                                  DateUtils.dateOnly(selected),
                                )
                            : null,
                        child: const Text(
                          'OK',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
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
  }

  Widget reportDateField() {
    final controller = f('report_date');
    final bad = _manualInvalid.contains('report_date');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('Report date', invalid: bad),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _generating
              ? null
              : () async {
                  final today = DateUtils.dateOnly(DateTime.now());
                  var initial = _parseReportDate(controller.text) ?? today;
                  if (initial.isAfter(today)) initial = today;
                  if (initial.isBefore(DateTime(2024))) {
                    initial = DateTime(2024);
                  }

                  final picked = await _pickMinimalDate(
                    initial,
                    DateTime(2024),
                    today,
                  );
                  if (picked == null || !mounted) return;
                  controller.text = _formatReportDate(picked);
                  _manualInvalid.remove('report_date');
                  setState(() {});
                },
          child: Container(
            height: _h,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: bad ? danger : line,
                width: bad ? 1.25 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    controller.text.trim().isEmpty
                        ? 'DD-MM-YYYY'
                        : controller.text.trim(),
                    style: _valueStyle.copyWith(
                      color: controller.text.trim().isEmpty
                          ? const Color(0xFF94A3B8)
                          : ink,
                    ),
                  ),
                ),
                const Icon(CupertinoIcons.calendar, size: 15, color: ink),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget schoolDetailsPanel() {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return section(
      'School details',
      [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: mobile ? 10 : 12,
            vertical: mobile ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: line),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: line),
                ),
                child: const Icon(Icons.school_outlined, size: 16, color: ink),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_school?['school_name'] ?? 'School'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'UDISE ${_school?['udise'] ?? '—'}  •  NIC ${_school?['school_id'] ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                ),
              ),
              const Icon(CupertinoIcons.checkmark_seal_fill,
                  size: 15, color: Color(0xFF16A34A)),
            ],
          ),
        ),
        const SizedBox(height: 9),
        subLabel('Report'),
        grid(
          [
            field('dispatch', 'Dispatch no.'),
            reportDateField(),
            field('working_days', 'Working days', numeric: true, integer: true),
          ],
          minWidth: 145,
          preferTwoOnMobile: true,
          maxColumns: 3,
        ),
        const SizedBox(height: 10),
        subLabel('Facilities'),
        grid(
          [
            choice(
              'school_detail_kitchen_shed',
              'Kitchen shed',
              const ['Complete', 'Incomplete', 'Repairable', 'N.A.'],
            ),
            choice(
              'school_detail_gas_connection',
              'Gas connection',
              const ['YES-SBC', 'YES-DBC', 'NO'],
            ),
            choice(
              'school_detail_utensils',
              'Utensils',
              const ['Sufficient', 'Un-Sufficient'],
            ),
            yesNoField('school_detail_drinking_water', 'Drinking water'),
            yesNoField('school_detail_fire_extinguisher', 'Fire extinguisher'),
            yesNoField('school_detail_weighing_machine', 'Weighing machine'),
            yesNoField('school_detail_height_measurement', 'Height measure'),
            yesNoField('school_detail_hand_washing', 'Hand washing'),
            yesNoField('school_detail_electricity', 'Electricity'),
            choice(
              'school_detail_toilet_status',
              'Toilet status',
              const ['Complete', 'Incomplete', 'Repairable', 'N.A.'],
            ),
            field('school_detail_toilet_boys', 'Boys toilets', numeric: true, integer: true),
            field('school_detail_toilet_girls', 'Girls toilets', numeric: true, integer: true),
          ],
          minWidth: 145,
          preferTwoOnMobile: true,
          maxColumns: 4,
        ),
        const SizedBox(height: 2),
        hint('Saved per school • printed directly in the MPR header.'),
      ],
      note: 'Visible here for faster monthly filling',
      icon: Icons.domain_outlined,
    );
  }

  // ───────── Step 1 · Meals ─────────
  List<Widget> reportPage() => [
    schoolDetailsPanel(),
    verifiedSummary(),
    for (final g in visible)
      section(
        labels[g]!,
        [
          subLabel('Cooking cost'),
          grid([
            field(
              'cooking_rate_$g',
              'Cooking rate ₹ / meal',
              numeric: true,
              required: map(_mealGroups[g])['total_meals'] != null,
            ),
            readonlyBox('Cooking expenditure', '₹ ${calc(g)}'),
          ], minWidth: 170, preferTwoOnMobile: true, maxColumns: 2),
          const SizedBox(height: 8),
          subLabel('Milk served'),
          grid([
            field(
              'milk_days_$g',
              'Milk served days',
              numeric: true,
              integer: true,
            ),
            field(
              'milk_count_$g',
              'Total milk servings',
              numeric: true,
              integer: true,
            ),
          ], minWidth: 160, preferTwoOnMobile: true, maxColumns: 2),
          const SizedBox(height: 8),
          section(
            'Attendance · optional',
            [
              grid([
                field(
                  'attendance_$g',
                  'Total attendance',
                  numeric: true,
                  integer: true,
                ),
                field('average_$g', 'Average override', numeric: true),
              ], minWidth: 160, preferTwoOnMobile: true, maxColumns: 2),
              hint(
                'Leave blank to keep the PDF blank. Average uses total attendance ÷ working days.',
              ),
            ],
            fold: true,
            nested: true,
          ),
        ],
        icon: Icons.restaurant_menu_rounded,
      ),
  ];

  // ───────── Step 2 · Milk & gas ─────────
  List<Widget> milkPage() => [
    groupFields(
      'Milk powder · kg',
      (g) => [
        grid(
          [
            field('powder_${g}_opening', 'Opening kg', numeric: true),
            field('powder_${g}_received', 'Received kg', numeric: true),
            field('powder_rate_$g', 'Grams / serving', numeric: true),
            readonlyBox('Consumption kg · auto', _powder(g)[0]),
            readonlyBox('Closing kg · auto', _powder(g)[1]),
          ],
          minWidth: 170,
          preferTwoOnMobile: true,
          maxColumns: 3,
        ),
        hint(
          'Consumption = milk servings (Step 1) × grams ÷ 1000. Closing = opening + received − consumption.',
        ),
      ],
      icon: Icons.local_drink_outlined,
    ),
    groupFields(
      'Sugar amount · ₹',
      (g) => [moneyRow('sugar_$g')],
      icon: Icons.cookie_outlined,
    ),
    section('Sugar consumed · kg', [
      grid([
        for (final g in visible)
          field('sugar_kg_$g', labels[g]!, numeric: true),
      ], minWidth: 170, preferTwoOnMobile: true, maxColumns: 3),
      hint(
        'Sugar amounts automatically copy into Part 11. Kilograms are entered separately.',
      ),
    ], icon: Icons.scale_outlined),
    section('Milk helper expenditure · ₹', [
      moneyRow('milk_helper'),
    ], icon: Icons.volunteer_activism_outlined),
    section('Gas cylinder · ₹', [
      moneyRow('gas'),
    ], icon: Icons.local_fire_department_outlined),
  ];

  // ───────── Step 3 · Staff ─────────
  List<Widget> peoplePage() => [
    cook('cook1', 'Cook 1', required: true),
    cook('cook2', 'Cook 2'),
    cook('cook3', 'Cook 3'),
    cook('helper', 'Milk work helper'),
    section('MDM incharge', [
      flexFields(
        [
          field('incharge_name', 'Name'),
          field('incharge_mobile', 'Mobile'),
        ],
        flexes: const [2, 1],
        stackBelow: 520,
      ),
      hint('Loaded from portal profile; editable and saved per school.'),
    ], icon: Icons.badge_outlined),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: _generating
            ? null
            : () async {
                await _saveSettings();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cook/helper details saved.')),
                  );
                }
              },
        icon: const Icon(Icons.bookmark_border_rounded, size: 16),
        label: const Text(
          'Save cook/helper details',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  ];

  // ───────── Step 4 · Health & others ─────────
  List<Widget> otherPage() => [
    section('Children health', [
      grid([
        field(
          'viffs_boys',
          '4+ tablets · boys',
          numeric: true,
          integer: true,
          readonly: _viffs?['entry_available'] == true,
        ),
        field(
          'viffs_girls',
          '4+ tablets · girls',
          numeric: true,
          integer: true,
          readonly: _viffs?['entry_available'] == true,
        ),
      ], minWidth: 160, preferTwoOnMobile: true, maxColumns: 2),
      _viffs?['entry_available'] == true
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: const [
                  Icon(CupertinoIcons.checkmark_alt, size: 12, color: muted),
                  SizedBox(width: 5),
                  Text(
                    'Verified from portal',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                  ),
                ],
              ),
            )
          : hint('No locked counts loaded. Leave blank or enter manually.'),
      const SizedBox(height: 8),
      flexFields(
        [
          field('checked_name', 'Checked by'),
          field('checked_mobile', 'Mobile'),
        ],
        flexes: const [2, 1],
        stackBelow: 520,
      ),
    ], icon: Icons.favorite_border_rounded),
    section('School inspection', [
      tickChoice(
        label: 'Inspection done?',
        value: _inspection,
        onChanged: (v) => setState(() => _inspection = v),
      ),
      if (_inspection == 'Yes')
        for (int i = 1; i <= 4; i++)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: flexFields(
              [
                field(
                  'inspection_${i}_name',
                  '${['Task force', 'District', 'Block / PEEO', 'SMC'][i - 1]} · name & post',
                ),
                field(
                  'inspection_${i}_count',
                  'Number',
                  numeric: true,
                  integer: true,
                ),
              ],
              flexes: const [3, 1],
              stackBelow: 600,
            ),
          ),
    ], icon: Icons.fact_check_outlined),
    section(
      'CCH & MME',
      [
        for (final r in ['cch', 'mme'])
          section(
            r.toUpperCase(),
            [moneyRow(r, expenditure: 'expenditure')],
            nested: true,
          ),
      ],
      fold: true,
      note: 'Optional',
      icon: Icons.account_balance_wallet_outlined,
    ),
    section(
      'Bank details',
      [
        for (final r in ['all', 'interest', 'total'])
          section(
            r == 'all'
                ? 'All heads'
                : r == 'interest'
                    ? 'Interest'
                    : 'Total',
            [moneyRow('bank_$r', expenditure: 'expenditure')],
            nested: true,
          ),
      ],
      fold: true,
      note: 'Optional',
      icon: Icons.account_balance_outlined,
    ),
  ];

  Widget periodPicker({bool labels = true}) => Row(
    children: [
      Expanded(
        child: _popupField<int>(
          label: 'Month',
          showLabel: labels,
          value: _month,
          enabled: !_loading && !_generating,
          items: [
            for (int m = 1; m <= 12; m++) MapEntry(m, monthNames[m - 1]),
          ],
          onSelected: (m) {
            if (m == _month) return;
            setState(() {
              _month = m;
              _clearMonth();
            });
            _load();
          },
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _popupField<int>(
          label: 'Year',
          showLabel: labels,
          value: _year,
          enabled: !_loading && !_generating,
          items: [
            for (int y = DateTime.now().year - 5; y <= DateTime.now().year; y++)
              MapEntry(y, '$y'),
          ],
          onSelected: (y) {
            if (y == _year) return;
            setState(() {
              _year = y;
              _clearMonth();
            });
            _load();
          },
        ),
      ),
    ],
  );

  Widget notices() => Column(
    children: [
      for (final e in _errors.entries)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: Color(0xFFEA580C),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${e.key}: ${e.value}',
                  style: const TextStyle(fontSize: 12, color: ink, height: 1.5),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  void switchPage(int page) {
    HapticFeedback.selectionClick();
    setState(() => _page = page);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  // ───────── Stepper header ─────────
  // Modern segmented progress: done = green, current = dark, upcoming = grey.
  Widget stepper() => Row(
    children: [
      for (int i = 0; i < stepLabels.length; i++)
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _generating ? null : () => switchPage(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? ink
                          : i < _page
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFD5DCE6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (i < _page) ...[
                        const Icon(
                          CupertinoIcons.checkmark_alt,
                          size: 11,
                          color: Color(0xFF16A34A),
                        ),
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(
                          stepLabels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                i == _page ? FontWeight.w700 : FontWeight.w500,
                            color: i == _page ? ink : muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Widget intro(int i) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                stepTitles[i],
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
            Text(
              '${i + 1}/${stepLabels.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          stepSubs[i],
          style: const TextStyle(fontSize: 11, color: muted, height: 1.3),
        ),
      ],
    ),
  );

  // School info + (sirf step 1 par) Month/Year ek hi card me; scroll ke saath jaata hai.
  Widget headerCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            iconBadge(Icons.school_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_school!['school_name']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'UDISE ${_school!['udise']} · NIC ${_school!['school_id']}',
                    style: const TextStyle(fontSize: 10, color: muted),
                  ),
                ],
              ),
            ),
            if (_page != 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F4F7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${monthNames[_month - 1]} $_year',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (_page == 0) ...[
          const SizedBox(height: 10),
          periodPicker(labels: false),
        ],
      ],
    ),
  );

  bool _validateStep(int step) {
    final missing = <String>{};

    if (step == 0) {
      for (final g in visible) {
        if (map(_mealGroups[g])['total_meals'] != null) {
          final key = 'cooking_rate_$g';
          final value = f(key).text.trim();
          if (value.isEmpty ||
              !RegExp(r'^\d+(\.\d+)?$').hasMatch(value) ||
              double.tryParse(value)?.isFinite != true) {
            missing.add(key);
          }
        }
      }
    }

    if (step == 2) {
      if (f('cook1_name').text.trim().isEmpty) missing.add('cook1_name');
      if (!['M', 'F'].contains(f('cook1_gender').text)) {
        missing.add('cook1_gender');
      }
    }

    if (missing.isNotEmpty) {
      setState(() {
        _manualInvalid
          ..clear()
          ..addAll(missing);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete the highlighted required fields.'),
        ),
      );
      return false;
    }

    if (_manualInvalid.isNotEmpty) {
      setState(() => _manualInvalid.clear());
    }
    return true;
  }

  void _nextStep() {
    if (_generating) return;
    if (!_validateStep(_page)) return;
    if (_page < _lastStep) switchPage(_page + 1);
  }

  // Sab pages mounted hain, isliye poora validate karke pehle galat step par le jaata hai.
  Future<void> _onGenerate() async {
    if (!_ready || _generating) return;

    if (!_validateStep(0)) {
      switchPage(0);
      return;
    }
    if (!_validateStep(2)) {
      switchPage(2);
      return;
    }

    _invalidKey = null;
    final valid = _form.currentState?.validate() ?? false;
    if (!valid) {
      final key = _invalidKey;
      switchPage(pageFor(key ?? 'cook1_name'));
      if (key != null) setState(() => _manualInvalid.add(key));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fix the highlighted field before generating.'),
        ),
      );
      return;
    }

    await _generate();
  }

  PreferredSizeWidget _alignedTopBar({
    required String title,
    required VoidCallback onBack,
    Widget? action,
  }) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: Material(
        color: const Color(0xF2F8FAFC),
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isPhone = width < 600;
              final contentWidth = isPhone
                  ? width
                  : AppAdaptive.contentWidth(width);
              final side = width >= 900
                  ? 20.0
                  : isPhone
                      ? 10.0
                      : 14.0;

              return Center(
                child: SizedBox(
                  width: contentWidth,
                  height: 56,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: side),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton(
                            tooltip: 'Back',
                            padding: EdgeInsets.zero,
                            splashRadius: 18,
                            onPressed: onBack,
                            icon: const Icon(
                              CupertinoIcons.chevron_back,
                              size: 19,
                              color: ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                        ),
                        if (action != null) ...[
                          const SizedBox(width: 8),
                          action,
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _circleTopAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    Color iconColor = ink,
  }) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xF5FFFFFF),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE5EAF0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        splashRadius: 19,
        icon: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }

  Widget _appBackground() => const Positioned.fill(
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.45, 1.0],
                    colors: [
                      Color(0xFFF8FAFC),
                      Color(0xFFF1F5F9),
                      Color(0xFFFEF3C7),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: -50,
                top: -40,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0x59BAE6FD),
                        Color(0x00BAE6FD),
                      ],
                    ),
                  ),
                  child: SizedBox(width: 270, height: 270),
                ),
              ),
              Positioned(
                right: -50,
                top: 40,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0x59FDE68A),
                        Color(0x00FDE68A),
                      ],
                    ),
                  ),
                  child: SizedBox(width: 260, height: 260),
                ),
              ),
            ],
          ),
        ),
      );

  Widget bottomBar() {
    final last = _page == _lastStep;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isPhone = screenWidth < 600;

    final side = screenWidth >= 900
        ? 20.0
        : isPhone
            ? 10.0
            : 14.0;

    final contentWidth = isPhone
        ? screenWidth
        : AppAdaptive.contentWidth(screenWidth);

    Widget backButton() => SizedBox(
          height: 40,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: ink,
              side: const BorderSide(color: line),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _generating ? null : () => switchPage(_page - 1),
            icon: const Icon(CupertinoIcons.chevron_back, size: 12.5),
            label: Text(
              isPhone ? 'Back' : 'Back',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );

    Widget cookingTotal() => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Cooking total',
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1,
                  color: muted,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _hasTotal ? '₹ $_totalCooking' : '—',
                style: const TextStyle(
                  fontSize: 14,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          ),
        );

    Widget primaryButton() => SizedBox(
          height: 40,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _generating && last
                  ? const Color(0xFFF1F6FD)
                  : ink,
              foregroundColor: _generating && last
                  ? ink
                  : Colors.white,
              disabledBackgroundColor: _generating && last
                  ? const Color(0xFFF1F6FD)
                  : const Color(0xFFCBD5E1),
              disabledForegroundColor: _generating && last
                  ? ink
                  : Colors.white,
              elevation: 0,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: _generating && last
                    ? const BorderSide(color: Color(0xFFD7E8FC))
                    : BorderSide.none,
              ),
            ),
            onPressed: _generating
                ? null
                : last
                    ? _onGenerate
                    : _nextStep,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: _generating && last
                  ? Row(
                      key: const ValueKey('generating'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NicDownloadIndicator(
                          size: 19,
                          progress: _pdfProgress,
                          color: const Color(0xFF007AFF),
                          trackColor: const Color(0x2E007AFF),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Generating…',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: ink,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      key: ValueKey(last ? 'generate' : 'next'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (last) ...[
                          const Icon(CupertinoIcons.doc_text, size: 12.5),
                          const SizedBox(width: 7),
                        ],
                        Text(
                          last ? 'Generate PDF' : 'Next',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!last) ...[
                          const SizedBox(width: 7),
                          const Icon(
                            CupertinoIcons.chevron_forward,
                            size: 12.5,
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        );

    return SizedBox(
      height: 58,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          minimum: EdgeInsets.zero,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: contentWidth,
              child: Padding(
                padding: EdgeInsets.fromLTRB(side, 5, side, 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_page > 0) backButton(),
                    const Spacer(),
                    cookingTotal(),
                    primaryButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _ready
        ? [reportPage(), milkPage(), peoplePage(), otherPage()]
        : <List<Widget>>[];

    final theme = ThemeData(
      useMaterial3: true,
      fontFamily: 'PlusJakartaSans',
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      colorScheme: const ColorScheme.light(
        primary: ink,
        onPrimary: Colors.white,
        secondary: ink,
        surface: Colors.white,
        onSurface: ink,
        error: danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF8FAFC),
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      dividerColor: line,
      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: muted,
        collapsedIconColor: muted,
        textColor: ink,
        collapsedTextColor: ink,
      ),
    );

    return Theme(
      data: theme,
      child: PopScope(
        canPop: !_generating,
        child: Scaffold(
          extendBody: true,
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: _alignedTopBar(
            title: 'MPR & Milk Report',
            onBack: () => Navigator.maybePop(context),
            action: _circleTopAction(
              tooltip: 'Refresh portal data',
              icon: CupertinoIcons.refresh,
              onPressed: _loading || _generating ? null : _load,
              iconColor: muted,
            ),
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              _appBackground(),
              SafeArea(
                top: false,
                child: LayoutBuilder(
                  builder: (context, viewport) {
                    final isPhone = viewport.maxWidth < 600;
                    final side = viewport.maxWidth >= 900
                        ? 20.0
                        : isPhone
                            ? 10.0
                            : 14.0;
                    final maxContentWidth = isPhone
                        ? viewport.maxWidth
                        : AppAdaptive.contentWidth(viewport.maxWidth);

                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: maxContentWidth,
                          minWidth: isPhone ? viewport.maxWidth : 0,
                        ),
                        child: Column(
                          children: [
                            if (!_ready)
                              Padding(
                                padding: EdgeInsets.fromLTRB(side, 2, side, 8),
                                child: periodPicker(),
                              ),
                            if (_ready) ...[
                              Padding(
                                padding: EdgeInsets.fromLTRB(side, 4, side, 0),
                                child: stepper(),
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: Form(
                                  key: _form,
                                  child: SingleChildScrollView(
                                    controller: _scroll,
                                    keyboardDismissBehavior:
                                        ScrollViewKeyboardDismissBehavior.onDrag,
                                    padding: EdgeInsets.fromLTRB(
                                      side,
                                      0,
                                      side,
                                      88,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        headerCard(),
                                        const SizedBox(height: 6),
                                        notices(),
                                        for (int i = 0; i < pages.length; i++)
                                          Offstage(
                                            offstage: _page != i,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                intro(i),
                                                ...pages[i],
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ] else
                              Expanded(
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: _loading
                                        ? const Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 26,
                                                height: 26,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2.4,
                                                  color: ink,
                                                ),
                                              ),
                                              SizedBox(height: 18),
                                              Text(
                                                'Preparing your monthly report',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              SizedBox(height: 6),
                                              Text(
                                                'Loading school, meals, stock and VIFFS…',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: muted,
                                                ),
                                              ),
                                            ],
                                          )
                                        : SingleChildScrollView(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.description_outlined,
                                                  size: 32,
                                                  color: muted,
                                                ),
                                                const SizedBox(height: 8),
                                                const Text(
                                                  'Report data could not be loaded',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                notices(),
                                                OutlinedButton.icon(
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor: ink,
                                                  ),
                                                  onPressed: _load,
                                                  icon: const Icon(
                                                    Icons.refresh_rounded,
                                                    size: 18,
                                                  ),
                                                  label:
                                                      const Text('Try again'),
                                                ),
                                              ],
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          bottomNavigationBar: _ready ? bottomBar() : null,
        ),
      ),
    );
  }

  void _clearMonth() {
    for (final e in _fields.entries) {
      if (!savedKey(e.key)) e.value.clear();
    }
    f('milk_helper_consumption').text = '500';
    _inspection = '';
  }
}

class NicDownloadIndicator extends StatelessWidget {
  final double size;
  final double progress;
  final Color color;
  final Color? trackColor;

  const NicDownloadIndicator({
    super.key,
    this.size = 17.0,
    required this.progress,
    this.color = const Color(0xFF007AFF),
    this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: 0.0,
        end: progress.clamp(0.0, 1.0).toDouble(),
      ),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _IosProgressRingPainter(
              progress: animatedValue,
              color: color,
              trackColor: trackColor ?? color.withValues(alpha: 0.18),
            ),
          ),
        );
      },
    );
  }
}

class _IosProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _IosProgressRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.125;
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0.02) {
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;

      const startAngle = -1.5707963267948966;
      final sweepAngle = progress * 6.283185307179586;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }

    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth * 0.95;

    final arrowTop = center.dy - (size.height * 0.20);
    final arrowBottom = center.dy + (size.height * 0.20);
    final wingSpanX = size.width * 0.16;
    final wingSpanY = size.height * 0.14;

    final arrowPath = Path()
      ..moveTo(center.dx, arrowTop)
      ..lineTo(center.dx, arrowBottom)
      ..moveTo(center.dx - wingSpanX, arrowBottom - wingSpanY)
      ..lineTo(center.dx, arrowBottom)
      ..lineTo(center.dx + wingSpanX, arrowBottom - wingSpanY);

    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _IosProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}

