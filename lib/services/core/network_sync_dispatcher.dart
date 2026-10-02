import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shaladarpan/services/core/ecosystem_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/offline_attendance_queue.dart';

class NetworkSyncDispatcher {
  static final NetworkSyncDispatcher _instance = NetworkSyncDispatcher._internal();
  factory NetworkSyncDispatcher() => _instance;
  NetworkSyncDispatcher._internal();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isSyncing = false;
  bool _enabled = false;
  VoidCallback? onSyncSuccess;

  void initialize({VoidCallback? onSyncCompleted}) {
    if (onSyncCompleted != null) onSyncSuccess = onSyncCompleted;
    _enabled = true;
    _subscription ??= Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) unawaited(triggerAutoSync());
    });
    unawaited(triggerAutoSync());
  }

  Future<void> triggerAutoSync() async {
    if (_isSyncing || !_enabled || !EcosystemService.isSchoolReady) return;
    _isSyncing = true;
    try {
      if (!await OfflineAttendanceQueue.hasPendingQueue() || !_enabled) return;
      final result = await OfflineAttendanceQueue.syncNow();
      if (_enabled && result['success'] == true) onSyncSuccess?.call();
    } catch (_) {
      debugPrint('Offline attendance retained after sync failure.');
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _enabled = false;
    _subscription?.cancel();
    _subscription = null;
    onSyncSuccess = null;
  }
}
