// conversation_screen.dart for AKRAMYG Chat Interface

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/database.dart';
import '../core/ai_client.dart';
import '../core/memory_engine.dart';
import '../core/event_bus.dart';
import '../core/ai_models.dart';

class ConversationScreen extends StatefulWidget {
  final GeminiAiClient aiClient;
  final MemoryEngine memoryEngine;
  const ConversationScreen({super.key, required this.aiClient, required this.memoryEngine});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final EventBus _eventBus = EventBus();

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _errorSubscription;
  
  String _activeConversationId = 'default_chat';
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _ensureDefaultConversation();
    _errorSubscription = _eventBus.on<AiServiceFailureEvent>().listen((event) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text(
              'AI Service Alert: ${event.error}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    });
  }

  Future<void> _ensureDefaultConversation() async {
    final exist = await _db.queryById('conversations', _activeConversationId);
    if (exist == null) {
      await _db.insert('conversations', {
        'id': _activeConversationId,
        'title': 'Default Chat',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String()
      });
    }
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final results = await _db.rawQuery(
      "SELECT * FROM messages WHERE conversation_id = ? ORDER BY created_at ASC",
      [_activeConversationId]
    );
    setState(() {
      _messages = results;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    setState(() {
      _isLoading = true;
    });

    final userMsgId = DateTime.now().millisecondsSinceEpoch.toString() + '_user';
    final userMsg = {
      'id': userMsgId,
      'conversation_id': _activeConversationId,
      'sender': 'user',
      'text': text,
      'created_at': DateTime.now().toIso8601String()
    };

    await _db.insert('messages', userMsg);
    await _loadMessages();

    // 1. Prepare history for AI
    final historyLimit = _messages.length > 6 ? _messages.sublist(_messages.length - 6) : _messages;
    final List<Map<String, dynamic>> history = historyLimit.map((m) => {
      'sender': m['sender'],
      'text': m['text']
    }).toList();

    // 2. Fetch AI interpretation
    final aiResult = await widget.aiClient.interpretConversation(text, history);
    final intent = aiResult.intent;
    final String reply = aiResult.replySuggestion;
    
    final ProposedTask? extractedTask = aiResult.extractedTask;
    final MemoryCandidate? memoryCandidate = aiResult.memoryCandidate;

    // Generate response tags or metadata
    String? entitiesJson;
    if (intent == 'create_task' && extractedTask != null && extractedTask.title != null) {
      entitiesJson = jsonEncode({
        'intent': 'create_task',
        'task': {
          'title': extractedTask.title,
          'deadline': extractedTask.deadline?.toIso8601String() ?? DateTime.now().add(const Duration(days: 1)).toIso8601String(),
          'description': extractedTask.description ?? 'Created from chat conversation.'
        }
      });
    } else if (intent == 'log_preference' && memoryCandidate != null && memoryCandidate.value != null) {
      entitiesJson = jsonEncode({
        'intent': 'log_preference',
        'memory': {
          'category': memoryCandidate.category,
          'value': memoryCandidate.value
        }
      });
    }

    final assistantMsgId = DateTime.now().millisecondsSinceEpoch.toString() + '_assistant';
    final assistantMsg = {
      'id': assistantMsgId,
      'conversation_id': _activeConversationId,
      'sender': 'assistant',
      'text': reply,
      'extracted_entities': entitiesJson,
      'created_at': DateTime.now().toIso8601String()
    };

    await _db.insert('messages', assistantMsg);
    
    setState(() {
      _isLoading = false;
    });
    _loadMessages();
  }

  Future<void> _confirmProposedTask(Map<String, dynamic> taskProposal, String messageId) async {
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    final taskVal = {
      'id': taskId,
      'project_id': null,
      'title': taskProposal['title'],
      'description': taskProposal['description'],
      'deadline': taskProposal['deadline'],
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String()
    };

    await _db.insert('tasks', taskVal);
    _eventBus.publish(TaskCreatedEvent(taskVal));

    // Clear proposal from message so user can't click confirm again
    await _db.execute("UPDATE messages SET extracted_entities = NULL WHERE id = ?", [messageId]);
    _loadMessages();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Task "${taskProposal['title']}" successfully created!')),
    );
  }

  Future<void> _confirmProposedMemory(Map<String, dynamic> memoryProposal, String messageId) async {
    final memId = DateTime.now().millisecondsSinceEpoch.toString();
    final memoryVal = {
      'id': memId,
      'category': memoryProposal['category'],
      'value': memoryProposal['value'],
      'confidence': 1.0,
      'source': 'ai_inference',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'is_deleted': 0 // Persist immediately on confirmation
    };

    await _db.insert('memories', memoryVal);

    // Clear proposal from message
    await _db.execute("UPDATE messages SET extracted_entities = NULL WHERE id = ?", [messageId]);
    _loadMessages();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Learned preference saved to memory!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final cardColor = Theme.of(context).cardColor;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final textMuted = Theme.of(context).textTheme.bodySmall?.color ?? const Color(0xFF8A7B76);
    final dividerColor = Theme.of(context).dividerColor;

    return Scaffold(
      appBar: AppBar(
        title: Text('Conversations', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: textColor)),
        backgroundColor: cardColor,
      ),
      body: Column(
        children: [
          // Message List
          Expanded(
            child: _messages.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, size: 48, color: primaryColor.withOpacity(0.4)),
                        const SizedBox(height: 16),
                        Text(
                          'Welcome to AKRAMYG',
                          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 18, color: textColor),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your AI-powered execution assistant.\nTry one of these to get started:',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textMuted, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        _buildOnboardingTile('📝', 'Create a task', '"Submit assignment by Friday 5pm"', primaryColor, textColor, textMuted),
                        _buildOnboardingTile('🧠', 'Save a habit', '"I work best after 10pm"', primaryColor, textColor, textMuted),
                        _buildOnboardingTile('🚀', 'Get a plan', '"Plan: prepare for math exam"', primaryColor, textColor, textMuted),
                        if (!widget.aiClient.isConfigured) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC0392B).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFC0392B).withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Color(0xFFC0392B), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'API key not set. Go to Settings → paste your Gemini key to enable AI features.',
                                    style: TextStyle(color: textColor, fontSize: 12, height: 1.3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg['sender'] == 'user';
                      final proposal = msg['extracted_entities'] != null
                          ? jsonDecode(msg['extracted_entities'])
                          : null;

                      return Column(
                        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          // Normal Bubble
                          Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isUser ? primaryColor : cardColor,
                                border: isUser ? null : Border.all(color: dividerColor),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(12),
                                  topRight: const Radius.circular(12),
                                  bottomLeft: isUser ? const Radius.circular(12) : Radius.zero,
                                  bottomRight: isUser ? Radius.zero : const Radius.circular(12),
                                ),
                              ),
                              child: Text(
                                msg['text'],
                                style: TextStyle(color: isUser ? Colors.white : textColor),
                              ),
                            ),
                          ),

                          // Proposal Custom Bubble (Interventions/Confirmations)
                          if (proposal != null) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 260,
                                margin: const EdgeInsets.only(top: 4, bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: scaffoldBg,
                                  border: Border.all(color: primaryColor.withOpacity(0.4)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (proposal['intent'] == 'create_task') ...[
                                      Row(
                                        children: [
                                          Icon(Icons.assignment_turned_in_rounded, size: 16, color: primaryColor),
                                          const SizedBox(width: 6),
                                          Text('Proposed Task', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primaryColor)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text('Title: ${proposal['task']['title']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
                                      Text('Due: ${proposal['task']['deadline'].toString().substring(0, 16)}', style: TextStyle(fontSize: 11, color: textMuted)),
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: () => _db.execute("UPDATE messages SET extracted_entities = NULL WHERE id = ?", [msg['id']]).then((_) => _loadMessages()),
                                            child: Text('Cancel', style: TextStyle(color: textMuted, fontSize: 12)),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: () => _confirmProposedTask(proposal['task'], msg['id']),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: primaryColor,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                            ),
                                            child: const Text('Confirm', style: TextStyle(fontSize: 12, color: Colors.white)),
                                          )
                                        ],
                                      )
                                    ] else if (proposal['intent'] == 'log_preference') ...[
                                      Row(
                                        children: [
                                          Icon(Icons.psychology_rounded, size: 16, color: primaryColor),
                                          const SizedBox(width: 6),
                                          Text('New Learning Memory', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primaryColor)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text('Fact: "${proposal['memory']['value']}"', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: textColor)),
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: () => _db.execute("UPDATE messages SET extracted_entities = NULL WHERE id = ?", [msg['id']]).then((_) => _loadMessages()),
                                            child: Text('Cancel', style: TextStyle(color: textMuted, fontSize: 12)),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: () => _confirmProposedMemory(proposal['memory'], msg['id']),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: primaryColor,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                            ),
                                            child: const Text('Confirm', style: TextStyle(fontSize: 12, color: Colors.white)),
                                          )
                                        ],
                                      )
                                    ]
                                  ],
                                ),
                              ),
                            )
                          ]
                        ],
                      );
                    },
                  ),
          ),

          // Loading Indicator
          if (_isLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'AKRAMYG is thinking...',
                    style: TextStyle(color: textMuted, fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),

          // Quick Prompts Suggestions
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _buildPromptChip('📝 "Complete auth endpoints by Friday"', primaryColor, cardColor, textColor),
                  _buildPromptChip('🚀 "Plan: Learn Flutter animations"', primaryColor, cardColor, textColor),
                  _buildPromptChip('🧠 "I prefer sienna and beige themes"', primaryColor, cardColor, textColor),
                  _buildPromptChip('📈 "Evaluate task risks and metrics"', primaryColor, cardColor, textColor),
                ],
              ),
            ),
          ),

          // Message Input Panel
          Container(
            padding: const EdgeInsets.all(12),
            color: cardColor,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onSubmitted: (_) => _sendMessage(),
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: textMuted),
                      filled: true,
                      fillColor: scaffoldBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send_rounded, color: primaryColor),
                  onPressed: _sendMessage,
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPromptChip(String promptText, Color primaryColor, Color cardColor, Color textColor) {
    String cleanText = promptText;
    if (promptText.contains('"')) {
      final parts = promptText.split('"');
      if (parts.length >= 2) {
        cleanText = parts[1];
      }
    }

    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: ActionChip(
        label: Text(promptText, style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.9), fontWeight: FontWeight.w600)),
        backgroundColor: cardColor,
        elevation: 0,
        pressElevation: 1,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: primaryColor.withOpacity(0.25)),
        ),
        onPressed: () {
          setState(() {
            _messageController.text = cleanText;
          });
        },
      ),
    );
  }

  Widget _buildOnboardingTile(String emoji, String title, String example, Color primaryColor, Color textColor, Color mutedColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          final text = example.replaceAll('"', '');
          _messageController.text = text;
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: primaryColor.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: textColor, fontSize: 13)),
                    Text(example, style: TextStyle(color: mutedColor, fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: mutedColor),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _errorSubscription?.cancel();
    super.dispose();
  }
}
