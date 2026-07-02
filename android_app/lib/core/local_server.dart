// local_server.dart for sync communication with Chrome Extension

import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'event_bus.dart';
import 'database.dart';
import 'ai_client.dart';

class LocalSyncServer {
  final EventBus _eventBus = EventBus();
  final DatabaseHelper _db = DatabaseHelper.instance;
  final AiClientInterface _aiClient;
  
  HttpServer? _server;
  String? _serverAddress;
  String? get serverAddress => _serverAddress;
  final Router _router = Router();
  final Map<String, String> _relayMailboxes = {};

  LocalSyncServer(this._aiClient) {
    _setupRoutes();
  }

  void _setupRoutes() {
    // 1. Status query route
    _router.get('/status', (Request request) async {
      try {
        // Query active focus sessions from database
        final activeSessions = await _db.rawQuery(
          "SELECT task_id, start_time FROM execution_sessions WHERE end_time IS NULL LIMIT 1"
        );

        String? activeTaskId;
        String? activeTaskTitle;
        String? activeTaskDescription;
        bool isFocusActive = false;
        List<Map<String, dynamic>> pendingSubtasks = [];

        if (activeSessions.isNotEmpty) {
          activeTaskId = activeSessions.first['task_id'] as String;
          isFocusActive = true;
          final task = await _db.queryById('tasks', activeTaskId);
          if (task != null) {
            activeTaskTitle = task['title'] as String;
            activeTaskDescription = task['description'] as String?;
            pendingSubtasks = await _db.rawQuery(
              "SELECT id, title, order_index FROM subtasks WHERE task_id = ? AND status = 'pending' AND is_deleted = 0 ORDER BY order_index ASC",
              [activeTaskId]
            );
          }
        }

        final statusPayload = {
          'isConnected': true,
          'activeTaskId': activeTaskId,
          'activeTaskTitle': activeTaskTitle,
          'activeTaskDescription': activeTaskDescription,
          'isFocusSessionActive': isFocusActive,
          'pendingSubtasks': pendingSubtasks,
          'serverTime': DateTime.now().toIso8601String()
        };

        return Response.ok(
          jsonEncode(statusPayload),
          headers: _corsHeaders(request),
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: _corsHeaders(request),
        );
      }
    });

    // 2. Sync payload submission route
    _router.post('/sync', (Request request) async {
      try {
        final payloadString = await request.readAsString();
        final payload = jsonDecode(payloadString);
        final List<dynamic> events = payload['events'] ?? [];

        print('LocalSyncServer: Received ${events.length} events from extension.');

        for (var ev in events) {
          try {
            final type = ev['type'] as String?;
            if (type == null) continue;
            final data = ev['data'] as Map<String, dynamic>?;
            if (data == null) continue;

            if (type == 'distraction') {
              _eventBus.publish(DistractionDetectedEvent(
                domain: data['domain'] ?? '',
                url: data['url'] ?? '',
                title: data['title'] ?? '',
                activeTaskId: data['activeTask'],
              ));
            } else if (type == 'deadline') {
              _eventBus.publish(DeadlineScrapedEvent(
                title: data['title'] ?? '',
                date: data['date'] ?? '',
                sourceUrl: data['sourceUrl'] ?? '',
                isCaptureProposal: data['isCaptureProposal'] ?? false,
              ));
            } else if (type == 'page_attach') {
              _eventBus.publish(PageAttachedEvent(
                url: data['url'] ?? '',
                title: data['title'] ?? '',
              ));
            } else if (type == 'entity' && data['category'] == 'active_tab') {
              final config = await _db.queryById('system_entities', 'foreground_app_provider');
              final enabled = config == null || config['value'] == 'true';
              if (enabled) {
                await _db.insert('context_snapshots', {
                  'id': DateTime.now().millisecondsSinceEpoch.toString() + '_tab',
                  'timestamp': DateTime.now().toIso8601String(),
                  'active_app': 'Browser: ${data['title']} (${data['value']})',
                  'battery_level': null,
                  'charging_state': null,
                  'network_status': 'online'
                });
              }
            }
          } catch (e) {
            print('LocalSyncServer: Error processing synchronized event iteration: $e');
          }
        }

        return Response.ok(
          jsonEncode({'success': true, 'synced_count': events.length}),
          headers: _corsHeaders(request),
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: _corsHeaders(request),
        );
      }
    });

    // 3. Summarize page text route
    _router.post('/summarize', (Request request) async {
      try {
        final payloadString = await request.readAsString();
        final payload = jsonDecode(payloadString);
        final String title = payload['title'] ?? '';
        final String url = payload['url'] ?? '';
        final String text = payload['text'] ?? '';

        final summary = await _aiClient.summarizePage(title, url, text);

        return Response.ok(
          jsonEncode({'summary': summary}),
          headers: _corsHeaders(request),
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: _corsHeaders(request),
        );
      }
    });

    // 3b. Complete subtask route
    _router.post('/complete-subtask', (Request request) async {
      try {
        final payloadString = await request.readAsString();
        final payload = jsonDecode(payloadString);
        final String subtaskId = payload['subtaskId'] ?? '';

        if (subtaskId.isEmpty) {
          return Response.badRequest(
            body: jsonEncode({'error': 'subtaskId is required'}),
            headers: _corsHeaders(request),
          );
        }

        await _db.execute(
          "UPDATE subtasks SET status = 'completed', updated_at = ? WHERE id = ?",
          [DateTime.now().toIso8601String(), subtaskId]
        );

        // Fetch task_id of this subtask to fire TaskUpdatedEvent
        final subtask = await _db.queryById('subtasks', subtaskId);
        if (subtask != null) {
          final taskId = subtask['task_id'] as String;
          _eventBus.publish(TaskUpdatedEvent({'id': taskId}));
        }

        return Response.ok(
          jsonEncode({'success': true}),
          headers: _corsHeaders(request),
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: _corsHeaders(request),
        );
      }
    });

    _router.post('/complete-task', (Request request) async {
      try {
        final payloadString = await request.readAsString();
        final payload = jsonDecode(payloadString);
        final String taskId = payload['taskId'] ?? '';

        if (taskId.isEmpty) {
          return Response.badRequest(
            body: jsonEncode({'error': 'taskId is required'}),
            headers: _corsHeaders(request),
          );
        }

        await _db.execute(
          "UPDATE tasks SET status = 'completed', updated_at = ? WHERE id = ?",
          [DateTime.now().toIso8601String(), taskId]
        );

        _eventBus.publish(TaskUpdatedEvent({'id': taskId}));

        return Response.ok(
          jsonEncode({'success': true}),
          headers: _corsHeaders(request),
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: _corsHeaders(request),
        );
      }
    });

    // 4. GET /relay/<channel>
    _router.get('/relay/<channel>', (Request request, String channel) {
      final payload = _relayMailboxes.remove(channel);
      return Response.ok(
        jsonEncode({'payload': payload ?? ''}),
        headers: _corsHeaders(request),
      );
    });

    // 5. POST /relay/<channel>
    _router.post('/relay/<channel>', (Request request, String channel) async {
      try {
        final bodyStr = await request.readAsString();
        final body = jsonDecode(bodyStr);
        final payload = body['payload'] as String?;
        if (payload != null && payload.isNotEmpty) {
          _relayMailboxes[channel] = payload;
        }
        return Response.ok(
          jsonEncode({'success': true}),
          headers: _corsHeaders(request),
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: _corsHeaders(request),
        );
      }
    });

    // Catch-all options route for CORS/PNA preflights
    _router.all('/<ignored|.*>', (Request request) {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders(request));
      }
      return Response.notFound('Not Found');
    });
  }

  /// Generates the necessary CORS and Private Network Access headers
  Map<String, String> _corsHeaders(Request request) {
    final origin = request.headers['origin'];
    String allowedOrigin = '*';
    if (origin != null) {
      if (origin.startsWith('chrome-extension://') ||
          origin.startsWith('http://localhost') ||
          origin.startsWith('http://127.0.0.1') ||
          origin.startsWith('http://192.168.')) {
        allowedOrigin = origin;
      } else {
        allowedOrigin = 'null'; // Reject unauthorized cross-origin requests
      }
    }

    final headers = {
      'Access-Control-Allow-Origin': allowedOrigin,
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Access-Control-Request-Private-Network',
      'Content-Type': 'application/json',
    };

    // If request contains Private Network request check, respond to PNA preflight
    if (request.headers.containsKey('Access-Control-Request-Private-Network')) {
      headers['Access-Control-Allow-Private-Network'] = 'true';
    }

    return headers;
  }

  /// Start HTTP server on local address
  Future<void> start({int port = 8080}) async {
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(_router.call);

    // Bind to all interfaces (IPv4)
    _server = await io.serve(handler, InternetAddress.anyIPv4, port);
    _serverAddress = await getLocalIpAddress();
    print('LocalSyncServer: Listening on http://$_serverAddress:${_server!.port}');
  }

  /// Stop server
  Future<void> stop() async {
    await _server?.close(force: true);
    print('LocalSyncServer stopped.');
  }

  /// Helper to get current device local Wi-Fi IP address
  static Future<String> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168.')) {
            return addr.address;
          }
        }
      }
      // Fallback first non-loopback
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
      return '127.0.0.1';
    } catch (_) {
      return '127.0.0.1';
    }
  }
}
