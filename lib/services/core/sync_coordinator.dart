import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shaladarpan/services/core/local_db_service.dart';

class SyncCoordinator {
  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static bool _isSyncing = false;
  static int _generation = 0;
  static final Map<String, Future<bool> Function(Map<String, dynamic>)> _handlers = {};

  // A handler must return true only after its backend operation is confirmed.
  static void registerHandler(String portal, String taskType, Future<bool> Function(Map<String, dynamic>) handler) {
    _handlers['$portal:$taskType'] = handler;
  }

  static void startListening() {
    if (_subscription != null) return;
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) unawaited(triggerSync());
    });
  }

  static Future<void> triggerSync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    final generation = _generation;
    try {
      for (final task in LocalDbService.getPendingTasks()) {
        if (generation != _generation) break;
        final handler = _handlers['${task['portal']}:${task['taskType']}'];
        if (handler == null) continue; // Unimplemented tasks stay in the database.
        final taskId = task['taskId'];
        if (taskId is! String) continue;
        try {
          if (await handler(task) == true) await LocalDbService.removeTask(taskId);
        } catch (_) {
          debugPrint('Pending task retained after sync failure.');
        }
      }
    } catch (_) {
      debugPrint('Pending task database is unavailable; data was not deleted.');
    } finally {
      _isSyncing = false;
    }
  }

  static void dispose() {
    _generation++;
    _subscription?.cancel();
    _subscription = null;
  }
}
