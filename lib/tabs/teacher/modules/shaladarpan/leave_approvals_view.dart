// lib/tabs/teacher/modules/shaladarpan/leave_approvals_view.dart

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shaladarpan/services/portals/shaladarpan/leave_approval_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/leave_result_messages.dart';

const String kAppFont = 'PlusJakartaSans';

class LeaveApprovalsView extends StatefulWidget {
  final VoidCallback? onLeaveProcessed;
  const LeaveApprovalsView({super.key, this.onLeaveProcessed});

  @override
  State<LeaveApprovalsView> createState() => _LeaveApprovalsViewState();
}

class _LeaveApprovalsViewState extends State<LeaveApprovalsView> {
  List<Map<String, dynamic>> _leaveRequests = [];
  bool _isLoading = true;
  bool _hasVerified = false;
  bool _fetching = false;
  String? _fetchError;
  final Set<String> _processingIds = {}; // Tracks leaves currently submitting

  @override
  void initState() {
    super.initState();
    _loadCachedDataFirst();
  }

  void _haptic() => HapticFeedback.selectionClick();

  // 1. Instant 0ms Load from Local Storage
  Future<void> _loadCachedDataFirst() async {
    final cached = await LeaveApprovalService.getCachedLeaves();
    if (cached != null && cached['applications'] is List) {
      if (mounted) {
        setState(() {
          _leaveRequests = _formatBackendData(
            List<Map<String, dynamic>>.from(cached['applications']),
          );
        });
      }
    }
    // Background fetch for fresh portal data
    _fetchFreshLeaves(silent: _leaveRequests.isNotEmpty, fresh: false);
  }

  // 2. Fetch Fresh Data from Portal & Update Local Cache
  Future<void> _fetchFreshLeaves({
    bool silent = false,
    bool fresh = true,
  }) async {
    if (_fetching || _processingIds.isNotEmpty || !mounted) return;
    _fetching = true;
    setState(() {
      _isLoading = true;
      _hasVerified = false;
      _fetchError = null;
    });
    try {
      final res = await LeaveApprovalService.fetchLeaveApprovals(fresh: fresh);
      if (!mounted) return;
      final data = res['data'];
      if (res['success'] == true &&
          data is Map &&
          LeaveApprovalService.valid(data)) {
        setState(() {
          _leaveRequests = _formatBackendData(
            List<Map<String, dynamic>>.from(data['applications']),
          );
          _hasVerified = true;
        });
      } else {
        setState(
          () => _fetchError = LeaveResultMessages.display(
            res,
            fallback: 'Leave approval status is not confirmed.',
          ),
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _fetchError =
              'App: Leave approval status could not be confirmed.',
        );
    } finally {
      _fetching = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Transform Shala Darpan Scraped Format to UI Model
  List<Map<String, dynamic>> _formatBackendData(
    List<Map<String, dynamic>> rawList,
  ) {
    return rawList.map((item) {
      final daysVal = item['days']?.toString() ?? '1';
      final formattedDays = daysVal.endsWith('.0')
          ? daysVal.replaceAll('.0', '')
          : daysVal;

      return {
        "leave_id": item['leave_id']?.toString() ?? '',
        "sno": item['sno']?.toString() ?? '',
        "name": item['name']?.toString() ?? 'Unknown Staff',
        "type": item['leave_type']?.toString() ?? 'Leave',
        "duration":
            "$formattedDays ${double.tryParse(formattedDays) == 1 ? 'day' : 'days'}",
        "date": "${item['from_date'] ?? ''} - ${item['to_date'] ?? ''}",
        "reason":
            (item['reason'] != null && item['reason'].toString().isNotEmpty)
            ? item['reason'].toString()
            : "Official Leave Application",
        "status": item['status'] ?? "Pending",
      };
    }).toList();
  }

  // An action owns the screen until its result settles. Only a fresh portal
  // read replaces records; a verified action never invents a local row status.
  Future<void> _handleAction(
    Map<String, dynamic> leave,
    String statusCode,
  ) async {
    if (!_hasVerified || _isLoading || _processingIds.isNotEmpty) return;
    final leaveId = leave['leave_id']?.toString() ?? '';
    if (leaveId.isEmpty) return;
    _haptic();
    setState(() {
      _processingIds.add(leaveId);
      _hasVerified = false;
    });
    try {
      final res = await LeaveApprovalService.submitLeaveAction(
        leaveId: leaveId,
        status: statusCode,
      );
      if (!mounted) return;
      setState(() => _processingIds.remove(leaveId));
      if (LeaveApprovalService.isActionConfirmed(res, [
        {'leave_id': leaveId, 'status': statusCode},
      ])) {
        await _fetchFreshLeaves(silent: true);
        if (!mounted) return;
        widget.onLeaveProcessed?.call();
      } else {
        setState(() {
          _hasVerified = false;
          _fetchError = LeaveResultMessages.display(
            res,
            fallback: 'Leave action result is not confirmed. Refresh before retrying.',
          );
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LeaveResultMessages.display(res)),
          backgroundColor: res['success'] == true && statusCode == '1'
              ? const Color(0xFF16A34A)
              : const Color(0xFFDC2626),
        ),
      );
    } catch (_) {
      if (mounted)
        setState(() {
          _hasVerified = false;
          _fetchError = 'App: Leave action result could not be confirmed. Refresh before retrying.';
        });
    } finally {
      if (mounted) setState(() => _processingIds.remove(leaveId));
    }
  }

  // Crash-proof Initials Generator (Never throws RangeError on empty/odd strings)
  String _getInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return "L";
    final parts = clean
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return "L";
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return "${parts[0][0]}${parts[parts.length - 1][0]}".toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        return RefreshIndicator(
          onRefresh: () => _fetchFreshLeaves(),
          color: const Color(0xFF0F172A),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.only(bottom: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with Refresh Status
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFF1F5F9)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/icons/leave.png',
                          width: 15,
                          height: 15,
                          color: const Color(0xFF64748B),
                          errorBuilder: (c, e, s) => const Icon(
                            CupertinoIcons.calendar_today,
                            size: 15,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(width: 7),
                        const Text(
                          "Leave Requests",
                          style: TextStyle(
                            fontFamily: kAppFont,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const Spacer(),
                        if (_isLoading)
                          const CupertinoActivityIndicator(radius: 7)
                        else
                          GestureDetector(
                            onTap: () => _fetchFreshLeaves(),
                            child: const Icon(
                              CupertinoIcons.arrow_clockwise,
                              size: 14,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                      ],
                    ),
                  ),

                  if (!_hasVerified && !_isLoading && _processingIds.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fetchError ??
                                'Checking portal leave approval status…',
                            style: const TextStyle(
                              fontFamily: kAppFont,
                              fontSize: 12,
                              color: Color(0xFFB45309),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _fetchFreshLeaves(),
                            child: const Text('Retry'),
                          ),
                          if (_leaveRequests.isNotEmpty)
                            const Text(
                              'Last loaded records • Not confirmed',
                              style: TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 10.5,
                                color: Color(0xFF64748B),
                              ),
                            ),
                        ],
                      ),
                    ),
                  // Empty state only follows a verified portal zero.

                  if (_leaveRequests.isEmpty &&
                      !_isLoading &&
                      _hasVerified &&
                      _fetchError == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.check_mark_circled,
                              color: Color(0xFF34C759),
                              size: 36,
                            ),
                            SizedBox(height: 8),
                            Text(
                              "All Caught Up",
                              style: TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 14.0,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "No pending leave applications",
                              style: TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 11.5,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: _leaveRequests.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      itemBuilder: (context, index) {
                        final leave = _leaveRequests[index];
                        final String leaveId =
                            leave["leave_id"]?.toString() ?? '';
                        final bool isPending =
                            _hasVerified &&
                            !_isLoading &&
                            leave["status"] == "Pending";
                        final bool isProcessing = _processingIds.contains(
                          leaveId,
                        );

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    _getInitials(leave["name"]),
                                    style: const TextStyle(
                                      fontFamily: kAppFont,
                                      fontSize: 13.0,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      leave["name"],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: kAppFont,
                                        fontSize: compact ? 11.5 : 13.0,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Image.asset(
                                          'assets/icons/leave.png',
                                          width: 13,
                                          height: 13,
                                          color: const Color(0xFF64748B),
                                          errorBuilder: (c, e, s) => const Icon(
                                            CupertinoIcons.calendar,
                                            size: 13,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            "${leave["type"]} • ${leave["duration"]}",
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontFamily: kAppFont,
                                              fontSize: 11.0,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      leave["date"],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: kAppFont,
                                        fontSize: 11.0,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    if (isProcessing)
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          children: [
                                            CupertinoActivityIndicator(
                                              radius: 8,
                                            ),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                "Submitting to portal...",
                                                style: TextStyle(
                                                  fontFamily: kAppFont,
                                                  fontSize: 11.0,
                                                  color: Color(0xFF64748B),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else if (isPending)
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 8,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFEF3C7),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              leave["status"],
                                              style: const TextStyle(
                                                fontFamily: kAppFont,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFFD97706),
                                              ),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () =>
                                                _handleAction(leave, "2"),
                                            behavior: HitTestBehavior.opaque,
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 7,
                                              ),
                                              child: Text(
                                                "Reject",
                                                style: TextStyle(
                                                  fontFamily: kAppFont,
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF0F172A),
                                                ),
                                              ),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () =>
                                                _handleAction(leave, "1"),
                                            behavior: HitTestBehavior.opaque,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 7,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF0F172A),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                "Approve",
                                                style: TextStyle(
                                                  fontFamily: kAppFont,
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: leave["status"] == "Approved"
                                              ? const Color(0xFFDCFCE7)
                                              : const Color(0xFFFEE2E2),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          leave["status"],
                                          style: TextStyle(
                                            fontFamily: kAppFont,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: leave["status"] == "Approved"
                                                ? const Color(0xFF16A34A)
                                                : const Color(0xFFDC2626),
                                          ),
                                        ),
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
              ),
            ),
          ),
        );
      },
    );
  }
}
