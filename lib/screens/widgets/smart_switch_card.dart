import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/timer_model.dart';
import '../../providers/ble_provider.dart';
import '../../providers/smart_switch_provider.dart';

/// Smart Switch Card - displays a single switch with timer
class SmartSwitchCard extends StatefulWidget {
  final int switchIndex; // 0-3 for relays
  final String switchName;
  final VoidCallback? onTimerTap;
  final Function(bool)? onStateChanged;

  const SmartSwitchCard({
    super.key,
    required this.switchIndex,
    required this.switchName,
    this.onTimerTap,
    this.onStateChanged,
  });

  @override
  State<SmartSwitchCard> createState() => _SmartSwitchCardState();
}

class _SmartSwitchCardState extends State<SmartSwitchCard> {
  bool _isAnimating = false;

  @override
  Widget build(BuildContext context) {
    final bleProvider = context.watch<BleProvider>();
    final switchProvider = context.watch<SmartSwitchProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get relay state from BLE provider
    final relayBitmap = bleProvider.deviceStatus?.relayBitmap ?? 0;
    final isOn = (relayBitmap >> widget.switchIndex) & 1 == 1;

    // Get runtime state and active timers
    final runtimeState =
        switchProvider.getRuntimeState('relay_${widget.switchIndex}');
    final timers =
        switchProvider.getTimersForSwitch('relay_${widget.switchIndex}');
    final activeTimer = timers.firstWhere(
      (t) => runtimeState?.activeTimerId == t.id,
      orElse: () => SwitchTimer(
        id: '',
        switchId: 'relay_${widget.switchIndex}',
        timerType: TimerType.countdown,
        isEnabled: false,
        name: '',
      ),
    );

    return Material(
      child: GestureDetector(
        onTap: widget.onTimerTap,
        child: Card(
          elevation: isDark ? 2 : 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          color: isDark
              ? (isOn ? Colors.blue.shade900 : Colors.grey.shade800)
              : (isOn ? Colors.blue.shade50 : Colors.white),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Name + Timer Icon
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.switchName,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isOn
                                      ? Colors.blue
                                      : (isDark
                                          ? Colors.white70
                                          : Colors.black87),
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (activeTimer.id.isNotEmpty && runtimeState != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _getTimerDisplayText(activeTimer, runtimeState),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onTimerTap,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.timer_outlined,
                          color: timers.isNotEmpty
                              ? Colors.orange
                              : (isDark ? Colors.grey : Colors.grey.shade400),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Toggle Switch
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isOn ? 'ON' : 'OFF',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isOn
                                ? Colors.green
                                : (isDark ? Colors.grey : Colors.grey.shade600),
                          ),
                    ),
                    Transform.scale(
                      scale: 1.2,
                      child: Switch(
                        value: isOn,
                        onChanged: !bleProvider.isConnected
                            ? null
                            : (value) async {
                                if (_isAnimating) return;
                                _isAnimating = true;

                                try {
                                  // TODO: Send command to device via BLE
                                  // await bleProvider.setSwitchState(widget.switchIndex, value);
                                  widget.onStateChanged?.call(value);
                                } finally {
                                  _isAnimating = false;
                                }
                              },
                        activeThumbColor: Colors.green,
                        inactiveThumbColor: isDark
                            ? Colors.grey.shade600
                            : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),

                // Timers List
                if (timers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Divider(
                    height: 12,
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: timers.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final timer = timers[index];
                        final isActive =
                            timer.id == runtimeState?.activeTimerId;
                        return _TimerBadge(
                          timer: timer,
                          isActive: isActive,
                          onDelete: () => switchProvider.deleteTimer(timer.id),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getTimerDisplayText(SwitchTimer timer, SwitchRuntimeState state) {
    if (timer.timerType == TimerType.countdown) {
      final remaining = state.remainingSeconds;
      if (remaining == null) return '';

      if (remaining > 3600) {
        final hours = remaining ~/ 3600;
        final minutes = (remaining % 3600) ~/ 60;
        return '$hours:${minutes.toString().padLeft(2, '0')}h remaining';
      } else if (remaining > 60) {
        final minutes = remaining ~/ 60;
        return '${minutes}m remaining';
      } else {
        return '${remaining}s remaining';
      }
    }

    final scheduled = timer.scheduledConfig;
    if (scheduled != null) {
      return 'Scheduled: ${scheduled.timeString} → ${scheduled.targetState ? 'ON' : 'OFF'}';
    }

    return '';
  }
}

/// Timer Badge - displays a timer in the switch card
class _TimerBadge extends StatelessWidget {
  final SwitchTimer timer;
  final bool isActive;
  final VoidCallback onDelete;

  const _TimerBadge({
    required this.timer,
    required this.isActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.orange
            : (isDark ? Colors.grey.shade700 : Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
        border: isActive
            ? Border.all(color: Colors.orange.shade700, width: 2)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            timer.timerType == TimerType.countdown
                ? Icons.hourglass_bottom
                : Icons.schedule,
            size: 14,
            color: isActive
                ? Colors.white
                : (isDark ? Colors.grey : Colors.grey.shade600),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              timer.name.isEmpty
                  ? timer.timerType.toString().split('.').last
                  : timer.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? Colors.white
                    : (isDark ? Colors.grey : Colors.grey.shade600),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDelete,
            child: Icon(
              Icons.close,
              size: 12,
              color: isActive
                  ? Colors.white
                  : (isDark ? Colors.grey : Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}
