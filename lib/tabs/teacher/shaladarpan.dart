// lib/tabs/teacher/shaladarpan.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shaladarpan/services/portals/shaladarpan/leave_approval_service.dart';

import 'modules/shaladarpan/attendance_view.dart';
import 'modules/shaladarpan/leave_approvals_view.dart';
import 'modules/shaladarpan/class_mapping_view.dart';
import 'modules/shaladarpan/incharge_roles_view.dart';

const String kAppFont = 'PlusJakartaSans';

class ShaladarpanView extends StatefulWidget {
  final String schoolId;
  final VoidCallback? onAttendanceUpdated;
  final int initialSubIndex;

  const ShaladarpanView({
    super.key,
    required this.schoolId,
    this.onAttendanceUpdated,
    this.initialSubIndex = 0,
  });

  @override
  State<ShaladarpanView> createState() => _ShaladarpanViewState();
}

class _ShaladarpanViewState extends State<ShaladarpanView>
    with AutomaticKeepAliveClientMixin {
  late int _selectedModuleIndex;
  int? _pendingLeaveCount;
  bool _leaveStatusLoading = true;
  String? _leaveStatusError;
  int _attendanceRefreshRevision = 0;
  int _leaveCountRequest = 0;
  bool _attendanceNeedsRefresh = false;
  late final Set<int> _activatedIndices;
  late final List<FocusScopeNode> _moduleFocus;
  final List<GlobalKey> _moduleButtonKeys = List.generate(4, (_) => GlobalKey());

  static const List<String> _shalaModules = [
    'Attendance', 'Leave Approvals', 'Class Mapping', 'Incharge Roles',
  ];

  @override
  bool get wantKeepAlive => true;

  int _safeIndex(int index) => index.clamp(0, _shalaModules.length - 1).toInt();

  @override
  void initState() {
    super.initState();
    _selectedModuleIndex = _safeIndex(widget.initialSubIndex);
    _activatedIndices = {_selectedModuleIndex};
    _moduleFocus = List.generate(_shalaModules.length,
        (index) => FocusScopeNode(debugLabel: 'shaladarpan_module_$index'));
    LeaveApprovalService.liveStatus.addListener(_onLeaveStatusChanged);
    _loadPendingLeaveCount();
    _restoreActiveScope();
  }

  @override
  void dispose() {
    LeaveApprovalService.liveStatus.removeListener(_onLeaveStatusChanged);
    _leaveCountRequest++;
    for (final scope in _moduleFocus) {
      scope.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ShaladarpanView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.schoolId != oldWidget.schoolId) {
      _moduleFocus[_selectedModuleIndex].unfocus();
      _selectedModuleIndex = _safeIndex(widget.initialSubIndex);
      _activatedIndices
        ..clear()
        ..add(_selectedModuleIndex);
      _pendingLeaveCount = null;
      _leaveStatusLoading = true;
      _leaveStatusError = null;
      _attendanceNeedsRefresh = false;
      _attendanceRefreshRevision++;
      _loadPendingLeaveCount();
      _restoreActiveScope();
    } else if (widget.initialSubIndex != oldWidget.initialSubIndex) {
      _selectModule(_safeIndex(widget.initialSubIndex), haptic: false);
    }
  }

  void _selectModule(int index, {bool haptic = true}) {
    final safeIndex = _safeIndex(index);
    if (safeIndex == _selectedModuleIndex) {
      _restoreActiveScope();
      _loadPendingLeaveCount();
      return;
    }
    _moduleFocus[_selectedModuleIndex].unfocus();
    if (haptic) HapticFeedback.selectionClick();
    setState(() {
      if (safeIndex == 0 && _attendanceNeedsRefresh) {
        _attendanceRefreshRevision++;
        _attendanceNeedsRefresh = false;
      }
      _selectedModuleIndex = safeIndex;
      _activatedIndices.add(safeIndex);
    });
    _restoreActiveScope();
    _loadPendingLeaveCount();
  }

  void _restoreActiveScope() {
    final index = _selectedModuleIndex;
    final school = widget.schoolId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index != _selectedModuleIndex || school != widget.schoolId) return;
      final scope = _moduleFocus[index];
      // Keep this scope enabled; visibility is gated only by ExcludeFocus.
      // Restore after the new tab's focus tree has been attached.
      scope.canRequestFocus = true;
      if (!scope.hasFocus) scope.requestFocus();
      final buttonContext = _moduleButtonKeys[index].currentContext;
      if (buttonContext != null) {
        Scrollable.ensureVisible(buttonContext,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: 0.5,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit);
      }
    });
  }

  void _applyLeaveStatus(Map<String, dynamic> result) {
    if (!mounted || result['school_id'] != widget.schoolId) return;
    final data = result['data'];
    final confirmed = result['success'] == true && data is Map && LeaveApprovalService.valid(data);
    setState(() {
      _pendingLeaveCount = confirmed ? data['pending_count'] as int : null;
      _leaveStatusLoading = result['loading'] == true;
      _leaveStatusError = confirmed || _leaveStatusLoading ? null :
          result['message']?.toString() ?? 'Leave approval status could not be confirmed.';
    });
  }

  void _onLeaveStatusChanged() {
    final status = LeaveApprovalService.liveStatus.value;
    if (status != null) _applyLeaveStatus(status);
  }

  Future<void> _loadPendingLeaveCount({bool fresh = false}) async {
    final request = ++_leaveCountRequest;
    final school = widget.schoolId;
    try {
      final result = await LeaveApprovalService.fetchLeaveApprovals(fresh: fresh);
      if (!mounted || request != _leaveCountRequest || widget.schoolId != school) return;
      _applyLeaveStatus({...result, 'school_id': school, 'loading': false});
    } catch (_) {
      if (!mounted || request != _leaveCountRequest || widget.schoolId != school) return;
      _applyLeaveStatus({'school_id': school, 'success': false, 'loading': false,
        'message': 'Leave approval status could not be confirmed.'});
    }
  }

  Widget _attendanceModule() {
    if (_pendingLeaveCount != null) {
      return AttendanceView(
        key: ValueKey('attendance_${widget.schoolId}_$_attendanceRefreshRevision'),
        onAttendanceUpdated: () {
          _loadPendingLeaveCount();
          widget.onAttendanceUpdated?.call();
        },
      );
    }
    return Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_leaveStatusLoading) const CupertinoActivityIndicator(radius: 11),
        const SizedBox(height: 12),
        Text(_leaveStatusLoading ? 'Checking leave approvals' : 'Leave status not confirmed',
          style: const TextStyle(fontFamily: kAppFont, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(_leaveStatusError ?? 'Attendance will open after the portal leave status is confirmed.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: kAppFont, fontSize: 12, color: Color(0xFF64748B))),
        if (!_leaveStatusLoading) TextButton(
          onPressed: () => _loadPendingLeaveCount(fresh: true),
          child: const Text('Retry')),
      ]),
    ));
  }

  void _handleLeaveOrAttendanceUpdate() {
    if (!mounted) return;
    // A late leave callback must not dispose an active attendance search/form.
    // Refresh the attendance roster when the user next enters that module.
    _attendanceNeedsRefresh = true;
    _loadPendingLeaveCount();
    widget.onAttendanceUpdated?.call();
  }

  Widget _module(int index, Widget Function() builder) {
    final active = _selectedModuleIndex == index;
    return FocusScope(
      key: ValueKey('module_scope_${widget.schoolId}_$index'),
      node: _moduleFocus[index],
      canRequestFocus: true,
      child: ExcludeFocus(
        excluding: !active,
        child: IgnorePointer(
          ignoring: !active,
          child: TickerMode(
            enabled: active,
            child: _activatedIndices.contains(index) ? builder() : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: List.generate(_shalaModules.length, (index) {
            final isSelected = _selectedModuleIndex == index;
            final isLeaveTab = index == 1;
            return Padding(
              key: _moduleButtonKeys[index],
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _selectModule(index),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF0F172A) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isSelected
                        ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_shalaModules[index], style: TextStyle(
                      fontFamily: kAppFont, fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? Colors.white : const Color(0xFF475569),
                    )),
                    if (isLeaveTab && (_pendingLeaveCount == null || _pendingLeaveCount! > 0)) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_pendingLeaveCount?.toString() ?? (_leaveStatusLoading ? '…' : '!'), style: TextStyle(
                          fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w700,
                          color: isSelected ? const Color(0xFF0F172A) : Colors.white,
                        )),
                      ),
                    ],
                  ]),
                ),
              ),
            );
          })),
        ),
        const SizedBox(height: 8),
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IndexedStack(
            index: _selectedModuleIndex,
            children: [
              _module(0, _attendanceModule),
              _module(1, () => LeaveApprovalsView(
                onLeaveProcessed: _handleLeaveOrAttendanceUpdate,
              )),
              _module(2, () => ClassMappingView(
                key: PageStorageKey('class_mapping_${widget.schoolId}'),
                schoolId: widget.schoolId,
              )),
              _module(3, () => InchargeRolesView(
                key: PageStorageKey('incharge_roles_${widget.schoolId}'),
              )),
            ],
          ),
        )),
      ],
    );
  }
}
