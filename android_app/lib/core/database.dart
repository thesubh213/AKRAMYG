// database.dart for AKRAMYG SQLite storage

import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  // Singleton pattern
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();
  factory DatabaseHelper() => instance;

  static Database? _database;
  static Completer<Database>? _dbInitCompleter;

  Future<Database> get database async {
    if (_database != null) return _database!;
    
    if (_dbInitCompleter != null) {
      return await _dbInitCompleter!.future;
    }

    _dbInitCompleter = Completer<Database>();
    try {
      final db = await _initDatabase();
      // Dynamically ensure configuration table exists
      await db.execute('''
        CREATE TABLE IF NOT EXISTS system_entities (
          id TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      // Safe migration: add priority and tags columns to tasks if missing
      await _migrateTasksTable(db);

      _database = db;
      _dbInitCompleter!.complete(db);
      return db;
    } catch (e) {
      _dbInitCompleter!.completeError(e);
      _dbInitCompleter = null;
      rethrow;
    }
  }

  /// Safely adds new columns to the tasks table for existing installs
  Future<void> _migrateTasksTable(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(tasks)");
    final colNames = cols.map((c) => c['name'] as String).toSet();

    if (!colNames.contains('priority')) {
      await db.execute("ALTER TABLE tasks ADD COLUMN priority TEXT DEFAULT 'medium'");
    }
    if (!colNames.contains('tags')) {
      await db.execute("ALTER TABLE tasks ADD COLUMN tags TEXT");
    }
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final pathString = join(dbPath, 'akramyg.db');

    return await openDatabase(
      pathString,
      version: 1,
      onCreate: _onCreate,
      onConfigure: _onConfigure,
    );
  }

  Future<void> _onConfigure(Database db) async {
    // Enable foreign keys
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Objectives Table
    await db.execute('''
      CREATE TABLE objectives (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        origin_subsystem TEXT DEFAULT 'system',
        sync_state TEXT DEFAULT 'local_only',
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 2. Projects Table
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        objective_id TEXT,
        title TEXT NOT NULL,
        description TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        origin_subsystem TEXT DEFAULT 'system',
        sync_state TEXT DEFAULT 'local_only',
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (objective_id) REFERENCES objectives (id) ON DELETE SET NULL
      )
    ''');

    // 3. Tasks Table
    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        project_id TEXT,
        title TEXT NOT NULL,
        description TEXT,
        deadline TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT,
        estimated_duration INTEGER NOT NULL DEFAULT 0, -- in minutes
        actual_duration INTEGER NOT NULL DEFAULT 0, -- in minutes
        execution_confidence REAL DEFAULT 1.0,
        origin_subsystem TEXT DEFAULT 'system',
        sync_state TEXT DEFAULT 'local_only',
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE SET NULL
      )
    ''');

    // 4. Subtasks Table
    await db.execute('''
      CREATE TABLE subtasks (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        title TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending', -- 'pending' | 'completed'
        order_index INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE CASCADE
      )
    ''');

    // 5. File References Table
    await db.execute('''
      CREATE TABLE file_references (
        id TEXT PRIMARY KEY,
        task_id TEXT,
        path TEXT NOT NULL,
        filename TEXT NOT NULL,
        extension TEXT,
        checksum TEXT,
        modified_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE SET NULL
      )
    ''');

    // 6. Memories Table
    await db.execute('''
      CREATE TABLE memories (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL, -- e.g. 'work_hours', 'preference', 'delay_habit'
        value TEXT NOT NULL,
        confidence REAL NOT NULL DEFAULT 1.0,
        source TEXT NOT NULL, -- e.g. 'ai_inference', 'user_explicit'
        expiration TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 7. Context Snapshots Table
    await db.execute('''
      CREATE TABLE context_snapshots (
        id TEXT PRIMARY KEY,
        timestamp TEXT NOT NULL,
        active_app TEXT,
        battery_level INTEGER,
        charging_state TEXT,
        network_status TEXT
      )
    ''');

    // 8. Conversations Table
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 9. Messages Table
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        sender TEXT NOT NULL, -- 'user' | 'assistant'
        text TEXT NOT NULL,
        extracted_entities TEXT, -- JSON string
        related_tasks TEXT,      -- JSON string
        created_at TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
      )
    ''');

    // 10. Insights Table
    await db.execute('''
      CREATE TABLE insights (
        id TEXT PRIMARY KEY,
        insight_type TEXT NOT NULL,
        confidence REAL NOT NULL DEFAULT 1.0,
        supporting_evidence TEXT,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_dismissed INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 11. Execution Sessions Table
    await db.execute('''
      CREATE TABLE execution_sessions (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        interruptions INTEGER NOT NULL DEFAULT 0,
        apps_used TEXT, -- JSON array of apps
        productivity_metrics TEXT, -- JSON details
        FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE CASCADE
      )
    ''');

    // 12. Notifications Table
    await db.execute('''
      CREATE TABLE notifications (
        id TEXT PRIMARY KEY,
        task_id TEXT,
        type TEXT NOT NULL, -- 'standard' | 'critical' | 'fullscreen'
        trigger TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        delivery_status TEXT NOT NULL, -- 'pending' | 'delivered' | 'clicked' | 'dismissed'
        user_response TEXT,
        FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE SET NULL
      )
    ''');

    // 13. Knowledge Graph Nodes and Relationships
    await db.execute('''
      CREATE TABLE graph_nodes (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL, -- 'task' | 'file' | 'memory' | 'concept'
        entity_id TEXT,
        label TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE graph_relationships (
        id TEXT PRIMARY KEY,
        source_node_id TEXT NOT NULL,
        target_node_id TEXT NOT NULL,
        relation_type TEXT NOT NULL,
        confidence REAL NOT NULL DEFAULT 1.0,
        source TEXT,
        FOREIGN KEY (source_node_id) REFERENCES graph_nodes (id) ON DELETE CASCADE,
        FOREIGN KEY (target_node_id) REFERENCES graph_nodes (id) ON DELETE CASCADE
      )
    ''');

    // 14. Behavior Models (Duration/Productivity/Intervention weights)
    await db.execute('''
      CREATE TABLE behavior_models (
        id TEXT PRIMARY KEY,
        model_type TEXT NOT NULL, -- 'duration' | 'productivity' | 'intervention'
        version INTEGER NOT NULL DEFAULT 1,
        weights TEXT NOT NULL, -- JSON parameter string
        updated_at TEXT NOT NULL
      )
    ''');

    // 15. System Entities (Configurations, settings, active provider status)
    await db.execute('''
      CREATE TABLE system_entities (
        id TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  // Generic helper CRUD methods

  void _validateTableName(String table) {
    const validTables = {
      'objectives', 'projects', 'tasks', 'subtasks', 'file_references', 
      'memories', 'context_snapshots', 'conversations', 'messages', 
      'insights', 'execution_sessions', 'notifications', 'graph_nodes', 
      'graph_relationships', 'behavior_models', 'system_entities'
    };
    if (!validTables.contains(table)) {
      throw ArgumentError('Invalid or unauthorized table name: $table');
    }
  }

  /// Insert a row into a table
  Future<int> insert(String table, Map<String, dynamic> row) async {
    _validateTableName(table);
    final db = await database;
    if (table == 'tasks') {
      if (row['title'] == null || row['title'].toString().trim().isEmpty) {
        throw ArgumentError('Task title is required and cannot be empty.');
      }
      if (row['deadline'] == null || row['deadline'].toString().trim().isEmpty) {
        throw ArgumentError('Task deadline is required and cannot be empty.');
      }
    }
    return await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Query all active (not soft deleted) rows in a table
  Future<List<Map<String, dynamic>>> queryAll(String table) async {
    _validateTableName(table);
    final db = await database;
    // Check if table contains is_deleted column
    final cols = await db.rawQuery("PRAGMA table_info($table)");
    final hasDeleted = cols.any((col) => col['name'] == 'is_deleted');

    if (hasDeleted) {
      return await db.query(table, where: 'is_deleted = 0');
    } else {
      return await db.query(table);
    }
  }

  /// Query a single row by ID
  Future<Map<String, dynamic>?> queryById(String table, String id) async {
    _validateTableName(table);
    final db = await database;
    final results = await db.query(table, where: 'id = ?', whereArgs: [id]);
    if (results.isNotEmpty) return results.first;
    return null;
  }

  /// Update a row
  Future<int> update(String table, Map<String, dynamic> row, String id) async {
    _validateTableName(table);
    final db = await database;
    return await db.update(
      table,
      row,
      where: 'id = ?',
      whereArgs: [id],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Soft delete a row if it supports it, otherwise hard delete
  Future<int> delete(String table, String id) async {
    _validateTableName(table);
    final db = await database;
    final cols = await db.rawQuery("PRAGMA table_info($table)");
    final hasDeleted = cols.any((col) => col['name'] == 'is_deleted');

    if (hasDeleted) {
      return await db.update(
        table,
        {
          'is_deleted': 1,
          'updated_at': DateTime.now().toIso8601String(),
          'sync_state': 'pending_sync'
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      return await db.delete(table, where: 'id = ?', whereArgs: [id]);
    }
  }

  /// Perform raw query
  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<dynamic>? arguments]) async {
    final db = await database;
    return await db.rawQuery(sql, arguments);
  }

  /// Execute raw statement
  Future<void> execute(String sql, [List<dynamic>? arguments]) async {
    final db = await database;
    await db.execute(sql, arguments);
  }
}
