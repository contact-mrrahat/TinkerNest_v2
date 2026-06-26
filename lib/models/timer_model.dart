import 'package:json_annotation/json_annotation.dart';

part 'timer_model.g.dart';

/// Timer type enumeration
enum TimerType {
  @JsonValue('countdown')
  countdown, // 10 minutes, 1 hour, etc.
  @JsonValue('on_time')
  onTime, // Turn ON at specific time (e.g., 08:00 AM)
  @JsonValue('off_time')
  offTime, // Turn OFF at specific time (e.g., 06:00 PM)
  @JsonValue('daily')
  daily, // Repeat daily at specific time
  @JsonValue('weekly')
  weekly, // Repeat weekly at specific day & time
}

/// Countdown timer configuration
@JsonSerializable()
class CountdownTimer {
  const CountdownTimer({
    required this.durationSeconds,
    required this.targetState, // true = ON, false = OFF
  });

  final int durationSeconds;
  final bool targetState;

  factory CountdownTimer.fromJson(Map<String, dynamic> json) =>
      _$CountdownTimerFromJson(json);

  Map<String, dynamic> toJson() => _$CountdownTimerToJson(this);

  CountdownTimer copyWith({
    int? durationSeconds,
    bool? targetState,
  }) =>
      CountdownTimer(
        durationSeconds: durationSeconds ?? this.durationSeconds,
        targetState: targetState ?? this.targetState,
      );
}

/// Scheduled timer configuration (specific time)
@JsonSerializable()
class ScheduledTimer {
  const ScheduledTimer({
    required this.hour,
    required this.minute,
    required this.targetState, // true = ON, false = OFF
    this.daysOfWeek = const [1, 2, 3, 4, 5, 6, 7], // 1-7 (Mon-Sun)
  });

  final int hour; // 0-23
  final int minute; // 0-59
  final bool targetState;
  final List<int> daysOfWeek; // Only for weekly schedules

  factory ScheduledTimer.fromJson(Map<String, dynamic> json) =>
      _$ScheduledTimerFromJson(json);

  Map<String, dynamic> toJson() => _$ScheduledTimerToJson(this);

  ScheduledTimer copyWith({
    int? hour,
    int? minute,
    bool? targetState,
    List<int>? daysOfWeek,
  }) =>
      ScheduledTimer(
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        targetState: targetState ?? this.targetState,
        daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      );

  String get timeString =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Main timer configuration for a switch
@JsonSerializable()
class SwitchTimer {
  const SwitchTimer({
    required this.id,
    required this.switchId,
    required this.timerType,
    this.countdownConfig,
    this.scheduledConfig,
    this.isEnabled = true,
    this.name = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String switchId;
  final TimerType timerType;
  final CountdownTimer? countdownConfig;
  final ScheduledTimer? scheduledConfig;
  final bool isEnabled;
  final String name;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory SwitchTimer.fromJson(Map<String, dynamic> json) =>
      _$SwitchTimerFromJson(json);

  Map<String, dynamic> toJson() => _$SwitchTimerToJson(this);

  SwitchTimer copyWith({
    String? id,
    String? switchId,
    TimerType? timerType,
    CountdownTimer? countdownConfig,
    ScheduledTimer? scheduledConfig,
    bool? isEnabled,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      SwitchTimer(
        id: id ?? this.id,
        switchId: switchId ?? this.switchId,
        timerType: timerType ?? this.timerType,
        countdownConfig: countdownConfig ?? this.countdownConfig,
        scheduledConfig: scheduledConfig ?? this.scheduledConfig,
        isEnabled: isEnabled ?? this.isEnabled,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Switch runtime state (for tracking active timers)
@JsonSerializable()
class SwitchRuntimeState {
  const SwitchRuntimeState({
    required this.switchId,
    this.isOn = false,
    this.activeTimerId,
    this.countdownEndTime,
    this.lastUpdated,
  });

  final String switchId;
  final bool isOn;
  final String? activeTimerId;
  final DateTime? countdownEndTime;
  final DateTime? lastUpdated;

  factory SwitchRuntimeState.fromJson(Map<String, dynamic> json) =>
      _$SwitchRuntimeStateFromJson(json);

  Map<String, dynamic> toJson() => _$SwitchRuntimeStateToJson(this);

  SwitchRuntimeState copyWith({
    String? switchId,
    bool? isOn,
    String? activeTimerId,
    DateTime? countdownEndTime,
    DateTime? lastUpdated,
  }) =>
      SwitchRuntimeState(
        switchId: switchId ?? this.switchId,
        isOn: isOn ?? this.isOn,
        activeTimerId: activeTimerId ?? this.activeTimerId,
        countdownEndTime: countdownEndTime ?? this.countdownEndTime,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );

  int? get remainingSeconds {
    if (countdownEndTime == null) return null;
    final remaining = countdownEndTime!.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : null;
  }
}
