import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/constants/ble_constants.dart';
import '../models/device_status.dart';

// -----------------------------------------------------------------------------
// Public types
// -----------------------------------------------------------------------------

/// High-level BLE session state exposed to the app layer.
enum BleConnectionState {
  disconnected,
  connecting,
  connected,
  discovering,
  ready,
  reconnecting,
  error,
}

/// Provisioning responses from the firmware status characteristic.
enum ProvisioningStatus {
  testing,
  saved,
  jsonError,
  missingFields,
  wifiFail,
  unknown,
}

/// Parsed provisioning notification.
class ProvisioningMessage {
  const ProvisioningMessage({
    required this.status,
    required this.raw,
  });

  final ProvisioningStatus status;
  final String raw;
}

/// WiFi access point entry from a `WIFI_SCAN` notification.
class WifiAccessPoint {
  const WifiAccessPoint({
    required this.ssid,
    required this.rssi,
    required this.secure,
  });

  final String ssid;
  final int rssi;
  final bool secure;
}

/// Domain-specific BLE failures with optional underlying cause.
class BleServiceException implements Exception {
  const BleServiceException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'BleServiceException: $message${cause == null ? '' : ' ($cause)'}';
}

// -----------------------------------------------------------------------------
// BLE service
// -----------------------------------------------------------------------------

/// Production BLE client for TinkrNest Smart Switch firmware.
///
/// Handles scanning, connection, GATT discovery, notifications, commands,
/// provisioning, STATUS parsing, and optional auto-reconnect.
class BleService {
  BleService({
    Duration scanTimeout = const Duration(seconds: 15),
    Duration commandTimeout = const Duration(seconds: 10),
    Duration provisioningTimeout = const Duration(seconds: 45),
    Duration reconnectDelay = const Duration(seconds: 2),
    int maxReconnectAttempts = 5,
  })  : _scanTimeout = scanTimeout,
        _commandTimeout = commandTimeout,
        _provisioningTimeout = provisioningTimeout,
        _reconnectDelay = reconnectDelay,
        _maxReconnectAttempts = maxReconnectAttempts;

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  final Duration _scanTimeout;
  final Duration _commandTimeout;
  final Duration _provisioningTimeout;
  final Duration _reconnectDelay;
  final int _maxReconnectAttempts;

  static final Guid _serviceGuid = Guid(BleConstants.serviceUuid);
  static final Guid _commandGuid = Guid(BleConstants.commandCharacteristicUuid);
  static final Guid _statusGuid = Guid(BleConstants.statusCharacteristicUuid);

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  BluetoothDevice? _device;
  BluetoothCharacteristic? _commandCharacteristic;
  BluetoothCharacteristic? _statusCharacteristic;

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  bool _autoReconnectEnabled = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _scanStopSubscription;
  bool _nativeScanActive = false;
  StreamSubscription<BluetoothConnectionState>? _deviceConnectionSubscription;
  StreamSubscription<List<int>>? _statusValueSubscription;

  final StreamController<BleConnectionState> _connectionStateController =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<DeviceStatus> _deviceStatusController =
      StreamController<DeviceStatus>.broadcast();
  final StreamController<String> _notificationController =
      StreamController<String>.broadcast();

  final StreamController<List<ScanResult>> _scanResultsController =
      StreamController<List<ScanResult>>.broadcast();

  bool _disposed = false;

  /// Serializes STATUS / WIFI_SCAN / provisioning so responses cannot cross.
  Future<void> _operationChain = Future<void>.value();

  final StringBuffer _rxBuffer = StringBuffer();

  static final RegExp _textNotificationPattern = RegExp(
    r'^(TESTING|OK:SAVED|OK|ERR:[A-Z_]+|R[1-4]:[01]|ALL:[01]|PERSIST:[01])',
  );

  // ---------------------------------------------------------------------------
  // Public streams & getters
  // ---------------------------------------------------------------------------

  /// Connection lifecycle updates.
  Stream<BleConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// Parsed STATUS JSON payloads only.
  Stream<DeviceStatus> get deviceStatusStream => _deviceStatusController.stream;

  /// Raw UTF-8 notification strings from the status characteristic.
  Stream<String> get notificationStream => _notificationController.stream;

  /// Filtered scan results (name or service UUID).
  Stream<List<ScanResult>> get scanResultsStream => _scanResultsController.stream;

  BleConnectionState get connectionState => _connectionState;

  BluetoothDevice? get connectedDevice => _device;

  bool get isConnected => _device?.isConnected ?? false;

  bool get isReady =>
      _connectionState == BleConnectionState.ready &&
      _commandCharacteristic != null &&
      _statusCharacteristic != null;

  bool get autoReconnectEnabled => _autoReconnectEnabled;

  // ---------------------------------------------------------------------------
  // Scan
  // ---------------------------------------------------------------------------

  /// Scans for TinkrNest devices filtered by name and service UUID.
  ///
  /// Returns a stream of cumulative filtered [ScanResult] lists until [stopScan]
  /// is called or [timeout] elapses.
  Stream<List<ScanResult>> scanDevices({
    Duration? timeout,
    bool allowDuplicates = false,
  }) {
    _ensureNotDisposed();
    debugPrint('[BleService] scanDevices requested');

    if (_nativeScanActive) {
      debugPrint('[BleService] scan already running');
      return _scanResultsController.stream;
    }

    final effectiveTimeout = timeout ?? _scanTimeout;
    final seen = <String, ScanResult>{};

    unawaited(_startScanInternal(
      effectiveTimeout: effectiveTimeout,
      allowDuplicates: allowDuplicates,
      seen: seen,
    ));

    return _scanResultsController.stream;
  }

  Future<void> _startScanInternal({
    required Duration effectiveTimeout,
    required bool allowDuplicates,
    required Map<String, ScanResult> seen,
  }) async {
    debugPrint('[BleService] startScan requested');

    if (_nativeScanActive) {
      debugPrint('[BleService] scan already running');
      return;
    }

    try {
      if (await FlutterBluePlus.isScanning.first) {
        debugPrint('[BleService] stopping stale platform scan');
        await FlutterBluePlus.stopScan();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    } catch (_) {
      // Best-effort platform check.
    }

    try {
      await _ensureAdapterReady();

      await _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.onScanResults.listen(
        (results) {
          final filtered = <ScanResult>[];
          for (final result in results) {
            if (!_matchesTinkrNestDevice(result)) continue;
            final id = result.device.remoteId.str;
            if (!allowDuplicates && seen.containsKey(id)) {
              final existing = seen[id]!;
              if (result.rssi <= existing.rssi) continue;
            }
            seen[id] = result;
          }
          filtered.addAll(seen.values.toList()
            ..sort((a, b) => b.rssi.compareTo(a.rssi)));
          if (!_scanResultsController.isClosed) {
            _scanResultsController.add(filtered);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _emitConnectionState(BleConnectionState.error);
          if (!_scanResultsController.isClosed) {
            _scanResultsController.addError(
              BleServiceException('Scan failed.', cause: error),
              stackTrace,
            );
          }
        },
      );

      FlutterBluePlus.cancelWhenScanComplete(_scanSubscription!);

      final usesFineLocation = _androidUsesFineLocationForScan();
      final checkLocationServices = _androidCheckLocationServicesForScan();
      debugPrint(
        '[BleService] startScan — androidUsesFineLocation=$usesFineLocation, '
        'androidCheckLocationServices=$checkLocationServices',
      );

      await FlutterBluePlus.startScan(
        withNames: [BleConstants.deviceName],
        withServices: [_serviceGuid],
        timeout: effectiveTimeout,
        androidUsesFineLocation: usesFineLocation,
        androidCheckLocationServices: checkLocationServices,
      );

      _nativeScanActive = true;
      debugPrint('[BleService] scan started');
      _watchScanStop();
    } on PlatformException catch (error, stackTrace) {
      _nativeScanActive = false;
      final message = error.message ?? error.code;
      debugPrint('[BleService] startScan PlatformException: $message');
      final scanError = BleServiceException(message, cause: error);
      if (!_scanResultsController.isClosed) {
        _scanResultsController.addError(scanError, stackTrace);
      }
      throw scanError;
    } on BleServiceException {
      _nativeScanActive = false;
      rethrow;
    } catch (error, stackTrace) {
      _nativeScanActive = false;
      final message = _scanErrorMessage(error);
      debugPrint('[BleService] startScan failed: $message');
      if (!_scanResultsController.isClosed) {
        _scanResultsController.addError(
          BleServiceException(message, cause: error),
          stackTrace,
        );
      }
      rethrow;
    }
  }

  /// Stops an active BLE scan.
  Future<void> stopScan() async {
    _ensureNotDisposed();
    if (!_nativeScanActive) {
      try {
        if (!await FlutterBluePlus.isScanning.first) return;
      } catch (_) {
        return;
      }
    }

    debugPrint('[BleService] stopScan requested');
    try {
      if (await FlutterBluePlus.isScanning.first) {
        await FlutterBluePlus.stopScan();
      }
    } catch (_) {
      // Ignore stop-scan errors when adapter is unavailable.
    }
    await _scanStopSubscription?.cancel();
    _scanStopSubscription = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _nativeScanActive = false;
    debugPrint('[BleService] scan stopped');
  }

  void _watchScanStop() {
    _scanStopSubscription?.cancel();
    var seenActive = false;
    _scanStopSubscription = FlutterBluePlus.isScanning.listen((scanning) {
      if (scanning) {
        seenActive = true;
        return;
      }
      if (!seenActive || !_nativeScanActive) return;
      _nativeScanActive = false;
      debugPrint('[BleService] scan stopped');
    });
  }

  bool _matchesTinkrNestDevice(ScanResult result) {
    final advName = result.advertisementData.advName;
    if (advName == BleConstants.deviceName) return true;

    final platformName = result.device.platformName;
    if (platformName == BleConstants.deviceName) return true;

    final serviceUuids = result.advertisementData.serviceUuids;
    return serviceUuids.any(
      (uuid) => uuid.str.toLowerCase() == BleConstants.serviceUuid.toLowerCase(),
    );
  }

  // ---------------------------------------------------------------------------
  // Connect / disconnect
  // ---------------------------------------------------------------------------

  /// Connects to [device], discovers GATT services, and enables notifications.
  Future<void> connect(
    BluetoothDevice device, {
    bool enableAutoReconnect = true,
  }) async {
    _ensureNotDisposed();
    _autoReconnectEnabled = enableAutoReconnect;
    _reconnectAttempts = 0;
    _device = device;

    await _connectAndPrepare();
  }

  /// Connects using a persisted [remoteId] from a previous session.
  Future<void> connectById(
    String remoteId, {
    bool enableAutoReconnect = true,
  }) async {
    _ensureNotDisposed();
    final device = BluetoothDevice.fromId(remoteId);
    await connect(device, enableAutoReconnect: enableAutoReconnect);
  }

  /// Disconnects and disables auto-reconnect until the next [connect] call.
  Future<void> disconnect() async {
    _ensureNotDisposed();
    _autoReconnectEnabled = false;
    _cancelReconnectTimer();
    await _tearDownGattSubscriptions();

    final device = _device;
    if (device != null && device.isConnected) {
      try {
        await device.disconnect();
      } catch (error) {
        throw BleServiceException('Disconnect failed.', cause: error);
      }
    }

    _commandCharacteristic = null;
    _statusCharacteristic = null;
    _emitConnectionState(BleConnectionState.disconnected);
  }

  /// Enables or disables auto-reconnect for the current or next session.
  void setAutoReconnectEnabled(bool enabled) {
    _autoReconnectEnabled = enabled;
    if (!enabled) {
      _cancelReconnectTimer();
      _reconnectAttempts = 0;
    }
  }

  Future<void> _connectAndPrepare() async {
    final device = _device;
    if (device == null) {
      throw const BleServiceException('No device selected for connection.');
    }

    _emitConnectionState(BleConnectionState.connecting);

    try {
      await _ensureAdapterReady();

      if (!device.isConnected) {
        await device.connect(
          license: License.free,
          timeout: const Duration(seconds: 15),
          autoConnect: false,
        );
      }

      if (!device.isConnected) {
        await device.connectionState
            .where((state) => state == BluetoothConnectionState.connected)
            .first
            .timeout(const Duration(seconds: 15));
      }

      debugPrint('[BLE] device connected');
      _emitConnectionState(BleConnectionState.connected);
      _listenToDeviceConnection(device);

      try {
        final mtu = await device.requestMtu(512);
        debugPrint('[BLE] MTU negotiated: $mtu');
      } catch (error) {
        debugPrint('[BLE] MTU request failed: $error');
      }

      await discoverServices();
      _reconnectAttempts = 0;
      _emitConnectionState(BleConnectionState.ready);
    } on TimeoutException catch (error) {
      _emitConnectionState(BleConnectionState.error);
      throw BleServiceException('Connection timed out.', cause: error);
    } on BleServiceException {
      _emitConnectionState(BleConnectionState.error);
      rethrow;
    } catch (error) {
      _emitConnectionState(BleConnectionState.error);
      throw BleServiceException('Connection failed.', cause: error);
    }
  }

  void _listenToDeviceConnection(BluetoothDevice device) {
    _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        if (_connectionState == BleConnectionState.reconnecting) {
          unawaited(_handleReconnected(device));
        }
      } else if (state == BluetoothConnectionState.disconnected) {
        _handleUnexpectedDisconnect();
      }
    });

    device.cancelWhenDisconnected(
      _deviceConnectionSubscription!,
      delayed: true,
      next: false,
    );
  }

  Future<void> _handleReconnected(BluetoothDevice device) async {
    try {
      _emitConnectionState(BleConnectionState.discovering);
      await discoverServices();
      _emitConnectionState(BleConnectionState.ready);
    } catch (error) {
      _emitConnectionState(BleConnectionState.error);
      _scheduleReconnect();
    }
  }

  void _handleUnexpectedDisconnect() {
    unawaited(_tearDownGattSubscriptions());
    _commandCharacteristic = null;
    _statusCharacteristic = null;
    _emitConnectionState(BleConnectionState.disconnected);

    if (_autoReconnectEnabled && _device != null) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_autoReconnectEnabled || _device == null || _disposed) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _emitConnectionState(BleConnectionState.error);
      return;
    }

    _cancelReconnectTimer();
    _reconnectAttempts++;
    _emitConnectionState(BleConnectionState.reconnecting);

    _reconnectTimer = Timer(_reconnectDelay, () async {
      if (_disposed || !_autoReconnectEnabled || _device == null) return;
      try {
        await _connectAndPrepare();
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  // ---------------------------------------------------------------------------
  // GATT discovery
  // ---------------------------------------------------------------------------

  /// Discovers services and binds command/status characteristics.
  Future<void> discoverServices() async {
    _ensureNotDisposed();
    final device = _device;
    if (device == null || !device.isConnected) {
      throw const BleServiceException(
        'Cannot discover services while disconnected.',
      );
    }

    _emitConnectionState(BleConnectionState.discovering);

    try {
      final services = await device.discoverServices().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw const BleServiceException(
          'Service discovery timed out.',
        ),
      );
      debugPrint('[BLE] services discovered (count=${services.length})');
      final service = _findService(services, _serviceGuid);
      if (service == null) {
        throw BleServiceException(
          'Service not found: ${BleConstants.serviceUuid}',
        );
      }

      _commandCharacteristic = _findCharacteristic(service, _commandGuid);
      _statusCharacteristic = _findCharacteristic(service, _statusGuid);

      if (_commandCharacteristic == null) {
        throw BleServiceException(
          'Command characteristic not found: '
          '${BleConstants.commandCharacteristicUuid}',
        );
      }
      if (_statusCharacteristic == null) {
        throw BleServiceException(
          'Status characteristic not found: '
          '${BleConstants.statusCharacteristicUuid}',
        );
      }

      debugPrint(
        '[BLE] GATT verified — '
        'service=${BleConstants.serviceUuid}, '
        'command=${BleConstants.commandCharacteristicUuid}, '
        'status=${BleConstants.statusCharacteristicUuid}',
      );

      await _enableNotifications(_statusCharacteristic!);
      await _settleNotifications();
    } on BleServiceException {
      rethrow;
    } catch (error) {
      throw BleServiceException('Service discovery failed.', cause: error);
    }
  }

  /// Clears cached notify payload and gives CCCD time to settle after connect.
  Future<void> _settleNotifications() async {
    _clearRxBuffer();
    final characteristic = _statusCharacteristic;
    if (characteristic != null && characteristic.properties.read) {
      try {
        await characteristic.read();
      } catch (_) {
        // Best-effort drain of stale GATT value.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _clearRxBuffer();
  }

  BluetoothService? _findService(
    List<BluetoothService> services,
    Guid target,
  ) {
    for (final service in services) {
      if (service.uuid == target) return service;
    }
    return null;
  }

  BluetoothCharacteristic? _findCharacteristic(
    BluetoothService service,
    Guid target,
  ) {
    for (final characteristic in service.characteristics) {
      if (characteristic.uuid == target) return characteristic;
    }
    return null;
  }

  Future<void> _enableNotifications(BluetoothCharacteristic characteristic) async {
    await _statusValueSubscription?.cancel();
    _statusValueSubscription = characteristic.onValueReceived.listen(
      _onStatusNotification,
      onError: (Object error, StackTrace stackTrace) {
        if (!_notificationController.isClosed) {
          _notificationController.addError(
            BleServiceException('Notification stream error.', cause: error),
            stackTrace,
          );
        }
      },
    );

    final device = _device;
    if (device != null) {
      device.cancelWhenDisconnected(_statusValueSubscription!);
    }

    if (characteristic.properties.notify ||
        characteristic.properties.indicate) {
      await characteristic.setNotifyValue(true);
      debugPrint(
        '[BLE] notifications enabled on '
        '${BleConstants.statusCharacteristicUuid}',
      );
    } else {
      throw BleServiceException(
        'Status characteristic does not support notifications.',
      );
    }
  }

  void _onStatusNotification(List<int> value) {
    if (value.isEmpty) return;
    _rxBuffer.write(utf8.decode(value, allowMalformed: true));
    _drainRxBuffer();
  }

  void _clearRxBuffer() {
    _rxBuffer.clear();
  }

  void _consumeRxBuffer(int length) {
    final content = _rxBuffer.toString();
    _rxBuffer
      ..clear()
      ..write(content.substring(length));
  }

  int? _findJsonObjectEnd(String content) {
    final start = content.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < content.length; i++) {
      final ch = content[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }

      if (ch == '"') {
        inString = true;
        continue;
      }
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) return i + 1;
      }
    }
    return null;
  }

  void _drainRxBuffer() {
    while (true) {
      var content = _rxBuffer.toString();
      if (content.isEmpty) break;

      content = content.trimLeft();
      if (content.isEmpty) break;

      if (!content.contains('{')) {
        final match = _textNotificationPattern.firstMatch(content);
        if (match == null) {
          if (content.length > 128) _clearRxBuffer();
          break;
        }
        final message = match.group(1)!;
        _consumeRxBuffer(match.end);
        _dispatchNotification(message);
        continue;
      }

      final end = _findJsonObjectEnd(content);
      if (end == null) {
        if (content.length > 4096) _clearRxBuffer();
        break;
      }

      final message = content.substring(0, end).trim();
      _consumeRxBuffer(end);
      _dispatchNotification(message);
    }
  }

  void _dispatchNotification(String raw) {
    if (raw.isEmpty) return;

    debugPrint('[BLE] notify callback: $raw');

    if (!_notificationController.isClosed) {
      _notificationController.add(raw);
    }

    final status = _tryParseDeviceStatus(raw);
    if (status != null && !_deviceStatusController.isClosed) {
      _deviceStatusController.add(status);
    }
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final result = _operationChain.then((_) => operation());
    _operationChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<T> _awaitNotification<T>({
    required Future<void> Function() send,
    required bool Function(String raw) matches,
    required T Function(String raw) parse,
    required Duration timeout,
    String timeoutMessage = 'BLE request timed out.',
  }) {
    return _runExclusive(() async {
      _clearRxBuffer();

      late StreamSubscription<String> subscription;
      final completer = Completer<T>();
      var acceptResponses = false;

      subscription = notificationStream.listen(
        (raw) {
          if (!acceptResponses || completer.isCompleted) return;
          if (!matches(raw)) return;
          completer.complete(parse(raw));
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
      );

      try {
        await send();
        acceptResponses = true;
        return await completer.future.timeout(
          timeout,
          onTimeout: () => throw TimeoutException(timeoutMessage),
        );
      } on TimeoutException catch (error) {
        throw BleServiceException(timeoutMessage, cause: error);
      } finally {
        await subscription.cancel();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Commands
  // ---------------------------------------------------------------------------

  /// Sends a raw UTF-8 command to the command characteristic.
  Future<void> sendCommand(
    String command, {
    bool withoutResponse = true,
  }) async {
    _ensureReady();
    final characteristic = _commandCharacteristic!;

    try {
      await characteristic.write(
        utf8.encode(command),
        withoutResponse: withoutResponse,
      );
    } catch (error) {
      throw BleServiceException(
        'Failed to send command "$command".',
        cause: error,
      );
    }
  }

  /// Requests a fresh STATUS snapshot and waits for the JSON notification.
  Future<DeviceStatus> requestStatus({Duration? timeout}) async {
    _ensureReady();
    final effectiveTimeout = timeout ?? _commandTimeout;
    debugPrint('[STATUS] request started');

    return _awaitNotification<DeviceStatus>(
      timeout: effectiveTimeout,
      timeoutMessage: 'STATUS request timed out.',
      send: () => sendCommand('STATUS', withoutResponse: false),
      matches: (raw) {
        final trimmed = raw.trim();
        if (trimmed.startsWith('ERR:')) return true;
        return _tryParseDeviceStatus(raw) != null;
      },
      parse: (raw) {
        final trimmed = raw.trim();
        if (trimmed.startsWith('ERR:')) {
          throw BleServiceException('STATUS rejected by device: $trimmed');
        }
        final status = _tryParseDeviceStatus(raw);
        if (status == null) {
          throw BleServiceException('Invalid STATUS response.');
        }
        debugPrint('[STATUS] response received: $status');
        return status;
      },
    );
  }

  /// Scans nearby WiFi networks via the connected device.
  Future<List<WifiAccessPoint>> requestWifiScan({
    Duration? timeout,
  }) async {
    _ensureReady();
    final effectiveTimeout = timeout ?? const Duration(seconds: 30);
    debugPrint('[WIFI] scan requested');

    return _awaitNotification<List<WifiAccessPoint>>(
      timeout: effectiveTimeout,
      timeoutMessage: 'WIFI scan timed out.',
      send: () => sendCommand('WIFI_SCAN', withoutResponse: false),
      matches: (raw) {
        final trimmed = raw.trim();
        if (trimmed.startsWith('ERR:')) return true;
        return _tryParseWifiScanResponse(raw) != null;
      },
      parse: (raw) {
        final trimmed = raw.trim();
        if (trimmed.startsWith('ERR:')) {
          final message = trimmed == 'ERR:UNKNOWN'
              ? 'WIFI_SCAN is not supported by this device firmware. '
                  'Flash TinkrNest v7.0 (ESP32 DevKit) and try again.'
              : 'WiFi scan rejected by device: $trimmed';
          throw BleServiceException(message);
        }
        final networks = _tryParseWifiScanResponse(raw);
        if (networks == null) {
          throw BleServiceException('Invalid WIFI_SCAN response.');
        }
        debugPrint('[WIFI] scan response received');
        debugPrint('[WIFI] networks count: ${networks.length}');
        return networks;
      },
    );
  }

  Future<void> setRelay1(bool on) => sendCommand('R1:${on ? 1 : 0}');
  Future<void> setRelay2(bool on) => sendCommand('R2:${on ? 1 : 0}');
  Future<void> setRelay3(bool on) => sendCommand('R3:${on ? 1 : 0}');
  Future<void> setRelay4(bool on) => sendCommand('R4:${on ? 1 : 0}');

  /// Sets relay [relayNumber] where 1 = R1 … 4 = R4.
  Future<void> setRelay(int relayNumber, bool on) {
    if (relayNumber < 1 || relayNumber > 4) {
      throw BleServiceException('Relay number must be between 1 and 4.');
    }
    return sendCommand('R$relayNumber:${on ? 1 : 0}');
  }

  Future<void> setAllRelays(bool on) => sendCommand('ALL:${on ? 1 : 0}');
  Future<void> setPersist(bool enabled) =>
      sendCommand('PERSIST:${enabled ? 1 : 0}');
  Future<void> reboot() => sendCommand('REBOOT');

  // ---------------------------------------------------------------------------
  // Provisioning
  // ---------------------------------------------------------------------------

  /// Sends a provisioning JSON payload and emits firmware provisioning messages.
  ///
  /// Typical sequence: `TESTING` → `OK:SAVED` (then device reboots) or `ERR:*`.
  Stream<ProvisioningMessage> provision(Map<String, dynamic> payload) async* {
    _ensureReady();

    final events = await _runExclusive(() async {
      _clearRxBuffer();

      final messages = <ProvisioningMessage>[];
      var finished = false;
      late final StreamSubscription<String> subscription;

      subscription = notificationStream.listen(
        (raw) {
          final message = _mapProvisioningMessage(raw);
          if (message == null) return;
          messages.add(message);
          if (message.status != ProvisioningStatus.testing) {
            finished = true;
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!finished) {
            finished = true;
          }
        },
      );

      try {
        await sendProvisioningPayload(payload);

        final deadline = DateTime.now().add(_provisioningTimeout);
        while (!finished && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }

        if (!finished) {
          throw const BleServiceException(
            'Provisioning timed out waiting for device response.',
          );
        }

        return List<ProvisioningMessage>.from(messages);
      } finally {
        await subscription.cancel();
      }
    });

    for (final message in events) {
      yield message;
    }
  }

  /// Writes a JSON provisioning payload with response semantics for reliability.
  Future<void> sendProvisioningPayload(Map<String, dynamic> payload) async {
    _ensureReady();
    final characteristic = _commandCharacteristic!;

    try {
      final bytes = utf8.encode(jsonEncode(payload));
      await characteristic.write(
        bytes,
        withoutResponse: false,
        allowLongWrite: true,
        timeout: 30,
      );
    } catch (error) {
      throw BleServiceException(
        'Failed to send provisioning payload.',
        cause: error,
      );
    }
  }

  ProvisioningMessage? _mapProvisioningMessage(String raw) {
    final normalized = raw.trim();

    switch (normalized) {
      case 'TESTING':
        return ProvisioningMessage(
          status: ProvisioningStatus.testing,
          raw: normalized,
        );
      case 'OK:SAVED':
        return ProvisioningMessage(
          status: ProvisioningStatus.saved,
          raw: normalized,
        );
      case 'ERR:JSON':
        return ProvisioningMessage(
          status: ProvisioningStatus.jsonError,
          raw: normalized,
        );
      case 'ERR:MISSING':
        return ProvisioningMessage(
          status: ProvisioningStatus.missingFields,
          raw: normalized,
        );
      case 'ERR:WIFI_FAIL':
        return ProvisioningMessage(
          status: ProvisioningStatus.wifiFail,
          raw: normalized,
        );
      case 'ERR:BUSY':
        return ProvisioningMessage(
          status: ProvisioningStatus.unknown,
          raw: normalized,
        );
      default:
        if (normalized.startsWith('ERR:')) {
          return ProvisioningMessage(
            status: ProvisioningStatus.unknown,
            raw: normalized,
          );
        }
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Parsing helpers
  // ---------------------------------------------------------------------------

  DeviceStatus? _tryParseDeviceStatus(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) return null;
    if (trimmed.contains('"networks"')) return null;

    try {
      final dynamic decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return null;
      if (!decoded.containsKey('fw')) return null;
      return DeviceStatus.fromJson(decoded);
    } catch (error) {
      debugPrint('[BleService] STATUS JSON parse failed: $error');
      return null;
    }
  }

  List<WifiAccessPoint>? _tryParseWifiScanResponse(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) return null;

    try {
      final dynamic decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return null;
      final networks = decoded['networks'];
      if (networks is! List) return null;

      final results = <WifiAccessPoint>[];
      for (final entry in networks) {
        if (entry is! Map<String, dynamic>) continue;
        final ssid = entry['ssid']?.toString().trim() ?? '';
        if (ssid.isEmpty) continue;
        final rssi = entry['rssi'];
        final secureRaw = entry['sec'] ?? entry['secure'];
        results.add(
          WifiAccessPoint(
            ssid: ssid,
            rssi: rssi is num ? rssi.round() : -100,
            secure: secureRaw == true ||
                secureRaw == 1 ||
                secureRaw == '1',
          ),
        );
      }

      results.sort((a, b) => b.rssi.compareTo(a.rssi));
      return results;
    } catch (error) {
      debugPrint('[BleService] WIFI_SCAN JSON parse failed: $error');
      return null;
    }
  }


  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _autoReconnectEnabled = false;
    _cancelReconnectTimer();

    await stopScan();
    await _tearDownGattSubscriptions();

    try {
      if (_device?.isConnected ?? false) {
        await _device!.disconnect();
      }
    } catch (_) {
      // Best-effort disconnect on dispose.
    }

    await _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = null;

    await _connectionStateController.close();
    await _deviceStatusController.close();
    await _notificationController.close();
    await _scanResultsController.close();

    _device = null;
    _commandCharacteristic = null;
    _statusCharacteristic = null;
  }

  Future<void> _tearDownGattSubscriptions() async {
    await _statusValueSubscription?.cancel();
    _statusValueSubscription = null;

    final characteristic = _statusCharacteristic;
    if (characteristic != null) {
      try {
        if (characteristic.isNotifying) {
          await characteristic.setNotifyValue(false);
        }
      } catch (_) {
        // Ignore notify teardown errors.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Internal guards
  // ---------------------------------------------------------------------------

  Future<void> _ensureAdapterReady() async {
    if (await FlutterBluePlus.isSupported == false) {
      throw const BleServiceException('Bluetooth is not supported on this device.');
    }

  await FlutterBluePlus.adapterState
        .where((state) => state == BluetoothAdapterState.on)
        .first
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw const BleServiceException(
            'Bluetooth adapter did not become ready.',
          ),
        );
  }

  void _ensureReady() {
    _ensureNotDisposed();
    if (!isReady) {
      throw const BleServiceException(
        'BLE service is not ready. Connect and discover services first.',
      );
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const BleServiceException('BleService has been disposed.');
    }
  }

  void _emitConnectionState(BleConnectionState state) {
    _connectionState = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  /// Must stay false when BLUETOOTH_SCAN uses neverForLocation (API 31+).
  /// On API <= 30, flutter_blue_plus adds ACCESS_FINE_LOCATION natively.
  bool _androidUsesFineLocationForScan() => false;

  /// Location services gate only needed on legacy Android (API <= 30).
  bool _androidCheckLocationServicesForScan() {
    if (!Platform.isAndroid) return false;
    final sdk = _androidSdkInt();
    if (sdk != null) return sdk <= 30;
    return false;
  }

  int? _androidSdkInt() {
    final version = Platform.operatingSystemVersion;
    final apiMatch = RegExp(r'API[\s-]*(\d+)', caseSensitive: false)
        .firstMatch(version);
    if (apiMatch != null) return int.tryParse(apiMatch.group(1)!);

    const releaseToApi = <int, int>{
      12: 31,
      13: 33,
      14: 34,
      15: 35,
      16: 36,
    };
    for (final part in version.split(RegExp(r'\s+'))) {
      final release = int.tryParse(part);
      if (release == null || release < 1 || release > 99) continue;
      return releaseToApi[release] ?? (release >= 12 ? 31 + (release - 12) : null);
    }
    return null;
  }

  String _scanErrorMessage(Object error) {
    if (error is PlatformException) {
      return error.message ?? error.code;
    }
    if (error is BleServiceException) return error.message;
    return error.toString();
  }
}
