import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hive_flutter/hive_flutter.dart';

class LocalDbService {
  // Hive box ka naam jisme pending offline tasks save honge
  static const String _boxName = 'offline_tasks';
  static int _sequence = 0;

  // 1. App start hote hi Local Database initialize karna
  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_boxName);
  }

  // 2. Offline Task Diary me save karna
  static Future<void> savePendingTask({
    required String portal, // Shaladarpan, Staff, ya RajSIMS
    required String taskType, // attendance, mdm_entry, etc.
    required Map<String, dynamic> data, // Actual data
  }) async {
    final box = Hive.box(_boxName);

    // A millisecond timestamp alone can repeat when two tasks are queued in the
    // same millisecond, silently overwriting the first one. Microseconds plus a
    // process-wide counter keeps every task ID unique.
    final taskId = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

    final taskPayload = {
      'taskId': taskId,
      'portal': portal,
      'taskType': taskType,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await box.put(taskId, jsonEncode(taskPayload));
    debugPrint('Offline task saved: $taskType for $portal (ID: $taskId)');
  }

  // 3. Internet aane par saare bache hue tasks nikalna
  static List<Map<String, dynamic>> getPendingTasks() {
    final tasks = <Map<String, dynamic>>[];
    // main() swallows an init failure; do not crash every later sync with
    // "box not found" when the database never opened.
    if (!Hive.isBoxOpen(_boxName)) return tasks;
    final box = Hive.box(_boxName);

    for (final key in box.keys) {
      // One unreadable entry must not block every other pending task. The bad
      // entry stays in the box (nothing is deleted) and is simply skipped.
      try {
        final raw = box.get(key);
        if (raw is! String) continue;
        final decoded = jsonDecode(raw);
        if (decoded is Map) tasks.add(Map<String, dynamic>.from(decoded));
      } catch (_) {
        debugPrint('Skipping unreadable offline task: $key');
      }
    }
    return tasks;
  }

  // 4. Task sync ho jane ke baad usko diary se delete karna
  static Future<void> removeTask(String taskId) async {
    final box = Hive.box(_boxName);
    await box.delete(taskId);
    debugPrint('Synced & removed from offline box: $taskId');
  }

  // 5. Box clear karna
  static Future<void> clearAll() async {
    final box = Hive.box(_boxName);
    await box.clear();
  }
}
