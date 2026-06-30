// core_test.dart - Android App Shared Core Unit Tests

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:akramyg_app/core/event_bus.dart';
import 'package:akramyg_app/core/ai_models.dart';
import 'package:akramyg_app/core/database.dart';
import 'package:akramyg_app/core/crypto_helper.dart';

void main() {
  group('EventBus Tests', () {
    late EventBus eventBus;

    setUp(() {
      eventBus = EventBus();
    });

    test('Should publish and subscribe to TaskCreatedEvent correctly', () async {
      final taskMock = {
        'id': 'test_123',
        'title': 'Solve Calculus homework',
        'deadline': '2026-07-01T12:00:00Z',
      };

      // Set up listener and wait for event
      final completer = Completer<TaskCreatedEvent>();
      final sub = eventBus.on<TaskCreatedEvent>().listen((event) {
        completer.complete(event);
      });

      // Publish event
      eventBus.publish(TaskCreatedEvent(taskMock));

      final receivedEvent = await completer.future;
      expect(receivedEvent.task['id'], equals('test_123'));
      expect(receivedEvent.task['title'], equals('Solve Calculus homework'));

      await sub.cancel();
    });

    test('Should filter specific events correctly', () async {
      int focusStartTriggered = 0;
      int taskCreatedTriggered = 0;

      final sub1 = eventBus.on<FocusSessionStartedEvent>().listen((_) {
        focusStartTriggered++;
      });
      final sub2 = eventBus.on<TaskCreatedEvent>().listen((_) {
        taskCreatedTriggered++;
      });

      // Dispatch event
      eventBus.publish(FocusSessionStartedEvent('some_task_id'));

      // Wait a moment for async streams to process
      await Future.delayed(const Duration(milliseconds: 10));

      expect(focusStartTriggered, equals(1));
      expect(taskCreatedTriggered, equals(0));

      await sub1.cancel();
      await sub2.cancel();
    });
  });

  group('AI Model Schema Tests', () {
    test('TaskParseResult.fromJson should enforce defaults and parse fields correctly', () {
      final jsonInput = {
        'title': 'Study Biology',
        'description': 'Prepare for midterm test',
        'deadline': '2026-07-02T15:00:00.000',
        'estimated_duration_mins': 90,
        'tags': ['study', 'biology'],
        'confidence': 0.95
      };

      final parsed = TaskParseResult.fromJson(jsonInput);
      
      expect(parsed.title, equals('Study Biology'));
      expect(parsed.description, equals('Prepare for midterm test'));
      expect(parsed.deadline, isNotNull);
      expect(parsed.deadline!.day, equals(2));
      expect(parsed.estimatedDurationMins, equals(90));
      expect(parsed.tags, contains('biology'));
      expect(parsed.confidence, equals(0.95));
    });

    test('TaskParseResult.fromJson should fallback gracefully on empty json', () {
      final parsed = TaskParseResult.fromJson({});
      
      expect(parsed.title, equals('Untitled Task'));
      expect(parsed.description, equals(''));
      expect(parsed.deadline, isNull);
      expect(parsed.estimatedDurationMins, equals(60));
      expect(parsed.tags, contains('general'));
      expect(parsed.confidence, equals(0.5));
    });

    test('PlanResult.fromJson should parse steps and prep work correctly', () {
      final jsonInput = {
        'steps': [
          {'title': 'Read syllabus', 'order': 1},
          {'title': 'Complete quiz', 'order': 2}
        ],
        'suggested_prep_work': 'Log into school dashboard',
        'potential_blockers': ['Server maintenance'],
        'confidence': 0.8
      };

      final parsed = PlanResult.fromJson(jsonInput);
      
      expect(parsed.steps.length, equals(2));
      expect(parsed.steps[0].title, equals('Read syllabus'));
      expect(parsed.steps[0].orderIndex, equals(1));
      expect(parsed.suggestedPrepWork, equals('Log into school dashboard'));
      expect(parsed.potentialBlockers, contains('Server maintenance'));
      expect(parsed.confidence, equals(0.8));
    });
  });

  group('Database Whitelist Safety Tests', () {
    test('DatabaseHelper generic methods should throw ArgumentError on invalid table names', () async {
      final dbHelper = DatabaseHelper.instance;

      expect(() => dbHelper.queryAll('non_existent_table_drop_databases'), throwsArgumentError);
      expect(() => dbHelper.queryById('users_hacked_table', '123'), throwsArgumentError);
      expect(() => dbHelper.delete('secrets_leak', '123'), throwsArgumentError);
    });
  });

  group('Zero-Knowledge Crypto Helper Tests', () {
    test('Should derive channel ID deterministically', () {
      final key1 = CryptoHelper.deriveChannelId('my-secret-key-123');
      final key2 = CryptoHelper.deriveChannelId('my-secret-key-123');
      final key3 = CryptoHelper.deriveChannelId('different-key');

      expect(key1, equals(key2));
      expect(key1, isNot(equals(key3)));
      expect(key1.length, equals(32));
    });

    test('Should decrypt GCM payloads generated with same passphrase key material', () {
      final passphrase = 'secret-pairing-passphrase';
      final plainText = '{"events": [{"type": "distraction", "data": {"domain": "youtube.com"}}]}';

      // Manually encrypt in test to test decrypter
      final key = CryptoHelper.deriveKey(passphrase);
      final iv = enc.IV.fromSecureRandom(12); // standard 12-byte GCM IV
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
      
      final encrypted = encrypter.encrypt(plainText, iv: iv);
      
      // Package as: IV (12 bytes) + Ciphertext (includes Tag)
      final Uint8List combined = Uint8List(12 + encrypted.bytes.length);
      combined.setRange(0, 12, iv.bytes);
      combined.setRange(12, combined.length, encrypted.bytes);

      final base64Payload = base64.encode(combined);

      // Decrypt using helper
      final decrypted = CryptoHelper.decryptPayload(base64Payload, passphrase);
      expect(decrypted, equals(plainText));
    });
  });
}
