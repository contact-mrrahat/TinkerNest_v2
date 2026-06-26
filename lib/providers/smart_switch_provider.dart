import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:tinkrnest_app/models/timer_model.dart';
import 'package:tinkrnest_app/core/repositories/timer_repository.dart';
import 'package:tinkrnest_app/services/smart_switch_timer_service.dart';

/// Smart Switch Provider - manages switch state and timers
class SmartSwitchProvider extends ChangeNotifier {
  final TimerRepository _repository;
  late final SmartSwitchTimerService _timerService;

  SmartSwitchProvider({required TimerRepository repository})
    : _repository = repository {
    _initializeService();
  }

  // ==================== State ====================
  List<SwitchTimer> _timers = [];
  Map<String, SwitchRuntimeState> _runtimeStates = {};
  bool _isLoading = false;
  String? _error;

  // Getters
  List<SwitchTimer> get timers => List.unmodifiable(_timers);
  Map<String, SwitchRuntimeState> get runtimeStates =>
      Map.unmodifiable(_runtimeStates);
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ==================== Initialization ====================

  void _initializeService() {
    _timerService = SmartSwitchTimerService(
      repository: _repository,
      onTimerTick: _handleTimerTick,
      onTimerComplete: _handleTimerComplete,
      onTimerStateChange: _handleTimerStateChange,
    );
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _loadAllTimers();
      await _loadAllRuntimeStates();
      await _timerService.resumeAllActiveTimers();
      _error = null;
    } catch (e) {
      _error = 'Failed to initialize: $e';
      if (kDebugMode) print('Initialization error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timerService.dispose();
    super.dispose();
  }

  // ==================== Timer Management ====================

  /// Create and save a new countdown timer
  Future<void> createCountdownTimer({
    required String switchId,
    required String name,
    required int durationSeconds,
    required bool targetState,
  }) async {
    try {
      final timerId = _generateId();
      final timer = SwitchTimer(
        id: timerId,
        switchId: switchId,
        timerType: TimerType.countdown,
        countdownConfig: CountdownTimer(
          durationSeconds: durationSeconds,
          targetState: targetState,
        ),
        isEnabled: true,
        name: name,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _repository.saveTimer(timer);
      _timers.add(timer);

      // Start the timer
      await _timerService.startCountdownTimer(timer);

      notifyListeners();
    } catch (e) {
      _error = 'Failed to create timer: $e';
      if (kDebugMode) print('Create timer error: $e');
      notifyListeners();
    }
  }

  /// Create and save a scheduled timer
  Future<void> createScheduledTimer({
    required String switchId,
    required String name,
    required int hour,
    required int minute,
    required bool targetState,
    List<int>? daysOfWeek,
  }) async {
    try {
      final timerId = _generateId();
      final timer = SwitchTimer(
        id: timerId,
        switchId: switchId,
        timerType: TimerType.daily,
        scheduledConfig: ScheduledTimer(
          hour: hour,
          minute: minute,
          targetState: targetState,
          daysOfWeek: daysOfWeek ?? [1, 2, 3, 4, 5, 6, 7],
        ),
        isEnabled: true,
        name: name,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _repository.saveTimer(timer);
      _timers.add(timer);

      // Start the timer
      await _timerService.startScheduledTimer(timer);

      notifyListeners();
    } catch (e) {
      _error = 'Failed to create scheduled timer: $e';
      if (kDebugMode) print('Create scheduled timer error: $e');
      notifyListeners();
    }
  }

  /// Toggle timer enabled state
  Future<void> toggleTimerEnabled(String timerId) async {
    try {
      final timerIndex = _timers.indexWhere((t) => t.id == timerId);
      if (timerIndex == -1) return;

      final timer = _timers[timerIndex];
      final updatedTimer = timer.copyWith(
        isEnabled: !timer.isEnabled,
        updatedAt: DateTime.now(),
      );

      await _repository.saveTimer(updatedTimer);
      _timers[timerIndex] = updatedTimer;

      if (updatedTimer.isEnabled) {
        switch (updatedTimer.timerType) {
          case TimerType.countdown:
            await _timerService.startCountdownTimer(updatedTimer);
            break;
          case TimerType.onTime:
          case TimerType.offTime:
          case TimerType.daily:
          case TimerType.weekly:
            await _timerService.startScheduledTimer(updatedTimer);
            break;
        }
      } else {
        await _timerService.cancelTimer(timerId);
      }

      notifyListeners();
    } catch (e) {
      _error = 'Failed to toggle timer: $e';
      if (kDebugMode) print('Toggle timer error: $e');
      notifyListeners();
    }
  }

  /// Delete a timer
  Future<void> deleteTimer(String timerId) async {
    try {
      await _timerService.cancelTimer(timerId);
      await _repository.deleteTimer(timerId);
      _timers.removeWhere((t) => t.id == timerId);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete timer: $e';
      if (kDebugMode) print('Delete timer error: $e');
      notifyListeners();
    }
  }

  /// Get timers for a specific switch
  List<SwitchTimer> getTimersForSwitch(String switchId) {
    return _timers.where((t) => t.switchId == switchId).toList();
  }

  /// Get runtime state for a switch
  SwitchRuntimeState? getRuntimeState(String switchId) {
    return _runtimeStates[switchId];
  }

  // ==================== Private Methods ====================

  Future<void> _loadAllTimers() async {
    _timers = await _repository.getAllTimers();
  }

  Future<void> _loadAllRuntimeStates() async {
    final states = await _repository.getAllRuntimeStates();
    _runtimeStates = {for (final state in states) state.switchId: state};
  }

  Future<void> _handleTimerTick(
    SwitchTimer timer,
    SwitchRuntimeState state,
  ) async {
    _runtimeStates[state.switchId] = state;
    notifyListeners();
  }

  Future<void> _handleTimerComplete(
    SwitchTimer timer,
    SwitchRuntimeState state,
  ) async {
    _runtimeStates[state.switchId] = state;
    await _repository.saveSwitchRuntimeState(state);
    notifyListeners();
  }

  Future<void> _handleTimerStateChange(
    SwitchTimer timer,
    SwitchRuntimeState state,
  ) async {
    _runtimeStates[state.switchId] = state;
    await _repository.saveSwitchRuntimeState(state);
    notifyListeners();
  }

  String _generateId() => const Uuid().v4();

  /// Clear all timers (for debugging/reset)
  Future<void> clearAllTimers() async {
    await _repository.clearAllData();
    _timers.clear();
    _runtimeStates.clear();
    notifyListeners();
  }
}
