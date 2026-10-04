// lib/tabs/teacher/modules/shaladarpan/incharge_roles_view.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/core/backend_config.dart';

const String kAppFont = 'PlusJakartaSans';

class InchargeRolesView extends StatefulWidget {
  final String? schoolId;
  const InchargeRolesView({super.key, this.schoolId});

  @override
  State<InchargeRolesView> createState() => _InchargeRolesViewState();
}

class _InchargeRolesViewState extends State<InchargeRolesView> {
  String get _baseUrl => BackendConfig.baseUrl;

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _selectedRoleId;
  String? _selectedTeacherId;

  List<Map<String, dynamic>> _rolesList = [];
  List<Map<String, dynamic>> _teachersList = [];
  List<Map<String, dynamic>> _currentIncharges = [];

  OverlayEntry? _currentToastEntry;

  @override
  void initState() {
    super.initState();
    _loadCachedDataFirst();
  }

  @override
  void dispose() {
    _currentToastEntry?.remove();
    super.dispose();
  }

  void _haptic() => HapticFeedback.selectionClick();

  void _showAppleToast(String message, {IconData icon = CupertinoIcons.checkmark_alt, Color iconColor = const Color(0xFF34C759)}) {
    _haptic();
    _currentToastEntry?.remove();
    _currentToastEntry = null;

    final overlay = Overlay.of(context);
    final topInset = MediaQuery.of(context).padding.top;

    _currentToastEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: topInset + 12,
        left: 24,
        right: 24,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8.5),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withOpacity(0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: iconColor, size: 14),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      message,
                      style: const TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_currentToastEntry!);
    Future.delayed(const Duration(milliseconds: 2100), () {
      _currentToastEntry?.remove();
      _currentToastEntry = null;
    });
  }

  Future<void> _loadCachedDataFirst() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_incharge_mapping');
      if (cached != null && cached.isNotEmpty) {
        final data = jsonDecode(cached);
        if (data is Map) {
          _applyPayload(Map<String, dynamic>.from(data));
        }
      }
    } catch (_) {}

    _fetchInchargeData(silent: _currentIncharges.isNotEmpty);
  }

  Future<void> _fetchInchargeData({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final sId = widget.schoolId ?? prefs.getString('saved_school_id') ?? prefs.getString('school_id') ?? "480481";

      final res = await http.post(
        Uri.parse("$_baseUrl/api/shaladarpan/incharge/fetch"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'school_id': sId}),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded['success'] == true) {
          await prefs.setString('cached_incharge_mapping', jsonEncode(decoded));
          if (mounted) {
            setState(() {
              _applyPayload(Map<String, dynamic>.from(decoded));
              _isLoading = false;
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("Incharge fetch error: $e");
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _applyPayload(Map<String, dynamic> data) {
    if (data['roles'] is List) {
      _rolesList = List<Map<String, dynamic>>.from(
        (data['roles'] as List).map((x) => Map<String, dynamic>.from(x)),
      );
    }
    if (data['teachers'] is List) {
      _teachersList = List<Map<String, dynamic>>.from(
        (data['teachers'] as List).map((x) => Map<String, dynamic>.from(x)),
      );
    }
    if (data['current_list'] is List) {
      _currentIncharges = List<Map<String, dynamic>>.from(
        (data['current_list'] as List).map((x) => Map<String, dynamic>.from(x)),
      );
    }
  }

  // 🌟 Modern Sleek Bottom Sheet Picker
  void _showModernSelector({
    required String title,
    required List<Map<String, dynamic>> items,
    required String? selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    _haptic();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontFamily: kAppFont, fontSize: 16.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final val = item['value'].toString();
                  final label = item['label'].toString();
                  final isSelected = selectedValue == val;

                  return GestureDetector(
                    onTap: () {
                      _haptic();
                      onSelected(val);
                      Navigator.pop(ctx);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFF1F5F9) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontFamily: kAppFont,
                                fontSize: MediaQuery.sizeOf(context).width < 452 ? 11.5 : 13.0,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155),
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_rounded, color: Color(0xFF0F172A), size: 18),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Confirmation Modal before Adding Incharge
  void _confirmAddIncharge() {
    if (_selectedRoleId == null || _selectedRoleId == "-1" || _selectedTeacherId == null || _selectedTeacherId == "-1") {
      _showAppleToast("Please select both Role and Incharge", icon: CupertinoIcons.exclamationmark_triangle, iconColor: const Color(0xFFF59E0B));
      return;
    }

    final roleLabel = _rolesList.firstWhere((r) => r['value'].toString() == _selectedRoleId, orElse: () => {'label': 'Selected Role'})['label'];
    final teacherLabel = _teachersList.firstWhere((t) => t['value'].toString() == _selectedTeacherId, orElse: () => {'label': 'Selected Teacher'})['label'];

    _haptic();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(22.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.verified_user_rounded, color: Color(0xFF0F172A), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Confirm Incharge Assignment", style: TextStyle(fontFamily: kAppFont, fontSize: 16.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                      Text("Are you sure you want to assign this role on portal?", style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Role: $roleLabel", style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                  const SizedBox(height: 4),
                  Text("Incharge: $teacherLabel", style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w500, color: Color(0xFF475569))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel", style: TextStyle(fontFamily: kAppFont, color: Color(0xFF475569), fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _addIncharge();
                    },
                    child: const Text("Yes, Assign", style: TextStyle(fontFamily: kAppFont, color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addIncharge() async {
    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final sId = widget.schoolId ?? prefs.getString('saved_school_id') ?? "480481";

      final res = await http.post(
        Uri.parse("$_baseUrl/api/shaladarpan/incharge/action"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'school_id': sId,
          'action_type': 'add',
          'role_id': _selectedRoleId,
          'teacher_id': _selectedTeacherId,
        }),
      ).timeout(const Duration(seconds: 35));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded['success'] == true && decoded['data'] != null) {
          final responseData = Map<String, dynamic>.from(decoded['data']);
          await prefs.setString('cached_incharge_mapping', jsonEncode(responseData));
          setState(() {
            _applyPayload(responseData);
            _selectedRoleId = null;
            _selectedTeacherId = null;
            _isSubmitting = false;
          });
          _showAppleToast("Incharge assigned successfully");
          return;
        }
      }
      throw Exception("Failed to assign incharge");
    } catch (e) {
      if (mounted) setState(() => _isSubmitting = false);
      _showAppleToast("Error: $e", icon: CupertinoIcons.xmark_circle, iconColor: const Color(0xFFDC2626));
    }
  }

  void _confirmDeactivateIncharge(String buttonId, String roleName) {
    _haptic();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(22.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Deactivate Incharge Role", style: TextStyle(fontFamily: kAppFont, fontSize: 16.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                      Text("Are you sure you want to remove this charge?", style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Text("Role: $roleName", style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel", style: TextStyle(fontFamily: kAppFont, color: Color(0xFF475569), fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deactivateIncharge(buttonId);
                    },
                    child: const Text("Yes, Deactivate", style: TextStyle(fontFamily: kAppFont, color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deactivateIncharge(String buttonId) async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final sId = widget.schoolId ?? prefs.getString('saved_school_id') ?? "480481";

      final res = await http.post(
        Uri.parse("$_baseUrl/api/shaladarpan/incharge/action"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'school_id': sId,
          'action_type': 'deactive',
          'button_id': buttonId,
          'employee_id': _currentIncharges.firstWhere((r) => r['button_id']?.toString() == buttonId)['employee_id'],
          'expected_role': _currentIncharges.firstWhere((r) => r['button_id']?.toString() == buttonId)['role'],
        }),
      ).timeout(const Duration(seconds: 35));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded['success'] == true && decoded['data'] != null) {
          final responseData = Map<String, dynamic>.from(decoded['data']);
          await prefs.setString('cached_incharge_mapping', jsonEncode(responseData));
          setState(() {
            _applyPayload(responseData);
            _isLoading = false;
          });
          _showAppleToast("Incharge deactivated successfully");
          return;
        }
      }
      throw Exception("Failed to deactivate");
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showAppleToast("Error: $e", icon: CupertinoIcons.xmark_circle, iconColor: const Color(0xFFDC2626));
    }
  }

  Widget _selectorField({required String label, required String placeholder,
      required bool empty, required bool compact,
      required VoidCallback? onTap}) {
    return Semantics(button: true, enabled: onTap != null, child: Material(
      color: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9),
        side: const BorderSide(color: Color(0xFFE2E8F0))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Expanded(child: Text(empty ? placeholder : label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: kAppFont, fontSize: compact ? 11.5 : 13,
                fontWeight: empty ? FontWeight.w400 : FontWeight.w500,
                color: empty ? const Color(0xFF94A3B8) : const Color(0xFF0F172A)))),
          ]),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _rolesList.isEmpty && _teachersList.isEmpty && _currentIncharges.isEmpty) {
      return const Center(child: CupertinoActivityIndicator(radius: 12));
    }
    // Find selected labels for display
    final selectedRoleLabel = _selectedRoleId == null || _selectedRoleId == "-1"
        ? "-Select Role -"
        : (_rolesList.firstWhere((r) => r['value'].toString() == _selectedRoleId, orElse: () => {'label': '-Select Role -'})['label'].toString());

    final selectedTeacherLabel = _selectedTeacherId == null || _selectedTeacherId == "-1"
        ? "-Select Incharge -"
        : (_teachersList.firstWhere((t) => t['value'].toString() == _selectedTeacherId, orElse: () => {'label': '-Select Incharge -'})['label'].toString());

    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 420;
      return RefreshIndicator(
      onRefresh: () => _fetchInchargeData(),
      color: const Color(0xFF0F172A),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Notice Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Color(0xFF64748B), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "एक रोल में एक ही इंचार्ज को नियुक्त किया जा सकता है। इंचार्ज बदलने के लिए पहले पुराने को Deactive करें।",
                      style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, height: 1.5, fontWeight: FontWeight.w400, color: Color(0xFF475569)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Assignment Form Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Assign New Incharge Role",
                    style: TextStyle(fontFamily: kAppFont, fontSize: 14.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 12),

                  // Modern Role Selector
                  const Text("Select Role", style: TextStyle(fontFamily: kAppFont,
                    fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  _selectorField(
                    label: selectedRoleLabel,
                    placeholder: '-Select Role -',
                    empty: _selectedRoleId == null || _selectedRoleId == '-1',
                    compact: compact,
                    onTap: _isSubmitting || _isLoading ? null : () => _showModernSelector(
                      title: 'Select Role',
                      items: _rolesList,
                      selectedValue: _selectedRoleId,
                      onSelected: (val) => setState(() => _selectedRoleId = val),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Modern Teacher Selector
                  const Text("Select Incharge", style: TextStyle(fontFamily: kAppFont,
                    fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  _selectorField(
                    label: selectedTeacherLabel,
                    placeholder: '-Select Incharge -',
                    empty: _selectedTeacherId == null || _selectedTeacherId == '-1',
                    compact: compact,
                    onTap: _isSubmitting || _isLoading ? null : () => _showModernSelector(
                      title: 'Select Incharge',
                      items: _teachersList,
                      selectedValue: _selectedTeacherId,
                      onSelected: (val) => setState(() => _selectedTeacherId = val),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Add Button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      onPressed: _isSubmitting || _isLoading ? null : _confirmAddIncharge,
                      child: _isSubmitting
                          ? const CupertinoActivityIndicator(color: Colors.white, radius: 8)
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(CupertinoIcons.plus, size: 15, color: Colors.white),
                                SizedBox(width: 7),
                                Text("Add Incharge", style: TextStyle(fontFamily: kAppFont,
                                  fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Current Incharges Table Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(child: Text(
                  "Current Incharge on Role",
                  style: TextStyle(fontFamily: kAppFont, fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                )),
                if (_isLoading) const CupertinoActivityIndicator(radius: 6),
              ],
            ),
            const SizedBox(height: 8),

            // Current Incharges List Card
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: _currentIncharges.isEmpty && !_isLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: Text("No active incharge mappings found", style: TextStyle(fontFamily: kAppFont, fontSize: 12, color: Color(0xFF94A3B8)))),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _currentIncharges.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      itemBuilder: (context, index) {
                        final item = _currentIncharges[index];
                        final bool isActive = item['status']?.toString().toLowerCase() == 'active';
                        final roleName = item['role']?.toString() ?? 'Role';

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                child: Text(
                                  item['sr_no']?.toString() ?? '${index + 1}',
                                  style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      roleName,
                                      style: TextStyle(fontFamily: kAppFont, fontSize: compact ? 11.5 : 13.0, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "${item['name']} • ${item['employee_id']}",
                                      style: TextStyle(fontFamily: kAppFont, fontSize: compact ? 11.5 : 13.0, color: const Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item['status']?.toString() ?? 'Active',
                                      style: TextStyle(
                                        fontFamily: kAppFont,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: isActive ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                      ),
                                    ),
                                  ),
                                  if (isActive && item['button_id'] != null && item['button_id'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    GestureDetector(
                                      onTap: _isSubmitting || _isLoading ? null : () => _confirmDeactivateIncharge(item['button_id'].toString(), roleName),
                                      behavior: HitTestBehavior.opaque,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF2F2),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFFCA5A5), width: 0.8),
                                        ),
                                        child: const Text(
                                          "Deactive",
                                          style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    });
  }
}
