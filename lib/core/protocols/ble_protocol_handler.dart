import 'dart:convert';
import 'dart:typed_data';

import '../models/timer_model.dart';

/// BLE Protocol Handler for Smart Switch device communication
/// Implements JSON-based protocol for relay control and timer management
class BleProtocolHandler {
  static const String _commandPrefix = 'CMD';
  static const String _responsePrefix = 'RESP';

  // ==================== Device Commands ====================

  /// Generate command to set relay state
  static String generateSetRelayCommand({
    required int switchId, // 0-3
    required bool state, // true = ON, false = OFF
  }) {
    final payload = {
      'cmd': 'SET_RELAY',
      'switch_id': switchId,
      'state': state ? 'ON' : 'OFF',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    return jsonEncode(payload);
  }

  /// Generate command to set countdown timer
  static String generateCountdownTimerCommand({
    required int switchId,
    required int durationSeconds,
    required bool targetState,
  }) {
    final payload = {
      'cmd': 'SET_COUNTDOWN_TIMER',
      'switch_id': switchId,
      'timer': {
        'type': 'countdown',
        'duration_seconds': durationSeconds,
        'target_state': targetState ? 'ON' : 'OFF',
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    return jsonEncode(payload);
  }

  /// Generate command to set scheduled timer
  static String generateScheduledTimerCommand({
    required int switchId,
    required int hour,
    required int minute,
    required bool targetState,
    required List<int> daysOfWeek,
  }) {
    final payload = {
      'cmd': 'SET_SCHEDULED_TIMER',
      'switch_id': switchId,
      'timer': {
        'type': 'scheduled',
        'hour': hour,
        'minute': minute,
        'target_state': targetState ? 'ON' : 'OFF',
        'days_of_week': daysOfWeek,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    return jsonEncode(payload);
  }

  /// Generate command to disable timer
  static String generateDisableTimerCommand({
    required int switchId,
  }) {
    final payload = {
      'cmd': 'DISABLE_TIMER',
      'switch_id': switchId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    return jsonEncode(payload);
  }

  /// Generate command to get device status
  static String generateGetStatusCommand() {
    final payload = {
      'cmd': 'GET_STATUS',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    return jsonEncode(payload);
  }

  /// Generate command to reset all timers
  static String generateResetAllTimersCommand() {
    final payload = {
      'cmd': 'RESET_ALL_TIMERS',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    return jsonEncode(payload);
  }

  // ==================== Response Parsing ====================

  /// Parse device status response
  static DeviceStatusResponse? parseStatusResponse(String response) {
    try {
      final json = jsonDecode(response) as Map<String, dynamic>;
      return DeviceStatusResponse.fromJson(json);
    } catch (e) {
      print('Error parsing status response: $e');
      return null;
    }
  }

  /// Parse timer acknowledgment response
  static TimerAckResponse? parseTimerAckResponse(String response) {
    try {
      final json = jsonDecode(response) as Map<String, dynamic>;
      return TimerAckResponse.fromJson(json);
    } catch (e) {
      print('Error parsing timer ack response: $e');
      return null;
    }
  }

  /// Parse generic command acknowledgment
  static CommandAckResponse? parseCommandAckResponse(String response) {
    try {
      final json = jsonDecode(response) as Map<String, dynamic>;
      return CommandAckResponse.fromJson(json);
    } catch (e) {
      print('Error parsing command ack response: $e');
      return null;
    }
  }

  // ==================== Utilities ====================

  /// Convert timer to BLE transport format
  static Map<String, dynamic> timerToJson(SwitchTimer timer) {
    return {
      'id': timer.id,
      'switch_id': timer.switchId,
      'type': timer.timerType.toString().split('.').last,
      'enabled': timer.isEnabled,
      'name': timer.name,
      'countdown': timer.countdownConfig?.toJson(),
      'scheduled': timer.scheduledConfig?.toJson(),
    };
  }

  /// Reconstruct timer from BLE format
  static SwitchTimer? timerFromJson(Map<String, dynamic> json) {
    try {
      final typeStr = json['type'] as String?;
      TimerType? timerType;

      switch (typeStr) {
        case 'countdown':
          timerType = TimerType.countdown;
          break;
        case 'on_time':
          timerType = TimerType.onTime;
          break;
        case 'off_time':
          timerType = TimerType.offTime;
          break;
        case 'daily':
          timerType = TimerType.daily;
          break;
        case 'weekly':
          timerType = TimerType.weekly;
          break;
      }

      if (timerType == null) return null;

      CountdownTimer? countdownConfig;
      if (json['countdown'] != null) {
        countdownConfig = CountdownTimer.fromJson(json['countdown']);
      }

      ScheduledTimer? scheduledConfig;
      if (json['scheduled'] != null) {
        scheduledConfig = ScheduledTimer.fromJson(json['scheduled']);
      }

      return SwitchTimer(
        id: json['id'] as String,
        switchId: json['switch_id'] as String,
        timerType: timerType,
        countdownConfig: countdownConfig,
        scheduledConfig: scheduledConfig,
        isEnabled: json['enabled'] as bool? ?? true,
        name: json['name'] as String? ?? '',
      );
    } catch (e) {
      print('Error reconstructing timer: $e');
      return null;
    }
  }
}

// ==================== Response Models ====================

/// Device status response from firmware
class DeviceStatusResponse {
  final String firmwareVersion;
  final bool wifiConnected;
  final bool internetConnected;
  final int relayBitmap; // 0-15: bit 0 = relay 1, etc.
  final List<int> activeTimers; // Timer IDs active on device
  final Map<String, dynamic>? additionalData;

  DeviceStatusResponse({
    required this.firmwareVersion,
    required this.wifiConnected,
    required this.internetConnected,
    required this.relayBitmap,
    required this.activeTimers,
    this.additionalData,
  });

  factory DeviceStatusResponse.fromJson(Map<String, dynamic> json) {
    return DeviceStatusResponse(
      firmwareVersion: json['fw'] as String? ?? '',
      wifiConnected: json['wifi'] as bool? ?? false,
      internetConnected: json['inet'] as bool? ?? false,
      relayBitmap: json['relays'] as int? ?? 0,
      activeTimers: List<int>.from(json['timers'] as List? ?? []),
      additionalData: json,
    );
  }

  Map<String, dynamic> toJson() => {
        'fw': firmwareVersion,
        'wifi': wifiConnected,
        'inet': internetConnected,
        'relays': relayBitmap,
        'timers': activeTimers,
      };

  bool relayIsOn(int index) {
    if (index < 0 || index > 3) return false;
    return (relayBitmap >> index) & 1 == 1;
  }
}

/// Timer acknowledgment response from firmware
class TimerAckResponse {
  final bool success;
  final String message;
  final String? timerId;
  final int switchId;
  final Map<String, dynamic>? details;

  TimerAckResponse({
    required this.success,
    required this.message,
    this.timerId,
    required this.switchId,
    this.details,
  });

  factory TimerAckResponse.fromJson(Map<String, dynamic> json) {
    return TimerAckResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      timerId: json['timer_id'] as String?,
      switchId: json['switch_id'] as int? ?? -1,
      details: json,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'message': message,
        'timer_id': timerId,
        'switch_id': switchId,
      };
}

/// Generic command acknowledgment
class CommandAckResponse {
  final bool success;
  final String command;
  final String? error;
  final Map<String, dynamic>? data;

  CommandAckResponse({
    required this.success,
    required this.command,
    this.error,
    this.data,
  });

  factory CommandAckResponse.fromJson(Map<String, dynamic> json) {
    return CommandAckResponse(
      success: json['success'] as bool? ?? false,
      command: json['cmd'] as String? ?? '',
      error: json['error'] as String?,
      data: json['data'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'cmd': command,
        'error': error,
        'data': data,
      };
}
