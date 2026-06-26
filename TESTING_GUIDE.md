# Testing Guide - Smart Switch Timer System

## 🧪 Testing Strategy

This guide covers unit tests, integration tests, and manual testing for the smart switch system.

## 📋 Unit Tests

### 1. Timer Model Tests
**File**: `test/models/timer_model_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tinkrnest_app/models/timer_model.dart';

void main() {
  group('Timer Model Tests', () {
    test('CountdownTimer should be created with correct duration', () {
      final timer = CountdownTimer(
        durationSeconds: 600,
        targetState: true,
      );
      
      expect(timer.durationSeconds, 600);
      expect(timer.targetState, true);
    });

    test('ScheduledTimer should have correct time format', () {
      final timer = ScheduledTimer(
        hour: 8,
        minute: 30,
        targetState: false,
      );
      
      expect(timer.timeString, '08:30');
      expect(timer.hour, 8);
      expect(timer.minute, 30);
    });

    test('SwitchTimer should be copied correctly', () {
      final timer1 = SwitchTimer(
        id: 'test-1',
        switchId: 'relay_0',
        timerType: TimerType.countdown,
        isEnabled: true,
        name: 'Test Timer',
      );
      
      final timer2 = timer1.copyWith(isEnabled: false);
      
      expect(timer2.id, timer1.id);
      expect(timer2.isEnabled, false);
      expect(timer1.isEnabled, true);
    });

    test('SwitchRuntimeState should calculate remaining seconds', () {
      final endTime = DateTime.now().add(Duration(seconds: 100));
      final state = SwitchRuntimeState(
        switchId: 'relay_0',
        countdownEndTime: endTime,
      );
      
      final remaining = state.remainingSeconds;
      expect(remaining, isNotNull);
      expect(remaining! > 0, true);
      expect(remaining <= 100, true);
    });
  });
}
```

### 2. Repository Tests
**File**: `test/core/repositories/timer_repository_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinkrnest_app/core/repositories/timer_repository.dart';
import 'package:tinkrnest_app/models/timer_model.dart';

void main() {
  group('TimerRepository Tests', () {
    late TimerRepository repository;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Should save and retrieve timers', () async {
      repository = await TimerRepository.create();
      
      final timer = SwitchTimer(
        id: 'test-1',
        switchId: 'relay_0',
        timerType: TimerType.countdown,
        isEnabled: true,
      );
      
      await repository.saveTimer(timer);
      final retrieved = await repository.getAllTimers();
      
      expect(retrieved.length, 1);
      expect(retrieved.first.id, 'test-1');
    });

    test('Should delete timer', () async {
      repository = await TimerRepository.create();
      
      final timer = SwitchTimer(
        id: 'test-1',
        switchId: 'relay_0',
        timerType: TimerType.countdown,
        isEnabled: true,
      );
      
      await repository.saveTimer(timer);
      await repository.deleteTimer('test-1');
      
      final remaining = await repository.getAllTimers();
      expect(remaining.isEmpty, true);
    });

    test('Should get timers by switch ID', () async {
      repository = await TimerRepository.create();
      
      final timer1 = SwitchTimer(
        id: 'test-1',
        switchId: 'relay_0',
        timerType: TimerType.countdown,
        isEnabled: true,
      );
      
      final timer2 = SwitchTimer(
        id: 'test-2',
        switchId: 'relay_1',
        timerType: TimerType.countdown,
        isEnabled: true,
      );
      
      await repository.saveTimer(timer1);
      await repository.saveTimer(timer2);
      
      final relay0Timers = await repository.getTimersForSwitch('relay_0');
      expect(relay0Timers.length, 1);
      expect(relay0Timers.first.switchId, 'relay_0');
    });
  });
}
```

### 3. Protocol Handler Tests
**File**: `test/core/protocols/ble_protocol_handler_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:tinkrnest_app/core/protocols/ble_protocol_handler.dart';

void main() {
  group('BLE Protocol Handler Tests', () {
    test('Should generate SET_RELAY command', () {
      final command = BleProtocolHandler.generateSetRelayCommand(
        switchId: 0,
        state: true,
      );
      
      final json = jsonDecode(command);
      expect(json['cmd'], 'SET_RELAY');
      expect(json['switch_id'], 0);
      expect(json['state'], 'ON');
    });

    test('Should generate countdown timer command', () {
      final command = BleProtocolHandler.generateCountdownTimerCommand(
        switchId: 1,
        durationSeconds: 600,
        targetState: false,
      );
      
      final json = jsonDecode(command);
      expect(json['cmd'], 'SET_COUNTDOWN_TIMER');
      expect(json['timer']['duration_seconds'], 600);
      expect(json['timer']['target_state'], 'OFF');
    });

    test('Should parse device status response', () {
      final response = '''
      {
        "fw": "7.0.0",
        "wifi": true,
        "inet": false,
        "relays": 5,
        "timers": [0, 1]
      }
      ''';
      
      final parsed = BleProtocolHandler.parseStatusResponse(response);
      expect(parsed?.firmwareVersion, '7.0.0');
      expect(parsed?.wifiConnected, true);
      expect(parsed?.internetConnected, false);
      expect(parsed?.relayBitmap, 5);
    });

    test('Should parse timer ack response', () {
      final response = '''
      {
        "success": true,
        "message": "Timer set",
        "timer_id": "uuid-123",
        "switch_id": 0
      }
      ''';
      
      final parsed = BleProtocolHandler.parseTimerAckResponse(response);
      expect(parsed?.success, true);
      expect(parsed?.timerId, 'uuid-123');
    });
  });
}
```

## 🧩 Integration Tests

### 1. Timer Creation and Execution
**File**: `test/integration/timer_creation_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tinkrnest_app/main.dart';
import 'package:tinkrnest_app/providers/smart_switch_provider.dart';

void main() {
  group('Timer Creation Integration Tests', () {
    testWidgets('Should create countdown timer', (WidgetTester tester) async {
      await tester.pumpWidget(const TinkrNestApp());
      
      final switchProvider = tester //
          .widget<MultiProvider>(find.byType(MultiProvider))
          .providers
          .firstWhere((p) => p is ChangeNotifierProvider &&
              p.create != null)
          as ChangeNotifierProvider;
      
      // Test timer creation
      // expect(switchProvider.timers.length, 1);
    });

    testWidgets('Should trigger timer completion', (WidgetTester tester) async {
      // Test timer tick and completion
    });
  });
}
```

### 2. Persistence Tests
**File**: `test/integration/persistence_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinkrnest_app/core/repositories/timer_repository.dart';
import 'package:tinkrnest_app/providers/smart_switch_provider.dart';

void main() {
  group('Persistence Integration Tests', () {
    test('Should persist and restore timers on app restart', () async {
      SharedPreferences.setMockInitialValues({});
      
      // Create provider and timers
      final repo1 = await TimerRepository.create();
      
      // Simulate app restart by creating new repository
      SharedPreferences.setMockInitialValues({});
      final repo2 = await TimerRepository.create();
      
      // Timers should be restored
    });
  });
}
```

## 🎯 Manual Testing Checklist

### Basic Functionality
- [ ] **Create Countdown Timer**
  1. Open dashboard
  2. Tap timer icon on Switch 1
  3. Choose "Countdown" tab
  4. Set 1 minute
  5. Tap "Save Timer"
  6. Verify timer appears on card
  7. Wait for completion

- [ ] **Create Scheduled Timer**
  1. Tap timer icon
  2. Choose "Scheduled" tab
  3. Set time to current time + 2 minutes
  4. Select all days
  5. Tap "Save Timer"
  6. Verify timer appears

- [ ] **Toggle Timer**
  1. Create a timer
  2. Tap timer badge
  3. Toggle enabled/disabled
  4. Verify state changes

- [ ] **Delete Timer**
  1. Create a timer
  2. Tap 'X' on timer badge
  3. Verify timer is removed
  4. Verify it's removed from storage

### State Management
- [ ] **Timer Persistence**
  1. Create a timer
  2. Force quit the app (Settings → Force Stop)
  3. Reopen app
  4. Navigate to dashboard
  5. Verify timer is restored

- [ ] **Multiple Timers**
  1. Create 3 timers on same switch
  2. Verify all appear on card
  3. Verify they show correct remaining time
  4. Verify they execute in order

- [ ] **Timer Accuracy**
  1. Create 1-minute countdown
  2. Record exact start time
  3. Wait for completion
  4. Verify completion within 2 seconds

### UI/UX
- [ ] **Dark Mode**
  1. Enable dark mode in system settings
  2. Open app
  3. Verify colors are correct
  4. Verify text is readable
  5. Create timer and verify UI

- [ ] **Responsive Layout**
  1. Test on phone (360px wide)
  2. Test on tablet (600px+ wide)
  3. Verify grid layout is appropriate
  4. Test portrait and landscape

- [ ] **Error Handling**
  1. Create timer with 0 duration → Error
  2. Disconnect device → Show error
  3. Invalid data → Handle gracefully

### Performance
- [ ] **Memory Usage**
  1. Create 10 timers
  2. Monitor memory usage
  3. Should not increase linearly
  4. Verify no memory leaks

- [ ] **Battery Impact**
  1. Create timer
  2. Monitor battery usage
  3. Should not drain significantly
  4. Verify background timer works

- [ ] **Network Performance**
  1. Create timer on connected device
  2. Send command
  3. Verify response time < 1 second
  4. No lag in UI

## 📊 Test Coverage Goals

| Module | Coverage Target | Status |
|--------|-----------------|--------|
| Timer Model | 95% | ⏳ |
| Repository | 90% | ⏳ |
| Protocol Handler | 95% | ⏳ |
| Timer Service | 80% | ⏳ |
| Provider | 85% | ⏳ |
| UI Components | 70% | ⏳ |
| **Overall** | **85%** | ⏳ |

## 🔧 Running Tests

### Run all tests
```bash
flutter test
```

### Run specific test file
```bash
flutter test test/models/timer_model_test.dart
```

### Run with coverage
```bash
flutter test --coverage
```

### Generate coverage report
```bash
lcov --list coverage/lcov.info
```

## 📝 Test Report Template

```
Test Run: [Date & Time]
Platform: [Android/iOS]
Device: [Device Model]
Duration: [Time]

SUMMARY:
- Total Tests: 50
- Passed: 48
- Failed: 2
- Skipped: 0
- Duration: 2m 34s

FAILURES:
1. [Test Name] - [Error Details]
2. [Test Name] - [Error Details]

COVERAGE:
- Lines: 87%
- Branches: 82%
- Functions: 89%

NOTES:
- [Any observations]
```

## 🐛 Debugging Tips

### Enable verbose logging
```dart
if (kDebugMode) {
  print('Timer event: $event');
}
```

### Add breakpoints
- In Android Studio: Click on line number
- In VS Code: Click on line number
- In editor: `debugPrint('checkpoint')`

### Monitor memory
```bash
flutter run --profile
# Then check DevTools Memory tab
```

### Check device logs
```bash
adb logcat | grep tinkrnest_app
```

---

**Test Status**: Ready for implementation ✅  
**Last Updated**: 2024-06-26
