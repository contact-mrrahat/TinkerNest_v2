// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timer_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CountdownTimer _$CountdownTimerFromJson(Map<String, dynamic> json) =>
    CountdownTimer(
      durationSeconds: (json['durationSeconds'] as num).toInt(),
      targetState: json['targetState'] as bool,
    );

Map<String, dynamic> _$CountdownTimerToJson(CountdownTimer instance) =>
    <String, dynamic>{
      'durationSeconds': instance.durationSeconds,
      'targetState': instance.targetState,
    };

ScheduledTimer _$ScheduledTimerFromJson(Map<String, dynamic> json) =>
    ScheduledTimer(
      hour: (json['hour'] as num).toInt(),
      minute: (json['minute'] as num).toInt(),
      targetState: json['targetState'] as bool,
      daysOfWeek:
          (json['daysOfWeek'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [1, 2, 3, 4, 5, 6, 7],
    );

Map<String, dynamic> _$ScheduledTimerToJson(ScheduledTimer instance) =>
    <String, dynamic>{
      'hour': instance.hour,
      'minute': instance.minute,
      'targetState': instance.targetState,
      'daysOfWeek': instance.daysOfWeek,
    };

SwitchTimer _$SwitchTimerFromJson(Map<String, dynamic> json) => SwitchTimer(
  id: json['id'] as String,
  switchId: json['switchId'] as String,
  timerType: $enumDecode(_$TimerTypeEnumMap, json['timerType']),
  countdownConfig: json['countdownConfig'] == null
      ? null
      : CountdownTimer.fromJson(
          json['countdownConfig'] as Map<String, dynamic>,
        ),
  scheduledConfig: json['scheduledConfig'] == null
      ? null
      : ScheduledTimer.fromJson(
          json['scheduledConfig'] as Map<String, dynamic>,
        ),
  isEnabled: json['isEnabled'] as bool? ?? true,
  name: json['name'] as String? ?? '',
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$SwitchTimerToJson(SwitchTimer instance) =>
    <String, dynamic>{
      'id': instance.id,
      'switchId': instance.switchId,
      'timerType': _$TimerTypeEnumMap[instance.timerType]!,
      'countdownConfig': instance.countdownConfig,
      'scheduledConfig': instance.scheduledConfig,
      'isEnabled': instance.isEnabled,
      'name': instance.name,
      'createdAt': instance.createdAt?.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
    };

const _$TimerTypeEnumMap = {
  TimerType.countdown: 'countdown',
  TimerType.onTime: 'on_time',
  TimerType.offTime: 'off_time',
  TimerType.daily: 'daily',
  TimerType.weekly: 'weekly',
};

SwitchRuntimeState _$SwitchRuntimeStateFromJson(Map<String, dynamic> json) =>
    SwitchRuntimeState(
      switchId: json['switchId'] as String,
      isOn: json['isOn'] as bool? ?? false,
      activeTimerId: json['activeTimerId'] as String?,
      countdownEndTime: json['countdownEndTime'] == null
          ? null
          : DateTime.parse(json['countdownEndTime'] as String),
      lastUpdated: json['lastUpdated'] == null
          ? null
          : DateTime.parse(json['lastUpdated'] as String),
    );

Map<String, dynamic> _$SwitchRuntimeStateToJson(SwitchRuntimeState instance) =>
    <String, dynamic>{
      'switchId': instance.switchId,
      'isOn': instance.isOn,
      'activeTimerId': instance.activeTimerId,
      'countdownEndTime': instance.countdownEndTime?.toIso8601String(),
      'lastUpdated': instance.lastUpdated?.toIso8601String(),
    };
