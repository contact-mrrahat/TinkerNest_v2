/// Device status payload returned by the firmware `STATUS` BLE command.
///
/// Example JSON:
/// ```json
/// {
///   "fw": "7.0.0-industrial",
///   "wifi": false,
///   "inet": false,
///   "blynk": false,
///   "t": null,
///   "h": null,
///   "persist": true,
///   "relays": 0
/// }
/// ```
class DeviceStatus {
  const DeviceStatus({
    required this.firmwareVersion,
    required this.wifiConnected,
    required this.internetConnected,
    required this.blynkConnected,
    required this.setupMode,
    required this.bleActive,
    required this.temperatureC,
    required this.humidityPercent,
    required this.persistEnabled,
    required this.relayBitmap,
  });

  final String firmwareVersion;
  final bool wifiConnected;
  final bool internetConnected;
  final bool blynkConnected;
  final bool setupMode;
  final bool bleActive;
  final double? temperatureC;
  final double? humidityPercent;
  final bool persistEnabled;

  /// Relay state bitmap (0–15). Bit 0 = Relay1 … bit 3 = Relay4.
  final int relayBitmap;

  // ---------------------------------------------------------------------------
  // Relay bitmap decoder
  // ---------------------------------------------------------------------------

  /// Returns `true` when the relay at [index] (0–3) is ON.
  static bool relayIsOn(int relayBitmap, int index) {
    if (index < 0 || index > 3) return false;
    return (relayBitmap >> index) & 1 == 1;
  }

  bool get relay1 => relayIsOn(relayBitmap, 0);
  bool get relay2 => relayIsOn(relayBitmap, 1);
  bool get relay3 => relayIsOn(relayBitmap, 2);
  bool get relay4 => relayIsOn(relayBitmap, 3);

  /// All four relay states as `[relay1, relay2, relay3, relay4]`.
  List<bool> get relays => [relay1, relay2, relay3, relay4];

  // ---------------------------------------------------------------------------
  // JSON
  // ---------------------------------------------------------------------------

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    return DeviceStatus(
      firmwareVersion: json['fw']?.toString() ?? '',
      wifiConnected: _readBool(json['wifi']),
      internetConnected: _readBool(json['inet']),
      blynkConnected: _readBool(json['blynk']),
      setupMode: json.containsKey('setup')
          ? _readBool(json['setup'])
          : !_readBool(json['wifi']) && !_readBool(json['blynk']),
      bleActive: _readBool(json['ble']),
      temperatureC: _readNullableDouble(json['t']),
      humidityPercent: _readNullableDouble(json['h']),
      persistEnabled: _readBool(json['persist'], defaultValue: true),
      relayBitmap: _readRelayBitmap(json['relays']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'fw': firmwareVersion,
      'wifi': wifiConnected,
      'inet': internetConnected,
      'blynk': blynkConnected,
      'setup': setupMode,
      'ble': bleActive,
      't': temperatureC,
      'h': humidityPercent,
      'persist': persistEnabled,
      'relays': relayBitmap,
    };
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  DeviceStatus copyWith({
    String? firmwareVersion,
    bool? wifiConnected,
    bool? internetConnected,
    bool? blynkConnected,
    bool? setupMode,
    bool? bleActive,
    double? temperatureC,
    bool clearTemperatureC = false,
    double? humidityPercent,
    bool clearHumidityPercent = false,
    bool? persistEnabled,
    int? relayBitmap,
  }) {
    return DeviceStatus(
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      wifiConnected: wifiConnected ?? this.wifiConnected,
      internetConnected: internetConnected ?? this.internetConnected,
      blynkConnected: blynkConnected ?? this.blynkConnected,
      setupMode: setupMode ?? this.setupMode,
      bleActive: bleActive ?? this.bleActive,
      temperatureC:
          clearTemperatureC ? null : (temperatureC ?? this.temperatureC),
      humidityPercent: clearHumidityPercent
          ? null
          : (humidityPercent ?? this.humidityPercent),
      persistEnabled: persistEnabled ?? this.persistEnabled,
      relayBitmap: relayBitmap ?? this.relayBitmap,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static bool _readBool(Object? value, {bool defaultValue = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return defaultValue;
  }

  static double? _readNullableDouble(Object? value) {
    if (value == null) return null;
    if (value is num) {
      final parsed = value.toDouble();
      if (parsed.isNaN || parsed.isInfinite) return null;
      return parsed;
    }
    return null;
  }

  static int _readRelayBitmap(Object? value) {
    if (value is int) return value.clamp(0, 15);
    if (value is num) return value.toInt().clamp(0, 15);
    return 0;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DeviceStatus &&
            runtimeType == other.runtimeType &&
            firmwareVersion == other.firmwareVersion &&
            wifiConnected == other.wifiConnected &&
            internetConnected == other.internetConnected &&
            blynkConnected == other.blynkConnected &&
            setupMode == other.setupMode &&
            bleActive == other.bleActive &&
            temperatureC == other.temperatureC &&
            humidityPercent == other.humidityPercent &&
            persistEnabled == other.persistEnabled &&
            relayBitmap == other.relayBitmap;
  }

  @override
  int get hashCode => Object.hash(
        firmwareVersion,
        wifiConnected,
        internetConnected,
        blynkConnected,
        setupMode,
        bleActive,
        temperatureC,
        humidityPercent,
        persistEnabled,
        relayBitmap,
      );

  @override
  String toString() {
    return 'DeviceStatus('
        'fw: $firmwareVersion, '
        'wifi: $wifiConnected, '
        'inet: $internetConnected, '
        'blynk: $blynkConnected, '
        'setup: $setupMode, '
        'ble: $bleActive, '
        't: $temperatureC, '
        'h: $humidityPercent, '
        'persist: $persistEnabled, '
        'relays: $relayBitmap, '
        'R1: $relay1, R2: $relay2, R3: $relay3, R4: $relay4'
        ')';
  }
}
