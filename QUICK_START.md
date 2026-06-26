# Quick Start Guide - Smart Switch Timer System

## 🚀 Getting Started in 5 Minutes

### Step 1: Install Dependencies
```bash
cd your_project_directory
flutter pub get
```

### Step 2: Update Your Dashboard Route
Update your app router to use the new dashboard:

```dart
// app_router.dart or your routing configuration
case AppRoutes.dashboard:
  return MaterialPageRoute(
    builder: (_) => const DashboardScreenV2(),
  );
```

### Step 3: Ensure SmartSwitchProvider is Initialized
In `main.dart` (already done):
```dart
final timerRepository = await TimerRepository.create();

runApp(
  MultiProvider(
    providers: [
      // ... existing providers
      ChangeNotifierProvider(
        create: (_) => SmartSwitchProvider(repository: timerRepository),
      ),
    ],
    child: const TinkrNestApp(),
  ),
);
```

### Step 4: Test the Dashboard
```bash
flutter run
```

Navigate to the Dashboard. You should see:
- 4 Smart Switch cards in a grid
- Each with ON/OFF toggle
- Timer icon to configure timers

## 📱 Using the System

### Creating a Timer via UI
1. Tap the timer icon (⏱) on a switch card
2. Choose "Countdown" or "Scheduled"
3. Configure time and target state
4. Tap "Save Timer"

### Creating a Timer Programmatically
```dart
final switchProvider = context.read<SmartSwitchProvider>();

// Countdown (10 minutes)
await switchProvider.createCountdownTimer(
  switchId: 'relay_0',
  name: 'Auto-off',
  durationSeconds: 600,
  targetState: false,
);

// Scheduled (6:00 AM daily)
await switchProvider.createScheduledTimer(
  switchId: 'relay_1',
  name: 'Morning Light',
  hour: 6,
  minute: 0,
  targetState: true,
  daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
);
```

### Monitoring Timer State
```dart
Consumer<SmartSwitchProvider>(
  builder: (context, switchProvider, _) {
    final state = switchProvider.getRuntimeState('relay_0');
    
    return Text(
      'Time remaining: ${state?.remainingSeconds}s'
    );
  },
)
```

### Deleting a Timer
```dart
await switchProvider.deleteTimer(timerId);
```

## 🔌 Device Communication Integration

Add these methods to your BLE provider:

```dart
// In ble_provider.dart

Future<void> setSwitchState(int switchId, bool state) async {
  final command = BleProtocolHandler.generateSetRelayCommand(
    switchId: switchId,
    state: state,
  );
  
  // Send via your BLE service
  await _bleService.writeCommand(command);
}

Future<void> setCountdownTimer({
  required int switchId,
  required int durationSeconds,
  required bool targetState,
}) async {
  final command = BleProtocolHandler.generateCountdownTimerCommand(
    switchId: switchId,
    durationSeconds: durationSeconds,
    targetState: targetState,
  );
  
  await _bleService.writeCommand(command);
}
```

Update SmartSwitchCard to use these:
```dart
// In smart_switch_card.dart

Switch(
  value: isOn,
  onChanged: (value) async {
    await bleProvider.setSwitchState(widget.switchIndex, value);
    widget.onStateChanged?.call(value);
  },
)
```

## 📂 File Structure Summary

```
lib/
├── models/
│   └── timer_model.dart              ✅ Timer data structures
├── providers/
│   └── smart_switch_provider.dart    ✅ State management
├── services/
│   └── smart_switch_timer_service.dart ✅ Timer engine
├── core/
│   ├── repositories/
│   │   └── timer_repository.dart     ✅ Persistence
│   └── protocols/
│       ├── ble_protocol_handler.dart ✅ Device protocol
│       └── device_command_executor.dart ✅ Command sender
└── screens/
    ├── dashboard_screen_v2.dart      ✅ Main dashboard
    ├── dialogs/
    │   └── timer_config_dialog.dart  ✅ Timer settings
    └── widgets/
        └── smart_switch_card.dart    ✅ Switch UI
```

## ✅ Verification Checklist

- [ ] Project builds without errors: `flutter pub get && flutter pub get`
- [ ] Dependencies installed: `flutter doctor -v`
- [ ] Dashboard screen loads
- [ ] Can create timers
- [ ] Timers appear on switch cards
- [ ] Timer dialog works
- [ ] Timers persist after app restart
- [ ] BLE commands are sent when implemented

## 🐛 Common Issues

### Issue: "TimerRepository not found"
**Solution**: Ensure `timer_repository.dart` is in `lib/core/repositories/`

### Issue: "SmartSwitchProvider not in scope"
**Solution**: Make sure it's added to `MultiProvider` in main.dart

### Issue: "SmartSwitchCard not found"
**Solution**: Check file location: `lib/screens/widgets/smart_switch_card.dart`

### Issue: "TimerConfigDialog not found"
**Solution**: Check file location: `lib/screens/dialogs/timer_config_dialog.dart`

### Issue: Import errors in timer_model.dart
**Solution**: Run `flutter pub run build_runner build` to generate JSON serialization code

```bash
flutter pub run build_runner build
# or for watching changes:
flutter pub run build_runner watch
```

## 🎯 Next Steps

1. **Connect to device**: Implement BLE command sending in BleProvider
2. **Test timers**: Create countdown and scheduled timers
3. **Verify persistence**: Kill app and check timers are restored
4. **Add device sync**: Send timers to device's EEPROM
5. **Monitor performance**: Check timer accuracy and memory usage
6. **Deploy**: Build release APK/IPA

## 📖 Full Documentation

For detailed information, see:
- `SMART_SWITCH_DOCUMENTATION.md` - Complete system documentation
- `IMPLEMENTATION_GUIDE.dart` - Detailed integration guide
- `lib/core/examples/smart_switch_examples.dart` - Code examples

## 🆘 Need Help?

1. Check the documentation files above
2. Review example code in `smart_switch_examples.dart`
3. Check console for error messages
4. Verify all files are in correct locations
5. Ensure all dependencies are installed

## 📞 Support

If you encounter issues:
1. Read the error message carefully
2. Check that all files exist in the correct locations
3. Run `flutter pub get` again
4. Clean build cache: `flutter clean && flutter pub get`
5. Review the implementation guide for your specific use case

---

**Status**: Ready to use ✅  
**Last Updated**: 2024-06-26
