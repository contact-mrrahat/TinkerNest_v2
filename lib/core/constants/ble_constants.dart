/// BLE GATT identifiers for TinkrNest Smart Switch firmware (NimBLE / NUS-style).
abstract final class BleConstants {
  /// Advertised BLE device name during setup mode.
  static const String deviceName = 'TinkrNest Setup';

  /// Primary GATT service UUID.
  static const String serviceUuid =
      '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

  /// Command characteristic — write provisioning JSON and text commands.
  static const String commandCharacteristicUuid =
      '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

  /// Status characteristic — read and subscribe for notifications.
  static const String statusCharacteristicUuid =
      '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
}
