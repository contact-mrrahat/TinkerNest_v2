import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/smart_switch_provider.dart';

/// Timer Configuration Dialog
class TimerConfigDialog extends StatefulWidget {
  final String switchId;
  final String switchName;

  const TimerConfigDialog({
    super.key,
    required this.switchId,
    required this.switchName,
  });

  @override
  State<TimerConfigDialog> createState() => _TimerConfigDialogState();
}

class _TimerConfigDialogState extends State<TimerConfigDialog> {
  late TabController _tabController;
  final TextEditingController _timerNameController = TextEditingController();

  // Countdown timer
  int _countdownMinutes = 1;
  int _countdownSeconds = 0;
  bool _countdownTargetState = true; // true = ON, false = OFF

  // Scheduled timer
  TimeOfDay _scheduledTime = TimeOfDay.now();
  bool _scheduledTargetState = true;
  final Set<int> _selectedDays = {1, 2, 3, 4, 5, 6, 7}; // Mon-Sun

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _timerNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade600,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Timer Settings',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        widget.switchName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.blue.shade100,
                            ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: Navigator.of(context).pop,
                  child: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            labelColor: Colors.blue.shade600,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue.shade600,
            tabs: const [
              Tab(text: 'Countdown'),
              Tab(text: 'Scheduled'),
            ],
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCountdownTab(),
                _buildScheduledTab(),
              ],
            ),
          ),

          // Buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: Navigator.of(context).pop,
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _handleSaveTimer,
                  child: const Text('Save Timer'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Tab Builders ====================

  Widget _buildCountdownTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timer name
          TextField(
            controller: _timerNameController,
            decoration: InputDecoration(
              labelText: 'Timer Name (optional)',
              hintText: 'e.g., Kitchen Timer',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.label_outline),
            ),
          ),

          const SizedBox(height: 24),

          // Time picker
          Text(
            'Duration',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),

          // Hours, Minutes, Seconds
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _TimeInputField(
                label: 'Minutes',
                value: _countdownMinutes,
                onChanged: (value) {
                  setState(() => _countdownMinutes = value);
                },
                maxValue: 999,
              ),
              _TimeInputField(
                label: 'Seconds',
                value: _countdownSeconds,
                onChanged: (value) {
                  setState(() => _countdownSeconds = value);
                },
                maxValue: 59,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Target state
          Text(
            'Target State',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),

          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Turn ON'),
                icon: Icon(Icons.power_settings_new),
              ),
              ButtonSegment(
                value: false,
                label: Text('Turn OFF'),
                icon: Icon(Icons.power_off),
              ),
            ],
            selected: {_countdownTargetState},
            onSelectionChanged: (Set<bool> newSelection) {
              setState(() => _countdownTargetState = newSelection.first);
            },
          ),

          const SizedBox(height: 16),

          // Summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Text(
              'After ${_countdownMinutes}m ${_countdownSeconds}s, turn ${_countdownTargetState ? 'ON' : 'OFF'}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduledTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timer name
          TextField(
            controller: _timerNameController,
            decoration: InputDecoration(
              labelText: 'Timer Name (optional)',
              hintText: 'e.g., Daily Morning',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.label_outline),
            ),
          ),

          const SizedBox(height: 24),

          // Time picker
          Text(
            'Schedule Time',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),

          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                title: Text(
                  _scheduledTime.format(context),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                trailing: const Icon(Icons.access_time),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: _scheduledTime,
                  );
                  if (time != null) {
                    setState(() => _scheduledTime = time);
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Target state
          Text(
            'Target State',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),

          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Turn ON'),
                icon: Icon(Icons.power_settings_new),
              ),
              ButtonSegment(
                value: false,
                label: Text('Turn OFF'),
                icon: Icon(Icons.power_off),
              ),
            ],
            selected: {_scheduledTargetState},
            onSelectionChanged: (Set<bool> newSelection) {
              setState(() => _scheduledTargetState = newSelection.first);
            },
          ),

          const SizedBox(height: 24),

          // Days of week
          Text(
            'Repeat On',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            children: [
              for (int day = 1; day <= 7; day++)
                FilterChip(
                  selected: _selectedDays.contains(day),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedDays.add(day);
                      } else {
                        _selectedDays.remove(day);
                      }
                    });
                  },
                  label: Text(
                    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day - 1],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),

          // Summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'At ${_scheduledTime.format(context)}, turn ${_scheduledTargetState ? 'ON' : 'OFF'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Every: ${_getDaysText()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Event Handlers ====================

  void _handleSaveTimer() async {
    final switchProvider = context.read<SmartSwitchProvider>();

    try {
      if (_tabController.index == 0) {
        // Countdown timer
        final totalSeconds = (_countdownMinutes * 60) + _countdownSeconds;
        if (totalSeconds <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Duration must be greater than 0')),
          );
          return;
        }

        await switchProvider.createCountdownTimer(
          switchId: widget.switchId,
          name: _timerNameController.text,
          durationSeconds: totalSeconds,
          targetState: _countdownTargetState,
        );
      } else {
        // Scheduled timer
        if (_selectedDays.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select at least one day')),
          );
          return;
        }

        await switchProvider.createScheduledTimer(
          switchId: widget.switchId,
          name: _timerNameController.text,
          hour: _scheduledTime.hour,
          minute: _scheduledTime.minute,
          targetState: _scheduledTargetState,
          daysOfWeek: _selectedDays.toList(),
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Timer saved successfully'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  String _getDaysText() {
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final selected = _selectedDays.toList()..sort();

    if (selected.length == 7) return 'Daily';
    if (selected.length == 5 &&
        !selected.contains(6) &&
        !selected.contains(7)) {
      return 'Weekdays';
    }
    if (selected.length == 2 && selected.contains(6) && selected.contains(7)) {
      return 'Weekends';
    }

    return selected.map((d) => dayNames[d - 1]).join(', ');
  }
}

/// Time input field for countdown timer
class _TimeInputField extends StatefulWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int maxValue;

  const _TimeInputField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.maxValue,
  });

  @override
  State<_TimeInputField> createState() => _TimeInputFieldState();
}

class _TimeInputFieldState extends State<_TimeInputField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (value) {
              final parsed = int.tryParse(value) ?? 0;
              widget.onChanged(parsed.clamp(0, widget.maxValue));
            },
          ),
          const SizedBox(height: 8),
          Text(
            widget.label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
