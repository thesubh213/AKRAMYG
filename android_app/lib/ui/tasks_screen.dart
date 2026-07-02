// tasks_screen.dart for AKRAMYG Task Management UI

import 'package:flutter/material.dart';
import '../core/database.dart';
import '../core/ai_client.dart';
import '../core/decision_engine.dart';
import '../core/event_bus.dart';

class TasksScreen extends StatefulWidget {
  final DecisionEngine decisionEngine;
  final GeminiAiClient aiClient;
  const TasksScreen({super.key, required this.decisionEngine, required this.aiClient});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final EventBus _eventBus = EventBus();

  List<Map<String, dynamic>> _tasks = [];
  String _searchQuery = '';
  String _filterStatus = 'pending'; // 'pending' | 'completed' | 'all'

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _eventBus.on<TaskCreatedEvent>().listen((_) => _loadTasks());
    _eventBus.on<TaskUpdatedEvent>().listen((_) => _loadTasks());
  }

  Future<void> _loadTasks() async {
    String query = "SELECT * FROM tasks WHERE is_deleted = 0";
    List<dynamic> args = [];

    if (_filterStatus == 'pending') {
      query += " AND status = 'pending'";
    } else if (_filterStatus == 'completed') {
      query += " AND status = 'completed'";
    }

    if (_searchQuery.isNotEmpty) {
      query += " AND (title LIKE ? OR description LIKE ?)";
      args.addAll(['%$_searchQuery%', '%$_searchQuery%']);
    }

    query += " ORDER BY deadline ASC";

    final results = await _db.rawQuery(query, args);
    setState(() {
      _tasks = results;
    });
  }

  void _showTaskDetailSheet(Map<String, dynamic> task) async {
    final taskId = task['id'] as String;
    
    // 1. Fetch subtasks
    final subtasks = await _db.rawQuery(
      "SELECT * FROM subtasks WHERE task_id = ? AND is_deleted = 0 ORDER BY order_index ASC",
      [taskId]
    );

    // 2. Fetch linked files
    final files = await _db.rawQuery(
      "SELECT * FROM file_references WHERE task_id = ? AND is_deleted = 0",
      [taskId]
    );

    // 3. Fetch task explanation/insight
    final insights = await _db.rawQuery(
      "SELECT content FROM insights WHERE supporting_evidence = ? ORDER BY created_at DESC LIMIT 1",
      [taskId]
    );
    final String explanationText = insights.isNotEmpty ? insights.first['content'] : 'No custom recommendations prepared.';

    if (!mounted) return;

    final primaryColor = Theme.of(context).primaryColor;
    final cardColor = Theme.of(context).cardColor;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final textMuted = Theme.of(context).textTheme.bodySmall?.color ?? const Color(0xFF8A7B76);
    final dividerColor = Theme.of(context).dividerColor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              maxChildSize: 0.95,
              minChildSize: 0.5,
              expand: false,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              task['title'],
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit', color: textColor),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFC0392B)),
                            onPressed: () async {
                              await _db.delete('tasks', taskId);
                              _eventBus.publish(TaskUpdatedEvent({'id': taskId}));
                              Navigator.pop(context);
                            },
                          )
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Deadline: ${task['deadline'].toString().substring(0, 16)}',
                        style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        task['description'] ?? 'No description provided.',
                        style: TextStyle(color: textColor),
                      ),
                      Divider(color: dividerColor, height: 32),

                      // AI Estimation Insights Box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scaffoldBg,
                          border: Border.all(color: primaryColor.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.psychology, color: primaryColor),
                                const SizedBox(width: 8),
                                Text(
                                  'AKRAMYG AI INSIGHTS',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor, fontSize: 12),
                                )
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text('Estimated Effort: ${task['estimated_duration']} minutes', style: TextStyle(color: textColor)),
                            Text('Execution Confidence: ${(task['execution_confidence'] * 100).toStringAsFixed(0)}%', style: TextStyle(color: textColor)),
                            const SizedBox(height: 8),
                            Text(
                              explanationText,
                              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: textMuted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Subtasks / Execution Steps
                      Text(
                        'EXECUTION STEPS (${subtasks.length})',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      if (subtasks.isEmpty)
                        Text('No subtask steps generated.', style: TextStyle(color: textMuted))
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: subtasks.length,
                          itemBuilder: (context, index) {
                            final sub = subtasks[index];
                            final isCompleted = sub['status'] == 'completed';

                            return CheckboxListTile(
                              title: Text(
                                sub['title'],
                                style: TextStyle(
                                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                                  color: isCompleted ? textMuted : textColor,
                                ),
                              ),
                              value: isCompleted,
                              activeColor: primaryColor,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (bool? val) async {
                                final newStatus = (val ?? false) ? 'completed' : 'pending';
                                await _db.execute(
                                  "UPDATE subtasks SET status = ?, updated_at = ? WHERE id = ?",
                                  [newStatus, DateTime.now().toIso8601String(), sub['id']]
                                );

                                // Reload sheet state
                                final updatedSubs = await _db.rawQuery(
                                  "SELECT * FROM subtasks WHERE task_id = ? AND is_deleted = 0 ORDER BY order_index ASC",
                                  [taskId]
                                );
                                setSheetState(() {
                                  subtasks.clear();
                                  subtasks.addAll(updatedSubs);
                                });
                                _eventBus.publish(TaskUpdatedEvent({'id': taskId}));
                              },
                            );
                          },
                        ),
                      
                      const SizedBox(height: 24),
                      // Linked File References
                      Text(
                        'ATTACHED REFERENCES (${files.length})',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (files.isEmpty)
                        Text('No reference links attached.', style: TextStyle(color: textMuted))
                      else
                        ...files.map((file) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(Icons.link_rounded, size: 16, color: textMuted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  file['filename'],
                                  style: TextStyle(fontSize: 13, decoration: TextDecoration.underline, color: textColor),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final textMuted = Theme.of(context).textTheme.bodySmall?.color ?? const Color(0xFF8A7B76);

    return Scaffold(
      appBar: AppBar(
        title: Text('Tasks', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: textColor)),
        backgroundColor: cardColor,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Search Input
                Expanded(
                  child: TextField(
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                      _loadTasks();
                    },
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Search tasks...',
                      hintStyle: TextStyle(color: textMuted),
                      prefixIcon: Icon(Icons.search_rounded, color: textMuted),
                      filled: true,
                      fillColor: scaffoldBg,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Filter Dropdown
                DropdownButton<String>(
                  value: _filterStatus,
                  dropdownColor: cardColor,
                  style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                  underline: const SizedBox(),
                  onChanged: (String? newVal) {
                    if (newVal != null) {
                      setState(() {
                        _filterStatus = newVal;
                      });
                      _loadTasks();
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'completed', child: Text('Completed')),
                    DropdownMenuItem(value: 'all', child: Text('All')),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
      body: _tasks.isEmpty
          ? Center(
              child: Text(
                'No matching tasks found.',
                style: TextStyle(color: textMuted),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                final isCompleted = task['status'] == 'completed';

                return Card(
                  color: cardColor,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      task['title'],
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        decoration: isCompleted ? TextDecoration.lineThrough : null,
                        color: isCompleted ? textMuted : textColor,
                      ),
                    ),
                    subtitle: Text(
                      'Due: ${task['deadline'].toString().substring(0, 16)}',
                      style: TextStyle(fontSize: 12, color: textMuted),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: textMuted),
                    onTap: () => _showTaskDetailSheet(task),
                  ),
                );
              },
            ),
    );
  }
}
