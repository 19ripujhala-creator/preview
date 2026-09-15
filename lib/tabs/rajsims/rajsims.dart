import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String kAppFont = 'PlusJakartaSans';

// ScrollBehavior to prevent overscroll red tint / glow
class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

// =========================================================================
// 1. MAIN RAJSIMS TAB VIEW
// =========================================================================
class RajsimsTabView extends StatefulWidget {
  const RajsimsTabView({super.key});

  @override
  State<RajsimsTabView> createState() => _RajsimsTabViewState();
}

class _RajsimsTabViewState extends State<RajsimsTabView> {
  void _haptic() => HapticFeedback.selectionClick();

  void _openNotice(String title, String desc) {
    _haptic();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(fontFamily: kAppFont, fontSize: 15.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
        ),
        content: Text(
          desc,
          style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, color: Color(0xFF64748B), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close", style: TextStyle(fontFamily: kAppFont, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width: double.infinity,
      color: Colors.transparent,
      child: ScrollConfiguration(
        behavior: const _NoGlowScrollBehavior(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 110.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(400.0, screenHeight - 160.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Header with Raj-SIMS Logo (46x46)
                Row(
                  children: [
                    Image.asset(
                      'assets/icons/rajsims.png',
                      width: 46,
                      height: 46,
                      fit: BoxFit.contain,
                      errorBuilder: (c, e, s) => const Icon(Icons.business_rounded, size: 46, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "Raj-SIMS Portal",
                            style: TextStyle(
                              fontFamily: kAppFont,
                              fontSize: 17.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Mid Day Meal Program (MDM)",
                            style: TextStyle(
                              fontFamily: kAppFont,
                              fontSize: 11.0,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(CupertinoIcons.circle_fill, size: 6, color: Color(0xFF10B981)),
                          SizedBox(width: 5),
                          Text(
                            "Active",
                            style: TextStyle(
                              fontFamily: kAppFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // 2. School Name & MDM Incharge Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "GOVT. PRIMARY SCHOOL JETHIYAKHEDI (480481)",
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        "MDM Incharge : Rekha Meena (Teacher L-1)",
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 11.0,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 3. Food Grain Stock Status
                const Text(
                  "Food Grain Stock Status",
                  style: TextStyle(
                    fontFamily: kAppFont,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildStockCard("Wheat (गेहूं)", "142.50", "Kg", 'assets/icons/wheat.png')),
                    const SizedBox(width: 10),
                    Expanded(child: _buildStockCard("Rice (चावल)", "98.20", "Kg", 'assets/icons/rice.png')),
                  ],
                ),

                const SizedBox(height: 14),

                // 4. Today's Distribution Status Indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "Today's Distribution Status",
                            style: TextStyle(
                              fontFamily: kAppFont,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Status: Completed • 32 Students served",
                            style: TextStyle(
                              fontFamily: kAppFont,
                              fontSize: 11.0,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(CupertinoIcons.checkmark_alt, size: 16, color: Color(0xFF16A34A)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 5. Action CTAs: Left: Legacy Entry | Right: Add Distribution
                Row(
                  children: [
                    // Left: Legacy Entry
                    Expanded(
                      child: _ScaleTouch(
                        onTap: () {
                          _haptic();
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const AddLegacyDistributionScreen()),
                          );
                        },
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(CupertinoIcons.arrow_counterclockwise, color: Color(0xFF0F172A), size: 13),
                              SizedBox(width: 5),
                              Text(
                                "Legacy Entry",
                                style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Right: Add Distribution
                    Expanded(
                      child: _ScaleTouch(
                        onTap: () {
                          _haptic();
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const AddDistributionScreen()),
                          );
                        },
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A).withOpacity(0.12),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(CupertinoIcons.add, color: Colors.white, size: 13),
                              SizedBox(width: 5),
                              Text(
                                "Add Distribution",
                                style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // 6. Registered Log Lists
                const Text(
                  "Distribution Records & Logs",
                  style: TextStyle(
                    fontFamily: kAppFont,
                    fontSize: 12.0,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),

                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _buildListRow(
                        title: "View Distribution List",
                        subtitle: "Consolidated daily consumption records",
                        icon: CupertinoIcons.list_bullet_below_rectangle,
                        onTap: () {
                          _haptic();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DistributionListScreen(isLegacy: false),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9), indent: 46, endIndent: 12),
                      _buildListRow(
                        title: "Distribution Legacy List",
                        subtitle: "Audit view for unsettled/settled legacy drafts",
                        icon: CupertinoIcons.clock_fill,
                        onTap: () {
                          _haptic();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DistributionListScreen(isLegacy: true),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStockCard(String title, String amount, String unit, String iconPath) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            iconPath,
            width: 24,
            height: 24,
            errorBuilder: (c, e, s) => const Icon(CupertinoIcons.cube_box_fill, size: 24, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontFamily: kAppFont,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                amount,
                style: const TextStyle(
                  fontFamily: kAppFont,
                  fontSize: 24.0,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  fontFamily: kAppFont,
                  fontSize: 12.0,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                    style: const TextStyle(fontFamily: kAppFont, fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontFamily: kAppFont, fontSize: 11, color: Color(0xFF64748B)),
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
}

// =========================================================================
// 2. FULL WINDOW: ADD DISTRIBUTION SCREEN (Today's Entry)
// =========================================================================
class AddDistributionScreen extends StatefulWidget {
  const AddDistributionScreen({super.key});

  @override
  State<AddDistributionScreen> createState() => _AddDistributionScreenState();
}

class _AddDistributionScreenState extends State<AddDistributionScreen> {
  String? _selectedProductName = 'Wheat';
  final List<String> _productOptions = ['Wheat (गेहूं)', 'Rice (चावल)'];

  bool _isZeroConsumption = false;
  String? _selectedZeroReason = 'Holiday in School';
  final List<String> _zeroReasons = [
    'Holiday in School',
    'Non availability of Food grains',
    'Non availability of funds/cooking cost/Ingredients',
    'Absence of cook-cum-helpers',
    'Food Not Arrived from NGO/SHG',
    'Others',
    'Shri Krishna Bhog/Atithi Bhog',
  ];

  final int _maxEnrolment = 32;
  bool _isRowSelected = true;
  final TextEditingController _beneficiaryController = TextEditingController();
  final TextEditingController _atithiMataCountController = TextEditingController(text: '1');
  double _issuedQty = 0.00;

  String _atithiMataChoice = '0'; // '1': Yes (हाँ), '0': No (नहीं)

  @override
  void initState() {
    super.initState();
    _beneficiaryController.addListener(_calculateIssuedQty);
  }

  void _calculateIssuedQty() {
    final int count = int.tryParse(_beneficiaryController.text.trim()) ?? 0;
    setState(() {
      _issuedQty = (count * 0.100);
    });
  }

  @override
  void dispose() {
    _beneficiaryController.dispose();
    _atithiMataCountController.dispose();
    super.dispose();
  }

  void _haptic() => HapticFeedback.selectionClick();

  void _showNotice(String message, {bool isSuccess = true}) {
    _haptic();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.16),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSuccess ? CupertinoIcons.checkmark_alt_circle_fill : CupertinoIcons.info_circle_fill,
                color: isSuccess ? const Color(0xFF34C759) : const Color(0xFFEF4444),
                size: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openProductSelectorDialog() {
    _haptic();
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: 360,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Select Food Grain", style: TextStyle(fontFamily: kAppFont, fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                      GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(CupertinoIcons.xmark, size: 16, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: _productOptions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF8FAFC)),
                  itemBuilder: (context, index) {
                    final item = _productOptions[index];
                    final isSelected = (_selectedProductName == 'Wheat' && item.startsWith('Wheat')) ||
                        (_selectedProductName == 'Rice' && item.startsWith('Rice'));
                    return InkWell(
                      onTap: () {
                        _haptic();
                        setState(() => _selectedProductName = item.startsWith('Wheat') ? 'Wheat' : 'Rice');
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: isSelected ? const Color(0xFFF8FAFC) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(item, style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155))),
                            if (isSelected) const Icon(CupertinoIcons.checkmark_alt, size: 15, color: Color(0xFF0F172A)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openZeroReasonSelectorDialog() {
    _haptic();
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: 390,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Select Reason", style: TextStyle(fontFamily: kAppFont, fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                      GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(CupertinoIcons.xmark, size: 16, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: _zeroReasons.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF8FAFC)),
                    itemBuilder: (context, index) {
                      final reason = _zeroReasons[index];
                      final isSelected = _selectedZeroReason == reason;
                      return InkWell(
                        onTap: () {
                          _haptic();
                          setState(() => _selectedZeroReason = reason);
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(color: isSelected ? const Color(0xFFF8FAFC) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text(reason, style: TextStyle(fontFamily: kAppFont, fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155)))),
                              if (isSelected) const Icon(CupertinoIcons.checkmark_alt, size: 15, color: Color(0xFF0F172A)),
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isShriKrishnaBhog = _isZeroConsumption && _selectedZeroReason == 'Shri Krishna Bhog/Atithi Bhog';

    return ScrollConfiguration(
      behavior: const _NoGlowScrollBehavior(),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white.withOpacity(0.85),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(CupertinoIcons.back, color: Color(0xFF0F172A), size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            "Add Distribution",
            style: TextStyle(fontFamily: kAppFont, fontSize: 15.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          ),
          centerTitle: false,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12.0, top: 10, bottom: 10),
              child: Container(
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _haptic();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const AddLegacyDistributionScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(CupertinoIcons.arrow_counterclockwise, size: 12, color: Colors.white),
                          SizedBox(width: 5),
                          Text(
                            "Legacy Distribution",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            // Atmospheric Ambient Mesh Background
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
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
            ),
            Positioned(
              left: -50,
              top: -40,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 85, sigmaY: 85),
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFBAE6FD).withOpacity(0.42),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -50,
              top: 40,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFDE68A).withOpacity(0.35),
                  ),
                ),
              ),
            ),

            SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(14.0, 6.0, 14.0, 30.0),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0.0, constraints.maxHeight - 36.0),
                      ),
                      child: IntrinsicHeight(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel("Transaction Type"),
                              _buildReadOnlyField("Distribution"),

                              const SizedBox(height: 10),
                              _buildLabel("Customer Type"),
                              _buildReadOnlyField("Beneficiary Dept."),

                              const SizedBox(height: 10),
                              _buildLabel("Distribution No."),
                              _buildReadOnlyField("Auto Generated"),

                              const SizedBox(height: 10),
                              _buildLabel("Distribution Date *", isRequired: true),
                              _buildReadOnlyField("14-Sep-2026"),

                              const SizedBox(height: 14),
                              const Text("Zero Consumption (If Any)", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                              const SizedBox(height: 6),

                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: _isZeroConsumption,
                                      onChanged: (val) {
                                        _haptic();
                                        setState(() => _isZeroConsumption = val ?? false);
                                      },
                                      activeColor: const Color(0xFF0F172A),
                                    ),
                                    const Expanded(
                                      child: Text("Zero consumption for this day", style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                    ),
                                  ],
                                ),
                              ),

                              if (_isZeroConsumption) ...[
                                const SizedBox(height: 12),
                                _buildLabel("Reason *", isRequired: true),
                                GestureDetector(
                                  onTap: _openZeroReasonSelectorDialog,
                                  behavior: HitTestBehavior.opaque,
                                  child: Container(
                                    height: 38,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFCBD5E1))),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _selectedZeroReason ?? "--Select Reason--",
                                            style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: _selectedZeroReason == null ? const Color(0xFF94A3B8) : const Color(0xFF0F172A)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Icon(CupertinoIcons.chevron_down, size: 13, color: Color(0xFF64748B)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],

                              if (!_isZeroConsumption || isShriKrishnaBhog) ...[
                                const SizedBox(height: 14),
                                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                const SizedBox(height: 12),

                                const Text("Daily Consumption Entry", style: TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),

                                if (!isShriKrishnaBhog) ...[
                                  const SizedBox(height: 8),
                                  _buildLabel("Product Name *", isRequired: true),
                                  GestureDetector(
                                    onTap: _openProductSelectorDialog,
                                    behavior: HitTestBehavior.opaque,
                                    child: Container(
                                      height: 38,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFCBD5E1))),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _selectedProductName == 'Wheat' ? "Wheat (गेहूं)" : _selectedProductName == 'Rice' ? "Rice (चावल)" : "--Select Product--",
                                            style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: _selectedProductName == null ? const Color(0xFF94A3B8) : const Color(0xFF0F172A)),
                                          ),
                                          const Icon(CupertinoIcons.chevron_down, size: 13, color: Color(0xFF64748B)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 12),

                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Checkbox(value: _isRowSelected, onChanged: (v) => setState(() => _isRowSelected = v ?? true), activeColor: const Color(0xFF0F172A)),
                                          const Expanded(
                                            child: Text("Primary School (Pre-Primary to 5)", style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFCBD5E1))),
                                            child: Text("Enrolment: $_maxEnrolment", style: const TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                                      const SizedBox(height: 10),

                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(isShriKrishnaBhog ? "Beneficiaries (Atithi Bhog)" : "No. Of Beneficiary *", style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                          GestureDetector(
                                            onTap: () {
                                              _haptic();
                                              _beneficiaryController.text = _maxEnrolment.toString();
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                              decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(5)),
                                              child: Text("Fill All ($_maxEnrolment)", style: const TextStyle(fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),

                                      Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: SizedBox(
                                              height: 36,
                                              child: TextField(
                                                controller: _beneficiaryController,
                                                keyboardType: TextInputType.number,
                                                style: const TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                                decoration: InputDecoration(
                                                  hintText: "Enter count...",
                                                  hintStyle: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, color: Color(0xFF94A3B8)),
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                  filled: true,
                                                  fillColor: Colors.white,
                                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F172A))),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            flex: 2,
                                            child: Container(
                                              height: 36,
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                                              alignment: Alignment.center,
                                              child: Text(
                                                isShriKrishnaBhog ? "0.00 Kg (Free)" : "${_issuedQty.toStringAsFixed(2)} Kg",
                                                style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w800, color: isShriKrishnaBhog ? const Color(0xFF16A34A) : const Color(0xFF0F172A)),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              // 6. Atithi Mata Tasting
                              if (!_isZeroConsumption) ...[
                                const SizedBox(height: 16),
                                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                const SizedBox(height: 14),

                                const Text("अतिथि माता (If Any)", style: TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                const SizedBox(height: 4),
                                const Text("क्या विद्यार्थियों को भोजन परोसने जाने से पूर्व उनकी माताओं / महिला अभिभावकों द्वारा भोजन को चखा गया है", style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, color: Color(0xFF475569), height: 1.3)),
                                const SizedBox(height: 8),

                                Container(
                                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(8)),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            _haptic();
                                            setState(() => _atithiMataChoice = '1');
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            decoration: BoxDecoration(color: _atithiMataChoice == '1' ? const Color(0xFF0F172A) : Colors.transparent, borderRadius: const BorderRadius.horizontal(left: Radius.circular(7))),
                                            alignment: Alignment.center,
                                            child: Text("हाँ", style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700, color: _atithiMataChoice == '1' ? Colors.white : const Color(0xFF0F172A))),
                                          ),
                                        ),
                                      ),
                                      Container(width: 1, height: 34, color: const Color(0xFFCBD5E1)),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            _haptic();
                                            setState(() => _atithiMataChoice = '0');
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            decoration: BoxDecoration(color: _atithiMataChoice == '0' ? const Color(0xFF0F172A) : Colors.transparent, borderRadius: const BorderRadius.horizontal(right: Radius.circular(7))),
                                            alignment: Alignment.center,
                                            child: Text("नहीं", style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700, color: _atithiMataChoice == '0' ? Colors.white : const Color(0xFF0F172A))),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                if (_atithiMataChoice == '1') ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                                    child: Row(
                                      children: [
                                        const Expanded(
                                          child: Text("अतिथि माता की संख्या *", style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                        ),
                                        SizedBox(
                                          width: 60,
                                          height: 32,
                                          child: TextField(
                                            controller: _atithiMataCountController,
                                            keyboardType: TextInputType.number,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                            decoration: InputDecoration(
                                              contentPadding: EdgeInsets.zero,
                                              filled: true,
                                              fillColor: Colors.white,
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F172A))),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],

                              const Spacer(),
                              const SizedBox(height: 20),

                              // Cancel on Left | Save on Right (Color: #00E676 - Non-deforming solid style)
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 36,
                                      child: OutlinedButton(
                                        onPressed: () => Navigator.pop(context),
                                        style: ButtonStyle(
                                          backgroundColor: MaterialStateProperty.all(Colors.white.withOpacity(0.9)),
                                          foregroundColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                          elevation: MaterialStateProperty.all(0),
                                          shadowColor: MaterialStateProperty.all(Colors.transparent),
                                          side: MaterialStateProperty.all(const BorderSide(color: Color(0xFFCBD5E1))),
                                          overlayColor: MaterialStateProperty.all(Colors.black.withOpacity(0.04)),
                                          splashFactory: NoSplash.splashFactory,
                                          shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                          padding: MaterialStateProperty.all(EdgeInsets.zero),
                                          minimumSize: MaterialStateProperty.all(const Size(0, 36)),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text("Cancel", style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SizedBox(
                                      height: 36,
                                      child: ElevatedButton(
                                        onPressed: () {
                                          if (_isZeroConsumption && !isShriKrishnaBhog) {
                                            if (_selectedZeroReason == null) {
                                              _showNotice("Please select reason for zero consumption", isSuccess: false);
                                              return;
                                            }
                                            _showNotice("Zero consumption entry reported successfully");
                                            Navigator.pop(context);
                                          } else {
                                            if (!isShriKrishnaBhog && _selectedProductName == null) {
                                              _showNotice("Please select food grain product", isSuccess: false);
                                              return;
                                            }
                                            _showNotice("Daily distribution entry saved successfully");
                                            Navigator.pop(context);
                                          }
                                        },
                                        style: ButtonStyle(
                                          backgroundColor: MaterialStateProperty.all(const Color(0xFF00E676)), // Clean Bright Green #00E676
                                          foregroundColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                          elevation: MaterialStateProperty.all(0),
                                          shadowColor: MaterialStateProperty.all(Colors.transparent),
                                          overlayColor: MaterialStateProperty.all(Colors.black.withOpacity(0.06)),
                                          splashFactory: NoSplash.splashFactory,
                                          shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                          padding: MaterialStateProperty.all(EdgeInsets.zero),
                                          minimumSize: MaterialStateProperty.all(const Size(0, 36)),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text("Save", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String label, {bool isRequired = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
          if (isRequired) const Text(" *", style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildReadOnlyField(String val) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
      alignment: Alignment.centerLeft,
      child: Text(val, style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
    );
  }
}

// =========================================================================
// 3. FULL WINDOW: ADD LEGACY DISTRIBUTION SCREEN (Clean Seamless Stretch)
// =========================================================================
class AddLegacyDistributionScreen extends StatefulWidget {
  const AddLegacyDistributionScreen({super.key});

  @override
  State<AddLegacyDistributionScreen> createState() => _AddLegacyDistributionScreenState();
}

class _AddLegacyDistributionScreenState extends State<AddLegacyDistributionScreen> {
  DateTime _legacyDate = DateTime.now().subtract(const Duration(days: 1));
  String? _selectedProductName = 'Wheat';
  final List<String> _productOptions = ['Wheat (गेहूं)', 'Rice (चावल)'];

  bool _isZeroConsumption = false;
  String? _selectedZeroReason = 'Holiday in School';
  final List<String> _zeroReasons = [
    'Holiday in School',
    'Non availability of Food grains',
    'Non availability of funds/cooking cost/Ingredients',
    'Absence of cook-cum-helpers',
    'Food Not Arrived from NGO/SHG',
    'Others',
    'Shri Krishna Bhog/Atithi Bhog',
  ];

  final int _maxEnrolment = 32;
  bool _isRowSelected = true;
  final TextEditingController _beneficiaryController = TextEditingController();
  double _issuedQty = 0.00;

  @override
  void initState() {
    super.initState();
    _beneficiaryController.addListener(_calculateIssuedQty);
  }

  void _calculateIssuedQty() {
    final int count = int.tryParse(_beneficiaryController.text.trim()) ?? 0;
    setState(() {
      _issuedQty = (count * 0.100);
    });
  }

  @override
  void dispose() {
    _beneficiaryController.dispose();
    super.dispose();
  }

  void _haptic() => HapticFeedback.selectionClick();

  void _showNotice(String message, {bool isSuccess = true}) {
    _haptic();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.16),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSuccess ? CupertinoIcons.checkmark_alt_circle_fill : CupertinoIcons.info_circle_fill,
                color: isSuccess ? const Color(0xFF34C759) : const Color(0xFFEF4444),
                size: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openLegacyCalendarPicker() {
    _haptic();
    DateTime tempDate = _legacyDate;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final int year = tempDate.year;
            final int month = tempDate.month;
            final int daysInMonth = DateUtils.getDaysInMonth(year, month);
            final int firstWeekday = DateTime(year, month, 1).weekday;
            const List<String> monthNames = [
              "", "January", "February", "March", "April", "May", "June",
              "July", "August", "September", "October", "November", "December"
            ];
            final List<int> yearsList = List.generate(15, (i) => 2018 + i);

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: 285,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 6))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        PopupMenuButton<int>(
                          initialValue: month,
                          color: Colors.white,
                          elevation: 3,
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
                                    fontSize: 12.0,
                                    fontWeight: i == month ? FontWeight.w700 : FontWeight.w500,
                                    color: i == month ? const Color(0xFFEF4444) : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                          ],
                          onSelected: (val) {
                            setDialogState(() {
                              tempDate = DateTime(year, val, math.min(tempDate.day, DateUtils.getDaysInMonth(year, val)));
                            });
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(monthNames[month], style: const TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                              const Icon(Icons.arrow_drop_down_rounded, size: 20, color: Color(0xFFEF4444)),
                            ],
                          ),
                        ),
                        PopupMenuButton<int>(
                          initialValue: year,
                          color: Colors.white,
                          elevation: 3,
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
                                    fontSize: 12.0,
                                    fontWeight: y == year ? FontWeight.w700 : FontWeight.w500,
                                    color: y == year ? const Color(0xFFEF4444) : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                          ],
                          onSelected: (val) {
                            setDialogState(() {
                              tempDate = DateTime(val, month, math.min(tempDate.day, DateUtils.getDaysInMonth(val, month)));
                            });
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("$year", style: const TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                              const Icon(Icons.arrow_drop_down_rounded, size: 20, color: Color(0xFFEF4444)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: const [
                        Text("Mo", style: TextStyle(fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                        Text("Tu", style: TextStyle(fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                        Text("We", style: TextStyle(fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                        Text("Th", style: TextStyle(fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                        Text("Fr", style: TextStyle(fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                        Text("Sa", style: TextStyle(fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                        Text("Su", style: TextStyle(fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                      ),
                      itemCount: daysInMonth + (firstWeekday - 1),
                      itemBuilder: (context, index) {
                        if (index < firstWeekday - 1) return const SizedBox.shrink();
                        final int day = index - (firstWeekday - 2);
                        final DateTime currentCellDate = DateTime(year, month, day);

                        final bool isDisabled = currentCellDate.isAfter(DateTime.now());
                        final bool isSelected = currentCellDate.year == tempDate.year &&
                            currentCellDate.month == tempDate.month &&
                            currentCellDate.day == tempDate.day;

                        return GestureDetector(
                          onTap: isDisabled ? null : () {
                            setDialogState(() => tempDate = currentCellDate);
                          },
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
                                fontSize: 10.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isDisabled ? const Color(0xFFCBD5E1) : isSelected ? Colors.white : const Color(0xFF1E293B),
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
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: const Size(48, 28),
                          ),
                          child: const Text("Cancel", style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, color: Color(0xFF64748B))),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton(
                          onPressed: () {
                            setState(() => _legacyDate = tempDate);
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            minimumSize: const Size(38, 28),
                            elevation: 0,
                          ),
                          child: const Text("OK", style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w700)),
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

  void _openProductSelectorDialog() {
    _haptic();
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: 360,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Select Food Grain", style: TextStyle(fontFamily: kAppFont, fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                      GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(CupertinoIcons.xmark, size: 16, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: _productOptions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF8FAFC)),
                  itemBuilder: (context, index) {
                    final item = _productOptions[index];
                    final isSelected = (_selectedProductName == 'Wheat' && item.startsWith('Wheat')) ||
                        (_selectedProductName == 'Rice' && item.startsWith('Rice'));
                    return InkWell(
                      onTap: () {
                        _haptic();
                        setState(() => _selectedProductName = item.startsWith('Wheat') ? 'Wheat' : 'Rice');
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: isSelected ? const Color(0xFFF8FAFC) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(item, style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155))),
                            if (isSelected) const Icon(CupertinoIcons.checkmark_alt, size: 15, color: Color(0xFF0F172A)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openZeroReasonSelectorDialog() {
    _haptic();
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: 390,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Select Reason", style: TextStyle(fontFamily: kAppFont, fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                      GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(CupertinoIcons.xmark, size: 16, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: _zeroReasons.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF8FAFC)),
                    itemBuilder: (context, index) {
                      final reason = _zeroReasons[index];
                      final isSelected = _selectedZeroReason == reason;
                      return InkWell(
                        onTap: () {
                          _haptic();
                          setState(() => _selectedZeroReason = reason);
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(color: isSelected ? const Color(0xFFF8FAFC) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text(reason, style: TextStyle(fontFamily: kAppFont, fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155)))),
                              if (isSelected) const Icon(CupertinoIcons.checkmark_alt, size: 15, color: Color(0xFF0F172A)),
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String formattedDate = "${_legacyDate.day.toString().padLeft(2, '0')}-${_legacyDate.month.toString().padLeft(2, '0')}-${_legacyDate.year}";
    final bool isShriKrishnaBhog = _isZeroConsumption && _selectedZeroReason == 'Shri Krishna Bhog/Atithi Bhog';

    return ScrollConfiguration(
      behavior: const _NoGlowScrollBehavior(),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white.withOpacity(0.85),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(CupertinoIcons.back, color: Color(0xFF0F172A), size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            "Add Legacy Distribution",
            style: TextStyle(fontFamily: kAppFont, fontSize: 15.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          ),
          centerTitle: false,
        ),
        body: Stack(
          children: [
            // Atmospheric Ambient Mesh Background
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
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
            ),
            Positioned(
              left: -50,
              top: -40,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 85, sigmaY: 85),
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFBAE6FD).withOpacity(0.42),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -50,
              top: 40,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFDE68A).withOpacity(0.35),
                  ),
                ),
              ),
            ),

            SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(14.0, 6.0, 14.0, 30.0),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0.0, constraints.maxHeight - 36.0),
                      ),
                      child: IntrinsicHeight(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      "• Legacy डिस्ट्रीब्यूशन में आज से पूर्व की तिथि की एंट्री होगी।",
                                      style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      "• Legacy एंट्री सर्व प्रथम Unsettled / Draft मोड में सेव होगी।",
                                      style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 12),
                              _buildLabel("Transaction Type"),
                              _buildReadOnlyField("Distribution"),

                              const SizedBox(height: 10),
                              _buildLabel("Customer Type"),
                              _buildReadOnlyField("Beneficiary Dept."),

                              const SizedBox(height: 10),
                              _buildLabel("Distribution Date (Legacy Date) *", isRequired: true),
                              GestureDetector(
                                onTap: _openLegacyCalendarPicker,
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  height: 36,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        formattedDate,
                                        style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                      ),
                                      Image.asset(
                                        'assets/icons/leave.png',
                                        width: 16,
                                        height: 16,
                                        color: const Color(0xFF0F172A),
                                        errorBuilder: (c, e, s) => const Icon(CupertinoIcons.calendar, size: 16, color: Color(0xFF0F172A)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 14),
                              const Text("Zero Consumption (If Any)", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                              const SizedBox(height: 6),

                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: _isZeroConsumption,
                                      onChanged: (val) {
                                        _haptic();
                                        setState(() => _isZeroConsumption = val ?? false);
                                      },
                                      activeColor: const Color(0xFF0F172A),
                                    ),
                                    const Expanded(
                                      child: Text("Zero consumption for this day", style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                    ),
                                  ],
                                ),
                              ),

                              if (_isZeroConsumption) ...[
                                const SizedBox(height: 12),
                                _buildLabel("Reason *", isRequired: true),
                                GestureDetector(
                                  onTap: _openZeroReasonSelectorDialog,
                                  behavior: HitTestBehavior.opaque,
                                  child: Container(
                                    height: 38,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFCBD5E1))),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _selectedZeroReason ?? "--Select Reason--",
                                            style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: _selectedZeroReason == null ? const Color(0xFF94A3B8) : const Color(0xFF0F172A)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Icon(CupertinoIcons.chevron_down, size: 13, color: Color(0xFF64748B)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],

                              if (!_isZeroConsumption || isShriKrishnaBhog) ...[
                                const SizedBox(height: 14),
                                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                const SizedBox(height: 12),

                                const Text("Daily Consumption Entry", style: TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),

                                if (!isShriKrishnaBhog) ...[
                                  const SizedBox(height: 8),
                                  _buildLabel("Product Name *", isRequired: true),
                                  GestureDetector(
                                    onTap: _openProductSelectorDialog,
                                    behavior: HitTestBehavior.opaque,
                                    child: Container(
                                      height: 38,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFCBD5E1))),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _selectedProductName == 'Wheat' ? "Wheat (गेहूं)" : _selectedProductName == 'Rice' ? "Rice (चावल)" : "--Select Product--",
                                            style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: _selectedProductName == null ? const Color(0xFF94A3B8) : const Color(0xFF0F172A)),
                                          ),
                                          const Icon(CupertinoIcons.chevron_down, size: 13, color: Color(0xFF64748B)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 12),

                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Checkbox(value: _isRowSelected, onChanged: (v) => setState(() => _isRowSelected = v ?? true), activeColor: const Color(0xFF0F172A)),
                                          const Expanded(
                                            child: Text("Primary School (Pre-Primary to 5)", style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFCBD5E1))),
                                            child: Text("Enrolment: $_maxEnrolment", style: const TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                                      const SizedBox(height: 10),

                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(isShriKrishnaBhog ? "Beneficiaries (Atithi Bhog)" : "No. Of Beneficiary *", style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                          GestureDetector(
                                            onTap: () {
                                              _haptic();
                                              _beneficiaryController.text = _maxEnrolment.toString();
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                              decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(5)),
                                              child: Text("Fill All ($_maxEnrolment)", style: const TextStyle(fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),

                                      Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: SizedBox(
                                              height: 36,
                                              child: TextField(
                                                controller: _beneficiaryController,
                                                keyboardType: TextInputType.number,
                                                style: const TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                                decoration: InputDecoration(
                                                  hintText: "Enter count...",
                                                  hintStyle: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, color: Color(0xFF94A3B8)),
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                  filled: true,
                                                  fillColor: Colors.white,
                                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F172A))),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            flex: 2,
                                            child: Container(
                                              height: 36,
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                                              alignment: Alignment.center,
                                              child: Text(
                                                isShriKrishnaBhog ? "0.00 Kg" : "${_issuedQty.toStringAsFixed(2)} Kg",
                                                style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w800, color: isShriKrishnaBhog ? const Color(0xFF16A34A) : const Color(0xFF0F172A)),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const Spacer(),
                              const SizedBox(height: 20),

                              // Cancel on Left | Save (Green #00E676) on Right
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 36,
                                      child: OutlinedButton(
                                        onPressed: () => Navigator.pop(context),
                                        style: ButtonStyle(
                                          backgroundColor: MaterialStateProperty.all(Colors.white.withOpacity(0.9)),
                                          foregroundColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                          elevation: MaterialStateProperty.all(0),
                                          shadowColor: MaterialStateProperty.all(Colors.transparent),
                                          side: MaterialStateProperty.all(const BorderSide(color: Color(0xFFCBD5E1))),
                                          overlayColor: MaterialStateProperty.all(Colors.black.withOpacity(0.04)),
                                          splashFactory: NoSplash.splashFactory,
                                          shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                          padding: MaterialStateProperty.all(EdgeInsets.zero),
                                          minimumSize: MaterialStateProperty.all(const Size(0, 36)),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text("Cancel", style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SizedBox(
                                      height: 36,
                                      child: ElevatedButton(
                                        onPressed: () {
                                          if (_isZeroConsumption && !isShriKrishnaBhog) {
                                            if (_selectedZeroReason == null) {
                                              _showNotice("Please select reason for zero consumption", isSuccess: false);
                                              return;
                                            }
                                            _showNotice("Legacy draft saved as Unsettled");
                                            Navigator.pop(context);
                                          } else {
                                            if (!isShriKrishnaBhog && _selectedProductName == null) {
                                              _showNotice("Please select food grain product", isSuccess: false);
                                              return;
                                            }
                                            _showNotice("Legacy draft saved as Unsettled");
                                            Navigator.pop(context);
                                          }
                                        },
                                        style: ButtonStyle(
                                          backgroundColor: MaterialStateProperty.all(const Color(0xFF00E676)), // #00E676
                                          foregroundColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                          elevation: MaterialStateProperty.all(0),
                                          shadowColor: MaterialStateProperty.all(Colors.transparent),
                                          overlayColor: MaterialStateProperty.all(Colors.black.withOpacity(0.06)),
                                          splashFactory: NoSplash.splashFactory,
                                          shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                          padding: MaterialStateProperty.all(EdgeInsets.zero),
                                          minimumSize: MaterialStateProperty.all(const Size(0, 36)),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text("Save", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String label, {bool isRequired = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
          if (isRequired) const Text(" *", style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildReadOnlyField(String val) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
      alignment: Alignment.centerLeft,
      child: Text(val, style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
    );
  }
}

// =========================================================================
// 4. FULL WINDOW: DISTRIBUTION LIST / LEGACY LIST SCREEN
// =========================================================================
class DistributionListScreen extends StatefulWidget {
  final bool isLegacy;
  const DistributionListScreen({super.key, required this.isLegacy});

  @override
  State<DistributionListScreen> createState() => _DistributionListScreenState();
}

class _DistributionListScreenState extends State<DistributionListScreen> {
  String _searchQuery = "";

  final List<Map<String, String>> _allRecords = [
    {"sNo": "1", "distNo": "ED/MDM/School09043/DIS/26-27/103", "date": "14-Sep-2026", "type": "Beneficiary Dept.", "status": "Approved"},
    {"sNo": "2", "distNo": "ED/MDM/School09043/DIS/26-27/102", "date": "12-Sep-2026", "type": "Beneficiary Dept.", "status": "Approved"},
    {"sNo": "3", "distNo": "ED/MDM/School09043/DIS/26-27/101", "date": "11-Sep-2026", "type": "Beneficiary Dept.", "status": "Approved"},
    {"sNo": "4", "distNo": "ED/MDM/School09043/DIS/26-27/100", "date": "10-Sep-2026", "type": "Beneficiary Dept.", "status": "Approved"},
    {"sNo": "5", "distNo": "ED/MDM/School09043/DIS/26-27/99",  "date": "09-Sep-2026", "type": "Beneficiary Dept.", "status": "Approved"},
    {"sNo": "6", "distNo": "ED/MDM/School09043/DIS/26-27/98",  "date": "08-Sep-2026", "type": "Beneficiary Dept.", "status": "Approved"},
    {"sNo": "7", "distNo": "ED/MDM/School09043/DIS/26-27/97",  "date": "07-Sep-2026", "type": "Beneficiary Dept.", "status": "Approved"},
    {"sNo": "8", "distNo": "ED/MDM/School09043/DIS/26-27/96",  "date": "05-Sep-2026", "type": "Beneficiary Dept.", "status": "Approved"},
    {"sNo": "9", "distNo": "ED/MDM/School09043/DIS/26-27/95",  "date": "03-Sep-2026", "type": "Beneficiary Dept.", "status": "Approved"},
    {"sNo": "10", "distNo": "ED/MDM/School09043/DIS/26-27/94", "date": "02-Sep-2026", "type": "Beneficiary Dept.", "status": "Approved"},
  ];

  List<Map<String, String>> get _filteredRecords {
    if (_searchQuery.isEmpty) return _allRecords;
    final q = _searchQuery.toLowerCase();
    return _allRecords.where((r) =>
      r["distNo"]!.toLowerCase().contains(q) ||
      r["date"]!.toLowerCase().contains(q) ||
      r["status"]!.toLowerCase().contains(q)
    ).toList();
  }

  void _haptic() => HapticFeedback.selectionClick();

  @override
  Widget build(BuildContext context) {
    final title = widget.isLegacy ? "Distribution Legacy List" : "Distribution List";
    final displayedList = _filteredRecords;

    return ScrollConfiguration(
      behavior: const _NoGlowScrollBehavior(),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white.withOpacity(0.85),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(CupertinoIcons.back, color: Color(0xFF0F172A), size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            title,
            style: const TextStyle(fontFamily: kAppFont, fontSize: 15.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          ),
          centerTitle: false,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12.0, top: 10, bottom: 10),
              child: ElevatedButton.icon(
                onPressed: () {
                  _haptic();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => widget.isLegacy ? const AddLegacyDistributionScreen() : const AddDistributionScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(CupertinoIcons.add, size: 12, color: Colors.white),
                label: const Text(
                  "Add Record",
                  style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            // Ambient Atmospheric Background
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
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
            ),
            Positioned(
              left: -50,
              top: -40,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 85, sigmaY: 85),
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFBAE6FD).withOpacity(0.42),
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v.trim()),
                        style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, color: Color(0xFF0F172A)),
                        decoration: const InputDecoration(
                          hintText: "Search Distribution No. or Date...",
                          hintStyle: TextStyle(fontFamily: kAppFont, fontSize: 11.5, color: Color(0xFF94A3B8)),
                          prefixIcon: Icon(CupertinoIcons.search, size: 15, color: Color(0xFF64748B)),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 9.0),
                        ),
                      ),
                    ),
                  ),

                  // Results count banner
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Showing ${displayedList.length} of ${_allRecords.length} records",
                          style: const TextStyle(fontFamily: kAppFont, fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                        ),
                        const Text(
                          "Page 1 Of 1",
                          style: TextStyle(fontFamily: kAppFont, fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Record Cards List
                  Expanded(
                    child: displayedList.isEmpty
                        ? Center(
                            child: Text(
                              "No records found matching '$_searchQuery'",
                              style: const TextStyle(fontFamily: kAppFont, fontSize: 12, color: Color(0xFF94A3B8)),
                            ),
                          )
                        : ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                            itemCount: displayedList.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = displayedList[index];
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withOpacity(0.015), blurRadius: 6, offset: const Offset(0, 1)),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        item["sNo"]!,
                                        style: const TextStyle(fontFamily: kAppFont, fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                                      ),
                                    ),
                                    const SizedBox(width: 10),

                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item["distNo"]!,
                                            style: const TextStyle(
                                              fontFamily: kAppFont,
                                              fontSize: 12.0,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF0F172A),
                                              letterSpacing: -0.2,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Text(
                                                item["date"]!,
                                                style: const TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                              ),
                                              const SizedBox(width: 6),
                                              const Text("•", style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 10)),
                                              const SizedBox(width: 6),
                                              Text(
                                                item["type"]!,
                                                style: const TextStyle(fontFamily: kAppFont, fontSize: 10.5, color: Color(0xFF64748B)),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        item["status"]!,
                                        style: const TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w700, color: Color(0xFF16A34A)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    IconButton(
                                      icon: const Icon(CupertinoIcons.pencil_circle_fill, size: 18, color: Color(0xFF0F172A)),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 28),
                                      onPressed: () {
                                        _haptic();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text("Editing ${item["distNo"]}"),
                                            duration: const Duration(seconds: 1),
                                          ),
                                        );
                                      },
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
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 5. PRESS SCALE TOUCH FEEDBACK
// ==========================================
class _ScaleTouch extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _ScaleTouch({super.key, required this.child, required this.onTap});

  @override
  State<_ScaleTouch> createState() => _ScaleTouchState();
}

class _ScaleTouchState extends State<_ScaleTouch> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}