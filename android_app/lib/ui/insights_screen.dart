// insights_screen.dart for AKRAMYG Analytics UI

import 'package:flutter/material.dart';
import '../core/database.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<Map<String, dynamic>> _insights = [];
  int _completedCount = 0;
  int _totalFocusMins = 0;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    // 1. Fetch completed tasks count
    final tasksResult = await _db.rawQuery(
      "SELECT COUNT(*) as count FROM tasks WHERE status = 'completed' AND is_deleted = 0"
    );
    final completedCount = tasksResult.isNotEmpty ? tasksResult.first['count'] as int : 0;

    // 2. Fetch focus sessions metrics
    final sessionsResult = await _db.rawQuery(
      "SELECT COUNT(*) as count, SUM(actual_duration) as sum_duration FROM tasks WHERE actual_duration > 0"
    );
    final totalFocusMins = sessionsResult.isNotEmpty && sessionsResult.first['sum_duration'] != null
        ? sessionsResult.first['sum_duration'] as int
        : 0;

    // 3. Fetch active insights list
    final insightsList = await _db.rawQuery(
      "SELECT * FROM insights WHERE is_dismissed = 0 ORDER BY created_at DESC"
    );

    setState(() {
      _completedCount = completedCount;
      _totalFocusMins = totalFocusMins;
      _insights = insightsList;
    });
  }

  Future<void> _dismissInsight(String id) async {
    await _db.execute("UPDATE insights SET is_dismissed = 1 WHERE id = ?", [id]);
    _loadAnalytics();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final cardColor = Theme.of(context).cardColor;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final textMuted = Theme.of(context).textTheme.bodySmall?.color ?? const Color(0xFF8A7B76);
    final dividerColor = Theme.of(context).dividerColor;

    return Scaffold(
      appBar: AppBar(
        title: Text('Behavior Insights', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: textColor)),
        backgroundColor: cardColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Analytics Dashboard Summary
            Text(
              'PERFORMANCE SUMMARY',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Card(
                    color: cardColor,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Text('$_completedCount', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF27AE60))),
                          const SizedBox(height: 4),
                          Text('Tasks Finished', style: TextStyle(fontSize: 12, color: textMuted)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Card(
                    color: cardColor,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Text('$_totalFocusMins', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: primaryColor)),
                          const SizedBox(height: 4),
                          Text('Focus Minutes', style: TextStyle(fontSize: 12, color: textMuted)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Dynamic Insights list
            Text(
              'DYNAMIC INSIGHTS',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            if (_insights.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    'No behavioral insights compiled yet.\nInsights will appear here as you log focus sessions.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textMuted),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _insights.length,
                itemBuilder: (context, index) {
                  final insight = _insights[index];

                  return Card(
                    color: cardColor,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: dividerColor),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Chip(
                                label: Text(
                                  (insight['insight_type'] as String).toUpperCase(),
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                backgroundColor: primaryColor.withOpacity(0.6),
                                padding: EdgeInsets.zero,
                              ),
                              IconButton(
                                icon: Icon(Icons.close_rounded, size: 16, color: textMuted),
                                onPressed: () => _dismissInsight(insight['id']),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            insight['content'],
                            style: TextStyle(fontSize: 13, height: 1.4, color: textColor),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Confidence: ${(insight['confidence'] * 100).toStringAsFixed(0)}% • Inferred: ${insight['created_at'].toString().substring(0, 10)}',
                            style: TextStyle(fontSize: 11, color: textMuted),
                          ),
                        ],
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
}
