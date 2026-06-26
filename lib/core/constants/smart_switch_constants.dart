/// Smart Switch System Constants
library;

// Timer constraints
class TimerConstraints {
  static const int minCountdownSeconds = 1;
  static const int maxCountdownSeconds = 86400; // 24 hours
  static const int minScheduleHour = 0;
  static const int maxScheduleHour = 23;
  static const int minScheduleMinute = 0;
  static const int maxScheduleMinute = 59;
}

// UI dimensions
class SmartSwitchUI {
  static const double switchCardHeight = 200;
  static const double switchCardBorderRadius = 12;
  static const double timerBadgeBorderRadius = 16;
  static const int switchGridColumns = 2;
  static const double switchGridSpacing = 12;
}

// Animation durations
class AnimationDurations {
  static const Duration switchToggle = Duration(milliseconds: 300);
  static const Duration cardEnter = Duration(milliseconds: 400);
  static const Duration timerUpdate = Duration(milliseconds: 500);
  static const Duration dialogOpen = Duration(milliseconds: 300);
}

// Timer update frequencies
class TimerFrequencies {
  static const Duration countdownTickRate = Duration(milliseconds: 500);
  static const Duration scheduleCheckRate = Duration(minutes: 1);
  static const Duration deviceStatusRefresh = Duration(seconds: 5);
}

// Device communication
class DeviceCommands {
  static const String setRelay = 'SET_RELAY';
  static const String setCountdownTimer = 'SET_COUNTDOWN_TIMER';
  static const String setScheduledTimer = 'SET_SCHEDULED_TIMER';
  static const String disableTimer = 'DISABLE_TIMER';
  static const String getStatus = 'GET_STATUS';
  static const String resetAllTimers = 'RESET_ALL_TIMERS';
}

// Response messages
class ResponseMessages {
  static const String timerCreatedSuccess = 'Timer created successfully';
  static const String timerDeletedSuccess = 'Timer deleted successfully';
  static const String timerAppliedSuccess = 'Timer applied to device';
  static const String deviceConnectedSuccess = 'Connected to device';
  static const String deviceDisconnected = 'Disconnected from device';
  static const String commandFailed = 'Command failed. Please try again.';
  static const String invalidDuration = 'Duration must be greater than 0';
  static const String selectAtLeastOneDay = 'Select at least one day';
}

// Error codes
class ErrorCodes {
  static const int connectionFailed = 1001;
  static const int commandTimeout = 1002;
  static const int invalidPayload = 1003;
  static const int deviceNotReady = 1004;
  static const int timerLimitExceeded = 1005;
  static const int storageError = 1006;
}

// Storage keys
class StorageKeys {
  static const String timersKey = 'smart_switch_timers';
  static const String runtimeStateKey = 'smart_switch_runtime_state';
  static const String deviceConfigKey = 'device_config';
  static const String lastSyncKey = 'last_sync_time';
}

// Day of week constants
class DaysOfWeek {
  static const int monday = 1;
  static const int tuesday = 2;
  static const int wednesday = 3;
  static const int thursday = 4;
  static const int friday = 5;
  static const int saturday = 6;
  static const int sunday = 7;

  static const List<int> weekdays = [1, 2, 3, 4, 5];
  static const List<int> weekends = [6, 7];
  static const List<int> allDays = [1, 2, 3, 4, 5, 6, 7];

  static const Map<int, String> dayNames = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  static const Map<int, String> shortDayNames = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };
}

// Relay/Switch indices
class SwitchIndices {
  static const int relay1 = 0;
  static const int relay2 = 1;
  static const int relay3 = 2;
  static const int relay4 = 3;

  static const int maxSwitches = 4;

  static String getSwitchId(int index) => 'relay_$index';
  static String getSwitchName(int index) => 'Relay ${index + 1}';

  static int? parseSwitchIndex(String switchId) {
    if (switchId.startsWith('relay_')) {
      try {
        return int.parse(switchId.split('_')[1]);
      } catch (_) {}
    }
    return null;
  }
}

// Timer types
class TimerTypeNames {
  static const String countdown = 'Countdown Timer';
  static const String onTime = 'Turn On Schedule';
  static const String offTime = 'Turn Off Schedule';
  static const String daily = 'Daily Schedule';
  static const String weekly = 'Weekly Schedule';
}

// Format patterns
class DateTimeFormats {
  static const String timePattern = 'HH:mm';
  static const String datePattern = 'dd/MM/yyyy';
  static const String dateTimePattern = 'dd/MM/yyyy HH:mm:ss';
  static const String isoPattern = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
}

// BLE characteristics (example - update with actual UUIDs)
class BleCharacteristics {
  static const String serviceUuid = '12345678-1234-5678-1234-567812345678';
  static const String commandCharUuid = '12345678-1234-5678-1234-567812345679';
  static const String responseCharUuid = '12345678-1234-5678-1234-567812345680';
  static const String notifyCharUuid = '12345678-1234-5678-1234-567812345681';
}

// Retry policy
class RetryPolicy {
  static const int maxRetries = 3;
  static const Duration initialDelay = Duration(milliseconds: 500);
  static const double backoffMultiplier = 2.0;
  static const Duration maxDelay = Duration(seconds: 10);
}

// Feature flags
class FeatureFlags {
  static const bool enableLocalTimerBackup = true;
  static const bool enableDeviceSync = true;
  static const bool enableAnalytics = false;
  static const bool enableCloudSync = false;
  static const bool enableVoiceControl = false;
  static const bool enableScenes = false;
}

// Default values
class DefaultValues {
  static const int defaultCountdownMinutes = 1;
  static const int defaultCountdownSeconds = 0;
  static const int defaultScheduleHour = 8;
  static const int defaultScheduleMinute = 0;
  static const bool defaultTargetState = true; // ON
  static const List<int> defaultDaysOfWeek = DaysOfWeek.allDays;
}

// Performance metrics
class PerformanceMetrics {
  static const int maxTimersPerSwitch = 10;
  static const int maxTotalTimers = 40;
  static const Duration timerCheckInterval = Duration(seconds: 1);
  static const Duration deviceStatusCacheTime = Duration(seconds: 5);
}

// Logging
class LoggingConfig {
  static const bool enableFileLogging = false;
  static const bool enableConsoleLogging = true;
  static const String logFileName = 'smart_switch.log';
  static const int maxLogSize = 1024 * 1024; // 1 MB
}
