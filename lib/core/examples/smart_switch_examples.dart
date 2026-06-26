/// Complete Usage Examples for Smart Switch Timer System
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Example 1: Creating Timers Programmatically
class TimerCreationExample {
  static Future<void> createCountdownTimer(BuildContext context) async {
    final switchProvider = context.read<SmartSwitchProvider>();

    // Create a 10-minute countdown timer that turns OFF the relay
    await switchProvider.createCountdownTimer(
      switchId: 'relay_0',
      name: 'Kitchen Light Auto-Off',
      durationSeconds: 600, // 10 minutes
      targetState: false, // Turn OFF
    );

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Countdown timer created')));
  }

  static Future<void> createScheduledTimer(BuildContext context) async {
    final switchProvider = context.read<SmartSwitchProvider>();

    // Create a daily timer that turns ON at 6:00 AM
    await switchProvider.createScheduledTimer(
      switchId: 'relay_1',
      name: 'Morning Light',
      hour: 6,
      minute: 0,
      targetState: true, // Turn ON
      daysOfWeek: [1, 2, 3, 4, 5, 6, 7], // Every day
    );

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Scheduled timer created')));
  }

  static Future<void> createWeekdayTimer(BuildContext context) async {
    final switchProvider = context.read<SmartSwitchProvider>();

    // Create a weekday timer (Mon-Fri)
    await switchProvider.createScheduledTimer(
      switchId: 'relay_2',
      name: 'Work Days Schedule',
      hour: 9,
      minute: 0,
      targetState: true,
      daysOfWeek: [1, 2, 3, 4, 5], // Monday to Friday
    );
  }

  static Future<void> createWeekendTimer(BuildContext context) async {
    final switchProvider = context.read<SmartSwitchProvider>();

    // Create a weekend timer (Sat-Sun)
    await switchProvider.createScheduledTimer(
      switchId: 'relay_3',
      name: 'Weekend Routine',
      hour: 10,
      minute: 30,
      targetState: false,
      daysOfWeek: [6, 7], // Saturday and Sunday
    );
  }
}

// Example 2: Monitoring Timer State
class TimerMonitoringExample extends StatelessWidget {
  const TimerMonitoringExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SmartSwitchProvider>(
      builder: (context, switchProvider, _) {
        final runtimeState = switchProvider.getRuntimeState('relay_0');
        final timers = switchProvider.getTimersForSwitch('relay_0');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show all timers for this switch
            Text('Active Timers (${timers.length})'),
            ...timers.map((timer) {
              final isActive = timer.id == runtimeState?.activeTimerId;
              return ListTile(
                leading: isActive
                    ? const Icon(Icons.play_circle, color: Colors.orange)
                    : const Icon(Icons.schedule),
                title: Text(timer.name.isEmpty ? 'Timer' : timer.name),
                subtitle: _getTimerSubtitle(timer),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => switchProvider.deleteTimer(timer.id),
                ),
              );
            }),

            // Show remaining time for active countdown timer
            if (runtimeState?.remainingSeconds != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Time remaining: ${_formatDuration(runtimeState!.remainingSeconds!)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _getTimerSubtitle(SwitchTimer timer) {
    if (timer.timerType == TimerType.countdown) {
      final config = timer.countdownConfig;
      final minutes = (config?.durationSeconds ?? 0) ~/ 60;
      final seconds = (config?.durationSeconds ?? 0) % 60;
      final action = config?.targetState ?? false ? 'Turn ON' : 'Turn OFF';
      return '$minutes:${seconds.toString().padLeft(2, '0')} - $action';
    } else {
      final config = timer.scheduledConfig;
      return 'At ${config?.timeString} - ${config?.targetState ?? false ? 'ON' : 'OFF'}';
    }
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${secs.toString().padLeft(2, '0')}';
    }
  }
}

// Example 3: Device Command Execution
class DeviceCommandExample {
  static Future<void> sendSwitchCommand(
    BuildContext context,
    int switchId,
    bool state,
  ) async {
    final bleProvider = context.read<BleProvider>();

    if (!bleProvider.isConnected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Device not connected')));
      return;
    }

    try {
      // Send command to device
      // TODO: Implement based on your BLE service
      print('Sending SET_RELAY command: switch=$switchId, state=$state');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Relay $switchId turned ${state ? 'ON' : 'OFF'}'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  static Future<void> sendTimerCommand(
    BuildContext context,
    int switchId,
    SwitchTimer timer,
  ) async {
    final bleProvider = context.read<BleProvider>();

    if (!bleProvider.isConnected) {
      return;
    }

    try {
      if (timer.timerType == TimerType.countdown) {
        // Send countdown timer to device
        // TODO: Implement based on your BLE service
        print('Sending countdown timer to device');
      } else {
        // Send scheduled timer to device
        // TODO: Implement based on your BLE service
        print('Sending scheduled timer to device');
      }
    } catch (e) {
      print('Error sending timer: $e');
    }
  }
}

// Example 4: Batch Operations
class BatchOperationsExample {
  static Future<void> createMultipleTimers(BuildContext context) async {
    final switchProvider = context.read<SmartSwitchProvider>();

    // Create a set of timers for a morning routine
    final timers = [
      {
        'name': 'Bedroom Light',
        'switchId': 'relay_0',
        'hour': 6,
        'minute': 30,
        'state': true,
      },
      {
        'name': 'Bathroom Light',
        'switchId': 'relay_1',
        'hour': 6,
        'minute': 45,
        'state': true,
      },
      {
        'name': 'Kitchen Light',
        'switchId': 'relay_2',
        'hour': 7,
        'minute': 0,
        'state': true,
      },
    ];

    for (final timer in timers) {
      await switchProvider.createScheduledTimer(
        switchId: timer['switchId'] as String,
        name: timer['name'] as String,
        hour: timer['hour'] as int,
        minute: timer['minute'] as int,
        targetState: timer['state'] as bool,
        daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Morning routine timers created')),
    );
  }

  static Future<void> deleteAllTimersForSwitch(
    BuildContext context,
    String switchId,
  ) async {
    final switchProvider = context.read<SmartSwitchProvider>();

    final timers = switchProvider.getTimersForSwitch(switchId);
    for (final timer in timers) {
      await switchProvider.deleteTimer(timer.id);
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('All timers for $switchId deleted')));
  }

  static Future<void> toggleAllTimers(BuildContext context) async {
    final switchProvider = context.read<SmartSwitchProvider>();

    for (final timer in switchProvider.timers) {
      await switchProvider.toggleTimerEnabled(timer.id);
    }
  }
}

// Example 5: Error Handling
class ErrorHandlingExample {
  static Future<void> createTimerWithErrorHandling(BuildContext context) async {
    final switchProvider = context.read<SmartSwitchProvider>();

    try {
      // Validate input
      const durationSeconds = 600;
      if (durationSeconds <= 0) {
        throw Exception('Duration must be greater than 0');
      }

      // Create timer
      await switchProvider.createCountdownTimer(
        switchId: 'relay_0',
        name: 'Test Timer',
        durationSeconds: durationSeconds,
        targetState: true,
      );

      // Show success
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Timer created successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Show error
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// Example 6: UI Integration
class SmartSwitchDashboardExample extends StatefulWidget {
  const SmartSwitchDashboardExample({super.key});

  @override
  State<SmartSwitchDashboardExample> createState() =>
      _SmartSwitchDashboardExampleState();
}

class _SmartSwitchDashboardExampleState
    extends State<SmartSwitchDashboardExample> {
  @override
  void initState() {
    super.initState();
    _loadTimers();
  }

  Future<void> _loadTimers() async {
    final switchProvider = context.read<SmartSwitchProvider>();
    await switchProvider.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Switch Example')),
      body: Consumer<SmartSwitchProvider>(
        builder: (context, switchProvider, _) {
          if (switchProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Create countdown timer button
              FilledButton(
                onPressed: () =>
                    TimerCreationExample.createCountdownTimer(context),
                child: const Text('Create Countdown Timer'),
              ),
              const SizedBox(height: 8),

              // Create scheduled timer button
              FilledButton(
                onPressed: () =>
                    TimerCreationExample.createScheduledTimer(context),
                child: const Text('Create Scheduled Timer'),
              ),
              const SizedBox(height: 24),

              // Monitoring section
              const Divider(),
              const Text('Timer Monitoring', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              const TimerMonitoringExample(),
            ],
          );
        },
      ),
    );
  }
}

// Example 7: Data Export/Import
class DataManagementExample {
  static Future<String> exportTimersAsJson(
    SmartSwitchProvider switchProvider,
  ) async {
    final timers = switchProvider.timers;
    final jsonList = timers.map((t) => t.toJson()).toList();
    return jsonEncode(jsonList);
  }

  static Future<void> importTimersFromJson(
    SmartSwitchProvider switchProvider,
    String jsonString,
  ) async {
    try {
      final jsonList = jsonDecode(jsonString) as List;
      for (final json in jsonList) {
        // Manually recreate timers from JSON
        // This is a manual process as timer creation needs IDs
      }
    } catch (e) {
      print('Error importing timers: $e');
    }
  }

  static Map<String, dynamic> generateStatistics(
    SmartSwitchProvider switchProvider,
  ) {
    final timers = switchProvider.timers;
    final countdownTimers = timers
        .where((t) => t.timerType == TimerType.countdown)
        .length;
    final scheduledTimers = timers
        .where((t) => t.timerType != TimerType.countdown)
        .length;
    final enabledTimers = timers.where((t) => t.isEnabled).length;

    return {
      'total': timers.length,
      'countdown': countdownTimers,
      'scheduled': scheduledTimers,
      'enabled': enabledTimers,
      'disabled': timers.length - enabledTimers,
    };
  }
}
