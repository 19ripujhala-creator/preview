import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

const String kAppFont = 'PlusJakartaSans';

class JanaadharAuthView extends StatefulWidget {
  const JanaadharAuthView({super.key});

  @override
  State<JanaadharAuthView> createState() => _JanaadharAuthViewState();
}

class _JanaadharAuthViewState extends State<JanaadharAuthView> {
  String _selectedClassCode = "ALL";
  String _selectedClassLabel = "All Classes & Sections";
  bool _isClassDataLoaded = false;
  String? _expandedClassDetails;

  final ScrollController _cardsScrollController = ScrollController();
  int _activeCardIndicator = 0;

  // Portal Class Options
  final List<Map<String, dynamic>> _classList = [
    {"code": "ALL", "label": "All Classes & Sections", "icon": CupertinoIcons.square_grid_2x2_fill},
    {"code": "1", "label": "Class - 1/A", "icon": CupertinoIcons.book_fill},
    {"code": "2", "label": "Class - 2/A", "icon": CupertinoIcons.book_fill},
    {"code": "3", "label": "Class - 3/A", "icon": CupertinoIcons.book_fill},
    {"code": "4", "label": "Class - 4/A", "icon": CupertinoIcons.book_fill},
    {"code": "5", "label": "Class - 5/A", "icon": CupertinoIcons.book_fill},
  ];

  // Class Wise Statistics
  final List<Map<String, dynamic>> _classWiseStats = [
    {
      "id": "1",
      "classLabel": "Class - 1/A",
      "totalStudents": 9,
      "aadharAuth": 6,
      "aadharPending": 3,
      "janEntered": 6,
      "janAuth": 6,
      "janRemaining": 3
    },
    {
      "id": "2",
      "classLabel": "Class - 2/A",
      "totalStudents": 7,
      "aadharAuth": 4,
      "aadharPending": 3,
      "janEntered": 2,
      "janAuth": 2,
      "janRemaining": 5
    },
    {
      "id": "3",
      "classLabel": "Class - 3/A",
      "totalStudents": 2,
      "aadharAuth": 0,
      "aadharPending": 2,
      "janEntered": 0,
      "janAuth": 0,
      "janRemaining": 2
    },
    {
      "id": "4",
      "classLabel": "Class - 4/A",
      "totalStudents": 11,
      "aadharAuth": 9,
      "aadharPending": 2,
      "janEntered": 9,
      "janAuth": 8,
      "janRemaining": 3
    },
    {
      "id": "5",
      "classLabel": "Class - 5/A",
      "totalStudents": 14,
      "aadharAuth": 12,
      "aadharPending": 2,
      "janEntered": 12,
      "janAuth": 11,
      "janRemaining": 3
    },
  ];

  // Mock Students Data
  final List<Map<String, dynamic>> _studentsData = [
    {"sno": "1", "srNo": "1204", "name": "Ashok Meena", "dob": "X4/01/2021", "gender": "M", "janCard": "514XXXXX818", "janMemberId": "472XXXX8259", "aadhar": "[Aadhaar Verified]", "bankPresent": false, "authenticated": true, "aadharAuth": true, "janAuth": true},
    {"sno": "2", "srNo": "1205", "name": "Jaya Kumari", "dob": "X9/03/2020", "gender": "F", "janCard": "513XXXXX561", "janMemberId": "505XXXX3419", "aadhar": "[Aadhaar Verified]", "bankPresent": false, "authenticated": true, "aadharAuth": true, "janAuth": true},
    {"sno": "3", "srNo": "1206", "name": "Monika Meena", "dob": "X3/12/2020", "gender": "F", "janCard": "513XXXXX085", "janMemberId": "804XXXX8129", "aadhar": "[Aadhaar Verified]", "bankPresent": false, "authenticated": true, "aadharAuth": true, "janAuth": true},
    {"sno": "4", "srNo": "1207", "name": "Pawan Meena", "dob": "X4/12/2019", "gender": "M", "janCard": "520XXXXX332", "janMemberId": "991XXXX3717", "aadhar": "[Aadhaar Verified]", "bankPresent": false, "authenticated": true, "aadharAuth": true, "janAuth": true},
    {"sno": "5", "srNo": "1208", "name": "Pradeep Meena", "dob": "X7/03/2020", "gender": "M", "janCard": "", "janMemberId": "", "aadhar": "[Aadhaar Pending]", "bankPresent": false, "authenticated": false, "aadharAuth": false, "janAuth": false},
    {"sno": "6", "srNo": "1209", "name": "Raghav Meena", "dob": "X9/12/2019", "gender": "M", "janCard": "514XXXXX749", "janMemberId": "806XXXX6163", "aadhar": "[Aadhaar Verified]", "bankPresent": false, "authenticated": true, "aadharAuth": true, "janAuth": true},
    {"sno": "7", "srNo": "1210", "name": "Ravi", "dob": "X7/10/2019", "gender": "M", "janCard": "", "janMemberId": "", "aadhar": "", "bankPresent": false, "authenticated": false, "aadharAuth": false, "janAuth": false},
    {"sno": "8", "srNo": "1211", "name": "Raviraj", "dob": "X1/03/2021", "gender": "M", "janCard": "", "janMemberId": "", "aadhar": "[Aadhaar Pending]", "bankPresent": false, "authenticated": false, "aadharAuth": false, "janAuth": false},
    {"sno": "9", "srNo": "1212", "name": "Samarath Lal Meena", "dob": "X6/01/2021", "gender": "M", "janCard": "511XXXXX006", "janMemberId": "502XXXX8841", "aadhar": "[Aadhaar Verified]", "bankPresent": false, "authenticated": true, "aadharAuth": true, "janAuth": true},
  ];

  int get _pendingAadhaarCount {
    if (_selectedClassCode == "ALL") {
      return _classWiseStats.fold(0, (sum, c) => sum + (c["aadharPending"] as int));
    } else {
      final match = _classWiseStats.firstWhere(
        (c) => c["classLabel"].contains(_selectedClassCode),
        orElse: () => {"aadharPending": 0},
      );
      return match["aadharPending"] as int;
    }
  }

  int get _pendingJanCount {
    if (_selectedClassCode == "ALL") {
      return _classWiseStats.fold(0, (sum, c) => sum + (c["janRemaining"] as int));
    } else {
      final match = _classWiseStats.firstWhere(
        (c) => c["classLabel"].contains(_selectedClassCode),
        orElse: () => {"janRemaining": 0},
      );
      return match["janRemaining"] as int;
    }
  }

  @override
  void initState() {
    super.initState();
    _cardsScrollController.addListener(() {
      if (_cardsScrollController.hasClients) {
        final double itemWidth = 310.0 + 14.0;
        final int index = (_cardsScrollController.offset / itemWidth).round();
        if (index != _activeCardIndicator && mounted) {
          setState(() {
            _activeCardIndicator = index;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _cardsScrollController.dispose();
    super.dispose();
  }

  void _showAppleToast(String message, {IconData icon = CupertinoIcons.checkmark_circle_fill, Color color = const Color(0xFF34C759)}) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 24,
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
                    offset: Offset(0, -16 * (1 - value)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 16, offset: const Offset(0, 6))],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, color: color, size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              message,
                              style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: Colors.white),
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

  void _openClassSelectorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            width: 420,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 10))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Select Class & Section",
                        style: TextStyle(fontFamily: kAppFont, fontSize: 14.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(CupertinoIcons.xmark, size: 16, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    itemCount: _classList.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF8FAFC)),
                    itemBuilder: (context, index) {
                      final item = _classList[index];
                      final bool isSelected = item["code"] == _selectedClassCode;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedClassCode = item["code"]!;
                            _selectedClassLabel = item["label"]!;
                          });
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFF8FAFC) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(item["icon"] as IconData, size: 15, color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item["label"]!,
                                  style: TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 12.5,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155),
                                  ),
                                ),
                              ),
                              if (isSelected) const Icon(CupertinoIcons.checkmark_alt, size: 16, color: Color(0xFF0F172A)),
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

  void _openPdfReportDialog({required String title, required String pendingType}) {
    final List<Map<String, dynamic>> pendingStudents = pendingType == "aadhar"
        ? _studentsData.where((s) => s["aadharAuth"] == false).toList()
        : _studentsData.where((s) => s["janAuth"] == false).toList();

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Container(
            width: 720,
            height: MediaQuery.of(context).size.height * 0.88,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 30, offset: const Offset(0, 10))],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(CupertinoIcons.doc_text_fill, size: 18, color: Color(0xFF0F172A)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                title,
                                style: const TextStyle(fontFamily: kAppFont, fontSize: 14.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _showAppleToast("Downloaded $title PDF");
                            },
                            icon: Image.asset(
                              'assets/icons/download.png',
                              width: 17,
                              height: 17,
                              color: const Color(0xFF0F172A),
                              errorBuilder: (c, e, s) => const Icon(CupertinoIcons.arrow_down_to_line, size: 18, color: Color(0xFF0F172A)),
                            ),
                            tooltip: "Download PDF",
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(CupertinoIcons.xmark, size: 18, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                Expanded(
                  child: Container(
                    color: const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 620),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Column(
                                children: [
                                  const Text(
                                    "GOVERNMENT OF RAJASTHAN - SHALA DARPAN",
                                    style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    title.toUpperCase(),
                                    style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    "Govt. Upper Primary School • School NIC: 480481",
                                    style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Divider(height: 1, color: Color(0xFFE2E8F0)),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Filter: $_selectedClassLabel", style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                Text("Total Pending: ${pendingStudents.length}", style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: const [
                                  SizedBox(width: 32, child: Text("S.No", style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)))),
                                  SizedBox(width: 45, child: Text("SR No", style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)))),
                                  Expanded(child: Text("Student Name", style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)))),
                                  SizedBox(width: 30, child: Text("Gen", style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)))),
                                  SizedBox(width: 85, child: Text("Status", style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)))),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: pendingStudents.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                itemBuilder: (context, idx) {
                                  final st = pendingStudents[idx];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    child: Row(
                                      children: [
                                        SizedBox(width: 32, child: Text("${idx + 1}", style: const TextStyle(fontFamily: kAppFont, fontSize: 10.0, color: Color(0xFF475569)))),
                                        SizedBox(width: 45, child: Text("${st['srNo']}", style: const TextStyle(fontFamily: kAppFont, fontSize: 10.0, color: Color(0xFF475569)))),
                                        Expanded(child: Text("${st['name']}", style: const TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)))),
                                        SizedBox(width: 30, child: Text("${st['gender']}", style: const TextStyle(fontFamily: kAppFont, fontSize: 10.0, color: Color(0xFF475569)))),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                                          child: const Text("Pending", style: TextStyle(fontFamily: kAppFont, fontSize: 9.0, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
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
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingReportCard({
    required String title,
    required String subtitle,
    required String count,
    required String iconAssetPath,
    required VoidCallback onView,
    required VoidCallback onDownload,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Image.asset(
                  iconAssetPath,
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Icon(CupertinoIcons.doc_text_fill, color: Color(0xFF0F172A), size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontFamily: kAppFont, fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, color: Color(0xFF64748B)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "$count Pending",
                  style: const TextStyle(fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onView,
                  icon: const Icon(CupertinoIcons.eye_fill, size: 14, color: Colors.white),
                  label: const Text("View PDF", style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDownload,
                  icon: Image.asset(
                    'assets/icons/download.png',
                    width: 14,
                    height: 14,
                    color: const Color(0xFF0F172A),
                    errorBuilder: (c, e, s) => const Icon(CupertinoIcons.arrow_down_to_line, size: 14, color: Color(0xFF0F172A)),
                  ),
                  label: const Text("Download PDF", style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =============================================================
  // REFINED CLASS STATUS CARD: BALANCED WEIGHT & SPACIOUS PODS
  // =============================================================
  Widget _buildCleanClassCard(Map<String, dynamic> stat, bool isSelected) {
    final int total = stat["totalStudents"] as int;
    final int aadharAuth = stat["aadharAuth"] as int;
    final int janAuth = stat["janAuth"] as int;

    final int totalRequired = total * 2;
    final int totalVerified = aadharAuth + janAuth;
    final int overallPct = totalRequired > 0 ? ((totalVerified / totalRequired) * 100).round() : 0;
    final double completionRatio = totalRequired > 0 ? (totalVerified / totalRequired).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: () {
        setState(() {
          _expandedClassDetails = stat["classLabel"];
        });
        if (_expandedClassDetails != "Class - 1/A") {
          _showAppleToast("Showing records for ${stat['classLabel']}", icon: CupertinoIcons.info_circle_fill, color: const Color(0xFF334155));
        }
      },
      child: Container(
        width: 310,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF8FAFC) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
            width: isSelected ? 1.6 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(isSelected ? 0.08 : 0.03),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Row: Class Header & Done Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          stat["id"].toString(),
                          style: TextStyle(
                            fontFamily: kAppFont,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: isSelected ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      stat["classLabel"],
                      style: const TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 15.0,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    "$overallPct% Done",
                    style: const TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 11.0,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),

            // Progress Bar Section with comfortable spacing
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Overall Progress",
                      style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                    ),
                    Text(
                      "$total Students",
                      style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Container(
                    height: 5.0,
                    width: double.infinity,
                    color: const Color(0xFFF1F5F9),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: completionRatio,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Proper Gap between Progress Bar and Metric Pods
            const SizedBox(height: 14),

            // Middle: Data Pods with balanced weight & proper spacing before "Verified"
            Row(
              children: [
                // JanAadhaar Pod
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Image.asset(
                              'assets/icons/janaadhar.png',
                              width: 26,
                              height: 26,
                              fit: BoxFit.contain,
                              errorBuilder: (c, e, s) => const Icon(CupertinoIcons.doc_fill, size: 22, color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              "JanAadhaar",
                              style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              "$janAuth/$total",
                              style: const TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 22.5,
                                fontWeight: FontWeight.w600, // Reduced weight from w800
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 8), // Added spacing before Verified text
                            const Text(
                              "Verified",
                              style: TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Aadhaar Pod
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Image.asset(
                              'assets/icons/aadhar.png',
                              width: 26,
                              height: 26,
                              fit: BoxFit.contain,
                              errorBuilder: (c, e, s) => const Icon(CupertinoIcons.doc_fill, size: 22, color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              "Aadhaar",
                              style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              "$aadharAuth/$total",
                              style: const TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 22.5,
                                fontWeight: FontWeight.w600, // Reduced weight from w800
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 8), // Added spacing before Verified text
                            const Text(
                              "Verified",
                              style: TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Bottom Prompt
            Column(
              children: [
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Click here for student list",
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 11.0,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isSelected ? CupertinoIcons.checkmark_alt : CupertinoIcons.arrow_right,
                      size: 12,
                      color: const Color(0xFF0F172A),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> displayedClassStats = _selectedClassCode == "ALL"
        ? _classWiseStats
        : _classWiseStats.where((c) => c["classLabel"].contains(_selectedClassCode)).toList();

    return Theme(
      data: ThemeData(
        useMaterial3: true,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0F172A),
          onPrimary: Colors.white,
          surfaceTint: Colors.transparent,
        ),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Unified Header & Instructions in One Single Tile with Visible Separator
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title Row
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Center(
                          child: Image.asset(
                            'assets/icons/janaadhar.png',
                            width: 26,
                            height: 26,
                            fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => const Icon(
                              CupertinoIcons.shield_fill,
                              color: Color(0xFF0F172A),
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              "Janaadhar Authentication",
                              style: TextStyle(fontFamily: kAppFont, fontSize: 15.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "Update & Verify Student ID Data",
                              style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, color: Color(0xFF64748B)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  const Divider(height: 1, thickness: 1.0, color: Color(0xFFCBD5E1)),
                  const SizedBox(height: 12),

                  // Integrated Directions / Guidelines directly beneath the title
                  Row(
                    children: const [
                      Icon(CupertinoIcons.info_circle, color: Color(0xFF0F172A), size: 15),
                      SizedBox(width: 6),
                      Text(
                        "महत्वपूर्ण निर्देश (Guidelines)",
                        style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "• यह प्रोग्राम विद्यार्थी के जनाधार-आधार सूचना प्रविष्ट एवं अथेंटीकेट करने हेतु है।",
                    style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, color: Color(0xFF334155), height: 1.5, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    "• विद्यार्थी का नाम, जन्मतिथि एवं जेंडर, जनाधार/आधार डाटाबेस (कार्ड) से मिलान होना आवश्यक है।",
                    style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, color: Color(0xFF334155), height: 1.5, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    "• प्रदर्शित डाटा अथेंटीकेटेड (Verified) स्थिति को दर्शाता है।",
                    style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, color: Color(0xFF334155), height: 1.5, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 2. Class Selector Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Select Class & Section",
                    style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _openClassSelectorDialog,
                    child: Container(
                      height: 44,
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
                            _selectedClassLabel,
                            style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                          ),
                          const Icon(CupertinoIcons.chevron_down, size: 14, color: Color(0xFF64748B)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _isClassDataLoaded = false;
                              _expandedClassDetails = null;
                              _selectedClassCode = "ALL";
                              _selectedClassLabel = "All Classes & Sections";
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          child: const Text(
                            "Clear",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _isClassDataLoaded = true;
                              _expandedClassDetails = null;
                              _activeCardIndicator = 0;
                            });
                            _showAppleToast("Data loaded for $_selectedClassLabel");
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            elevation: 0,
                          ),
                          child: const Text(
                            "Get Class Wise Data",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 3. Pending Reports & Action Cards
            if (_isClassDataLoaded) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Pending Authentication Reports",
                    style: TextStyle(fontFamily: kAppFont, fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    _selectedClassCode == "ALL" ? "All Classes" : _selectedClassLabel,
                    style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Card 1: Pending Aadhaar Student List
              _buildPendingReportCard(
                title: "Pending Aadhaar Authentication List",
                subtitle: "Students whose Aadhaar verification is pending",
                count: "$_pendingAadhaarCount",
                iconAssetPath: 'assets/icons/aadhar.png',
                onView: () => _openPdfReportDialog(
                  title: "Pending Aadhaar Verification List",
                  pendingType: "aadhar",
                ),
                onDownload: () => _showAppleToast("Downloaded Pending Aadhaar List PDF"),
              ),
              const SizedBox(height: 12),

              // Card 2: Pending Janaadhar Student List
              _buildPendingReportCard(
                title: "Pending Janaadhar Authentication List",
                subtitle: "Students whose JanAadhaar verification is pending",
                count: "$_pendingJanCount",
                iconAssetPath: 'assets/icons/janaadhar.png',
                onView: () => _openPdfReportDialog(
                  title: "Pending Janaadhar Verification List",
                  pendingType: "jan",
                ),
                onDownload: () => _showAppleToast("Downloaded Pending Janaadhar List PDF"),
              ),
            ],

            // 4. Class Authentication Status Cards
            if (_isClassDataLoaded) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Class Authentication Status",
                    style: TextStyle(fontFamily: kAppFont, fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    "${displayedClassStats.length} Classes Available",
                    style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              SizedBox(
                height: 240,
                child: ListView.separated(
                  controller: _cardsScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: displayedClassStats.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final stat = displayedClassStats[index];
                    final bool isSelected = _expandedClassDetails == stat["classLabel"];
                    return _buildCleanClassCard(stat, isSelected);
                  },
                ),
              ),

              // Swipe Indicator
              if (_selectedClassCode == "ALL" && displayedClassStats.length > 1) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(displayedClassStats.length, (i) {
                    final bool isActive = _activeCardIndicator == i;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      height: 3.5,
                      width: isActive ? 18.0 : 6.0,
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2.0),
                      ),
                    );
                  }),
                ),
              ],
            ],

            // 5. Student List Table
            if (_expandedClassDetails == "Class - 1/A") ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(width: 6, height: 20, decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 10),
                  Text("Data of students: $_expandedClassDetails", style: const TextStyle(fontFamily: kAppFont, fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                ],
              ),
              const SizedBox(height: 12),

              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _studentsData.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final student = _studentsData[index];
                  final bool isAuth = student["authenticated"];
                  final bool isAadhaarLinked = student["aadharAuth"] == true;
                  final bool hasJanCard = student["janCard"].toString().isNotEmpty;

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                                child: Center(child: Text(student["sno"], style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)))),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            student["name"],
                                            style: const TextStyle(fontFamily: kAppFont, fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                                          child: Text(student["gender"], style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // DOB with leave.png icon
                                    Row(
                                      children: [
                                        Image.asset(
                                          'assets/icons/leave.png',
                                          width: 12,
                                          height: 12,
                                          color: const Color(0xFF64748B),
                                          errorBuilder: (c, e, s) => const Icon(CupertinoIcons.calendar, size: 12, color: Color(0xFF64748B)),
                                        ),
                                        const SizedBox(width: 5),
                                        Text("DOB: ${student['dob']}", style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: _buildIdField("JanAadhar No.", student["janCard"], hasJanCard, isAuth)),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildIdField("Member ID", student["janMemberId"], hasJanCard, isAuth)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildIdField(
                                      "Aadhaar Status",
                                      isAadhaarLinked ? "Linked & Verified" : "Pending / Not Linked",
                                      isAadhaarLinked,
                                      isAuth,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text("Bank Info Present", style: TextStyle(fontFamily: kAppFont, fontSize: 9.0, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
                                        const SizedBox(height: 3),
                                        Text(student["bankPresent"] ? "Yes" : "No", style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isAuth ? CupertinoIcons.checkmark_seal_fill : CupertinoIcons.exclamationmark_circle,
                                    size: 15,
                                    color: isAuth ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isAuth ? "Authenticated" : "Pending",
                                    style: TextStyle(
                                      fontFamily: kAppFont,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: isAuth ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                              if (!isAuth)
                                ElevatedButton.icon(
                                  onPressed: () => _openAuthModal(student),
                                  icon: const Icon(CupertinoIcons.checkmark_shield_fill, size: 13, color: Colors.white),
                                  label: const Text("Authenticate", style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w700)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F172A),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                                    minimumSize: const Size(0, 32),
                                    elevation: 0,
                                  ),
                                )
                              else
                                OutlinedButton(
                                  onPressed: () => _openAuthModal(student),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF1F5F9),
                                    foregroundColor: const Color(0xFF0F172A),
                                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                    minimumSize: const Size(0, 32),
                                  ),
                                  child: const Text("Verify Again", style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w600)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildIdField(String label, String value, bool isEntered, bool isAuth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontFamily: kAppFont, fontSize: 9.0, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
        const SizedBox(height: 3),
        Text(
          !isEntered ? "Not Available" : value,
          style: TextStyle(
            fontFamily: kAppFont,
            fontSize: 11.5,
            fontWeight: !isEntered ? FontWeight.w600 : FontWeight.w800,
            color: !isEntered ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
            letterSpacing: !isEntered ? 0 : 0.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  void _openAuthModal(Map<String, dynamic> student) {
    final TextEditingController janCardCtrl = TextEditingController(text: student["janCard"].toString().replaceAll('X', ''));
    final TextEditingController janMemCtrl = TextEditingController(text: student["janMemberId"].toString().replaceAll('X', ''));
    final TextEditingController aadhaarCtrl = TextEditingController();
    bool consentChecked = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return Theme(
          data: ThemeData.light().copyWith(
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            textSelectionTheme: const TextSelectionThemeData(
              cursorColor: Color(0xFF0F172A),
              selectionColor: Color(0x330F172A),
              selectionHandleColor: Color(0xFF0F172A),
            ),
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Container(
                  width: 500,
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 28, offset: const Offset(0, 14))]),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Student Authentication", style: TextStyle(fontFamily: kAppFont, fontSize: 16.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                  const SizedBox(height: 2),
                                  Text("${student['name']} • Class 1/A", style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w500, color: Color(0xFF64748B))),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(CupertinoIcons.xmark, size: 18, color: Color(0xFF64748B)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      Flexible(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                                child: Column(
                                  children: [
                                    Row(
                                      children: const [
                                        Icon(CupertinoIcons.info_circle_fill, size: 14, color: Color(0xFF64748B)),
                                        SizedBox(width: 6),
                                        Text("ShalaDarpan Portal Data (As per Form-5)", style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(child: _buildIdField("Date of Birth", student["dob"], true, false)),
                                        Expanded(child: _buildIdField("Gender", student["gender"] == "M" ? "Male" : "Female", true, false)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // 1. JanAadhar Number Field (Strictly 10 Digits)
                              const Text("JanAadhar Information", style: TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                              const SizedBox(height: 10),
                              const Padding(
                                padding: EdgeInsets.only(bottom: 5),
                                child: Text("JanAadhar Number (10 Digits) *", style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
                              ),
                              TextField(
                                controller: janCardCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                style: const TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w600, letterSpacing: 1.5, color: Color(0xFF0F172A)),
                                decoration: InputDecoration(
                                  hintText: "Enter exact 10 digit number",
                                  hintStyle: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, letterSpacing: 0, fontWeight: FontWeight.w500, color: Color(0xFF94A3B8)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F172A))),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // 2. JanAadhar Member ID (Strictly 11 Digits)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 5),
                                child: Text("Member ID (11 Digits) *", style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
                              ),
                              TextField(
                                controller: janMemCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(11),
                                ],
                                style: const TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w600, letterSpacing: 1.5, color: Color(0xFF0F172A)),
                                decoration: InputDecoration(
                                  hintText: "Enter exact 11 digit member ID",
                                  hintStyle: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, letterSpacing: 0, fontWeight: FontWeight.w500, color: Color(0xFF94A3B8)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F172A))),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // 3. Aadhaar Number Field (Strictly 12 Digits)
                              const Text("Aadhaar Information", style: TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                              const SizedBox(height: 10),
                              const Padding(
                                padding: EdgeInsets.only(bottom: 5),
                                child: Text("Aadhaar Number (12 Digits) *", style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
                              ),
                              TextField(
                                controller: aadhaarCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(12),
                                ],
                                style: const TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w600, letterSpacing: 1.5, color: Color(0xFF0F172A)),
                                decoration: InputDecoration(
                                  hintText: "Enter exact 12 digit number",
                                  hintStyle: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, letterSpacing: 0, fontWeight: FontWeight.w500, color: Color(0xFF94A3B8)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F172A))),
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Consent Box
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Checkbox(
                                        value: consentChecked,
                                        activeColor: const Color(0xFF0F172A),
                                        onChanged: (val) {
                                          setModalState(() {
                                            consentChecked = val ?? false;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        "The school has taken consent from the student for authentication and the identity information is used only for submission to the central identity data repository.",
                                        style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569), height: 1.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text("Cancel", style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: () {
                                  if (!consentChecked) {
                                    _showAppleToast("Please check the consent box", icon: CupertinoIcons.exclamationmark_triangle_fill, color: const Color(0xFF64748B));
                                    return;
                                  }

                                  final String janVal = janCardCtrl.text.trim();
                                  final String memVal = janMemCtrl.text.trim();
                                  final String adhVal = aadhaarCtrl.text.trim();

                                  if (janVal.isEmpty && adhVal.isEmpty) {
                                    _showAppleToast("Enter at least one ID to verify", icon: CupertinoIcons.exclamationmark_triangle_fill, color: const Color(0xFF64748B));
                                    return;
                                  }

                                  if (janVal.isNotEmpty && janVal.length != 10) {
                                    _showAppleToast("JanAadhar must be exactly 10 digits", icon: CupertinoIcons.exclamationmark_triangle_fill, color: const Color(0xFF0F172A));
                                    return;
                                  }

                                  if (memVal.isNotEmpty && memVal.length != 11) {
                                    _showAppleToast("Member ID must be exactly 11 digits", icon: CupertinoIcons.exclamationmark_triangle_fill, color: const Color(0xFF0F172A));
                                    return;
                                  }

                                  if (adhVal.isNotEmpty && adhVal.length != 12) {
                                    _showAppleToast("Aadhaar number must be exactly 12 digits", icon: CupertinoIcons.exclamationmark_triangle_fill, color: const Color(0xFF0F172A));
                                    return;
                                  }

                                  Navigator.pop(context);
                                  _showAppleToast("Verification Request Sent!");
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  elevation: 0,
                                ),
                                child: const Text("Authenticate & Save", style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        ),
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