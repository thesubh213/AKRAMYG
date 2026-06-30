// ai_client.dart — AKRAMYG AI Engine wrapping Google Gemini
// Dual-model architecture: _jsonModel for structured output, _textModel for free-text

import 'dart:async';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'database.dart';
import 'ai_models.dart';
import 'event_bus.dart';

abstract class AiClientInterface {
  Future<TaskParseResult> parseTask(String rawTaskText);
  Future<DurationEstimateResult> estimateDuration(String taskTitle, String description, List<Map<String, dynamic>> executionHistory);
  Future<PlanResult> generatePlan(String taskTitle, String deadline, String? description);
  Future<RiskEvaluationResult> evaluateRisk(Map<String, dynamic> task, List<Map<String, dynamic>> contextHistory);
  Future<EntityExtractionResult> extractEntities(String text);
  Future<DeadlineExtractionResult> extractDeadline(String pageText);
  Future<ConversationInterpretationResult> interpretConversation(String currentMessage, List<Map<String, dynamic>> messageHistory);
  Future<MemoryExtractionResult> extractMemories(String content);
  Future<String> generateExplanation(String decisionContext);
  Future<String> summarizePage(String title, String url, String pageText);
}

class GeminiAiClient implements AiClientInterface {
  final EventBus _eventBus = EventBus();
  String? _apiKey;
  String _modelName = 'gemini-2.5-flash';

  /// JSON-constrained model for structured outputs (parseTask, estimateDuration, etc.)
  GenerativeModel? _jsonModel;

  /// Unconstrained model for free-text outputs (summarizePage, generateExplanation)
  GenerativeModel? _textModel;

  // Legacy model names that must be auto-healed
  static const _legacyModels = {
    'gemini-1.5-flash',
    'gemini-1.5-flash-latest',
    'gemini-1.5-pro',
    'gemini-2.0-flash',
    'gemini-2.0-flash-lite',
  };

  static const _defaultModel = 'gemini-2.5-flash';

  GeminiAiClient() {
    _loadApiKey();
  }

  /// Load API Key and model name from local settings database
  Future<void> _loadApiKey() async {
    try {
      final db = DatabaseHelper.instance;
      final keyResult = await db.queryById('system_entities', 'gemini_api_key');
      final modelResult = await db.queryById('system_entities', 'gemini_model');

      String modelName = modelResult != null && modelResult['value'] != null
          ? modelResult['value'] as String
          : _defaultModel;

      // Auto-heal legacy/retired model names
      if (modelName.isEmpty || _legacyModels.contains(modelName)) {
        modelName = _defaultModel;
        await db.insert('system_entities', {
          'id': 'gemini_model',
          'value': _defaultModel,
          'updated_at': DateTime.now().toIso8601String()
        });
      }

      _modelName = modelName;

      if (keyResult != null) {
        _apiKey = keyResult['value'];
        if (_apiKey != null && _apiKey!.isNotEmpty) {
          _buildModels(_apiKey!, _modelName);
        }
      }
    } catch (e) {
      print('Warning: Failed to load API configuration from database: $e');
    }
  }

  /// Constructs both model instances from key + model name
  void _buildModels(String apiKey, String modelName) {
    _jsonModel = GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.2, // Deterministic for structured outputs
      ),
    );

    _textModel = GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7, // Creative for summaries and explanations
      ),
    );
  }

  /// Called from Settings when user saves new API key / model name
  Future<void> updateConfig(String newKey, String modelName) async {
    _apiKey = newKey;
    _modelName = modelName;
    _buildModels(newKey, modelName);
  }

  bool get isConfigured => _jsonModel != null;

  /// Validates the current model + key by sending a minimal probe request.
  /// Returns a human-readable status string.
  Future<String> validateModel() async {
    if (_jsonModel == null) {
      await _loadApiKey();
      if (_jsonModel == null) {
        return 'Not configured. Enter your API key in Settings.';
      }
    }

    try {
      final response = await _jsonModel!.generateContent([
        Content.text('Respond with exactly: {"status":"ok"}')
      ]);
      if (response.text != null && response.text!.contains('ok')) {
        return 'Connected successfully to $_modelName';
      }
      return 'Model responded but output was unexpected. Try a different model name.';
    } catch (e) {
      return _parseErrorMessage(e);
    }
  }

  /// Parses exceptions into actionable user-facing error messages
  String _parseErrorMessage(Object e) {
    final msg = e.toString().toLowerCase();

    if (msg.contains('404') || msg.contains('not found')) {
      return 'Model "$_modelName" not found. Go to Settings → change Model to "gemini-2.5-flash".';
    }
    if (msg.contains('429') || msg.contains('resource exhausted') || msg.contains('rate limit')) {
      return 'Rate limit reached (free tier: 15 requests/minute). Wait a moment and try again.';
    }
    if (msg.contains('403') || msg.contains('permission denied') || msg.contains('api key not valid')) {
      return 'API key is invalid or expired. Go to Settings → enter a valid key from Google AI Studio.';
    }
    if (msg.contains('400') || msg.contains('invalid argument')) {
      return 'Invalid request. Model "$_modelName" may not support this feature. Try "gemini-2.5-flash".';
    }
    if (msg.contains('socketexception') || msg.contains('network') || msg.contains('connection')) {
      return 'No internet connection. Using offline fallbacks.';
    }

    return 'AI service error: ${e.toString().length > 120 ? e.toString().substring(0, 120) : e}';
  }

  // ──────────────────────────────────────────────
  // JSON-structured generation with retry + backoff
  // ──────────────────────────────────────────────

  Future<Map<String, dynamic>> _generateJson(String prompt, Map<String, dynamic> fallback) async {
    if (_jsonModel == null) {
      await _loadApiKey();
      if (_jsonModel == null) {
        _eventBus.publish(AiServiceFailureEvent('API key not configured. Go to Settings to set up your Gemini API key.'));
        return fallback;
      }
    }

    const maxRetries = 2;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final content = [Content.text(prompt)];
        final response = await _jsonModel!.generateContent(content);

        if (response.text == null || response.text!.isEmpty) {
          _eventBus.publish(AiServiceFailureEvent('Received empty response from Gemini. Check your model configuration.'));
          return fallback;
        }

        String text = response.text!;

        // Strip markdown code fences if present
        if (text.contains('```')) {
          final matches = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').allMatches(text);
          if (matches.isNotEmpty) {
            text = matches.first.group(1) ?? text;
          }
        }
        text = text.trim();

        final parsed = jsonDecode(text);
        if (parsed is Map<String, dynamic>) {
          return parsed;
        }
        _eventBus.publish(AiServiceFailureEvent('Received malformed response. Retrying...'));
        return fallback;

      } catch (e) {
        final errorMsg = _parseErrorMessage(e);

        // Retry on rate limits (429) or server errors (503)
        final msg = e.toString().toLowerCase();
        final isRetryable = msg.contains('429') || msg.contains('503') || msg.contains('resource exhausted');

        if (isRetryable && attempt < maxRetries) {
          final delayMs = 1000 * (attempt + 1); // 1s, 2s backoff
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }

        _eventBus.publish(AiServiceFailureEvent(errorMsg));
        return fallback;
      }
    }

    return fallback;
  }

  // ──────────────────────────────────────────
  // Free-text generation (no JSON constraint)
  // ──────────────────────────────────────────

  Future<String> _generateText(String prompt, String fallback) async {
    if (_textModel == null) {
      await _loadApiKey();
      if (_textModel == null) return fallback;
    }

    try {
      final response = await _textModel!.generateContent([Content.text(prompt)]);
      return response.text ?? fallback;
    } catch (e) {
      _eventBus.publish(AiServiceFailureEvent(_parseErrorMessage(e)));
      return fallback;
    }
  }

  // ════════════════════════════════════════════
  //  Structured AI Methods (use _jsonModel)
  // ════════════════════════════════════════════

  @override
  Future<TaskParseResult> parseTask(String rawTaskText) async {
    final prompt = '''
    Analyze the following raw input and extract a structured task.
    Input: "$rawTaskText"
    
    Respond STRICTLY in JSON format with these exact keys:
    {
      "title": "Short descriptive title of the task",
      "description": "Elaborated details or notes",
      "deadline": "ISO8601 string of the deadline if mentioned, or null",
      "estimated_duration_mins": integer value in minutes (default to 60 if unsure),
      "tags": ["array", "of", "inferred", "tags"],
      "confidence": float between 0.0 and 1.0 representing understanding confidence
    }
    ''';

    final fallback = {
      'title': rawTaskText.length > 50 ? '${rawTaskText.substring(0, 50)}...' : rawTaskText,
      'description': rawTaskText,
      'deadline': null,
      'estimated_duration_mins': 60,
      'tags': ['general'],
      'confidence': 0.5
    };

    final json = await _generateJson(prompt, fallback);
    return TaskParseResult.fromJson(json);
  }

  @override
  Future<DurationEstimateResult> estimateDuration(
      String taskTitle, String description, List<Map<String, dynamic>> executionHistory) async {
    final prompt = '''
    Estimate the exact completion duration in minutes for the task: "$taskTitle".
    Description: "$description"
    
    Reference data of past completed tasks: ${jsonEncode(executionHistory)}
    
    Respond STRICTLY in JSON format with these exact keys:
    {
      "duration_mins": integer estimate,
      "reason": "short explanation of the estimate based on historical performance",
      "confidence": float between 0.0 and 1.0
    }
    ''';

    final fallback = {
      'duration_mins': 60,
      'reason': 'Default duration fallback used due to unavailable AI connection.',
      'confidence': 0.5
    };

    final json = await _generateJson(prompt, fallback);
    return DurationEstimateResult.fromJson(json);
  }

  @override
  Future<PlanResult> generatePlan(String taskTitle, String deadline, String? description) async {
    final prompt = '''
    Generate an execution plan with subtasks for a task titled "$taskTitle" with a deadline of $deadline.
    Description: "${description ?? ''}"
    
    Respond STRICTLY in JSON format with these exact keys:
    {
      "steps": [
        {"title": "Subtask title 1", "order": 1},
        {"title": "Subtask title 2", "order": 2}
      ],
      "suggested_prep_work": "preparatory advice text",
      "potential_blockers": ["blocker1", "blocker2"],
      "confidence": float between 0.0 and 1.0
    }
    ''';

    final fallback = {
      'steps': [
        {'title': 'Initial research & preparation', 'order': 1},
        {'title': 'Draft implementation / core work', 'order': 2},
        {'title': 'Review and finalize task requirements', 'order': 3}
      ],
      'suggested_prep_work': 'Review guidelines and gather necessary resources.',
      'potential_blockers': ['Underestimation of complexity'],
      'confidence': 0.5
    };

    final json = await _generateJson(prompt, fallback);
    return PlanResult.fromJson(json);
  }

  @override
  Future<RiskEvaluationResult> evaluateRisk(Map<String, dynamic> task, List<Map<String, dynamic>> contextHistory) async {
    final prompt = '''
    Evaluate the risk of missing the deadline for the task:
    Task: ${jsonEncode(task)}
    Recent user context history: ${jsonEncode(contextHistory)}
    
    Respond STRICTLY in JSON format with these exact keys:
    {
      "risk_level": "low" | "medium" | "high",
      "risk_score": float between 0.0 (no risk) and 1.0 (deadline will definitely be missed),
      "explanation": "clear textual reasoning",
      "recommended_intervention_level": "none" | "standard" | "critical"
    }
    ''';

    final fallback = {
      'risk_level': 'low',
      'risk_score': 0.1,
      'explanation': 'Automatic fallback calculation: task is on schedule.',
      'recommended_intervention_level': 'none'
    };

    final json = await _generateJson(prompt, fallback);
    return RiskEvaluationResult.fromJson(json);
  }

  @override
  Future<EntityExtractionResult> extractEntities(String text) async {
    final prompt = '''
    Extract actionable entities from the following text:
    "$text"
    
    Identify people, deadlines/dates, links/repositories, files, and project references.
    Respond STRICTLY in JSON format with these exact keys:
    {
      "entities": [
        {"category": "person"|"date"|"repository"|"meeting_link"|"file", "value": "extracted text value", "title": "friendly name"}
      ]
    }
    ''';

    final fallback = {
      'entities': <Map<String, dynamic>>[]
    };

    final json = await _generateJson(prompt, fallback);
    return EntityExtractionResult.fromJson(json);
  }

  @override
  Future<DeadlineExtractionResult> extractDeadline(String pageText) async {
    final prompt = '''
    Scrape this webpage text and identify any calendar dates or assignment deadlines that represent upcoming deadlines.
    Text: "$pageText"
    
    Respond STRICTLY in JSON format with these exact keys:
    {
      "deadline_found": boolean,
      "title": "description of the deadline",
      "date": "ISO8601 representation of the date, or null",
      "confidence": float between 0.0 and 1.0
    }
    ''';

    final fallback = {
      'deadline_found': false,
      'title': '',
      'date': null,
      'confidence': 0.0
    };

    final json = await _generateJson(prompt, fallback);
    return DeadlineExtractionResult.fromJson(json);
  }

  @override
  Future<ConversationInterpretationResult> interpretConversation(String currentMessage, List<Map<String, dynamic>> messageHistory) async {
    final prompt = '''
    Analyze the conversational chat exchange between the user and assistant.
    Current Message: "$currentMessage"
    History: ${jsonEncode(messageHistory)}
    
    Identify if the user is attempting to create a task, complete a task, ask for recommendations, or log a preference memory.
    Respond STRICTLY in JSON format with these exact keys:
    {
      "intent": "create_task" | "complete_task" | "query_insights" | "log_preference" | "general_chat",
      "extracted_task": {
        "title": "title, or null",
        "deadline": "date, or null",
        "description": "description, or null"
      },
      "reply_suggestion": "direct conversational reply text",
      "memory_candidate": {
        "category": "preference_or_habit",
        "value": "memory fact to store, or null"
      }
    }
    ''';

    final fallback = {
      'intent': 'general_chat',
      'extracted_task': {'title': null, 'deadline': null, 'description': null},
      'reply_suggestion': 'Acknowledged. How else can I help you?',
      'memory_candidate': {'category': 'preference_or_habit', 'value': null}
    };

    final json = await _generateJson(prompt, fallback);
    return ConversationInterpretationResult.fromJson(json);
  }

  @override
  Future<MemoryExtractionResult> extractMemories(String content) async {
    final prompt = '''
    Identify if there are any long-term learnings or user habits that should be stored from this description:
    "$content"
    
    Respond STRICTLY in JSON format with these exact keys:
    {
      "has_memory": boolean,
      "memories": [
        {"category": "work_preference"|"delay_habit"|"focus_strength", "value": "the extracted habit fact text", "confidence": float}
      ]
    }
    ''';

    final fallback = {
      'has_memory': false,
      'memories': <Map<String, dynamic>>[]
    };

    final json = await _generateJson(prompt, fallback);
    return MemoryExtractionResult.fromJson(json);
  }

  // ════════════════════════════════════════════
  //  Free-Text AI Methods (use _textModel)
  // ════════════════════════════════════════════

  @override
  Future<String> generateExplanation(String decisionContext) async {
    return _generateText(
      'Explain in a clear, friendly, and brief sentence the reasoning behind this decision context:\n"$decisionContext"',
      'Decision evaluated based on deadline proximity and distraction signals.',
    );
  }

  @override
  Future<String> summarizePage(String title, String url, String pageText) async {
    // Truncate very long page text to avoid token limits
    final truncatedText = pageText.length > 8000 ? pageText.substring(0, 8000) : pageText;

    return _generateText(
      'Summarize the following page content in three concise bullet points.\nPage Title: "$title"\nURL: "$url"\nText content:\n"$truncatedText"',
      'Offline: AI summarization unavailable. Webpage linked: $title ($url)',
    );
  }
}
