// behavioral_learning.dart for AKRAMYG Shared Core

import 'dart:convert';
import 'database.dart';

class BehavioralLearning {
  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Recalculates the duration scaling factor based on actual vs estimated times
  Future<void> trainDurationModel() async {
    try {
      final completedTasks = await _db.rawQuery(
        "SELECT estimated_duration, actual_duration FROM tasks WHERE status = 'completed' AND actual_duration > 0 AND is_deleted = 0"
      );

      if (completedTasks.isEmpty) return;

      double totalRatio = 0.0;
      for (var task in completedTasks) {
        final est = task['estimated_duration'] as int;
        final act = task['actual_duration'] as int;
        if (est > 0) {
          totalRatio += act / est;
        }
      }

      final double biasMultiplier = totalRatio / completedTasks.length;

      // Load or insert model
      final existing = await _db.queryById('behavior_models', 'duration_model');
      final version = existing != null ? (existing['version'] as int) + 1 : 1;

      await _db.insert('behavior_models', {
        'id': 'duration_model',
        'model_type': 'duration',
        'version': version,
        'weights': jsonEncode({'bias_multiplier': biasMultiplier}),
        'updated_at': DateTime.now().toIso8601String()
      });

      print('Behavioral Learning: Retrained Duration Model (v$version). New bias multiplier: $biasMultiplier');
    } catch (e) {
      print('Behavioral Learning Error: Failed training duration model: $e');
    }
  }

  /// Calculates which category of notification intervention resolves distraction quickest
  Future<void> trainInterventionModel() async {
    try {
      final notificationsLog = await _db.rawQuery(
        "SELECT type, delivery_status, user_response FROM notifications WHERE user_response IS NOT NULL"
      );

      if (notificationsLog.isEmpty) return;

      // Evaluate standard vs critical effectiveness
      int standardClickCount = 0;
      int criticalClickCount = 0;

      for (var note in notificationsLog) {
        final type = note['type'] as String;
        final status = note['delivery_status'] as String;
        if (status == 'clicked') {
          if (type == 'standard') standardClickCount++;
          if (type == 'critical') criticalClickCount++;
        }
      }

      final weights = {
        'standard_success_rate': standardClickCount / notificationsLog.length,
        'critical_success_rate': criticalClickCount / notificationsLog.length,
        'best_effective_type': criticalClickCount > standardClickCount ? 'critical' : 'standard'
      };

      final existing = await _db.queryById('behavior_models', 'intervention_model');
      final version = existing != null ? (existing['version'] as int) + 1 : 1;

      await _db.insert('behavior_models', {
        'id': 'intervention_model',
        'model_type': 'intervention',
        'version': version,
        'weights': jsonEncode(weights),
        'updated_at': DateTime.now().toIso8601String()
      });

      print('Behavioral Learning: Retrained Intervention Model (v$version). Best effective type: ${weights['best_effective_type']}');
    } catch (e) {
      print('Behavioral Learning Error: Failed training intervention model: $e');
    }
  }
}
