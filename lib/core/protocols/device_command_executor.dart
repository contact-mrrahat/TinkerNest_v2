import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../protocols/ble_protocol_handler.dart';

/// Helper class to execute device commands through BLE
class DeviceCommandExecutor {
  final BluetoothCharacteristic? commandCharacteristic;
  final BluetoothCharacteristic? responseCharacteristic;

  DeviceCommandExecutor({
    this.commandCharacteristic,
    this.responseCharacteristic,
  });

  bool get isReady =>
      commandCharacteristic != null && responseCharacteristic != null;

  /// Send a relay control command
  Future<bool> setSwitchState({
    required int switchId,
    required bool state,
  }) async {
    if (!isReady) return false;

    try {
      final command = BleProtocolHandler.generateSetRelayCommand(
        switchId: switchId,
        state: state,
      );

      await commandCharacteristic!.write(
        command.codeUnits,
        withoutResponse: false,
      );

      return true;
    } catch (e) {
      print('Error setting switch state: $e');
      return false;
    }
  }

  /// Send countdown timer command
  Future<bool> setCountdownTimer({
    required int switchId,
    required int durationSeconds,
    required bool targetState,
  }) async {
    if (!isReady) return false;

    try {
      final command = BleProtocolHandler.generateCountdownTimerCommand(
        switchId: switchId,
        durationSeconds: durationSeconds,
        targetState: targetState,
      );

      await commandCharacteristic!.write(
        command.codeUnits,
        withoutResponse: false,
      );

      return true;
    } catch (e) {
      print('Error setting countdown timer: $e');
      return false;
    }
  }

  /// Send scheduled timer command
  Future<bool> setScheduledTimer({
    required int switchId,
    required int hour,
    required int minute,
    required bool targetState,
    required List<int> daysOfWeek,
  }) async {
    if (!isReady) return false;

    try {
      final command = BleProtocolHandler.generateScheduledTimerCommand(
        switchId: switchId,
        hour: hour,
        minute: minute,
        targetState: targetState,
        daysOfWeek: daysOfWeek,
      );

      await commandCharacteristic!.write(
        command.codeUnits,
        withoutResponse: false,
      );

      return true;
    } catch (e) {
      print('Error setting scheduled timer: $e');
      return false;
    }
  }

  /// Send disable timer command
  Future<bool> disableTimer({required int switchId}) async {
    if (!isReady) return false;

    try {
      final command = BleProtocolHandler.generateDisableTimerCommand(
        switchId: switchId,
      );

      await commandCharacteristic!.write(
        command.codeUnits,
        withoutResponse: false,
      );

      return true;
    } catch (e) {
      print('Error disabling timer: $e');
      return false;
    }
  }

  /// Send reset all timers command
  Future<bool> resetAllTimers() async {
    if (!isReady) return false;

    try {
      final command = BleProtocolHandler.generateResetAllTimersCommand();

      await commandCharacteristic!.write(
        command.codeUnits,
        withoutResponse: false,
      );

      return true;
    } catch (e) {
      print('Error resetting all timers: $e');
      return false;
    }
  }
}
