import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

class LocalDbService {
  // Hive box ka naam jisme pending offline tasks save honge
  static const String _boxName = 'offline_tasks';

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

    // Unique timestamp-based task ID
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();

    final taskPayload = {
      'taskId': taskId,
      'portal': portal,
      'taskType': taskType,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await box.put(taskId, jsonEncode(taskPayload));
    print(" Offline Saved: $taskType for $portal (ID: $taskId)");
  }

  // 3. Internet aane par saare bache hue tasks nikalna
  static List<Map<String, dynamic>> getPendingTasks() {
    final box = Hive.box(_boxName);
    List<Map<String, dynamic>> tasks = [];

    for (var key in box.keys) {
      final dynamic raw = box.get(key);
      if (raw != null) {
        tasks.add(Map<String, dynamic>.from(jsonDecode(raw as String)));
      }
    }
    return tasks;
  }

  // 4. Task sync ho jane ke baad usko diary se delete karna
  static Future<void> removeTask(String taskId) async {
    final box = Hive.box(_boxName);
    await box.delete(taskId);
    print(" Synced & Removed from offline box: $taskId");
  }

  // 5. Box clear karna
  static Future<void> clearAll() async {
    final box = Hive.box(_boxName);
    await box.clear();
  }
}