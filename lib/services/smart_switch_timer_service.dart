import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:tinkrnest_app/models/timer_model.dart';
import 'package:tinkrnest_app/core/repositories/timer_repository.dart';

typedef TimerCallback =
    Future<void> Function(SwitchTimer timer, SwitchRuntimeState state);

/// High-performance timer scheduler engine
class SmartSwitchTimerService {
  final TimerRepository _repository;
  final TimerCallback onTimerTick;
  final TimerCallback? onTimerComplete;
  final TimerCallback? onTimerStateChange;

  SmartSwitchTimerService({
    required TimerRepository repository,
    required this.onTimerTick,
    this.onTimerComplete,
    this.onTimerStateChange,
  }) : _repository = repository {
    _initializeService();
  }

  // ==================== State ====================
  final Map<String, Timer?> _activeCountdownTimers = {};
  final Map<String, StreamSubscription?> _scheduledTimerSubscriptions = {};
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  // ==================== Lifecycle ====================

  void _initializeService() {
    _isRunning = true;
    _startScheduleChecker();
  }

  void dispose() {
    _isRunning = false;
    _cancelAllActiveTimers();
    _cancelAllScheduledTimers();
  }

  // ==================== Timer Management ====================

  /// Start a countdown timer for a switch
  Future<void> startCountdownTimer(SwitchTimer timer) async {
    if (!_isRunning) return;

    // Cancel existing timer for this switch
    await cancelTimer(timer.id);

    final config = timer.countdownConfig;
    if (config == null) {
      if (kDebugMode) print('Error: No countdown config for timer ${timer.id}');
      return;
    }

    final endTime = DateTime.now().add(
      Duration(seconds: config.durationSeconds),
    );

    // Update runtime state
    var runtimeState = await _repository.getRuntimeState(timer.switchId);
    if (runtimeState == null) {
      runtimeState = SwitchRuntimeState(
        switchId: timer.switchId,
        isOn: config.targetState,
        activeTimerId: timer.id,
        countdownEndTime: endTime,
      );
    } else {
      runtimeState = runtimeState.copyWith(
        isOn: config.targetState,
        activeTimerId: timer.id,
        countdownEndTime: endTime,
      );
    }

    await _repository.saveSwitchRuntimeState(runtimeState);
    await onTimerStateChange?.call(timer, runtimeState);

    // Start countdown timer
    final countdownTimer = Timer.periodic(Duration(milliseconds: 500), (
      asyncTimer,
    ) async {
      if (!_isRunning) {
        asyncTimer.cancel();
        return;
      }

      final currentState = await _repository.getRuntimeState(timer.switchId);
      if (currentState == null) {
        asyncTimer.cancel();
        return;
      }

      final remaining = currentState.remainingSeconds;

      // Tick callback
      await onTimerTick.call(timer, currentState);

      // Check if timer completed
      if (remaining != null && remaining <= 0) {
        asyncTimer.cancel();
        _activeCountdownTimers.remove(timer.id);

        // Apply target state
        final finalState = currentState.copyWith(
          isOn: config.targetState,
          activeTimerId: null,
          countdownEndTime: null,
          lastUpdated: DateTime.now(),
        );

        await _repository.saveSwitchRuntimeState(finalState);
        await onTimerComplete?.call(timer, finalState);
      }
    });

    _activeCountdownTimers[timer.id] = countdownTimer;
  }

  /// Start a scheduled timer (one-time or recurring)
  Future<void> startScheduledTimer(SwitchTimer timer) async {
    if (!_isRunning) return;

    await cancelTimer(timer.id);

    final config = timer.scheduledConfig;
    if (config == null) {
      if (kDebugMode) print('Error: No scheduled config for timer ${timer.id}');
      return;
    }

    // Calculate next trigger time
    final nextTrigger = _calculateNextTriggerTime(config);

    // Stream that ticks every minute
    final subscription = Stream.periodic(Duration(minutes: 1)).listen((
      _,
    ) async {
      if (!_isRunning) return;

      final now = DateTime.now();
      if (_shouldTrigger(config, now)) {
        var runtimeState = await _repository.getRuntimeState(timer.switchId);
        if (runtimeState == null) {
          runtimeState = SwitchRuntimeState(
            switchId: timer.switchId,
            isOn: config.targetState,
            lastUpdated: DateTime.now(),
          );
        } else {
          runtimeState = runtimeState.copyWith(
            isOn: config.targetState,
            lastUpdated: DateTime.now(),
          );
        }

        await _repository.saveSwitchRuntimeState(runtimeState);
        await onTimerComplete?.call(timer, runtimeState);
      }
    });

    _scheduledTimerSubscriptions[timer.id] = subscription;
  }

  /// Cancel a specific timer
  Future<void> cancelTimer(String timerId) async {
    // Cancel countdown timer
    _activeCountdownTimers[timerId]?.cancel();
    _activeCountdownTimers.remove(timerId);

    // Cancel scheduled timer
    await _scheduledTimerSubscriptions[timerId]?.cancel();
    _scheduledTimerSubscriptions.remove(timerId);
  }

  /// Resume all active timers (after app resume)
  Future<void> resumeAllActiveTimers() async {
    if (!_isRunning) return;

    final timers = await _repository.getAllTimers();
    for (final timer in timers.where((t) => t.isEnabled)) {
      switch (timer.timerType) {
        case TimerType.countdown:
          await startCountdownTimer(timer);
          break;
        case TimerType.onTime:
        case TimerType.offTime:
        case TimerType.daily:
        case TimerType.weekly:
          await startScheduledTimer(timer);
          break;
      }
    }
  }

  // ==================== Schedule Checker ====================

  void _startScheduleChecker() {
    // Periodically check for scheduled timers that need to trigger
    Timer.periodic(Duration(minutes: 1), (timer) async {
      if (!_isRunning) return;

      final timers = await _repository.getAllTimers();
      for (final t in timers.where((t) => t.isEnabled)) {
        if (t.timerType != TimerType.countdown) {
          final config = t.scheduledConfig;
          if (config != null && _shouldTrigger(config, DateTime.now())) {
            var runtimeState = await _repository.getRuntimeState(t.switchId);
            if (runtimeState == null) {
              runtimeState = SwitchRuntimeState(
                switchId: t.switchId,
                isOn: config.targetState,
                lastUpdated: DateTime.now(),
              );
            } else {
              runtimeState = runtimeState.copyWith(
                isOn: config.targetState,
                lastUpdated: DateTime.now(),
              );
            }

            await _repository.saveSwitchRuntimeState(runtimeState);
            await onTimerComplete?.call(t, runtimeState);
          }
        }
      }
    });
  }

  // ==================== Helpers ====================

  DateTime _calculateNextTriggerTime(ScheduledTimer config) {
    final now = DateTime.now();
    var nextTrigger = DateTime(
      now.year,
      now.month,
      now.day,
      config.hour,
      config.minute,
    );

    // If time has passed today, schedule for tomorrow
    if (nextTrigger.isBefore(now)) {
      nextTrigger = nextTrigger.add(Duration(days: 1));
    }

    return nextTrigger;
  }

  bool _shouldTrigger(ScheduledTimer config, DateTime now) {
    // Check if current time matches scheduled time (within 1 minute window)
    final timeDiff =
        DateTime(now.year, now.month, now.day, config.hour, config.minute)
            .difference(
              DateTime(now.year, now.month, now.day, now.hour, now.minute),
            )
            .inMinutes
            .abs();

    if (timeDiff > 1) return false;

    // Check day of week for weekly schedules
    return config.daysOfWeek.contains(now.weekday);
  }

  void _cancelAllActiveTimers() {
    for (final timer in _activeCountdownTimers.values) {
      timer?.cancel();
    }
    _activeCountdownTimers.clear();
  }

  void _cancelAllScheduledTimers() {
    for (final sub in _scheduledTimerSubscriptions.values) {
      sub?.cancel();
    }
    _scheduledTimerSubscriptions.clear();
  }
}
