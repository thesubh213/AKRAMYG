// knowledge_graph.dart for AKRAMYG Shared Core

import 'dart:async';
import 'database.dart';

class KnowledgeGraph {
  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Registers or retrieves a node in the graph
  Future<String> getOrCreateNode(String entityType, String entityId, String label) async {
    try {
      final results = await _db.rawQuery(
        "SELECT id FROM graph_nodes WHERE entity_type = ? AND entity_id = ?",
        [entityType, entityId]
      );

      if (results.isNotEmpty) {
        return results.first['id'] as String;
      }

      final nodeId = '${entityType}_$entityId';
      await _db.insert('graph_nodes', {
        'id': nodeId,
        'entity_type': entityType,
        'entity_id': entityId,
        'label': label
      });
      return nodeId;
    } catch (e) {
      print('Knowledge Graph Error: Failed getOrCreateNode: $e');
      return '${entityType}_$entityId'; // Safe fallback identifier
    }
  }

  /// Establishes a relationship link between nodes
  Future<void> addRelationship(
      String sourceNodeId, String targetNodeId, String relationType, double confidence, String source) async {
    try {
      // Prevent duplicate relations
      final exist = await _db.rawQuery(
        "SELECT id FROM graph_relationships WHERE source_node_id = ? AND target_node_id = ? AND relation_type = ?",
        [sourceNodeId, targetNodeId, relationType]
      );

      if (exist.isEmpty) {
        final relationId = '${sourceNodeId}_${targetNodeId}_$relationType';
        await _db.insert('graph_relationships', {
          'id': relationId,
          'source_node_id': sourceNodeId,
          'target_node_id': targetNodeId,
          'relation_type': relationType,
          'confidence': confidence,
          'source': source
        });
      }
    } catch (e) {
      print('Knowledge Graph Error: Failed to add relationship: $e');
    }
  }

  /// Suggests links between tasks based on shared references (files, text keywords)
  Future<List<Map<String, dynamic>>> suggestTaskLinks(String taskId) async {
    List<Map<String, dynamic>> suggestions = [];
    try {
      final currentTask = await _db.queryById('tasks', taskId);
      if (currentTask == null) return suggestions;

      final String currentTitle = currentTask['title'] as String;
      
      // Suggest based on matching title keywords in other tasks
      final tokens = currentTitle.toLowerCase().split(RegExp(r'\s+'));
      final activeTasks = await _db.rawQuery(
        "SELECT id, title FROM tasks WHERE id != ? AND status = 'pending' AND is_deleted = 0",
        [taskId]
      );

      for (var other in activeTasks) {
        final otherId = other['id'] as String;
        final otherTitle = (other['title'] as String).toLowerCase();

        int overlap = 0;
        for (var token in tokens) {
          if (token.length > 3 && otherTitle.contains(token)) {
            overlap++;
          }
        }

        if (overlap > 0) {
          suggestions.add({
            'suggested_task_id': otherId,
            'suggested_task_title': other['title'],
            'reason': 'Shared title keywords: "${tokens.where((t) => t.length > 3 && otherTitle.contains(t)).join(', ')}"',
            'relation_type': 'depends_on'
          });
        }
      }
    } catch (e) {
      print('Knowledge Graph Error: Failed to suggest task links: $e');
    }

    return suggestions;
  }
}
