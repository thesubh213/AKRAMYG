// cloud_relay_service.dart for zero-knowledge polling sync

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'database.dart';
import 'event_bus.dart';
import 'crypto_helper.dart';

class CloudRelayService {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final EventBus _eventBus = EventBus();
  Timer? _timer;
  bool _isPolling = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _pollRelay());
    print('CloudRelayService: Background polling service started.');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    print('CloudRelayService: Background polling service stopped.');
  }

  Future<void> _pollRelay() async {
    if (_isPolling) return;
    _isPolling = true;

    try {
      final enabledConfig = await _db.queryById('system_entities', 'cloud_relay_enabled');
      final isEnabled = enabledConfig != null && enabledConfig['value'] == 'true';
      if (!isEnabled) {
        _isPolling = false;
        return;
      }

      final urlConfig = await _db.queryById('system_entities', 'cloud_relay_url');
      final keyConfig = await _db.queryById('system_entities', 'cloud_relay_pairing_key');

      final String relayUrl = urlConfig != null ? urlConfig['value'] : 'http://192.168.1.100:8080/relay';
      final String? pairingKey = keyConfig != null ? keyConfig['value'] : null;

      if (pairingKey == null || pairingKey.trim().isEmpty) {
        _isPolling = false;
        return;
      }

      final channelId = CryptoHelper.deriveChannelId(pairingKey);
      final uri = Uri.parse('$relayUrl/$channelId');

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final String? base64Payload = body['payload'] as String?;
        if (base64Payload == null || base64Payload.isEmpty) {
          _isPolling = false;
          return;
        }

        print('CloudRelayService: Retrieved encrypted envelope from relay.');
        final String decryptedText = CryptoHelper.decryptPayload(base64Payload, pairingKey);
        final Map<String, dynamic> payloadJson = jsonDecode(decryptedText);

        final List<dynamic>? events = payloadJson['events'] as List<dynamic>?;
        if (events == null || events.isEmpty) {
          _isPolling = false;
          return;
        }

        print('CloudRelayService: Decrypted and processing ${events.length} synchronized events.');
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
          } catch (itemErr) {
            print('CloudRelayService: Error processing event payload item: $itemErr');
          }
        }
      }
    } catch (e) {
      print('CloudRelayService: Polling cycle error: $e');
    } finally {
      _isPolling = false;
    }
  }
}
