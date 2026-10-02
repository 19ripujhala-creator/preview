// lib/tabs/teacher/modules/shaladarpan/class_mapping_view.dart
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/core/backend_config.dart';

const String kAppFont = 'PlusJakartaSans';

class ClassMappingView extends StatefulWidget {
  final String schoolId;
  const ClassMappingView({super.key, required this.schoolId});

  @override
  State<ClassMappingView> createState() => _ClassMappingViewState();
}

class _ClassMappingViewState extends State<ClassMappingView> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  List<dynamic> _mappingRows = [];
  List<dynamic> _initialRowsBackup = [];
  String _academicSession = "2026-27";

  @override
  void initState() {
    super.initState();
    _loadCachedThenFetch();
  }

  void _haptic() => HapticFeedback.selectionClick();

  /// 1. Pehle local cache se instant load, phir backend se fresh data fetch
  Future<void> _loadCachedThenFetch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString("cached_class_mapping_${widget.schoolId}");
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final decoded = jsonDecode(cachedJson);
        if (decoded is List && decoded.isNotEmpty) {
          setState(() {
            _mappingRows = decoded;
            _initialRowsBackup = jsonDecode(jsonEncode(decoded));
            if (_mappingRows[0]['session'] != null) {
              _academicSession = _mappingRows[0]['session'];
            }
            _isLoading = false;
          });
        }
      }
    } catch (_) {}

    await _fetchClassMappings();
  }

  Future<void> _fetchClassMappings() async {
    if (_mappingRows.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await http.get(
        BackendConfig.uri('/api/shaladarpan/class-mapping/fetch?school_id=${widget.schoolId}'),
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        final jsonRes = jsonDecode(response.body);
        if (jsonRes['success'] == true && jsonRes['data'] != null && (jsonRes['data'] as List).isNotEmpty) {
          final freshData = jsonRes['data'];
          setState(() {
            _mappingRows = freshData;
            _initialRowsBackup = jsonDecode(jsonEncode(freshData));
            if (_mappingRows[0]['session'] != null) {
              _academicSession = _mappingRows[0]['session'];
            }
          });

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString("cached_class_mapping_${widget.schoolId}", jsonEncode(freshData));
        }
      }
    } catch (e) {
      if (_mappingRows.isEmpty) {
        final fallbackData = [
          {
            "index": 0,
            "class": "1",
            "section": "A",
            "session": "2026-27",
            "selected_teacher_id": "",
            "teachers_list": []
          }
        ];
        setState(() {
          _mappingRows = fallbackData;
          _initialRowsBackup = jsonDecode(jsonEncode(fallbackData));
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 2. Notification System: Jumble-proof and color-coded
  void _showSnackBar(
    String message, {
    bool isError = false,
    bool isCancel = false,
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();

    Color bgColor;
    IconData iconData;

    if (isError) {
      bgColor = const Color(0xFFDC2626);
      iconData = CupertinoIcons.exclamationmark_circle_fill;
    } else if (isCancel) {
      bgColor = const Color(0xFF334155);
      iconData = CupertinoIcons.arrow_counterclockwise_circle_fill;
    } else {
      bgColor = const Color(0xFF16A34A);
      iconData = CupertinoIcons.checkmark_circle_fill;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(iconData, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: kAppFont,
                  fontSize: 12.0,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(milliseconds: 2200),
      ),
    );
  }

  /// 3. Revert Changes on Cancel
  void _cancelChanges() {
    _haptic();
    setState(() {
      _mappingRows = jsonDecode(jsonEncode(_initialRowsBackup));
    });
    _showSnackBar("Changes cancelled & reverted to original.", isCancel: true);
  }

  /// 4. Save Mappings: Local-first persistence + Backend Portal Sync
  Future<void> _submitMappings() async {
    _haptic();
    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("cached_class_mapping_${widget.schoolId}", jsonEncode(_mappingRows));
    } catch (_) {}

    try {
      final response = await http.post(
        BackendConfig.uri('/api/shaladarpan/class-mapping/save'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "school_id": widget.schoolId,
          "updates": _mappingRows.map((row) => {
            "index": row['index'],
            "teacher_id": row['selected_teacher_id']
          }).toList()
        }),
      ).timeout(const Duration(seconds: 40));

      final jsonRes = jsonDecode(response.body);

      if (response.statusCode == 200 && jsonRes['success'] == true) {
        _initialRowsBackup = jsonDecode(jsonEncode(_mappingRows));
        _showSnackBar("Class Teacher Mappings saved successfully!", isError: false);
      } else {
        final errorMsg = jsonRes['message'] ?? "Portal session timed out. Retrying on next sync.";
        _showSnackBar("Saved locally. Portal: $errorMsg", isCancel: true);
      }
    } catch (e) {
      _showSnackBar("Saved offline. Changes are safe on device.", isCancel: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// 5. Incharge-Style Bottom Sheet Picker
  void _openTeacherPicker(int rowIndex, List teachers, String currentTeacherId) {
    _haptic();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.50),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  "Assign Class Teacher",
                  style: TextStyle(
                    fontFamily: kAppFont,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              Expanded(
                child: ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: teachers.length,
                  itemBuilder: (context, tIndex) {
                    final teacher = teachers[tIndex];
                    final bool isSelected = teacher['id'].toString() == currentTeacherId.toString();

                    return GestureDetector(
                      onTap: () {
                        _haptic();
                        setState(() {
                          _mappingRows[rowIndex]['selected_teacher_id'] = teacher['id'].toString();
                        });
                        Navigator.pop(context);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF0F172A).withOpacity(0.06) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                teacher['name'],
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: MediaQuery.sizeOf(context).width < 452 ? 11.5 : 13.0,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155),
                                ),
                              ),
                            ),
                            if (isSelected) const Icon(Icons.check_circle_rounded, color: Color(0xFF0F172A), size: 16),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _mappingChip(String label, {required bool compact}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(minWidth: 25),
        margin: const EdgeInsets.only(right: 5),
        padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: kAppFont, fontSize: 11,
            fontWeight: FontWeight.w600, color: Color(0xFF475569))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 420;
      final serialWidth = compact ? 24.0 : 36.0;
      final classWidth = compact ? 38.0 : 52.0;
      final sectionWidth = compact ? 48.0 : 56.0;
      return Padding(
      // Outer horizontal margin removed so it aligns uniformly with other modules
      padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Bar with "Class Teacher Mapping" and leave.png Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  "Class Teacher Mapping",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: kAppFont,
                    fontSize: 16.0,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/icons/leave.png',
                      width: 15,
                      height: 15,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(CupertinoIcons.calendar, size: 14, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _academicSession,
                      style: const TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 12.0,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 2. Uniform Width Table or Apple-style Loading Indicator
          Expanded(
            child: _isLoading
                ? const Center(child: CupertinoActivityIndicator(radius: 12))
                : Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        // Integrated Header with Dedicated Class & Section Columns
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: serialWidth,
                                child: Text(
                                  "Sr.",
                                  style: TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: classWidth,
                                child: Text(
                                  "Class",
                                  style: TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: sectionWidth,
                                child: Text(
                                  "Section",
                                  style: TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  "Assigned Class Teacher",
                                  style: TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // List of Classes
                        Expanded(
                          child: ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.zero,
                            itemCount: _mappingRows.length,
                            separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            itemBuilder: (context, index) {
                              final row = _mappingRows[index];
                              List teachers = row['teachers_list'] ?? [];
                              String selectedTeacherId = row['selected_teacher_id'] ?? "";

                              String selectedTeacherName = "Select Teacher";
                              for (var t in teachers) {
                                if (t['id'].toString() == selectedTeacherId.toString()) {
                                  selectedTeacherName = t['name'];
                                  break;
                                }
                              }

                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                child: Row(
                                  children: [
                                    // 1. Sr. No.
                                    SizedBox(
                                      width: serialWidth,
                                      child: Text(
                                        "${index + 1}",
                                        style: const TextStyle(
                                          fontFamily: kAppFont,
                                          fontSize: 12.0,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ),

                                    // 2. Class Column
                                    SizedBox(
                                      width: classWidth,
                                      child: _mappingChip('${row['class']}', compact: compact),
                                    ),

                                    // 3. Section Column
                                    SizedBox(
                                      width: sectionWidth,
                                      child: _mappingChip('${row['section']}', compact: compact),
                                    ),

                                    // 4. Teacher Selector Box
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => _openTeacherPicker(index, teachers, selectedTeacherId),
                                        behavior: HitTestBehavior.opaque,
                                        child: Container(
                                          height: 32,
                                          padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFFE2E8F0)),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  selectedTeacherName,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontFamily: kAppFont,
                                                    fontSize: compact ? 11.5 : 13.0,
                                                    fontWeight: selectedTeacherId.isEmpty ? FontWeight.w500 : FontWeight.w600,
                                                    color: selectedTeacherId.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Icon(CupertinoIcons.chevron_down, size: 11, color: Color(0xFF64748B)),
                                            ],
                                          ),
                                        ),
                                      ),
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

          // 3. Bottom Dual Action Bar (Full Uniform Width)
          if (!_isLoading && _mappingRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                // Cancel Action Button
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : _cancelChanges,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      backgroundColor: Colors.white,
                    ),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Save Action Button
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitMappings,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CupertinoActivityIndicator(color: Colors.white, radius: 8),
                          )
                        : const Icon(CupertinoIcons.checkmark_alt, size: 14),
                    label: Text(
                      _isSubmitting ? "Saving..." : "Save Mappings",
                      style: const TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    });
  }
}
