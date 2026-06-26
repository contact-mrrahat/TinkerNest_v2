import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/device_status.dart';
import '../services/ble_service.dart';

/// Application-layer BLE state owner backed by [BleService].
class BleProvider extends ChangeNotifier {
  BleProvider({BleService? bleService})
      : _bleService = bleService ?? BleService() {
    _bindServiceStreams();
  }

  final BleService _bleService;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BleConnectionState>? _connectionSubscription;
  StreamSubscription<DeviceStatus>? _statusSubscription;
  StreamSubscription<String>? _notificationSubscription;

  bool _notifyScheduled = false;
  bool _lastLoggedScanning = false;
  int _lastLoggedDeviceCount = -1;

  // ---------------------------------------------------------------------------
  // Scan state
  // ---------------------------------------------------------------------------

  bool _isScanning = false;
  List<ScanResult> _availableDevices = const [];

  bool get isScanning => _isScanning;
  List<ScanResult> get availableDevices => List.unmodifiable(_availableDevices);

  // ---------------------------------------------------------------------------
  // Connection state
  // ---------------------------------------------------------------------------

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  bool _autoReconnectEnabled = false;

  BleConnectionState get connectionState => _connectionState;
  bool get autoReconnectEnabled => _autoReconnectEnabled;
  bool get isAutoReconnecting =>
      _connectionState == BleConnectionState.reconnecting;

  bool get isConnecting =>
      _isConnecting ||
      _connectionState == BleConnectionState.connecting ||
      _connectionState == BleConnectionState.discovering ||
      _connectionState == BleConnectionState.reconnecting;

  bool get isConnected =>
      _bleService.isReady ||
      _connectionState == BleConnectionState.ready;

  BluetoothDevice? get connectedDevice => _bleService.connectedDevice;

  // ---------------------------------------------------------------------------
  // Device status
  // ---------------------------------------------------------------------------

  DeviceStatus? _deviceStatus;

  DeviceStatus? get deviceStatus => _deviceStatus;

  // ---------------------------------------------------------------------------
  // WiFi scan
  // ---------------------------------------------------------------------------

  List<WifiAccessPoint> _wifiNetworks = const [];
  bool _isWifiScanning = false;

  List<WifiAccessPoint> get wifiNetworks => List.unmodifiable(_wifiNetworks);
  bool get isWifiScanning => _isWifiScanning;

  // ---------------------------------------------------------------------------
  // Provisioning
  // ---------------------------------------------------------------------------

  ProvisioningStatus? _provisioningStatus;
  bool _isProvisioning = false;
  String? _provisioningRawMessage;

  ProvisioningStatus? get provisioningStatus => _provisioningStatus;
  bool get isProvisioning => _isProvisioning;
  String? get provisioningRawMessage => _provisioningRawMessage;

  // ---------------------------------------------------------------------------
  // Loading & errors
  // ---------------------------------------------------------------------------

  bool _isConnecting = false;
  bool _isCommandInFlight = false;
  String? _lastError;

  bool get isCommandInFlight => _isCommandInFlight;
  String? get lastError => _lastError;

  bool get isBusy =>
      _isScanning ||
      isConnecting ||
      _isProvisioning ||
      _isWifiScanning ||
      _isCommandInFlight;

  // ---------------------------------------------------------------------------
  // Scan
  // ---------------------------------------------------------------------------

  /// Starts scanning for TinkrNest devices and updates [availableDevices].
  Future<void> startScan({Duration? timeout}) async {
    debugPrint('[BleProvider] startScan requested');
    _clearError();

    if (_isScanning) {
      debugPrint('[BleProvider] scan already running');
      return;
    }

    try {
      if (await FlutterBluePlus.isScanning.first) {
        debugPrint('[BleProvider] stopping stale platform scan');
        await _bleService.stopScan();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    } catch (_) {
      // Best-effort platform check.
    }

    _isScanning = true;
    _availableDevices = const [];
    _safeNotifyListeners('startScan: scan started');

    final effectiveTimeout = timeout ?? const Duration(seconds: 15);
    final scanStream = _bleService.scanDevices(timeout: effectiveTimeout);

    await _scanSubscription?.cancel();
    _scanSubscription = scanStream.listen(
      (results) => _applyScanResults(results),
      onError: (Object error, StackTrace stackTrace) {
        _setError(_errorMessage(error));
        _isScanning = false;
        debugPrint('[BleProvider] scan stopped (error)');
        _safeNotifyListeners('scan stream: error');
      },
    );

    debugPrint('[BleProvider] scan started');
    unawaited(_completeScanWhenFinished(effectiveTimeout));
  }

  Future<void> _completeScanWhenFinished(Duration timeout) async {
    try {
      await FlutterBluePlus.isScanning
          .firstWhere((scanning) => scanning)
          .timeout(const Duration(seconds: 10));
      await FlutterBluePlus.isScanning
          .firstWhere((scanning) => !scanning)
          .timeout(timeout + const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[BleProvider] scan session ended: $e');
    } finally {
      if (_isScanning) {
        _isScanning = false;
        debugPrint('[BleProvider] scan stopped');
        _safeNotifyListeners('scan complete');
      }
    }
  }

  /// Stops an active device scan.
  Future<void> stopScan() async {
    debugPrint('[BleProvider] stopScan requested');
    try {
      await _bleService.stopScan();
    } catch (error) {
      _setError(_errorMessage(error));
    } finally {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      if (_isScanning) {
        _isScanning = false;
        debugPrint('[BleProvider] scan stopped');
      }
      _safeNotifyListeners('stopScan');
    }
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  /// Connects to a scanned device and prepares the GATT session.
  Future<void> connect(
    BluetoothDevice device, {
    bool enableAutoReconnect = true,
  }) async {
    debugPrint('[BLE] connect requested');
    _clearError();
    _isConnecting = true;
    _safeNotifyListeners('connect: started');

    try {
      await stopScan();
      await _bleService.connect(
        device,
        enableAutoReconnect: enableAutoReconnect,
      );
      _autoReconnectEnabled = enableAutoReconnect;
      debugPrint(
        '[BLE] provider state updated '
        '(connectionState=$_connectionState, '
        'device=${_bleService.connectedDevice?.remoteId.str}, '
        'isReady=${_bleService.isReady})',
      );
      await refreshStatus();
    } catch (error) {
      debugPrint('[BLE] connect failed: $error');
      _setError(_errorMessage(error));
      rethrow;
    } finally {
      _isConnecting = false;
      _safeNotifyListeners('connect: finished');
    }
  }

  /// Connects using a persisted remote device id.
  Future<void> connectById(
    String remoteId, {
    bool enableAutoReconnect = true,
  }) async {
    _clearError();
    _isConnecting = true;
    _safeNotifyListeners('connectById: started');

    try {
      await _bleService.connectById(
        remoteId,
        enableAutoReconnect: enableAutoReconnect,
      );
      _autoReconnectEnabled = enableAutoReconnect;
      await refreshStatus();
    } catch (error) {
      _setError(_errorMessage(error));
      rethrow;
    } finally {
      _isConnecting = false;
      _safeNotifyListeners('connectById: finished');
    }
  }

  /// Disconnects from the current device.
  Future<void> disconnect() async {
    _clearError();

    try {
      await _bleService.disconnect();
      _autoReconnectEnabled = false;
      _deviceStatus = null;
    } catch (error) {
      _setError(_errorMessage(error));
      rethrow;
    } finally {
      _safeNotifyListeners('disconnect');
    }
  }

  /// Enables or disables BLE auto-reconnect on the underlying service.
  void setAutoReconnectEnabled(bool enabled) {
    _bleService.setAutoReconnectEnabled(enabled);
    _autoReconnectEnabled = enabled;
    _safeNotifyListeners('setAutoReconnectEnabled');
  }

  // ---------------------------------------------------------------------------
  // Device status
  // ---------------------------------------------------------------------------

  /// Requests a fresh STATUS snapshot from the device.
  Future<DeviceStatus?> refreshStatus() async {
    _clearError();

    try {
      final status = await _bleService.requestStatus();
      _deviceStatus = status;
      _safeNotifyListeners('refreshStatus: success');
      return status;
    } catch (error) {
      debugPrint('[STATUS] request failed: $error');
      _setError(_errorMessage(error));
      _safeNotifyListeners('refreshStatus: error');
      return null;
    }
  }

  /// Scans nearby WiFi networks through the connected device.
  Future<List<WifiAccessPoint>> scanWifiNetworks() async {
    _clearError();
    _isWifiScanning = true;
    _wifiNetworks = const [];
    _safeNotifyListeners('scanWifiNetworks: started');

    try {
      final networks = await _bleService.requestWifiScan();
      _wifiNetworks = networks;
      _safeNotifyListeners('scanWifiNetworks: success');
      return networks;
    } catch (error) {
      debugPrint('[WIFI] scan failed: $error');
      _setError(_errorMessage(error));
      _safeNotifyListeners('scanWifiNetworks: error');
      rethrow;
    } finally {
      _isWifiScanning = false;
      _safeNotifyListeners('scanWifiNetworks: finished');
    }
  }

  // ---------------------------------------------------------------------------
  // Relay control
  // ---------------------------------------------------------------------------

  Future<void> toggleRelay1() => _toggleRelay(1);
  Future<void> toggleRelay2() => _toggleRelay(2);
  Future<void> toggleRelay3() => _toggleRelay(3);
  Future<void> toggleRelay4() => _toggleRelay(4);

  Future<void> allOn() => _runCommand(() => _bleService.setAllRelays(true));

  Future<void> allOff() => _runCommand(() => _bleService.setAllRelays(false));

  Future<void> _toggleRelay(int relayNumber) {
    final current = _deviceStatus;
    final isOn = switch (relayNumber) {
      1 => current?.relay1 ?? false,
      2 => current?.relay2 ?? false,
      3 => current?.relay3 ?? false,
      4 => current?.relay4 ?? false,
      _ => false,
    };

    return _runCommand(() => _bleService.setRelay(relayNumber, !isOn));
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<void> enablePersist() =>
      _runCommand(() => _bleService.setPersist(true));

  Future<void> disablePersist() =>
      _runCommand(() => _bleService.setPersist(false));

  // ---------------------------------------------------------------------------
  // Provisioning
  // ---------------------------------------------------------------------------

  /// Sends WiFi + Blynk provisioning JSON to the connected device.
  ///
  /// Expected keys: `ssid`, `pass`, `auth`, optional `tplId`, `tplName`.
  Future<void> sendProvisioningData(Map<String, dynamic> payload) async {
    _clearError();
    _isProvisioning = true;
    _provisioningStatus = null;
    _provisioningRawMessage = null;
    setAutoReconnectEnabled(false);
    _safeNotifyListeners('sendProvisioningData: started');

    try {
      await for (final message in _bleService.provision(payload)) {
        _provisioningStatus = message.status;
        _provisioningRawMessage = message.raw;
        _safeNotifyListeners('sendProvisioningData: progress');

        if (message.status != ProvisioningStatus.testing) {
          break;
        }
      }
    } catch (error) {
      // OK:SAVED may have arrived before BLE dropped on reboot.
      if (_provisioningStatus == ProvisioningStatus.saved) {
        _safeNotifyListeners('sendProvisioningData: saved despite disconnect');
      } else {
        _setError(_errorMessage(error));
        _provisioningStatus = ProvisioningStatus.unknown;
        _safeNotifyListeners('sendProvisioningData: error');
        rethrow;
      }
    } finally {
      _isProvisioning = false;
      _safeNotifyListeners('sendProvisioningData: finished');
    }
  }

  /// Marks provisioning complete and stops BLE reconnect churn after reboot.
  Future<void> finalizeProvisioningSession() async {
    setAutoReconnectEnabled(false);
    _deviceStatus = null;
    try {
      await _bleService.disconnect();
    } catch (_) {
      // Device may already have rebooted.
    }
    _safeNotifyListeners('finalizeProvisioningSession');
  }

  /// Clears the last provisioning result.
  void clearProvisioningStatus() {
    _provisioningStatus = null;
    _provisioningRawMessage = null;
    _safeNotifyListeners('clearProvisioningStatus');
  }

  // ---------------------------------------------------------------------------
  // Errors
  // ---------------------------------------------------------------------------

  /// Clears [lastError].
  void clearError() {
    _lastError = null;
    _safeNotifyListeners('clearError');
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    unawaited(_scanSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    unawaited(_notificationSubscription?.cancel());
    unawaited(_bleService.dispose());
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _bindServiceStreams() {
    _connectionSubscription =
        _bleService.connectionStateStream.listen((state) {
      if (_connectionState == state &&
          _autoReconnectEnabled == _bleService.autoReconnectEnabled) {
        return;
      }
      _connectionState = state;
      _autoReconnectEnabled = _bleService.autoReconnectEnabled;
      debugPrint(
        '[BLE] provider state updated '
        '(connectionState=$state, '
        'device=${_bleService.connectedDevice?.remoteId.str})',
      );
      _safeNotifyListeners('connectionStateStream');
    });

    _statusSubscription = _bleService.deviceStatusStream.listen((status) {
      _deviceStatus = status;
      _safeNotifyListeners('deviceStatusStream');
    });

    _notificationSubscription =
        _bleService.notificationStream.listen(_onRawNotification);
  }

  void _onRawNotification(String raw) {
    final trimmed = raw.trim();
    final relayMatch = RegExp(r'^R([1-4]):([01])$').firstMatch(trimmed);
    if (relayMatch != null) {
      final idx = int.parse(relayMatch.group(1)!) - 1;
      final on = relayMatch.group(2) == '1';
      final current = _deviceStatus;
      if (current == null || idx < 0 || idx > 3) return;
      final bit = 1 << idx;
      final newBitmap = on
          ? current.relayBitmap | bit
          : current.relayBitmap & ~bit;
      if (newBitmap == current.relayBitmap) return;
      _deviceStatus = current.copyWith(relayBitmap: newBitmap);
      _safeNotifyListeners('relayNotification');
      return;
    }

    if (trimmed == 'ALL:1' || trimmed == 'ALL:0') {
      final current = _deviceStatus;
      if (current == null) return;
      final newBitmap = trimmed == 'ALL:1' ? 0x0F : 0x00;
      if (newBitmap == current.relayBitmap) return;
      _deviceStatus = current.copyWith(relayBitmap: newBitmap);
      _safeNotifyListeners('relayNotification');
      return;
    }

    if (trimmed == 'PERSIST:1' || trimmed == 'PERSIST:0') {
      final current = _deviceStatus;
      if (current == null) return;
      final enabled = trimmed == 'PERSIST:1';
      if (enabled == current.persistEnabled) return;
      _deviceStatus = current.copyWith(persistEnabled: enabled);
      _safeNotifyListeners('persistNotification');
    }
  }

  Future<void> _runCommand(Future<void> Function() action) async {
    _clearError();
    _isCommandInFlight = true;
    _safeNotifyListeners('_runCommand: started');

    try {
      await action();
      await refreshStatus();
    } catch (error) {
      _setError(_errorMessage(error));
      rethrow;
    } finally {
      _isCommandInFlight = false;
      _safeNotifyListeners('_runCommand: finished');
    }
  }

  /// Defers [notifyListeners] to the next frame to avoid rebuilds during
  /// layout/semantics (parentDataDirty assertion loops).
  void _safeNotifyListeners(String reason) {
    if (_isScanning != _lastLoggedScanning) {
      _lastLoggedScanning = _isScanning;
    }
    if (_availableDevices.length != _lastLoggedDeviceCount) {
      _lastLoggedDeviceCount = _availableDevices.length;
    }

    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!hasListeners) return;
      notifyListeners();
    });
  }

  /// True when device count or identity set changed (ignores RSSI reorder).
  bool _scanResultsChanged(List<ScanResult> prev, List<ScanResult> next) {
    if (prev.length != next.length) return true;
    if (prev.isEmpty) return false;
    final prevIds = {for (final r in prev) r.device.remoteId};
    final nextIds = {for (final r in next) r.device.remoteId};
    return prevIds.length != nextIds.length ||
        !prevIds.containsAll(nextIds);
  }

  void _applyScanResults(List<ScanResult> results) {
    final next = List<ScanResult>.from(results);
    final structureChanged = _scanResultsChanged(_availableDevices, next);
    _availableDevices = next;
    if (structureChanged) {
      _safeNotifyListeners('scan stream: results updated');
    }
  }

  void _setError(String message) {
    _lastError = message;
  }

  void _clearError() {
    _lastError = null;
  }

  String _errorMessage(Object error) {
    if (error is BleServiceException) return error.message;
    return error.toString();
  }
}
