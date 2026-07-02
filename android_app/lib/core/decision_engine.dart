// decision_engine.dart for AKRAMYG Shared Core

import 'dart:async';
import 'event_bus.dart';
import 'database.dart';
import 'ai_client.dart';
import 'ai_models.dart';

class DecisionEngine {
  final EventBus _eventBus = EventBus();
  final DatabaseHelper _db = DatabaseHelper.instance;
  final AiClientInterface _aiClient;

  final List<StreamSubscription> _subscriptions = [];

  int _consecutiveDistractions = 0;
  String? _activeTaskId;

  DecisionEngine(this._aiClient);

  /// Initialize and bind event listeners
  void initialize() {
    // 1. Listen for new tasks to trigger plan generation and duration estimates
    _subscriptions.add(_eventBus.on<TaskCreatedEvent>().listen((event) {
      _handleNewTask(event.task);
    }));

    // 2. Listen to focus session changes
    _subscriptions.add(_eventBus.on<FocusSessionStartedEvent>().listen((event) {
      _activeTaskId = event.taskId;
      _consecutiveDistractions = 0;
      _logDecision(
          'focus_start', 'Focus session started for task ${event.taskId}');
    }));

    _subscriptions.add(_eventBus.on<FocusSessionStoppedEvent>().listen((event) {
      _activeTaskId = null;
      _consecutiveDistractions = 0;
      _logDecision('focus_stop',
          'Focus session ended. Duration: ${event.durationMins}m, Interruptions: ${event.interruptionsCount}');
    }));

    // 3. Handle distractions reported by extension
    _subscriptions.add(_eventBus.on<DistractionDetectedEvent>().listen((event) {
      _handleDistraction(event);
    }));

    // 4. Handle scraper deadlines
    _subscriptions.add(_eventBus.on<DeadlineScrapedEvent>().listen((event) {
      _handleScrapedDeadline(event);
    }));

    // 5. Handle page attachments from extension
    _subscriptions.add(_eventBus.on<PageAttachedEvent>().listen((event) {
      _handlePageAttached(event);
    }));
  }

  Future<void> _handleNewTask(Map<String, dynamic> task) async {
    final taskId = task['id'] as String;
    final title = task['title'] as String;
    final deadline = task['deadline'] as String;
    final description = task['description'] as String?;

    _logDecision('task_creation',
        'Task created: "$title". Initiating duration estimation and plan generation.');

    // 1. Query past execution history for similar tasks to pass to estimator
    final history = await _db.rawQuery(
        "SELECT title, estimated_duration, actual_duration FROM tasks WHERE status = 'completed' LIMIT 5");

    // 2. Fetch AI duration estimate
    final durationEstimate =
        await _aiClient.estimateDuration(title, description ?? '', history);
    final int estimatedMins = durationEstimate.durationMins;
    final double confidence = durationEstimate.confidence;

    // 3. Fetch AI execution plan
    final plan = await _aiClient.generatePlan(title, deadline, description);
    final List<PlanStep> steps = plan.steps;

    // 4. Update task details in DB
    await _db.execute(
        "UPDATE tasks SET estimated_duration = ?, execution_confidence = ?, updated_at = ? WHERE id = ?",
        [estimatedMins, confidence, DateTime.now().toIso8601String(), taskId]);

    // 5. Write plan steps into subtasks DB table
    for (var step in steps) {
      final stepTitle = step.title;
      final int orderIndex = step.orderIndex;
      final stepId = '${taskId}_sub_${orderIndex}';

      await _db.insert('subtasks', {
        'id': stepId,
        'task_id': taskId,
        'title': stepTitle,
        'status': 'pending',
        'order_index': orderIndex,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String()
      });
    }

    _logDecision('task_plan_ready',
        'Generated plan for task "$title" with $estimatedMins mins estimate and ${steps.length} steps.',
        relatedEntityId: taskId);

    // Query updated task to publish to system
    final updatedTask = await _db.queryById('tasks', taskId);
    if (updatedTask != null) {
      _eventBus.publish(TaskUpdatedEvent(updatedTask));
    }
  }

  Future<void> _handleDistraction(DistractionDetectedEvent event) async {
    if (_activeTaskId == null) return;
    _consecutiveDistractions++;

    _logDecision('distraction_detected',
        'Distraction detected: "${event.domain}" (consecutive: $_consecutiveDistractions)',
        relatedEntityId: _activeTaskId);

    // Escalate intervention if distractions continue
    if (_consecutiveDistractions >= 3) {
      final task = await _db.queryById('tasks', _activeTaskId!);
      final title = task != null ? task['title'] : 'your current task';

      // Decide loudness of intervention
      String category = 'standard';
      String message =
          'Are you still working on "$title"? Let\'s get back to it.';

      if (_consecutiveDistractions >= 5) {
        category = 'critical';
        message =
            'Urgent reminder: You have a focus session active for "$title". Please close "${event.domain}".';
      }

      _eventBus.publish(NotificationRequestedEvent(
          taskId: _activeTaskId,
          title: 'Focus Nudge',
          body: message,
          category: category));

      // Log notification in DB to track response effectiveness
      await _db.insert('notifications', {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'task_id': _activeTaskId,
        'type': category,
        'trigger': 'distraction_threshold_reached',
        'timestamp': DateTime.now().toIso8601String(),
        'delivery_status': 'delivered'
      });
    }
  }

  Future<void> _handleScrapedDeadline(DeadlineScrapedEvent event) async {
    _logDecision('deadline_scraped',
        'Detected candidate deadline online: "${event.title}" on ${event.date}');

    if (event.isCaptureProposal) {
      final taskId = DateTime.now().millisecondsSinceEpoch.toString() + '_proposal';
      final taskMap = {
        'id': taskId,
        'project_id': null,
        'title': event.title,
        'description': 'Captured via Chrome Extension Sensor\nSource URL: ${event.sourceUrl}',
        'deadline': event.date,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'estimated_duration': 0,
        'actual_duration': 0,
        'execution_confidence': 1.0,
        'origin_subsystem': 'sensor',
        'sync_state': 'local_only',
        'is_deleted': 0,
      };

      await _db.insert('tasks', taskMap);
      _eventBus.publish(TaskCreatedEvent(taskMap));
    } else {
      // Always ask for confirmation before writing to DB. Propose it as a pending notification or inbox task.
      _eventBus.publish(NotificationRequestedEvent(
          title: 'New Deadline Detected',
          body: 'Would you like to track "${event.title}" due on ${event.date}?',
          category: 'standard'));
    }
  }

  Future<void> _handlePageAttached(PageAttachedEvent event) async {
    final taskId = event.taskId ?? _activeTaskId;
    if (taskId == null) {
      _logDecision('page_attach_failed', 'Attempted to attach page "${event.title}", but no task is active.');
      return;
    }

    _logDecision('page_attached', 'Attaching webpage "${event.title}" to task $taskId');

    final refId = DateTime.now().millisecondsSinceEpoch.toString() + '_link';
    await _db.insert('file_references', {
      'id': refId,
      'task_id': taskId,
      'path': event.url,
      'filename': event.title,
      'extension': 'link',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String()
    });

    _eventBus.publish(TaskUpdatedEvent({'id': taskId}));
  }

  Future<void> recalculateAllTaskRisks() async {
    final activeTasks = await _db.rawQuery(
        "SELECT * FROM tasks WHERE status = 'pending' AND is_deleted = 0");
    for (var task in activeTasks) {
      final taskId = task['id'] as String;
      final deadlineStr = task['deadline'] as String;
      final deadline = DateTime.parse(deadlineStr);
      final durationEst = task['estimated_duration'] as int;

      final remainingTime = deadline.difference(DateTime.now());
      double riskScore = 0.0;

      // Base risk check: remaining time vs estimate
      if (remainingTime.isNegative) {
        riskScore = 1.0;
      } else {
        // Calculate factor of remaining minutes to estimated minutes needed
        final remainingMins = remainingTime.inMinutes;
        if (remainingMins < durationEst) {
          riskScore = 0.9; // High risk
        } else if (remainingMins < (durationEst * 2)) {
          riskScore = 0.5; // Medium risk
        } else {
          riskScore = 0.1; // Low risk
        }
      }

      final riskLevel =
          riskScore > 0.8 ? 'high' : (riskScore > 0.4 ? 'medium' : 'low');

      // AI Risk Validation (if configured)
      if (_aiClient is GeminiAiClient &&
          (_aiClient as GeminiAiClient).isConfigured) {
        final aiResult = await _aiClient.evaluateRisk(task, []);
        final aiRiskScore = aiResult.riskScore;
        riskScore =
            (riskScore + aiRiskScore) / 2; // Average deterministic and AI score
      }

      await _db.execute(
          "UPDATE tasks SET execution_confidence = ?, updated_at = ? WHERE id = ?",
          [1.0 - riskScore, DateTime.now().toIso8601String(), taskId]);

      if (riskLevel == 'high') {
        _eventBus.publish(NotificationRequestedEvent(
            taskId: taskId,
            title: 'High Risk Task',
            body: 'Task "${task['title']}" is at risk of missing its deadline!',
            category: 'standard'));
      }
    }
  }

  // Logs decisions into DB for future explainability queries
  Future<void> _logDecision(String type, String message,
      {String? relatedEntityId}) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString() + '_' + type;
    final explainText = await _aiClient.generateExplanation(message);

    await _db.insert('insights', {
      'id': id,
      'insight_type': type,
      'confidence': 1.0,
      'supporting_evidence': relatedEntityId,
      'content': 'Action: $message. Reason: $explainText',
      'created_at': DateTime.now().toIso8601String(),
      'is_dismissed': 0
    });

    print('Decision Engine Log: $message. Explain: $explainText');
  }

  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}
