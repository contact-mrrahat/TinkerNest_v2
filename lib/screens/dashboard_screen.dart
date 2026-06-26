import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_routes.dart';
import '../models/device_status.dart';
import '../providers/ble_provider.dart';

/// Main device control dashboard backed by [BleProvider] and [DeviceStatus].
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialRefresh();
    });
  }

  Future<void> _initialRefresh() async {
    final ble = context.read<BleProvider>();
    if (ble.isConnected) {
      await _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    final ble = context.read<BleProvider>();
    if (!ble.isConnected) return;

    setState(() => _isRefreshing = true);
    try {
      await ble.refreshStatus();
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TinkrNest Dashboard'),
        actions: [
          Consumer<BleProvider>(
            builder: (context, ble, _) {
              return IconButton(
                tooltip: 'Refresh status',
                onPressed: ble.isConnected && !_isRefreshing
                    ? _refreshStatus
                    : null,
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              );
            },
          ),
        ],
      ),
      body: Consumer<BleProvider>(
        builder: (context, ble, _) {
          return _DashboardBody(
            ble: ble,
            isRefreshing: _isRefreshing,
            onRefresh: _refreshStatus,
            onDismissError: ble.clearError,
          );
        },
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.ble,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onDismissError,
  });

  final BleProvider ble;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    if (!ble.isConnected) {
      return _DisconnectedView(
        isConnecting: ble.isConnecting,
        onScan: () => Navigator.pushNamed(context, AppRoutes.bleScan),
      );
    }

    final status = ble.deviceStatus;
    if (status == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Reading device status…'),
            ],
          ),
        ),
      );
    }

    final isLoading = isRefreshing || ble.isCommandInFlight;

    return Stack(
      children: [
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: RefreshIndicator(
                onRefresh: onRefresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          if (ble.lastError != null) ...[
                            _ErrorBanner(
                              message: ble.lastError!,
                              onDismiss: onDismissError,
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (status.setupMode)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _SetupModeBanner(
                                onConfigure: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.provision,
                                ),
                              ),
                            ),
                          _DeviceStatusCard(status: status),
                          const SizedBox(height: 12),
                          _SensorCard(status: status),
                          const SizedBox(height: 12),
                          _RelayControlSection(
                            status: status,
                            enabled: !isLoading,
                            onToggleRelay1: ble.toggleRelay1,
                            onToggleRelay2: ble.toggleRelay2,
                            onToggleRelay3: ble.toggleRelay3,
                            onToggleRelay4: ble.toggleRelay4,
                          ),
                          const SizedBox(height: 12),
                          _QuickActionsBar(
                            enabled: !isLoading,
                            onAllOn: ble.allOn,
                            onAllOff: ble.allOff,
                          ),
                          const SizedBox(height: 12),
                          _PersistenceCard(
                            persistEnabled: status.persistEnabled,
                            enabled: !isLoading,
                            onChanged: (enabled) => enabled
                                ? ble.enablePersist()
                                : ble.disablePersist(),
                          ),
                          const SizedBox(height: 24),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isLoading)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(minHeight: 3),
          ),
      ],
    );
  }
}

class _DisconnectedView extends StatelessWidget {
  const _DisconnectedView({
    required this.isConnecting,
    required this.onScan,
  });

  final bool isConnecting;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isConnecting) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  'Connecting to device…',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ] else ...[
                Icon(
                  Icons.bluetooth_disabled_rounded,
                  size: 80,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 20),
                Text(
                  'No device connected',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Connect to a TinkrNest Smart Switch over Bluetooth to '
                  'control relays and view sensor data.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: onScan,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Scan for device'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceStatusCard extends StatelessWidget {
  const _DeviceStatusCard({required this.status});

  final DeviceStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Device status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _StatusTile(
              icon: Icons.memory_rounded,
              label: 'Firmware',
              value: status.firmwareVersion.isEmpty
                  ? 'Unknown'
                  : status.firmwareVersion,
            ),
            const Divider(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 480;
                final tiles = [
                  _ConnectivityChip(
                    label: 'WiFi',
                    isOnline: status.wifiConnected,
                    onlineIcon: Icons.wifi,
                    offlineIcon: Icons.wifi_off,
                  ),
                  _ConnectivityChip(
                    label: 'Internet',
                    isOnline: status.internetConnected,
                    onlineIcon: Icons.public,
                    offlineIcon: Icons.public_off,
                  ),
                  _ConnectivityChip(
                    label: 'Blynk',
                    isOnline: status.blynkConnected,
                    onlineIcon: Icons.cloud_done_outlined,
                    offlineIcon: Icons.cloud_off_outlined,
                  ),
                  _ConnectivityChip(
                    label: 'BLE',
                    isOnline: status.bleActive,
                    onlineIcon: Icons.bluetooth_connected,
                    offlineIcon: Icons.bluetooth_disabled,
                  ),
                ];

                if (isWide) {
                  return Row(
                    children: [
                      for (var i = 0; i < tiles.length; i++) ...[
                        Expanded(child: tiles[i]),
                        if (i < tiles.length - 1) const SizedBox(width: 8),
                      ],
                    ],
                  );
                }

                return Column(
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      tiles[i],
                      if (i < tiles.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

class _ConnectivityChip extends StatelessWidget {
  const _ConnectivityChip({
    required this.label,
    required this.isOnline,
    required this.onlineIcon,
    required this.offlineIcon,
  });

  final String label;
  final bool isOnline;
  final IconData onlineIcon;
  final IconData offlineIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isOnline ? scheme.primary : scheme.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (isOnline ? scheme.primaryContainer : scheme.errorContainer)
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(isOnline ? onlineIcon : offlineIcon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  isOnline ? 'Online' : 'Offline',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({required this.status});

  final DeviceStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sensors_rounded, color: scheme.secondary),
                const SizedBox(width: 10),
                Text(
                  'Sensors',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 400;
                final temperature = _SensorTile(
                  icon: Icons.thermostat_rounded,
                  label: 'Temperature',
                  value: _formatTemperature(status.temperatureC),
                  accent: scheme.primary,
                );
                final humidity = _SensorTile(
                  icon: Icons.water_drop_outlined,
                  label: 'Humidity',
                  value: _formatHumidity(status.humidityPercent),
                  accent: scheme.tertiary,
                );

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: temperature),
                      const SizedBox(width: 12),
                      Expanded(child: humidity),
                    ],
                  );
                }

                return Column(
                  children: [
                    temperature,
                    const SizedBox(height: 12),
                    humidity,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatTemperature(double? value) {
    if (value == null) return '— °C';
    return '${value.toStringAsFixed(1)} °C';
  }

  String _formatHumidity(double? value) {
    if (value == null) return '— %';
    return '${value.toStringAsFixed(1)} %';
  }
}

class _SensorTile extends StatelessWidget {
  const _SensorTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: accent.withValues(alpha: 0.15),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayControlSection extends StatelessWidget {
  const _RelayControlSection({
    required this.status,
    required this.enabled,
    required this.onToggleRelay1,
    required this.onToggleRelay2,
    required this.onToggleRelay3,
    required this.onToggleRelay4,
  });

  final DeviceStatus status;
  final bool enabled;
  final Future<void> Function() onToggleRelay1;
  final Future<void> Function() onToggleRelay2;
  final Future<void> Function() onToggleRelay3;
  final Future<void> Function() onToggleRelay4;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final relays = [
      _RelayItem(number: 1, isOn: status.relay1, onToggle: onToggleRelay1),
      _RelayItem(number: 2, isOn: status.relay2, onToggle: onToggleRelay2),
      _RelayItem(number: 3, isOn: status.relay3, onToggle: onToggleRelay3),
      _RelayItem(number: 4, isOn: status.relay4, onToggle: onToggleRelay4),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.electrical_services_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Relay control',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth >= 560 ? 2 : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: crossAxisCount == 2 ? 2.8 : 3.4,
                  ),
                  itemCount: relays.length,
                  itemBuilder: (context, index) {
                    final relay = relays[index];
                    return _RelaySwitchTile(
                      label: 'Relay ${relay.number}',
                      isOn: relay.isOn,
                      enabled: enabled,
                      onChanged: (_) => relay.onToggle(),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RelayItem {
  const _RelayItem({
    required this.number,
    required this.isOn,
    required this.onToggle,
  });

  final int number;
  final bool isOn;
  final Future<void> Function() onToggle;
}

class _RelaySwitchTile extends StatelessWidget {
  const _RelaySwitchTile({
    required this.label,
    required this.isOn,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool isOn;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: isOn
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? () => onChanged(!isOn) : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                isOn ? Icons.power_rounded : Icons.power_off_rounded,
                color: isOn ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Switch.adaptive(
                value: isOn,
                onChanged: enabled ? onChanged : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionsBar extends StatelessWidget {
  const _QuickActionsBar({
    required this.enabled,
    required this.onAllOn,
    required this.onAllOff,
  });

  final bool enabled;
  final Future<void> Function() onAllOn;
  final Future<void> Function() onAllOff;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Quick actions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 400;

                final allOn = FilledButton.icon(
                  onPressed: enabled ? onAllOn : null,
                  icon: const Icon(Icons.flash_on_rounded),
                  label: const Text('All ON'),
                );

                final allOff = FilledButton.tonalIcon(
                  onPressed: enabled ? onAllOff : null,
                  icon: const Icon(Icons.flash_off_rounded),
                  label: const Text('All OFF'),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      allOn,
                      const SizedBox(height: 10),
                      allOff,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: allOn),
                    const SizedBox(width: 12),
                    Expanded(child: allOff),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PersistenceCard extends StatelessWidget {
  const _PersistenceCard({
    required this.persistEnabled,
    required this.enabled,
    required this.onChanged,
  });

  final bool persistEnabled;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.save_outlined, color: scheme.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Relay persistence',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    persistEnabled
                        ? 'Relay states are saved across reboots.'
                        : 'Relay states reset on reboot.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    persistEnabled ? 'Persist enabled' : 'Persist disabled',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: persistEnabled ? scheme.primary : scheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: persistEnabled,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupModeBanner extends StatelessWidget {
  const _SetupModeBanner({required this.onConfigure});

  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.settings_bluetooth, color: scheme.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Setup mode',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onPrimaryContainer,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'WiFi and Blynk are not configured. Tap to open the '
                    'provisioning wizard.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onConfigure,
              child: const Text('Configure'),
            ),
          ],
        ),
      ),
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
