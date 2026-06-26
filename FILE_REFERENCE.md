# 📖 Complete File Reference Guide

## Quick File Lookup

Use this guide to quickly find what you need.

---

## 🎯 Finding What You Need

### "I want to..."

#### Create a Timer
**Files**: 
1. `lib/providers/smart_switch_provider.dart` - Use `createCountdownTimer()` or `createScheduledTimer()`
2. `lib/screens/dialogs/timer_config_dialog.dart` - UI for timer settings
3. Example: `lib/core/examples/smart_switch_examples.dart` - See `TimerCreationExample`

#### Send a Command to Device
**Files**:
1. `lib/core/protocols/ble_protocol_handler.dart` - Generate JSON command
2. `lib/core/protocols/device_command_executor.dart` - Send command via BLE
3. Example: `lib/core/examples/smart_switch_examples.dart` - See `DeviceCommandExample`

#### Monitor Timer State
**Files**:
1. `lib/providers/smart_switch_provider.dart` - `getRuntimeState()` method
2. `lib/models/timer_model.dart` - `SwitchRuntimeState` class
3. Example: `lib/core/examples/smart_switch_examples.dart` - See `TimerMonitoringExample`

#### Persist Data
**Files**:
1. `lib/core/repositories/timer_repository.dart` - All persistence methods
2. `lib/main.dart` - Repository initialization

#### Add New Feature
**Start Here**: `lib/core/constants/smart_switch_constants.dart` - Add constants first
**Then**: Implement in appropriate layer (Model → Repository → Service → Provider → UI)

#### Fix a Bug
**Steps**:
1. Check console for error message
2. See `IMPLEMENTATION_GUIDE.dart` - Troubleshooting section
3. Review error handling in `lib/providers/smart_switch_provider.dart`
4. Check unit tests in `TESTING_GUIDE.md`

#### Write Unit Tests
**Files**:
1. `TESTING_GUIDE.md` - Test templates
2. Review `test/` directory structure
3. Example models in `lib/models/timer_model.dart`

#### Understand Architecture
**Files**:
1. `SMART_SWITCH_DOCUMENTATION.md` - Architecture section
2. `IMPLEMENTATION_GUIDE.dart` - Step-by-step breakdown
3. `PROJECT_COMPLETION_SUMMARY.md` - Architecture diagram

---

## 📁 File Organization by Purpose

### Data Models
```
lib/models/
├── timer_model.dart                    ← ALL timer data structures
│   ├── CountdownTimer
│   ├── ScheduledTimer
│   ├── SwitchTimer
│   └── SwitchRuntimeState
└── device_status.dart                  ← Device status (existing)
```

### State Management
```
lib/providers/
├── smart_switch_provider.dart          ← Main timer provider ⭐
├── ble_provider.dart                   ← BLE communication (existing)
├── auth_provider.dart                  ← Authentication (existing)
└── theme_provider.dart                 ← Theme state (existing)
```

### Data Persistence
```
lib/core/repositories/
└── timer_repository.dart               ← SharedPreferences access ⭐
```

### Business Logic
```
lib/services/
├── smart_switch_timer_service.dart     ← Timer scheduling engine ⭐
└── ble_service.dart                    ← BLE operations (existing)
```

### Device Communication
```
lib/core/protocols/
├── ble_protocol_handler.dart           ← JSON protocol ⭐
└── device_command_executor.dart        ← Command sending ⭐
```

### User Interface
```
lib/screens/
├── dashboard_screen_v2.dart            ← Main dashboard ⭐
├── widgets/
│   └── smart_switch_card.dart          ← Switch UI component ⭐
└── dialogs/
    └── timer_config_dialog.dart        ← Timer settings dialog ⭐
```

### Configuration
```
lib/core/constants/
├── smart_switch_constants.dart         ← System constants ⭐
├── app_routes.dart                     ← Routes (existing)
└── ble_constants.dart                  ← BLE constants (existing)
```

### Examples & Guides
```
lib/core/examples/
└── smart_switch_examples.dart          ← Complete usage examples ⭐
```

### Documentation
```
Project Root/
├── QUICK_START.md                      ← Start here! 5-min guide
├── SMART_SWITCH_DOCUMENTATION.md       ← Complete system docs
├── IMPLEMENTATION_GUIDE.dart           ← Integration steps
├── TESTING_GUIDE.md                    ← Testing strategy
├── PROJECT_COMPLETION_SUMMARY.md       ← Project overview
├── DEVELOPER_CHECKLIST.md              ← Implementation checklist
└── README.md                           ← This file
```

---

## 🔗 File Dependencies

### Initialization Chain
```
main.dart
  ↓
TimerRepository.create() → timer_repository.dart
  ↓
SmartSwitchProvider(repository) → smart_switch_provider.dart
  ↓
SmartSwitchTimerService(repository) → smart_switch_timer_service.dart
```

### Timer Creation Chain
```
TimerConfigDialog (user input)
  ↓
SmartSwitchProvider.createCountdownTimer()
  ↓
TimerRepository.saveTimer()
  ↓
SmartSwitchTimerService.startCountdownTimer()
```

### Device Communication Chain
```
SmartSwitchCard (user action)
  ↓
BleProtocolHandler.generateSetRelayCommand()
  ↓
DeviceCommandExecutor.setSwitchState()
  ↓
BLE Service writeCommand()
  ↓
Device (receives JSON)
```

---

## 📋 Code Snippets by File

### To Use SmartSwitchProvider
```dart
// In any widget with access to BuildContext
final switchProvider = context.read<SmartSwitchProvider>();

// Create timer
await switchProvider.createCountdownTimer(...);

// Get state
final runtimeState = switchProvider.getRuntimeState('relay_0');

// Get timers
final timers = switchProvider.getTimersForSwitch('relay_0');
```

**File**: `lib/providers/smart_switch_provider.dart`

### To Generate Device Command
```dart
// Generate SET_RELAY command
final command = BleProtocolHandler.generateSetRelayCommand(
  switchId: 0,
  state: true,
);

// Parse response
final response = BleProtocolHandler.parseStatusResponse(jsonString);
```

**File**: `lib/core/protocols/ble_protocol_handler.dart`

### To Persist Data
```dart
final repository = await TimerRepository.create();

// Save timer
await repository.saveTimer(timer);

// Get timers
final timers = await repository.getAllTimers();

// Delete timer
await repository.deleteTimer(timerId);
```

**File**: `lib/core/repositories/timer_repository.dart`

### To Monitor Timers
```dart
Consumer<SmartSwitchProvider>(
  builder: (context, switchProvider, _) {
    final state = switchProvider.getRuntimeState('relay_0');
    final timers = switchProvider.getTimersForSwitch('relay_0');
    
    return Text('${state?.remainingSeconds}s remaining');
  },
)
```

**File**: `lib/screens/widgets/smart_switch_card.dart`

---

## 🎨 UI Component Reference

### SmartSwitchCard
**File**: `lib/screens/widgets/smart_switch_card.dart`
**Purpose**: Display individual switch control
**Props**:
- `switchIndex` (0-3)
- `switchName` (e.g., "Relay 1")
- `onTimerTap` (callback)
- `onStateChanged` (callback)

### TimerConfigDialog
**File**: `lib/screens/dialogs/timer_config_dialog.dart`
**Purpose**: Configure timers
**Props**:
- `switchId` (relay ID)
- `switchName` (display name)

### DashboardScreenV2
**File**: `lib/screens/dashboard_screen_v2.dart`
**Purpose**: Main dashboard
**Features**:
- 4-switch grid
- Device status
- Settings menu
- Refresh capability

---

## 🔧 Configuration Reference

### Add New Constant
```dart
// File: lib/core/constants/smart_switch_constants.dart

// Add to appropriate class:
static const String myNewConstant = 'value';
```

### Change Timer Update Frequency
```dart
// File: lib/core/constants/smart_switch_constants.dart

class TimerFrequencies {
  static const Duration countdownTickRate = Duration(milliseconds: 500);
  // Adjust as needed
}
```

### Modify UI Dimensions
```dart
// File: lib/core/constants/smart_switch_constants.dart

class SmartSwitchUI {
  static const double switchCardHeight = 200;
  // Adjust as needed
}
```

### Add BLE Characteristic UUIDs
```dart
// File: lib/core/constants/smart_switch_constants.dart

class BleCharacteristics {
  static const String serviceUuid = 'YOUR_UUID';
  static const String commandCharUuid = 'YOUR_UUID';
  // Add your actual UUIDs
}
```

---

## 🧪 Testing File Reference

### Unit Test Templates
**File**: `TESTING_GUIDE.md`
**Contains**:
- Timer model tests
- Repository tests
- Protocol handler tests

### Example Tests
**File**: `test/` directory (create as needed)
**Structure**:
```
test/
├── models/
│   └── timer_model_test.dart
├── core/
│   └── repositories/
│       └── timer_repository_test.dart
└── integration/
    └── timer_creation_test.dart
```

---

## 📚 Documentation Reference

### For Quick Setup
→ **QUICK_START.md**

### For Complete Understanding
→ **SMART_SWITCH_DOCUMENTATION.md**

### For Integration Steps
→ **IMPLEMENTATION_GUIDE.dart**

### For Testing Strategy
→ **TESTING_GUIDE.md**

### For Project Overview
→ **PROJECT_COMPLETION_SUMMARY.md**

### For Implementation Tracking
→ **DEVELOPER_CHECKLIST.md**

### For Code Examples
→ **lib/core/examples/smart_switch_examples.dart**

---

## 🔍 Searching for Specific Functionality

| Need | File | Function/Class |
|------|------|----------------|
| Create timer | smart_switch_provider.dart | `createCountdownTimer()` |
| Get timer state | smart_switch_provider.dart | `getRuntimeState()` |
| Save to storage | timer_repository.dart | `saveTimer()` |
| Generate command | ble_protocol_handler.dart | `generateSetRelayCommand()` |
| Parse response | ble_protocol_handler.dart | `parseStatusResponse()` |
| Start timer | smart_switch_timer_service.dart | `startCountdownTimer()` |
| Get constants | smart_switch_constants.dart | Class constants |
| UI component | smart_switch_card.dart | `SmartSwitchCard` class |
| Timer dialog | timer_config_dialog.dart | `TimerConfigDialog` class |
| Dashboard | dashboard_screen_v2.dart | `DashboardScreenV2` class |

---

## 🚨 Debugging File Reference

### Getting Error Messages
**Check**: Console output → Search docs → File `IMPLEMENTATION_GUIDE.dart`

### Common Issues
**Check**: `IMPLEMENTATION_GUIDE.dart` → **Troubleshooting Guide** section

### Testing Issues
**Check**: `TESTING_GUIDE.md` → **Debugging Tips** section

### Build Issues
**Check**: `QUICK_START.md` → **Common Issues** section

---

## 📱 Mobile-Specific Files

### Android Configuration
**File**: `android/app/build.gradle.kts`
**Update**: As needed for your device

### iOS Configuration
**File**: `ios/Runner.xcodeproj/project.pbxproj`
**Update**: As needed for your device

### Manifest Files
**Android**: `android/app/src/main/AndroidManifest.xml`
**iOS**: `ios/Runner/Info.plist`

---

## 🔐 Security Files

### Credentials Management
**Note**: Never commit credentials
**Location**: Use environment variables or secure storage
**File**: `lib/main.dart` - Initialize with credentials

### Data Encryption
**Note**: For production, encrypt sensitive data
**Location**: Update `timer_repository.dart` to use encrypted storage

---

## 📊 Performance Monitoring Files

### Add Performance Logging
**File**: `lib/core/constants/smart_switch_constants.dart`
**Section**: `LoggingConfig` class

### Profile App
**Command**: `flutter run --profile`
**Then**: Open DevTools → Performance tab

### Check Memory
**Command**: In DevTools → Memory tab → Monitor allocation

---

## 🎓 Learning Path

1. **Start**: Read `QUICK_START.md` (5 min)
2. **Understand**: Read `SMART_SWITCH_DOCUMENTATION.md` (20 min)
3. **Implement**: Read `IMPLEMENTATION_GUIDE.dart` (30 min)
4. **Code**: Review `lib/core/examples/smart_switch_examples.dart` (15 min)
5. **Test**: Read `TESTING_GUIDE.md` (20 min)
6. **Deploy**: Follow `DEVELOPER_CHECKLIST.md` (Ongoing)

**Total Time**: ~1.5 hours for complete understanding

---

## 📞 Quick Help

| Problem | Solution |
|---------|----------|
| File not found | Check file path in this guide |
| Import error | Verify file is in correct location |
| Runtime error | See `IMPLEMENTATION_GUIDE.dart` troubleshooting |
| Build failure | Run `flutter clean && flutter pub get` |
| Timer not working | Check provider initialization in main.dart |
| UI looks wrong | Verify Material 3 theme is applied |

---

## 🎯 File Checklist

### Created Files ✅
- [x] lib/models/timer_model.dart
- [x] lib/core/repositories/timer_repository.dart
- [x] lib/services/smart_switch_timer_service.dart
- [x] lib/providers/smart_switch_provider.dart
- [x] lib/core/protocols/ble_protocol_handler.dart
- [x] lib/core/protocols/device_command_executor.dart
- [x] lib/screens/dashboard_screen_v2.dart
- [x] lib/screens/widgets/smart_switch_card.dart
- [x] lib/screens/dialogs/timer_config_dialog.dart
- [x] lib/core/constants/smart_switch_constants.dart
- [x] lib/core/examples/smart_switch_examples.dart

### Updated Files ✅
- [x] lib/main.dart
- [x] pubspec.yaml

### Documentation Files ✅
- [x] SMART_SWITCH_DOCUMENTATION.md
- [x] IMPLEMENTATION_GUIDE.dart
- [x] QUICK_START.md
- [x] TESTING_GUIDE.md
- [x] PROJECT_COMPLETION_SUMMARY.md
- [x] DEVELOPER_CHECKLIST.md
- [x] FILE_REFERENCE.md (this file)

---

**Version**: 1.0.0  
**Last Updated**: 2024-06-26  
**Status**: ✅ Complete
