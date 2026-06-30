// memory_engine.dart for AKRAMYG Shared Core

import 'dart:async';
import 'database.dart';
import 'ai_client.dart';
import 'ai_models.dart';

class MemoryEngine {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final AiClientInterface _aiClient;

  MemoryEngine(this._aiClient);

  /// Scans chat logs or task text to extract potential memory candidates.
  /// If memories are extracted, they are registered with a verification status in DB.
  Future<List<Map<String, dynamic>>> extractMemoryCandidates(String content, String source) async {
    final aiResult = await _aiClient.extractMemories(content);
    final bool hasMemory = aiResult.hasMemory;
    final List<MemoryItem> memories = aiResult.memories;

    List<Map<String, dynamic>> candidates = [];

    if (hasMemory) {
      for (var mem in memories) {
        final category = mem.category;
        final value = mem.value;
        final double confidence = mem.confidence;

        final candidate = {
          'id': DateTime.now().millisecondsSinceEpoch.toString() + '_' + category,
          'category': category,
          'value': value,
          'confidence': confidence,
          'source': source,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'is_deleted': 1 // Stored as 'soft deleted' or draft state until user confirms
        };

        candidates.add(candidate);
      }
    }

    return candidates;
  }

  /// Explicitly confirms a memory candidate, moving it from draft to active state
  Future<void> confirmMemory(String memoryId) async {
    await _db.execute(
      "UPDATE memories SET is_deleted = 0, updated_at = ? WHERE id = ?",
      [DateTime.now().toIso8601String(), memoryId]
    );
  }

  /// Deletes or retires a memory
  Future<void> deleteMemory(String memoryId) async {
    await _db.delete('memories', memoryId);
  }

  /// Retrieves relevant memories using keywords matching the task title/details
  Future<List<Map<String, dynamic>>> retrieveRelevantMemories(String queryText) async {
    final memories = await _db.rawQuery("SELECT * FROM memories WHERE is_deleted = 0");
    
    // Simple local keyword matching for relevance ranking
    List<Map<String, dynamic>> results = [];
    final queryTokens = queryText.toLowerCase().split(RegExp(r'\s+'));

    for (var memory in memories) {
      final value = (memory['value'] as String).toLowerCase();
      final category = (memory['category'] as String).toLowerCase();

      int score = 0;
      for (var token in queryTokens) {
        if (token.length > 2) {
          if (value.contains(token)) score += 2;
          if (category.contains(token)) score += 1;
        }
      }

      if (score > 0) {
        results.add({
          ...memory,
          'relevance_score': score,
        });
      }
    }

    // Sort by relevance score descending
    results.sort((a, b) => (b['relevance_score'] as int).compareTo(a['relevance_score'] as int));
    return results;
  }

  /// Run periodic maintenance: clean up expired memories
  Future<void> performMaintenance() async {
    final now = DateTime.now().toIso8601String();
    await _db.execute(
      "UPDATE memories SET is_deleted = 1, updated_at = ? WHERE expiration IS NOT NULL AND expiration < ?",
      [DateTime.now().toIso8601String(), now]
    );
  }
}
