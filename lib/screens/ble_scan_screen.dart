import '../core/constants/ble_constants.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_routes.dart';
import '../core/router/app_router.dart';
import '../providers/ble_provider.dart';
import '../services/ble_service.dart';

/// BLE device discovery and connection screen.
class BleScanScreen extends StatefulWidget {
  const BleScanScreen({super.key});

  @override
  State<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends State<BleScanScreen> {
  bool _permissionsGranted = false;
  bool _permissionsChecked = false;
  String? _permissionMessage;
  String? _connectingDeviceId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestBluetoothPermissions();
    });
  }

  Future<void> _requestBluetoothPermissions() async {
    debugPrint('[BleScan] _requestBluetoothPermissions() started');
    setState(() {
      _permissionsChecked = false;
      _permissionMessage = null;
    });

    final granted = await _ensureBlePermissions();
    if (!mounted) return;

    debugPrint(
      '[BleScan] _requestBluetoothPermissions() finished — granted=$granted',
    );

    setState(() {
      _permissionsGranted = granted;
      _permissionsChecked = true;
      if (!granted &&
          (_permissionMessage == null || _permissionMessage!.isEmpty)) {
        _permissionMessage =
            'Bluetooth permissions are required to scan for TinkrNest devices.';
      }
    });

    if (granted) {
      final ble = context.read<BleProvider>();
      if (ble.isScanning) {
        debugPrint('[BleScan] scan already running — skipping auto-start');
      } else {
        await ble.startScan();
      }
    }
  }

  /// Android 12+ (API 31+) uses [Permission.bluetoothScan] and
  /// [Permission.bluetoothConnect] only. Location is not declared for API 31+.
  int? _androidSdkInt() {
    if (!Platform.isAndroid) return null;
    final version = Platform.operatingSystemVersion;

    final apiMatch =
        RegExp(r'API[\s-]*(\d+)', caseSensitive: false).firstMatch(version);
    if (apiMatch != null) {
      return int.tryParse(apiMatch.group(1)!);
    }

    // Real devices return a build string, e.g.
    // "sdk_gphone64_arm64-userdebug 12 S2B2.211203.006 ..." — not "API 31".
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
      final mapped = releaseToApi[release];
      if (mapped != null) return mapped;
      if (release >= 12) return 31 + (release - 12);
    }

    return null;
  }

  bool _isAndroid12OrAbove(int? sdkInt) {
    if (sdkInt != null) return sdkInt >= 31;
    // Unparseable build string on a modern device — manifest only declares
    // location for maxSdkVersion 30, so assume API 31+ and skip location.
    return Platform.isAndroid;
  }

  void _logPermissionStatus(String label, PermissionStatus? status) {
    debugPrint('[BleScan] $label: ${status?.name ?? 'null'}');
  }

  bool _permissionGranted(PermissionStatus? status) =>
      status?.isGranted == true || status?.isLimited == true;

  Future<bool> _ensureBlePermissions() async {
    if (Platform.isAndroid) {
      final sdkInt = _androidSdkInt();
      final isAndroid12OrAbove = _isAndroid12OrAbove(sdkInt);

      debugPrint(
        '[BleScan] Android SDK=${sdkInt ?? 'unknown'} '
        '(raw="${Platform.operatingSystemVersion}") '
        'isAndroid12OrAbove=$isAndroid12OrAbove',
      );

      try {
        final adapterState = await FlutterBluePlus.adapterState.first;
        debugPrint('[BleScan] Bluetooth adapter state: $adapterState');
      } catch (e) {
        debugPrint('[BleScan] Bluetooth adapter state read failed: $e');
      }

      if (isAndroid12OrAbove) {
        final locationStatus = await Permission.locationWhenInUse.status;
        _logPermissionStatus(
            'locationWhenInUse (skipped on API 31+)', locationStatus);
      }

      final permissions = <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ];

      // Location is only in the manifest for API <= 30.
      if (!isAndroid12OrAbove) {
        permissions.add(Permission.locationWhenInUse);
      }

      final statuses = await permissions.request();

      final scanStatus = statuses[Permission.bluetoothScan];
      final connectStatus = statuses[Permission.bluetoothConnect];
      _logPermissionStatus('bluetoothScan (after request)', scanStatus);
      _logPermissionStatus('bluetoothConnect (after request)', connectStatus);

      final bleScanGranted = _permissionGranted(scanStatus);
      final bleConnectGranted = _permissionGranted(connectStatus);

      debugPrint(
        '[BleScan] bluetoothScan granted=$bleScanGranted, '
        'bluetoothConnect granted=$bleConnectGranted',
      );

      if (isAndroid12OrAbove) {
        if (!bleScanGranted || !bleConnectGranted) {
          if (scanStatus?.isPermanentlyDenied == true ||
              connectStatus?.isPermanentlyDenied == true) {
            _permissionMessage =
                'Bluetooth permissions are permanently denied. '
                'Enable Nearby devices in Settings.';
          }
          return false;
        }
        return true;
      }

      final locationStatus = statuses[Permission.locationWhenInUse];
      _logPermissionStatus('locationWhenInUse (after request)', locationStatus);
      final locationGranted = _permissionGranted(locationStatus);
      final allGranted = bleScanGranted && bleConnectGranted && locationGranted;

      if (!allGranted && locationStatus?.isPermanentlyDenied == true) {
        _permissionMessage = 'Location permission is permanently denied. '
            'Enable it in Settings for BLE scan on this Android version.';
      } else if (!allGranted &&
          (scanStatus?.isPermanentlyDenied == true ||
              connectStatus?.isPermanentlyDenied == true)) {
        _permissionMessage = 'Bluetooth permissions are permanently denied. '
            'Enable them in Settings.';
      }

      return allGranted;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      final status = await Permission.bluetooth.request();
      return status.isGranted || status.isLimited;
    }

    return true;
  }

  Future<void> _onRefresh() async {
    final ble = context.read<BleProvider>();
    ble.clearError();
    if (!_permissionsGranted) {
      await _requestBluetoothPermissions();
      return;
    }
    if (ble.isScanning) {
      debugPrint('[BleScan] scan already running — refresh ignored');
      return;
    }
    await ble.startScan();
  }

  Future<void> _startScan() async {
    if (!_permissionsGranted) {
      await _requestBluetoothPermissions();
      return;
    }
    final ble = context.read<BleProvider>();
    if (ble.isScanning) {
      debugPrint('[BleScan] scan already running — button ignored');
      return;
    }
    await ble.startScan();
  }

  Future<void> _stopScan() async {
    await context.read<BleProvider>().stopScan();
  }

  Future<void> _connectToDevice(ScanResult result) async {
    debugPrint('[BLE] connect requested');
    final ble = context.read<BleProvider>();
    final deviceId = result.device.remoteId.str;

    setState(() => _connectingDeviceId = deviceId);
    ble.clearError();

    try {
      await ble.connect(
        result.device,
        enableAutoReconnect: false,
      );
      if (!mounted) {
        debugPrint('[BLE] navigation skipped — context not mounted');
        return;
      }

      final status = await ble.refreshStatus();
      if (!mounted) return;

      final needsSetup = status?.setupMode ?? true;
      debugPrint('[BLE] navigating — setupMode=$needsSetup');
      await AppRouter.pushNamedAndRemoveUntil(
        needsSetup ? AppRoutes.provision : AppRoutes.dashboard,
        (route) => false,
      );
    } catch (error, stackTrace) {
      debugPrint('[BLE] connect flow failed: $error');
      debugPrint('$stackTrace');
      // Error surfaced via BleProvider.lastError.
    } finally {
      if (mounted) {
        setState(() => _connectingDeviceId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Find TinkrNest Device'),
        actions: [
          IconButton(
            tooltip: 'Refresh permissions & scan',
            onPressed: _permissionsChecked ? _onRefresh : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Selector<BleProvider, _BleScanSnapshot>(
        selector: (_, ble) => _BleScanSnapshot(
          isScanning: ble.isScanning,
          isConnecting: ble.isConnecting,
          connectionState: ble.connectionState,
          lastError: ble.lastError,
          devices: ble.availableDevices,
        ),
        builder: (context, snapshot, _) {
          return _BleScanBody(
            snapshot: snapshot,
            permissionsGranted: _permissionsGranted,
            permissionsChecked: _permissionsChecked,
            permissionMessage: _permissionMessage,
            connectingDeviceId: _connectingDeviceId,
            onRequestPermissions: _requestBluetoothPermissions,
            onRefresh: _onRefresh,
            onStartScan: _startScan,
            onStopScan: _stopScan,
            onConnect: _connectToDevice,
            onDismissError: context.read<BleProvider>().clearError,
          );
        },
      ),
    );
    return screen;
  }
}

/// UI snapshot for [Selector]; equality ignores RSSI-only scan updates.
class _BleScanSnapshot {
  const _BleScanSnapshot({
    required this.isScanning,
    required this.isConnecting,
    required this.connectionState,
    required this.lastError,
    required this.devices,
  });

  final bool isScanning;
  final bool isConnecting;
  final BleConnectionState connectionState;
  final String? lastError;
  final List<ScanResult> devices;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _BleScanSnapshot) return false;
    return isScanning == other.isScanning &&
        isConnecting == other.isConnecting &&
        connectionState == other.connectionState &&
        lastError == other.lastError &&
        _sameDeviceIds(devices, other.devices);
  }

  @override
  int get hashCode => Object.hash(
        isScanning,
        isConnecting,
        connectionState,
        lastError,
        devices.length,
        devices.isEmpty ? null : devices.first.device.remoteId,
      );

  static bool _sameDeviceIds(List<ScanResult> a, List<ScanResult> b) {
    if (a.length != b.length) return false;
    if (a.isEmpty) return true;
    final aIds = {for (final r in a) r.device.remoteId};
    final bIds = {for (final r in b) r.device.remoteId};
    return aIds.length == bIds.length && aIds.containsAll(bIds);
  }
}

class _BleScanBody extends StatelessWidget {
  const _BleScanBody({
    required this.snapshot,
    required this.permissionsGranted,
    required this.permissionsChecked,
    required this.permissionMessage,
    required this.connectingDeviceId,
    required this.onRequestPermissions,
    required this.onRefresh,
    required this.onStartScan,
    required this.onStopScan,
    required this.onConnect,
    required this.onDismissError,
  });

  final _BleScanSnapshot snapshot;
  final bool permissionsGranted;
  final bool permissionsChecked;
  final String? permissionMessage;
  final String? connectingDeviceId;
  final Future<void> Function() onRequestPermissions;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onStartScan;
  final Future<void> Function() onStopScan;
  final Future<void> Function(ScanResult result) onConnect;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isConnecting = snapshot.isConnecting || connectingDeviceId != null;
    final showTopLoader = !permissionsChecked ||
        (snapshot.isScanning && snapshot.devices.isEmpty);

    final body = Stack(
      fit: StackFit.expand,
      children: [
        SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 12),
                        _ConnectionStatusCard(state: snapshot.connectionState),
                        if (!permissionsGranted && permissionsChecked) ...[
                          const SizedBox(height: 12),
                          _PermissionBanner(
                            message: permissionMessage ??
                                'Bluetooth permissions are required.',
                            onOpenSettings: openAppSettings,
                            onRetry: onRequestPermissions,
                          ),
                        ],
                        if (snapshot.lastError != null) ...[
                          const SizedBox(height: 12),
                          _ErrorBanner(
                            message: snapshot.lastError!,
                            onDismiss: onDismissError,
                          ),
                        ],
                        const SizedBox(height: 16),
                        _ScanControls(
                          isScanning: snapshot.isScanning,
                          canScan: permissionsGranted,
                          onStartScan: onStartScan,
                          onStopScan: onStopScan,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: RefreshIndicator(
                        onRefresh: onRefresh,
                        edgeOffset: 8,
                        child: _buildDeviceList(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !showTopLoader,
            child: Opacity(
              opacity: showTopLoader ? 1 : 0,
              child: const _TopLoadingIndicator(),
            ),
          ),
        ),
        if (isConnecting)
          Positioned.fill(
            child: ColoredBox(
              color: scheme.scrim.withValues(alpha: 0.25),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Connecting to device…',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return body;
  }

  Widget _buildDeviceList(BuildContext context) {
    final devices = snapshot.devices;
    final isEmpty = devices.isEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView.separated(
          key: const PageStorageKey<String>('ble_scan_device_list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: isEmpty ? 1 : devices.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (isEmpty) {
              return _buildEmptyListContent(context);
            }

            final result = devices[index];
            final deviceId = result.device.remoteId.str;
            final isThisConnecting = connectingDeviceId == deviceId;

            return _DeviceCard(
              key: ValueKey(deviceId),
              result: result,
              isConnecting: isThisConnecting && snapshot.isConnecting,
              onTap: () => onConnect(result),
              onConnect: () => onConnect(result),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyListContent(BuildContext context) {
    final scanning = snapshot.isScanning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 8),
      child: IndexedStack(
        alignment: Alignment.topCenter,
        index: scanning ? 1 : 0,
        children: [
          const _EmptyState(
            title: 'No TinkrNest devices found',
            subtitle:
                'Make sure your switch is in setup mode (fast blinking LED) '
                'and tap Scan to search again.',
          ),
          Column(
            children: [
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 20),
              Text(
                'Scanning for ${BleConstants.deviceName}…',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  const _ConnectionStatusCard({required this.state});

  final BleConnectionState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = _connectionVisual(state, scheme);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(visual.icon, color: visual.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connection status',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    visual.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: visual.color,
                        ),
                  ),
                ],
              ),
            ),
            if (state == BleConnectionState.connecting ||
                state == BleConnectionState.reconnecting ||
                state == BleConnectionState.discovering)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
          ],
        ),
      ),
    );
  }

  _ConnectionVisual _connectionVisual(
    BleConnectionState state,
    ColorScheme scheme,
  ) {
    return switch (state) {
      BleConnectionState.ready ||
      BleConnectionState.connected =>
        _ConnectionVisual(
          label: 'Connected',
          icon: Icons.bluetooth_connected_rounded,
          color: scheme.primary,
        ),
      BleConnectionState.connecting ||
      BleConnectionState.discovering =>
        _ConnectionVisual(
          label: 'Connecting',
          icon: Icons.bluetooth_searching_rounded,
          color: scheme.tertiary,
        ),
      BleConnectionState.reconnecting => _ConnectionVisual(
          label: 'Reconnecting',
          icon: Icons.bluetooth_searching_rounded,
          color: scheme.tertiary,
        ),
      BleConnectionState.error => _ConnectionVisual(
          label: 'Disconnected',
          icon: Icons.bluetooth_disabled_rounded,
          color: scheme.error,
        ),
      BleConnectionState.disconnected => _ConnectionVisual(
          label: 'Disconnected',
          icon: Icons.bluetooth_disabled_rounded,
          color: scheme.onSurfaceVariant,
        ),
    };
  }
}

class _ConnectionVisual {
  const _ConnectionVisual({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

class _ScanControls extends StatelessWidget {
  const _ScanControls({
    required this.isScanning,
    required this.canScan,
    required this.onStartScan,
    required this.onStopScan,
  });

  final bool isScanning;
  final bool canScan;
  final VoidCallback onStartScan;
  final VoidCallback onStopScan;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 400;
        final scanEnabled = canScan && !isScanning;

        final startButton = FilledButton.icon(
          onPressed: scanEnabled ? onStartScan : null,
          icon: const Icon(Icons.search_rounded),
          label: const Text('Scan'),
        );

        final stopButton = OutlinedButton.icon(
          onPressed: isScanning ? onStopScan : null,
          icon: const Icon(Icons.stop_rounded),
          label: const Text('Stop'),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              startButton,
              const SizedBox(height: 10),
              stopButton,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: startButton),
            const SizedBox(width: 12),
            Expanded(child: stopButton),
          ],
        );
      },
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    super.key,
    required this.result,
    required this.isConnecting,
    required this.onTap,
    required this.onConnect,
  });

  final ScanResult result;
  final bool isConnecting;
  final VoidCallback onTap;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final device = result.device;
    final name = _deviceDisplayName(result);
    final rssi = result.rssi;
    final deviceId = device.remoteId.str;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isConnecting ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  Icons.electrical_services_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 6),
                    _InfoRow(
                      icon: Icons.signal_cellular_alt,
                      label: 'RSSI',
                      value: '$rssi dBm',
                      valueColor: _rssiColor(rssi, scheme),
                    ),
                    const SizedBox(height: 4),
                    _InfoRow(
                      icon: Icons.tag,
                      label: 'ID',
                      value: deviceId,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              isConnecting
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Flexible(
                      fit: FlexFit.loose,
                      child: FilledButton.tonal(
                        onPressed: onConnect,
                        child: const Text('Connect'),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  String _deviceDisplayName(ScanResult result) {
    final advName = result.advertisementData.advName;
    if (advName.isNotEmpty) return advName;

    final platformName = result.device.platformName;
    if (platformName.isNotEmpty) return platformName;

    return BleConstants.deviceName;
  }

  Color _rssiColor(int rssi, ColorScheme scheme) {
    if (rssi >= -60) return scheme.primary;
    if (rssi >= -75) return scheme.tertiary;
    return scheme.error;
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? scheme.onSurface,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: Icon(Icons.close, color: scheme.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({
    required this.message,
    required this.onOpenSettings,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.bluetooth_disabled_rounded,
                    color: scheme.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onTertiaryContainer,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: onOpenSettings,
                  child: const Text('Settings'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: onRetry,
                  child: const Text('Grant access'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.bluetooth_searching_rounded,
          size: 72,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _TopLoadingIndicator extends StatelessWidget {
  const _TopLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 4),
      child: LinearProgressIndicator(minHeight: 3),
    );
  }
}
