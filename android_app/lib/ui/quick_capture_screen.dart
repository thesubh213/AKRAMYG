// quick_capture_screen.dart for AKRAMYG Task Capture UI

import 'package:flutter/material.dart';
import '../core/database.dart';
import '../core/event_bus.dart';

class QuickCaptureScreen extends StatefulWidget {
  const QuickCaptureScreen({super.key});

  @override
  State<QuickCaptureScreen> createState() => _QuickCaptureScreenState();
}

class _QuickCaptureScreenState extends State<QuickCaptureScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final EventBus _eventBus = EventBus();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 17, minute: 0);

  Future<void> _selectDate(BuildContext context) async {
    final primaryColor = Theme.of(context).primaryColor;
    final cardColor = Theme.of(context).cardColor;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: primaryColor,
              onPrimary: Colors.white,
              surface: cardColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final primaryColor = Theme.of(context).primaryColor;
    final cardColor = Theme.of(context).cardColor;

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: primaryColor,
              onPrimary: Colors.white,
              surface: cardColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _saveTask() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task title.')),
      );
      return;
    }

    final deadline = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    final taskVal = {
      'id': taskId,
      'project_id': null,
      'title': title,
      'description': _descController.text.trim(),
      'deadline': deadline.toIso8601String(),
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'estimated_duration': 60, // Default fallback, updated asynchronously by AI in background
      'execution_confidence': 1.0
    };

    // 1. Persist immediately to SQLite to keep UI responsive
    await _db.insert('tasks', taskVal);

    // 2. Publish event to EventBus - triggers background DecisionEngine AI planning asynchronously
    _eventBus.publish(TaskCreatedEvent(taskVal));

    if (!mounted) return;
    Navigator.pop(context);
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
        title: Text('Quick Capture', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: textColor)),
        backgroundColor: cardColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Task Title Input
            Text(
              'WHAT NEEDS TO BE DONE?',
              style: TextStyle(letterSpacing: 1.5, fontSize: 11, fontWeight: FontWeight.bold, color: textMuted),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              autofocus: true,
              style: TextStyle(fontSize: 18, color: textColor),
              decoration: InputDecoration(
                hintText: 'e.g. Write biology research paper draft',
                hintStyle: TextStyle(color: textMuted),
                filled: true,
                fillColor: cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: primaryColor),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Description Input
            Text(
              'NOTES & CONTEXT (OPTIONAL)',
              style: TextStyle(letterSpacing: 1.5, fontSize: 11, fontWeight: FontWeight.bold, color: textMuted),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descController,
              maxLines: 4,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                hintText: 'e.g. Include references from Google Scholar and bibliography.',
                hintStyle: TextStyle(color: textMuted),
                filled: true,
                fillColor: cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: primaryColor),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Deadline Selectors
            Text(
              'DEADLINE',
              style: TextStyle(letterSpacing: 1.5, fontSize: 11, fontWeight: FontWeight.bold, color: textMuted),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.calendar_month_rounded, color: primaryColor),
                    label: Text('${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}', style: TextStyle(color: textColor)),
                    onPressed: () => _selectDate(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: dividerColor),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.access_time_rounded, color: primaryColor),
                    label: Text(_selectedTime.format(context), style: TextStyle(color: textColor)),
                    onPressed: () => _selectTime(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: dividerColor),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Action Button
            ElevatedButton(
              onPressed: _saveTask,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Capture Task', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }
}
