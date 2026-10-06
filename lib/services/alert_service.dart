import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/models/models.dart';
import 'hive_service.dart';

class AlertService {
  static const String prefBoxName = 'app_preferences';
  static const String readyKey = 'alerts_ready_ids';
  static const String dismissedKey = 'alerts_dismissed_ids';
  static const String tasksKey = 'alerts_custom_tasks';

  /// Inventory low stock threshold (defaults to 5, or user preference)
  static int get lowStockThreshold {
    try {
      final box = Hive.box(prefBoxName);
      final val = box.get('lowStockThreshold', defaultValue: 5);
      if (val is num) return val.toInt();
      return 5;
    } catch (_) {
      return 5;
    }
  }

  /// Whether low stock alerts are enabled
  static bool get lowStockAlertsEnabled {
    try {
      final box = Hive.box(prefBoxName);
      return box.get('lowStockAlerts', defaultValue: true) as bool;
    } catch (_) {
      return true;
    }
  }

  static final ValueNotifier<int> activeAlertsCountNotifier =
      ValueNotifier<int>(0);

  static Set<String> get readyAlertIds {
    try {
      final box = Hive.box(prefBoxName);
      final list = box.get(readyKey, defaultValue: <dynamic>[]) as List;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  static Set<String> get dismissedAlertIds {
    try {
      final box = Hive.box(prefBoxName);
      final list = box.get(dismissedKey, defaultValue: <dynamic>[]) as List;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  static List<Map<String, dynamic>> get customTasks {
    try {
      final box = Hive.box(prefBoxName);
      final list = box.get(tasksKey, defaultValue: <dynamic>[]) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveReadyAlertIds(Set<String> ids) async {
    try {
      final box = Hive.box(prefBoxName);
      await box.put(readyKey, ids.toList());
    } catch (_) {}
    recalculateCount();
  }

  static Future<void> saveDismissedAlertIds(Set<String> ids) async {
    try {
      final box = Hive.box(prefBoxName);
      await box.put(dismissedKey, ids.toList());
    } catch (_) {}
    recalculateCount();
  }

  static Future<void> saveCustomTasks(List<Map<String, dynamic>> tasks) async {
    try {
      final box = Hive.box(prefBoxName);
      await box.put(tasksKey, tasks);
    } catch (_) {}
    recalculateCount();
  }

  static void init() {
    recalculateCount();
    try {
      final productBox = Hive.box<Product>(HiveService.productBoxName);
      productBox.listenable().addListener(() {
        recalculateCount();
      });
    } catch (_) {}
  }

  static void recalculateCount() {
    try {
      final dismissed = dismissedAlertIds;
      final ready = readyAlertIds;

      int lowStockCount = 0;
      if (lowStockAlertsEnabled) {
        final productBox = Hive.box<Product>(HiveService.productBoxName);
        final threshold = lowStockThreshold;
        // Count only critical low stock items (<= threshold, default 5)
        // that are not dismissed and not marked as ready/resolved
        lowStockCount = productBox.values.where((p) {
          final isLow = p.stockQuantity <= threshold;
          return isLow &&
              !dismissed.contains(p.id) &&
              !ready.contains(p.id);
        }).length;
      }

      // Count uncompleted and undismissed custom store tasks
      final tasks = customTasks;
      final pendingTasksCount = tasks.where((t) {
        final id = t['id'] as String? ?? '';
        final isReady = t['isReady'] == true || ready.contains(id);
        final isDismissed = dismissed.contains(id);
        return !isReady && !isDismissed;
      }).length;

      activeAlertsCountNotifier.value = lowStockCount + pendingTasksCount;
    } catch (_) {
      activeAlertsCountNotifier.value = 0;
    }
  }
}
