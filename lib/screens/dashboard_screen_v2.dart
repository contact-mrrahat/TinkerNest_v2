import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_routes.dart';
import '../providers/ble_provider.dart';
import '../providers/smart_switch_provider.dart';
import 'dialogs/timer_config_dialog.dart';
import 'widgets/smart_switch_card.dart';

/// Production-ready Dashboard with Smart Switch Control
class DashboardScreenV2 extends StatefulWidget {
  const DashboardScreenV2({super.key});

  @override
  State<DashboardScreenV2> createState() => _DashboardScreenV2State();
}

class _DashboardScreenV2State extends State<DashboardScreenV2> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDashboard();
    });
  }

  Future<void> _initializeDashboard() async {
    final bleProvider = context.read<BleProvider>();
    final switchProvider = context.read<SmartSwitchProvider>();

    // Initialize smart switch provider
    await switchProvider.initialize();

    // Refresh device status
    if (bleProvider.isConnected) {
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
        title: const Text('Smart Switch Dashboard'),
        elevation: 2,
        actions: [
          // Refresh button
          Consumer<BleProvider>(
            builder: (context, ble, _) {
              return IconButton(
                tooltip: 'Refresh device status',
                onPressed:
                    ble.isConnected && !_isRefreshing ? _refreshStatus : null,
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

          // Settings menu
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'scan':
                  Navigator.pushNamed(context, AppRoutes.bleScan);
                  break;
                case 'provision':
                  Navigator.pushNamed(context, AppRoutes.provision);
                  break;
                case 'clear_timers':
                  _showClearTimersConfirm();
                  break;
                case 'settings':
                  Navigator.pushNamed(context, AppRoutes.settings);
                  break;
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'scan',
                child: Row(
                  children: [
                    Icon(Icons.bluetooth, size: 20),
                    SizedBox(width: 12),
                    Text('Scan Devices'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'provision',
                child: Row(
                  children: [
                    Icon(Icons.settings_remote, size: 20),
                    SizedBox(width: 12),
                    Text('Provision Device'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear_timers',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, size: 20),
                    SizedBox(width: 12),
                    Text('Clear All Timers'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, size: 20),
                    SizedBox(width: 12),
                    Text('Settings'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer2<BleProvider, SmartSwitchProvider>(
        builder: (context, bleProvider, switchProvider, _) {
          // Not connected
          if (!bleProvider.isConnected) {
            return _buildDisconnectedView(context, bleProvider);
          }

          // No device status
          if (bleProvider.deviceStatus == null) {
            return _buildLoadingView();
          }

          // Main dashboard
          return _buildConnectedView(
            context,
            bleProvider,
            switchProvider,
          );
        },
      ),
    );
  }

  Widget _buildDisconnectedView(BuildContext context, BleProvider bleProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_disabled,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 24),
            Text(
              'Not Connected',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please connect to a smart switch device',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: bleProvider.isConnecting
                  ? null
                  : () => Navigator.pushNamed(context, AppRoutes.bleScan),
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Scan for Devices'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading device status…'),
        ],
      ),
    );
  }

  Widget _buildConnectedView(
    BuildContext context,
    BleProvider bleProvider,
    SmartSwitchProvider switchProvider,
  ) {
    return RefreshIndicator(
      onRefresh: _refreshStatus,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Device connection status
                _buildDeviceStatusCard(bleProvider),
                const SizedBox(height: 16),

                // Relay/Switch controls
                Text(
                  'Smart Switches',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),

                // Grid of switches
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.0,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: 4,
                  itemBuilder: (context, index) {
                    return SmartSwitchCard(
                      switchIndex: index,
                      switchName: 'Relay ${index + 1}',
                      onTimerTap: () {
                        _showTimerDialog(
                          context,
                          'relay_$index',
                          'Relay ${index + 1}',
                        );
                      },
                      onStateChanged: (newState) {
                        // TODO: Send command to device
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Relay ${index + 1} turned ${newState ? 'ON' : 'OFF'}',
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 32),

                // Additional info
                _buildDeviceInfoCard(bleProvider),

                const SizedBox(height: 24),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceStatusCard(BleProvider bleProvider) {
    final status = bleProvider.deviceStatus;
    if (status == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Device Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Connected',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusItem(
                  context,
                  'WiFi',
                  status.wifiConnected,
                ),
                _buildStatusItem(
                  context,
                  'Internet',
                  status.internetConnected,
                ),
                _buildStatusItem(
                  context,
                  'Blynk',
                  status.blynkConnected,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(BuildContext context, String label, bool isActive) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive ? Colors.green.shade100 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isActive ? Icons.check_circle : Icons.cancel,
            color: isActive ? Colors.green : Colors.grey,
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }

  Widget _buildDeviceInfoCard(BleProvider bleProvider) {
    final status = bleProvider.deviceStatus;
    if (status == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device Information',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Firmware', status.firmwareVersion),
            _buildInfoRow(
              'Persistent State',
              status.persistEnabled ? 'Enabled' : 'Disabled',
            ),
            if (status.temperatureC != null)
              _buildInfoRow(
                'Temperature',
                '${status.temperatureC!.toStringAsFixed(1)}°C',
              ),
            if (status.humidityPercent != null)
              _buildInfoRow(
                'Humidity',
                '${status.humidityPercent!.toStringAsFixed(0)}%',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  void _showTimerDialog(
      BuildContext context, String switchId, String switchName) {
    showDialog(
      context: context,
      builder: (context) => TimerConfigDialog(
        switchId: switchId,
        switchName: switchName,
      ),
    );
  }

  void _showClearTimersConfirm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Timers?'),
        content: const Text(
          'This will delete all timers. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context.read<SmartSwitchProvider>().clearAllTimers();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All timers cleared')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// Export as replacement for old dashboard
typedef DashboardScreen = DashboardScreenV2;
