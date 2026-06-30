// home_screen.dart for AKRAMYG UI

import 'dart:async';
import 'package:flutter/material.dart';
import '../core/database.dart';
import '../core/event_bus.dart';
import '../core/decision_engine.dart';
import 'quick_capture_screen.dart';

class HomeScreen extends StatefulWidget {
  final DecisionEngine decisionEngine;
  const HomeScreen({super.key, required this.decisionEngine});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final EventBus _eventBus = EventBus();

  Map<String, dynamic>? _activeTask;
  List<Map<String, dynamic>> _upcomingTasks = [];
  
  bool _isFocusing = false;
  int _secondsElapsed = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadState();
    // Listen for task changes to update view
    _eventBus.on<TaskUpdatedEvent>().listen((_) => _loadState());
    _eventBus.on<TaskCreatedEvent>().listen((_) => _loadState());
  }

  Future<void> _loadState() async {
    // 1. Get active focus session from database
    final activeSessions = await _db.rawQuery(
      "SELECT task_id, start_time FROM execution_sessions WHERE end_time IS NULL LIMIT 1"
    );

    if (activeSessions.isNotEmpty) {
      final taskId = activeSessions.first['task_id'] as String;
      final task = await _db.queryById('tasks', taskId);
      final startTimeStr = activeSessions.first['start_time'] as String;
      final startTime = DateTime.parse(startTimeStr);

      setState(() {
        _activeTask = task;
        _isFocusing = true;
        _secondsElapsed = DateTime.now().difference(startTime).inSeconds;
      });
      _startTimer();
    } else {
      setState(() {
        _activeTask = null;
        _isFocusing = false;
        _secondsElapsed = 0;
      });
      _timer?.cancel();
    }

    // 2. Get upcoming pending tasks
    final upcoming = await _db.rawQuery(
      "SELECT * FROM tasks WHERE status = 'pending' AND is_deleted = 0 ORDER BY deadline ASC LIMIT 3"
    );
    setState(() {
      _upcomingTasks = upcoming;
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
      });
    });
  }

  Future<void> _startFocusSession(String taskId) async {
    final sessionVal = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'task_id': taskId,
      'start_time': DateTime.now().toIso8601String(),
      'interruptions': 0
    };

    await _db.insert('execution_sessions', sessionVal);
    _eventBus.publish(FocusSessionStartedEvent(taskId));
    _loadState();
  }

  Future<void> _stopFocusSession() async {
    if (_activeTask == null) return;
    final taskId = _activeTask!['id'] as String;

    // Fetch active session ID
    final activeSessions = await _db.rawQuery(
      "SELECT id, start_time, interruptions FROM execution_sessions WHERE end_time IS NULL LIMIT 1"
    );

    if (activeSessions.isNotEmpty) {
      final sessionId = activeSessions.first['id'] as String;
      final startTimeStr = activeSessions.first['start_time'] as String;
      final startTime = DateTime.parse(startTimeStr);
      final interruptions = activeSessions.first['interruptions'] as int;

      final durationMins = DateTime.now().difference(startTime).inMinutes;

      await _db.execute(
        "UPDATE execution_sessions SET end_time = ?, productivity_metrics = ? WHERE id = ?",
        [
          DateTime.now().toIso8601String(),
          '{"duration": $durationMins, "interruptions": $interruptions}',
          sessionId
        ]
      );

      // Save actual time spent in task
      final currentActual = _activeTask!['actual_duration'] as int? ?? 0;
      await _db.execute(
        "UPDATE tasks SET actual_duration = ?, updated_at = ? WHERE id = ?",
        [currentActual + durationMins, DateTime.now().toIso8601String(), taskId]
      );

      _eventBus.publish(FocusSessionStoppedEvent(taskId, durationMins, interruptions));
    }

    _loadState();
  }

  Future<void> _completeActiveTask() async {
    if (_activeTask == null) return;
    final taskId = _activeTask!['id'] as String;

    // 1. Stop active session
    await _stopFocusSession();

    // 2. Mark task as completed
    await _db.execute(
      "UPDATE tasks SET status = 'completed', completed_at = ?, updated_at = ? WHERE id = ?",
      [DateTime.now().toIso8601String(), DateTime.now().toIso8601String(), taskId]
    );

    _eventBus.publish(TaskUpdatedEvent({'id': taskId}));
    _loadState();
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final hStr = hours > 0 ? '${hours.toString().padLeft(2, '0')}:' : '';
    return '$hStr${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AKRAMYG', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: Color(0xFF2E2724))),
        backgroundColor: Theme.of(context).cardColor,
        actions: [
          IconButton(
            icon: Icon(Icons.add_circle_outline_rounded, color: Theme.of(context).primaryColor),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const QuickCaptureScreen()),
              ).then((_) => _loadState());
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current State Header
            Text(
              _isFocusing ? 'CURRENT WORK SESSION' : 'RECOMMENDED ACTION',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            // Active focus card
            Card(
              color: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: _isFocusing ? Theme.of(context).primaryColor : Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isFocusing && _activeTask != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _activeTask!['title'],
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Outfit', color: Theme.of(context).colorScheme.onSurface),
                            ),
                          ),
                          Chip(
                            label: const Text('FOCUSING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                            backgroundColor: Theme.of(context).primaryColor,
                          )
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _activeTask!['description'] ?? 'No task notes.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).textTheme.bodySmall?.color),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: Text(
                          _formatDuration(_secondsElapsed),
                          style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor, fontFamily: 'Outfit'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Complete'),
                              onPressed: _completeActiveTask,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF27AE60),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.pause_rounded),
                              label: const Text('Stop focus'),
                              onPressed: _stopFocusSession,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFC0392B),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      )
                    ] else ...[
                      const Text(
                        'No Active Session',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select a task from the list below or create a new one to begin focusing.',
                        style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
                      ),
                      const SizedBox(height: 16),
                      if (_upcomingTasks.isNotEmpty)
                        ElevatedButton(
                          onPressed: () => _startFocusSession(_upcomingTasks.first['id']),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            minimumSize: const Size.fromHeight(45),
                          ),
                          child: Text('Start focus: "${_upcomingTasks.first['title']}"', style: const TextStyle(color: Colors.white)),
                        ),
                    ]
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
            Text(
              'UPCOMING DEADLINES',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            if (_upcomingTasks.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('No upcoming tasks. Create one using the Quick Capture button.', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _upcomingTasks.length,
                itemBuilder: (context, index) {
                  final task = _upcomingTasks[index];
                  final deadline = DateTime.parse(task['deadline']);
                  final daysLeft = deadline.difference(DateTime.now()).inDays;

                  return Card(
                    color: Theme.of(context).cardColor,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(task['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Due in $daysLeft days (${deadline.toString().substring(0, 10)})'),
                      trailing: IconButton(
                        icon: Icon(Icons.play_circle_outline_rounded, color: Theme.of(context).primaryColor),
                        onPressed: _isFocusing ? null : () => _startFocusSession(task['id']),
                      ),
                    ),
                  );
                },
              )
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
