import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:tinkrnest_app/models/timer_model.dart';

/// Repository for managing timer persistence
class TimerRepository {
  static const String _timersKey = 'smart_switch_timers';
  static const String _runtimeStateKey = 'smart_switch_runtime_state';

  final SharedPreferences _prefs;

  TimerRepository(this._prefs);

  /// Factory constructor for initialization
  static Future<TimerRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return TimerRepository(prefs);
  }

  // ==================== Timer Management ====================

  /// Save a single timer
  Future<bool> saveTimer(SwitchTimer timer) async {
    try {
      final timers = await getAllTimers();
      final updatedTimers = timers.where((t) => t.id != timer.id).toList();
      updatedTimers.add(timer);
      return await _saveAllTimers(updatedTimers);
    } catch (e) {
      print('Error saving timer: $e');
      return false;
    }
  }

  /// Get all timers
  Future<List<SwitchTimer>> getAllTimers() async {
    try {
      final jsonString = _prefs.getString(_timersKey);
      if (jsonString == null) return [];

      final jsonList = jsonDecode(jsonString) as List;
      return jsonList
          .map((json) => SwitchTimer.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error getting all timers: $e');
      return [];
    }
  }

  /// Get timers for a specific switch
  Future<List<SwitchTimer>> getTimersForSwitch(String switchId) async {
    try {
      final timers = await getAllTimers();
      return timers.where((t) => t.switchId == switchId).toList();
    } catch (e) {
      print('Error getting timers for switch: $e');
      return [];
    }
  }

  /// Delete a timer
  Future<bool> deleteTimer(String timerId) async {
    try {
      final timers = await getAllTimers();
      final updatedTimers = timers.where((t) => t.id != timerId).toList();
      return await _saveAllTimers(updatedTimers);
    } catch (e) {
      print('Error deleting timer: $e');
      return false;
    }
  }

  /// Delete all timers for a switch
  Future<bool> deleteTimersForSwitch(String switchId) async {
    try {
      final timers = await getAllTimers();
      final updatedTimers = timers
          .where((t) => t.switchId != switchId)
          .toList();
      return await _saveAllTimers(updatedTimers);
    } catch (e) {
      print('Error deleting timers for switch: $e');
      return false;
    }
  }

  // ==================== Runtime State Management ====================

  /// Save switch runtime state
  Future<bool> saveSwitchRuntimeState(SwitchRuntimeState state) async {
    try {
      final states = await getAllRuntimeStates();
      final updatedStates = states
          .where((s) => s.switchId != state.switchId)
          .toList();
      updatedStates.add(state);
      return await _saveAllRuntimeStates(updatedStates);
    } catch (e) {
      print('Error saving runtime state: $e');
      return false;
    }
  }

  /// Get runtime state for a switch
  Future<SwitchRuntimeState?> getRuntimeState(String switchId) async {
    try {
      final states = await getAllRuntimeStates();
      return states.firstWhere(
        (s) => s.switchId == switchId,
        orElse: () => SwitchRuntimeState(switchId: switchId),
      );
    } catch (e) {
      print('Error getting runtime state: $e');
      return null;
    }
  }

  /// Get all runtime states
  Future<List<SwitchRuntimeState>> getAllRuntimeStates() async {
    try {
      final jsonString = _prefs.getString(_runtimeStateKey);
      if (jsonString == null) return [];

      final jsonList = jsonDecode(jsonString) as List;
      return jsonList
          .map(
            (json) => SwitchRuntimeState.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      print('Error getting all runtime states: $e');
      return [];
    }
  }

  // ==================== Private Helpers ====================

  Future<bool> _saveAllTimers(List<SwitchTimer> timers) async {
    try {
      final jsonList = timers.map((t) => t.toJson()).toList();
      return await _prefs.setString(_timersKey, jsonEncode(jsonList));
    } catch (e) {
      print('Error saving all timers: $e');
      return false;
    }
  }

  Future<bool> _saveAllRuntimeStates(List<SwitchRuntimeState> states) async {
    try {
      final jsonList = states.map((s) => s.toJson()).toList();
      return await _prefs.setString(_runtimeStateKey, jsonEncode(jsonList));
    } catch (e) {
      print('Error saving all runtime states: $e');
      return false;
    }
  }

  /// Clear all data (for debugging/reset)
  Future<bool> clearAllData() async {
    try {
      await _prefs.remove(_timersKey);
      await _prefs.remove(_runtimeStateKey);
      return true;
    } catch (e) {
      print('Error clearing data: $e');
      return false;
    }
  }
}
