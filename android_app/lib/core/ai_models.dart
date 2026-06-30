// ai_models.dart - Enforced type safety schemas for AI reasoning jobs

class TaskParseResult {
  final String title;
  final String description;
  final DateTime? deadline;
  final int estimatedDurationMins;
  final List<String> tags;
  final double confidence;

  TaskParseResult({
    required this.title,
    required this.description,
    this.deadline,
    required this.estimatedDurationMins,
    required this.tags,
    required this.confidence,
  });

  factory TaskParseResult.fromJson(Map<String, dynamic> json) {
    DateTime? deadlineDate;
    if (json['deadline'] != null) {
      try {
        deadlineDate = DateTime.parse(json['deadline'] as String);
      } catch (_) {}
    }

    return TaskParseResult(
      title: json['title'] as String? ?? 'Untitled Task',
      description: json['description'] as String? ?? '',
      deadline: deadlineDate,
      estimatedDurationMins: json['estimated_duration_mins'] as int? ?? 60,
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? ['general'],
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

class DurationEstimateResult {
  final int durationMins;
  final String reason;
  final double confidence;

  DurationEstimateResult({
    required this.durationMins,
    required this.reason,
    required this.confidence,
  });

  factory DurationEstimateResult.fromJson(Map<String, dynamic> json) {
    return DurationEstimateResult(
      durationMins: json['duration_mins'] as int? ?? 60,
      reason: json['reason'] as String? ?? 'Default duration estimate.',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

class PlanStep {
  final String title;
  final int orderIndex;

  PlanStep({required this.title, required this.orderIndex});

  factory PlanStep.fromJson(Map<String, dynamic> json) {
    return PlanStep(
      title: json['title'] as String? ?? 'Plan step',
      orderIndex: json['order'] as int? ?? 0,
    );
  }
}

class PlanResult {
  final List<PlanStep> steps;
  final String suggestedPrepWork;
  final List<String> potentialBlockers;
  final double confidence;

  PlanResult({
    required this.steps,
    required this.suggestedPrepWork,
    required this.potentialBlockers,
    required this.confidence,
  });

  factory PlanResult.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'] as List? ?? [];
    final stepsList = rawSteps
        .map((e) => PlanStep.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    return PlanResult(
      steps: stepsList,
      suggestedPrepWork: json['suggested_prep_work'] as String? ?? '',
      potentialBlockers: (json['potential_blockers'] as List?)?.map((e) => e.toString()).toList() ?? [],
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

class RiskEvaluationResult {
  final String riskLevel;
  final double riskScore;
  final String explanation;
  final String recommendedInterventionLevel;

  RiskEvaluationResult({
    required this.riskLevel,
    required this.riskScore,
    required this.explanation,
    required this.recommendedInterventionLevel,
  });

  factory RiskEvaluationResult.fromJson(Map<String, dynamic> json) {
    return RiskEvaluationResult(
      riskLevel: json['risk_level'] as String? ?? 'low',
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.1,
      explanation: json['explanation'] as String? ?? 'Task calculations evaluate as low risk.',
      recommendedInterventionLevel: json['recommended_intervention_level'] as String? ?? 'none',
    );
  }
}

class ExtractedEntity {
  final String category;
  final String value;
  final String title;

  ExtractedEntity({
    required this.category,
    required this.value,
    required this.title,
  });

  factory ExtractedEntity.fromJson(Map<String, dynamic> json) {
    return ExtractedEntity(
      category: json['category'] as String? ?? 'general',
      value: json['value'] as String? ?? '',
      title: json['title'] as String? ?? 'Entity',
    );
  }
}

class EntityExtractionResult {
  final List<ExtractedEntity> entities;

  EntityExtractionResult({required this.entities});

  factory EntityExtractionResult.fromJson(Map<String, dynamic> json) {
    final rawEntities = json['entities'] as List? ?? [];
    return EntityExtractionResult(
      entities: rawEntities
          .map((e) => ExtractedEntity.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class DeadlineExtractionResult {
  final bool deadlineFound;
  final String title;
  final DateTime? date;
  final double confidence;

  DeadlineExtractionResult({
    required this.deadlineFound,
    required this.title,
    this.date,
    required this.confidence,
  });

  factory DeadlineExtractionResult.fromJson(Map<String, dynamic> json) {
    DateTime? parsedDate;
    if (json['date'] != null) {
      try {
        parsedDate = DateTime.parse(json['date'] as String);
      } catch (_) {}
    }

    return DeadlineExtractionResult(
      deadlineFound: json['deadline_found'] as bool? ?? false,
      title: json['title'] as String? ?? '',
      date: parsedDate,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ProposedTask {
  final String? title;
  final DateTime? deadline;
  final String? description;

  ProposedTask({this.title, this.deadline, this.description});

  factory ProposedTask.fromJson(Map<String, dynamic> json) {
    DateTime? deadlineDate;
    if (json['deadline'] != null) {
      try {
        deadlineDate = DateTime.parse(json['deadline'] as String);
      } catch (_) {}
    }

    return ProposedTask(
      title: json['title'] as String?,
      deadline: deadlineDate,
      description: json['description'] as String?,
    );
  }
}

class MemoryCandidate {
  final String category;
  final String? value;

  MemoryCandidate({required this.category, this.value});

  factory MemoryCandidate.fromJson(Map<String, dynamic> json) {
    return MemoryCandidate(
      category: json['category'] as String? ?? 'preference_or_habit',
      value: json['value'] as String?,
    );
  }
}

class ConversationInterpretationResult {
  final String intent;
  final ProposedTask? extractedTask;
  final String replySuggestion;
  final MemoryCandidate? memoryCandidate;

  ConversationInterpretationResult({
    required this.intent,
    this.extractedTask,
    required this.replySuggestion,
    this.memoryCandidate,
  });

  factory ConversationInterpretationResult.fromJson(Map<String, dynamic> json) {
    ProposedTask? task;
    if (json['extracted_task'] != null) {
      task = ProposedTask.fromJson(Map<String, dynamic>.from(json['extracted_task'] as Map));
    }

    MemoryCandidate? memory;
    if (json['memory_candidate'] != null) {
      memory = MemoryCandidate.fromJson(Map<String, dynamic>.from(json['memory_candidate'] as Map));
    }

    return ConversationInterpretationResult(
      intent: json['intent'] as String? ?? 'general_chat',
      extractedTask: task,
      replySuggestion: json['reply_suggestion'] as String? ?? 'Acknowledged.',
      memoryCandidate: memory,
    );
  }
}

class MemoryItem {
  final String category;
  final String value;
  final double confidence;

  MemoryItem({
    required this.category,
    required this.value,
    required this.confidence,
  });

  factory MemoryItem.fromJson(Map<String, dynamic> json) {
    return MemoryItem(
      category: json['category'] as String? ?? 'preference_or_habit',
      value: json['value'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class MemoryExtractionResult {
  final bool hasMemory;
  final List<MemoryItem> memories;

  MemoryExtractionResult({required this.hasMemory, required this.memories});

  factory MemoryExtractionResult.fromJson(Map<String, dynamic> json) {
    final rawMemories = json['memories'] as List? ?? [];
    return MemoryExtractionResult(
      hasMemory: json['has_memory'] as bool? ?? false,
      memories: rawMemories
          .map((e) => MemoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class TaskCoachingResult {
  final String suggestion;
  final String encouragement;
  final String nextStepAdvice;
  final String priorityReason;

  TaskCoachingResult({
    required this.suggestion,
    required this.encouragement,
    required this.nextStepAdvice,
    required this.priorityReason,
  });

  factory TaskCoachingResult.fromJson(Map<String, dynamic> json) {
    return TaskCoachingResult(
      suggestion: json['suggestion'] as String? ?? 'Focus on completing the next subtask.',
      encouragement: json['encouragement'] as String? ?? 'You\'re making progress — keep going!',
      nextStepAdvice: json['next_step_advice'] as String? ?? 'Start with the first incomplete step.',
      priorityReason: json['priority_reason'] as String? ?? 'This task is on your schedule.',
    );
  }
}
