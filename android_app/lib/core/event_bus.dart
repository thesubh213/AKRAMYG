// event_bus.dart for AKRAMYG Shared Core

import 'dart:async';

/// Base class for all events in the system
abstract class AppEvent {
  final DateTime timestamp = DateTime.now();
}

/// Dispatched when a new task is created
class TaskCreatedEvent extends AppEvent {
  final Map<String, dynamic> task;
  TaskCreatedEvent(this.task);
}

/// Dispatched when a task is updated
class TaskUpdatedEvent extends AppEvent {
  final Map<String, dynamic> task;
  TaskUpdatedEvent(this.task);
}

/// Dispatched when a focus session starts
class FocusSessionStartedEvent extends AppEvent {
  final String taskId;
  FocusSessionStartedEvent(this.taskId);
}

/// Dispatched when a focus session stops
class FocusSessionStoppedEvent extends AppEvent {
  final String taskId;
  final int durationMins;
  final int interruptionsCount;
  FocusSessionStoppedEvent(this.taskId, this.durationMins, this.interruptionsCount);
}

/// Dispatched when Chrome extension reports a distraction website visit
class DistractionDetectedEvent extends AppEvent {
  final String domain;
  final String url;
  final String title;
  final String? activeTaskId;
  DistractionDetectedEvent({
    required this.domain,
    required this.url,
    required this.title,
    this.activeTaskId,
  });
}

/// Dispatched when Chrome extension scraper detects a deadline candidate
class DeadlineScrapedEvent extends AppEvent {
  final String title;
  final String date;
  final String sourceUrl;
  final bool isCaptureProposal;
  DeadlineScrapedEvent({
    required this.title,
    required this.date,
    required this.sourceUrl,
    this.isCaptureProposal = false,
  });
}

/// Dispatched when a web page is attached to a task
class PageAttachedEvent extends AppEvent {
  final String url;
  final String title;
  final String? taskId;
  PageAttachedEvent({required this.url, required this.title, this.taskId});
}

/// Dispatched when Decision Engine issues a notification request
class NotificationRequestedEvent extends AppEvent {
  final String? taskId;
  final String title;
  final String body;
  final String category; // 'standard' | 'critical' | 'fullscreen'
  NotificationRequestedEvent({
    this.taskId,
    required this.title,
    required this.body,
    required this.category,
  });
}

/// Dispatched when background AI services fail or have authentication issues
class AiServiceFailureEvent extends AppEvent {
  final String error;
  AiServiceFailureEvent(this.error);
}

/// Broadcast event bus for publishing and subscribing to system actions.
class EventBus {
  // Private constructor for singleton pattern
  EventBus._internal();
  static final EventBus _instance = EventBus._internal();
  factory EventBus() => _instance;

  final StreamController<AppEvent> _controller = StreamController<AppEvent>.broadcast();

  /// Publish a new event to all active subscribers
  void publish(AppEvent event) {
    _controller.add(event);
  }

  /// Subscribe to events of a specific type [T]
  Stream<T> on<T extends AppEvent>() {
    if (T == AppEvent) {
      return _controller.stream as Stream<T>;
    }
    return _controller.stream.where((event) => event is T).cast<T>();
  }

  /// Dispose of the bus controller
  void dispose() {
    _controller.close();
  }
}
