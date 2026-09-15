import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String kAppFont = 'PlusJakartaSans';

class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class AccountTabView extends StatefulWidget {
  final String schoolId;
  final VoidCallback onLogoutRequested;

  const AccountTabView({
    super.key,
    required this.schoolId,
    required this.onLogoutRequested,
  });

  @override
  State<AccountTabView> createState() => _AccountTabViewState();
}

class _AccountTabViewState extends State<AccountTabView> {
  // App Preferences
  bool _autoSyncEnabled = true;
  String _syncInterval = "Every 30 Mins";
  bool _attendanceCutoffAlert = true;
  bool _mdmDailyReminder = true;
  bool _biometricLock = false;
  bool _hapticsEnabled = true;

  // Multi-Portal Credentials & Live Status
  late String _shalaSchoolId;
  String _shalaPassword = "••••••••";
  String _shalaStatus = "Healthy (10:15 AM)";

  String _staffWindowId = "1553675";
  String _staffWindowPassword = "••••••••";
  String _staffStatus = "Active (09:40 AM)";

  String _rajsimsCode = "480481";
  String _rajsimsPassword = "••••••••";
  String _rajsimsStatus = "Synced (10:15 AM)";

  @override
  void initState() {
    super.initState();
    _shalaSchoolId = widget.schoolId;
  }

  void _haptic() {
    if (_hapticsEnabled) {
      HapticFeedback.selectionClick();
    }
  }

  void _showAppleToast(String message, {IconData icon = CupertinoIcons.checkmark_circle_fill}) {
    _haptic();
    final overlay = Overlay.of(context);
    final topInset = MediaQuery.of(context).padding.top;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: topInset + 14,
        left: 20,
        right: 20,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutBack,
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, -15 * (1 - value)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.14), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.16),
                            blurRadius: 16,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, color: const Color(0xFF10B981), size: 16),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              message,
                              style: const TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 12.0,
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
                );
              },
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 2000), () => entry.remove());
  }

  void _showSyncIntervalPicker() {
    _haptic();
    const intervals = ["Instant (On Open)", "Every 15 Mins", "Every 30 Mins", "Every 1 Hour", "Manual Only"];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Background Sync Interval",
              style: TextStyle(
                fontFamily: kAppFont,
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            ...intervals.map((intvl) {
              final isSelected = _syncInterval == intvl;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  intvl,
                  style: TextStyle(
                    fontFamily: kAppFont,
                    fontSize: 13.0,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                  ),
                ),
                trailing: isSelected
                    ? const Icon(CupertinoIcons.checkmark_circle_fill, size: 18, color: Color(0xFF10B981))
                    : null,
                onTap: () {
                  setState(() => _syncInterval = intvl);
                  Navigator.pop(context);
                  _showAppleToast("Sync interval: $intvl");
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showCredentialEditor({
    required String portalName,
    required String idLabel,
    required String currentId,
    required String currentPassword,
    required Function(String newId, String newPass) onSave,
  }) {
    _haptic();
    final idController = TextEditingController(text: currentId);
    final passController = TextEditingController(text: currentPassword == "••••••••" ? "" : currentPassword);
    bool obscurePassword = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "$portalName Credentials",
                          style: const TextStyle(
                            fontFamily: kAppFont,
                            fontSize: 16.0,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            "256-Bit Encrypted",
                            style: TextStyle(
                              fontFamily: kAppFont,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Automates daily attendance, leave logs, and Mid-Day Meal stock.",
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      idLabel.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        controller: idController,
                        style: const TextStyle(fontFamily: kAppFont, fontSize: 13, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "PORTAL PASSWORD / PIN",
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        controller: passController,
                        obscureText: obscurePassword,
                        style: const TextStyle(fontFamily: kAppFont, fontSize: 13, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                              size: 17,
                              color: const Color(0xFF64748B),
                            ),
                            onPressed: () => setSheetState(() => obscurePassword = !obscurePassword),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text("Cancel", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: ElevatedButton(
                              onPressed: () {
                                if (idController.text.trim().isNotEmpty) {
                                  onSave(idController.text.trim(), passController.text.trim().isEmpty ? "••••••••" : passController.text.trim());
                                  Navigator.pop(ctx);
                                  _showAppleToast("$portalName credentials updated");
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text("Save & Verify", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w700)),
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
        );
      },
    );
  }

  void _showStorageInspector() {
    _haptic();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
            const SizedBox(height: 16),
            const Text(
              "Local Offline Cache Details",
              style: TextStyle(fontFamily: kAppFont, fontSize: 16.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 14),
            _buildInspectorRow("Staff Details & Biometrics Cache", "1.2 MB"),
            const Divider(height: 14, color: Color(0xFFF1F5F9)),
            _buildInspectorRow("Student Attendance & Roster", "920 KB"),
            const Divider(height: 14, color: Color(0xFFF1F5F9)),
            _buildInspectorRow("Raj-SIMS MDM Food Grain Ledgers", "1.7 MB"),
            const Divider(height: 14, color: Color(0xFFF1F5F9)),
            _buildInspectorRow("Total Stored Offline Data", "3.82 MB", isBold: true),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                icon: const Icon(CupertinoIcons.trash, size: 15),
                label: const Text("Purge Cache & Reload", style: TextStyle(fontFamily: kAppFont, fontSize: 13, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _showAppleToast("Cache cleared (3.82 MB freed)", icon: CupertinoIcons.trash_fill);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectorRow(String label, String size, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: isBold ? FontWeight.w700 : FontWeight.w500, color: const Color(0xFF475569))),
        Text(size, style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700, color: isBold ? const Color(0xFF0F172A) : const Color(0xFF64748B))),
      ],
    );
  }

  void _confirmSignOut() {
    _haptic();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(22.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              "${widget.schoolId} !",
              style: const TextStyle(
                fontFamily: kAppFont,
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Are you sure you want to sign out of the Unified Portal Hub?",
              style: TextStyle(
                fontFamily: kAppFont,
                fontSize: 12.0,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(fontFamily: kAppFont, fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onLogoutRequested();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        "Sign Out",
                        style: TextStyle(fontFamily: kAppFont, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: ScrollConfiguration(
        behavior: const _NoGlowScrollBehavior(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 120.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. School & Identity Island
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withOpacity(0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFF1F5F9), width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/icons/user.png',
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => const Icon(
                                Icons.person_rounded,
                                size: 26,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      "${widget.schoolId} !",
                                      style: const TextStyle(
                                        fontFamily: kAppFont,
                                        fontSize: 16.0,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0F172A),
                                        letterSpacing: -0.3,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      "SSO Linked",
                                      style: TextStyle(
                                        fontFamily: kAppFont,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF16A34A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                "Headmaster / Institutional In-charge",
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 1),
                              const Text(
                                "Govt. Primary School Jethiyakhedi",
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 10.5,
                                  color: Color(0xFF94A3B8),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // School Info Chips Row
                    Row(
                      children: [
                        _buildMetaTag("U-DISE", "08270104801"),
                        const SizedBox(width: 6),
                        _buildMetaTag("Block", "Pratapgarh"),
                        const SizedBox(width: 6),
                        _buildMetaTag("Category", "Pri (1-5)"),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 2. Multi-Portal Credential Manager with Live Health Indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    "Credential & Portal Manager",
                    style: TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 13.0,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    "3/3 Connected",
                    style: TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 11.0,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildPortalHealthRow(
                      title: "Shaladarpan School Portal",
                      loginId: "ID: $_shalaSchoolId",
                      status: _shalaStatus,
                      badgeColor: const Color(0xFF10B981),
                      icon: CupertinoIcons.building_2_fill,
                      onTap: () => _showCredentialEditor(
                        portalName: "Shaladarpan",
                        idLabel: "School Login ID",
                        currentId: _shalaSchoolId,
                        currentPassword: _shalaPassword,
                        onSave: (id, pass) {
                          setState(() {
                            _shalaSchoolId = id;
                            _shalaPassword = pass;
                            _shalaStatus = "Updated Just now";
                          });
                        },
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9), indent: 46),
                    _buildPortalHealthRow(
                      title: "Staff Window Portal",
                      loginId: "NIC-SD: $_staffWindowId",
                      status: _staffStatus,
                      badgeColor: const Color(0xFF0284C7),
                      icon: CupertinoIcons.person_badge_plus_fill,
                      onTap: () => _showCredentialEditor(
                        portalName: "Staff Window",
                        idLabel: "Staff Login ID",
                        currentId: _staffWindowId,
                        currentPassword: _staffWindowPassword,
                        onSave: (id, pass) {
                          setState(() {
                            _staffWindowId = id;
                            _staffWindowPassword = pass;
                            _staffStatus = "Updated Just now";
                          });
                        },
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9), indent: 46),
                    _buildPortalHealthRow(
                      title: "Raj-SIMS MDM Portal",
                      loginId: "Code: $_rajsimsCode",
                      status: _rajsimsStatus,
                      badgeColor: const Color(0xFFF97316),
                      icon: CupertinoIcons.bag_fill,
                      onTap: () => _showCredentialEditor(
                        portalName: "Raj-SIMS",
                        idLabel: "School MDM Code",
                        currentId: _rajsimsCode,
                        currentPassword: _rajsimsPassword,
                        onSave: (id, pass) {
                          setState(() {
                            _rajsimsCode = id;
                            _rajsimsPassword = pass;
                            _rajsimsStatus = "Updated Just now";
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 3. Automation & Portal Sync Settings
              const Text(
                "Automation & Cutoff Reminders",
                style: TextStyle(
                  fontFamily: kAppFont,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 8),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildSwitchTile(
                      title: "1-Click Multi-Portal Auto-Sync",
                      subtitle: "Automates staff attendance and student records",
                      value: _autoSyncEnabled,
                      icon: CupertinoIcons.arrow_2_circlepath,
                      onChanged: (v) => setState(() => _autoSyncEnabled = v),
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9), indent: 46),
                    _buildNavTile(
                      title: "Sync Schedule",
                      subtitle: _syncInterval,
                      icon: CupertinoIcons.timer,
                      onTap: _showSyncIntervalPicker,
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9), indent: 46),
                    _buildSwitchTile(
                      title: "Staff Attendance Cutoff Alert",
                      subtitle: "Daily warning before 09:30 AM portal cutoff",
                      value: _attendanceCutoffAlert,
                      icon: CupertinoIcons.alarm,
                      onChanged: (v) => setState(() => _attendanceCutoffAlert = v),
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9), indent: 46),
                    _buildSwitchTile(
                      title: "Daily MDM Distribution Alert",
                      subtitle: "Daily reminder at 01:30 PM for meal entry",
                      value: _mdmDailyReminder,
                      icon: CupertinoIcons.bell,
                      onChanged: (v) => setState(() => _mdmDailyReminder = v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 4. Security & Local Offline Cache
              const Text(
                "Security & Local Storage",
                style: TextStyle(
                  fontFamily: kAppFont,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 8),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildSwitchTile(
                      title: "Biometric / App PIN Lock",
                      subtitle: "Protect credentials with Fingerprint/FaceID",
                      value: _biometricLock,
                      icon: CupertinoIcons.lock_shield_fill,
                      onChanged: (v) {
                        setState(() => _biometricLock = v);
                        _showAppleToast(v ? "Biometric lock enabled" : "Biometric lock disabled");
                      },
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9), indent: 46),
                    _buildSwitchTile(
                      title: "Haptic Feedback",
                      subtitle: "Tactile clicks on status changes & sync actions",
                      value: _hapticsEnabled,
                      icon: CupertinoIcons.waveform,
                      onChanged: (v) => setState(() => _hapticsEnabled = v),
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9), indent: 46),
                    _buildNavTile(
                      title: "Offline Storage Inspector",
                      subtitle: "3.82 MB cached • 1-Click Purge available",
                      icon: CupertinoIcons.tray_fill, // Replaced with valid CupertinoIcon
                      onTap: _showStorageInspector,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 5. App Specs & Support
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildInfoRowTile(
                      title: "Integrated Portal Engine",
                      value: "Shaladarpan + Staff + Raj-SIMS",
                      icon: CupertinoIcons.layers_alt_fill,
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9), indent: 46),
                    _buildInfoRowTile(
                      title: "Build Version",
                      value: "v2.6.0 (Enterprise 2026)",
                      icon: CupertinoIcons.info_circle_fill,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 6. Sign Out Button
              GestureDetector(
                onTap: _confirmSignOut,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 16),
                      SizedBox(width: 8),
                      Text(
                        "Sign Out of All Portals",
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEF4444),
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
    );
  }

  Widget _buildMetaTag(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontFamily: kAppFont, fontSize: 8.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
            Text(value, style: const TextStyle(fontFamily: kAppFont, fontSize: 10.0, color: Color(0xFF0F172A), fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildPortalHealthRow({
    required String title,
    required String loginId,
    required String status,
    required Color badgeColor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(icon, size: 16, color: const Color(0xFF0F172A)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: badgeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1.5),
                  Text(
                    "$loginId • $status",
                    style: const TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 10.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                "Edit",
                style: TextStyle(
                  fontFamily: kAppFont,
                  fontSize: 10.0,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required IconData icon,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF0F172A)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontFamily: kAppFont, fontSize: 10.5, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeColor: const Color(0xFF10B981),
            onChanged: (v) {
              _haptic();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF0F172A)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontFamily: kAppFont, fontSize: 10.5, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_forward, size: 13, color: Color(0xFFCBD5E1)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRowTile({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF0F172A)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}