import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_routes.dart';
import '../providers/ble_provider.dart';
import '../services/ble_service.dart';

/// Multi-step WiFi + Blynk provisioning wizard for TinkrNest devices.
class ProvisioningScreen extends StatefulWidget {
  const ProvisioningScreen({super.key});

  @override
  State<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends State<ProvisioningScreen> {
  static const _stepLabels = ['WiFi', 'Blynk', 'Review', 'Provision'];

  int _currentStep = 0;
  bool _provisionStarted = false;
  bool _provisionSucceeded = false;
  Timer? _successNavigationTimer;

  final _wifiFormKey = GlobalKey<FormState>();
  final _blynkFormKey = GlobalKey<FormState>();

  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authTokenController = TextEditingController();
  final _templateIdController = TextEditingController();
  final _templateNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initProvisioning());
  }

  Future<void> _initProvisioning() async {
    final ble = context.read<BleProvider>();

    for (var i = 0; i < 60 && mounted; i++) {
      if (!ble.isConnecting && !ble.isCommandInFlight) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    if (!mounted) return;
    await _loadWifiNetworks();
  }

  @override
  void dispose() {
    _successNavigationTimer?.cancel();
    _ssidController.dispose();
    _passwordController.dispose();
    _authTokenController.dispose();
    _templateIdController.dispose();
    _templateNameController.dispose();
    super.dispose();
  }

  Future<void> _loadWifiNetworks() async {
    final ble = context.read<BleProvider>();
    if (!ble.isConnected || ble.isWifiScanning || ble.isBusy) return;

    try {
      await ble.scanWifiNetworks();
    } catch (_) {
      // Error surfaced via BleProvider.lastError.
    }
  }

  Map<String, dynamic> _buildPayload() {
    final payload = <String, dynamic>{
      'ssid': _ssidController.text.trim(),
      'pass': _passwordController.text,
      'auth': _authTokenController.text.trim(),
    };

    final tplId = _templateIdController.text.trim();
    final tplName = _templateNameController.text.trim();
    if (tplId.isNotEmpty) payload['tplId'] = tplId;
    if (tplName.isNotEmpty) payload['tplName'] = tplName;

    return payload;
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _wifiFormKey.currentState?.validate() ?? false;
      case 1:
        return _blynkFormKey.currentState?.validate() ?? false;
      default:
        return true;
    }
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step.clamp(0, _stepLabels.length - 1));
  }

  void _onBack() {
    if (_currentStep == 0 || _provisionStarted) return;
    _goToStep(_currentStep - 1);
  }

  Future<void> _onNext() async {
    if (!_validateCurrentStep()) return;

    if (_currentStep < 2) {
      _goToStep(_currentStep + 1);
      return;
    }

    if (_currentStep == 2) {
      _goToStep(3);
      await _startProvisioning();
    }
  }

  Future<void> _startProvisioning() async {
    final ble = context.read<BleProvider>();
    if (!ble.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect to a TinkrNest device over BLE before provisioning.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _goToStep(0);
      return;
    }

    setState(() {
      _provisionStarted = true;
      _provisionSucceeded = false;
    });

    ble.clearProvisioningStatus();
    ble.clearError();

    try {
      await ble.sendProvisioningData(_buildPayload());

      if (!mounted) return;

      if (ble.provisioningStatus == ProvisioningStatus.saved) {
        setState(() => _provisionSucceeded = true);
        await ble.finalizeProvisioningSession();
        if (!mounted) return;
        _scheduleDashboardNavigation();
      }
    } catch (_) {
      // Errors are shown via BleProvider.lastError and provisioningStatus.
    }
  }

  void _scheduleDashboardNavigation() {
    _successNavigationTimer?.cancel();
    _successNavigationTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device setup'),
        leading: _currentStep > 0 && !_provisionStarted
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _onBack,
              )
            : null,
      ),
      body: Consumer<BleProvider>(
        builder: (context, ble, _) {
          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _StepProgressHeader(
                        labels: _stepLabels,
                        currentStep: _currentStep,
                      ),
                    ),
                    if (!ble.isConnected &&
                        !_provisionSucceeded &&
                        ble.provisioningStatus != ProvisioningStatus.saved) ...[
                      const SizedBox(height: 12),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: _ConnectionWarningBanner(),
                      ),
                    ],
                    if (ble.lastError != null) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _ErrorBanner(message: ble.lastError!),
                      ),
                    ],
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: _buildStepContent(ble),
                        ),
                      ),
                    ),
                    _BottomActions(
                      currentStep: _currentStep,
                      provisionStarted: _provisionStarted,
                      provisionSucceeded: _provisionSucceeded,
                      isProvisioning: ble.isProvisioning,
                      canProceed: ble.isConnected,
                      onBack: _onBack,
                      onNext: _onNext,
                      onRetry: () async {
                        setState(() {
                          _provisionStarted = false;
                          _provisionSucceeded = false;
                        });
                        ble.clearProvisioningStatus();
                        ble.clearError();
                        await _startProvisioning();
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStepContent(BleProvider ble) {
    return switch (_currentStep) {
      0 => _WifiSetupStep(
          key: const ValueKey('wifi'),
          formKey: _wifiFormKey,
          ssidController: _ssidController,
          passwordController: _passwordController,
          networks: ble.wifiNetworks,
          isScanning: ble.isWifiScanning,
          onRefresh: _loadWifiNetworks,
          onSelectSsid: (ssid) {
            setState(() => _ssidController.text = ssid);
          },
        ),
      1 => _BlynkSetupStep(
          key: const ValueKey('blynk'),
          formKey: _blynkFormKey,
          authTokenController: _authTokenController,
          templateIdController: _templateIdController,
          templateNameController: _templateNameController,
        ),
      2 => _ReviewStep(
          key: const ValueKey('review'),
          ssid: _ssidController.text.trim(),
          password: _passwordController.text,
          authToken: _authTokenController.text.trim(),
          templateId: _templateIdController.text.trim(),
          templateName: _templateNameController.text.trim(),
        ),
      _ => _ProvisionStep(
          key: const ValueKey('provision'),
          isProvisioning: ble.isProvisioning,
          provisionSucceeded: _provisionSucceeded,
          status: ble.provisioningStatus,
          rawMessage: ble.provisioningRawMessage,
          errorMessage: ble.lastError,
        ),
    };
  }
}

class _StepProgressHeader extends StatelessWidget {
  const _StepProgressHeader({
    required this.labels,
    required this.currentStep,
  });

  final List<String> labels;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (currentStep + 1) / labels.length,
            minHeight: 5,
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 420;

            if (compact) {
              return Row(
                children: [
                  _StepDot(
                    index: currentStep + 1,
                    total: labels.length,
                    label: labels[currentStep],
                    scheme: scheme,
                  ),
                  const Spacer(),
                  Text(
                    'Step ${currentStep + 1} of ${labels.length}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              );
            }

            return Row(
              children: [
                for (var i = 0; i < labels.length; i++) ...[
                  Expanded(
                    child: _StepChip(
                      label: labels[i],
                      index: i,
                      currentStep: currentStep,
                    ),
                  ),
                  if (i < labels.length - 1) const SizedBox(width: 6),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.total,
    required this.label,
    required this.scheme,
  });

  final int index;
  final int total;
  final String label;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: scheme.primary,
          child: Text(
            '$index',
            style: TextStyle(
              color: scheme.onPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.label,
    required this.index,
    required this.currentStep,
  });

  final String label;
  final int index;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = index == currentStep;
    final isComplete = index < currentStep;

    final background = isActive
        ? scheme.primaryContainer
        : isComplete
            ? scheme.secondaryContainer.withValues(alpha: 0.65)
            : scheme.surfaceContainerHighest;

    final foreground = isActive
        ? scheme.onPrimaryContainer
        : isComplete
            ? scheme.onSecondaryContainer
            : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isComplete ? Icons.check_circle : Icons.circle_outlined,
            size: 16,
            color: foreground,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WifiSetupStep extends StatelessWidget {
  const _WifiSetupStep({
    super.key,
    required this.formKey,
    required this.ssidController,
    required this.passwordController,
    required this.networks,
    required this.isScanning,
    required this.onRefresh,
    required this.onSelectSsid,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController ssidController;
  final TextEditingController passwordController;
  final List<WifiAccessPoint> networks;
  final bool isScanning;
  final VoidCallback onRefresh;
  final ValueChanged<String> onSelectSsid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _StepCard(
      title: 'Step 1 — WiFi setup',
      subtitle: 'Select a network or enter SSID manually.',
      icon: Icons.wifi_rounded,
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Nearby networks',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh scan',
                  onPressed: isScanning ? null : onRefresh,
                  icon: isScanning
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isScanning && networks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (networks.isEmpty)
              Text(
                'No networks found. Tap refresh or enter SSID manually.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: networks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final network = networks[index];
                    final selected =
                        ssidController.text.trim() == network.ssid;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        network.secure
                            ? Icons.lock_outline
                            : Icons.wifi_rounded,
                        color: selected ? scheme.primary : null,
                      ),
                      title: Text(
                        network.ssid,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('${network.rssi} dBm'),
                      trailing: selected
                          ? Icon(Icons.check_circle, color: scheme.primary)
                          : null,
                      onTap: () => onSelectSsid(network.ssid),
                    );
                  },
                ),
              ),
            const SizedBox(height: 20),
            TextFormField(
              controller: ssidController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'SSID',
                hintText: 'Network name',
                prefixIcon: Icon(Icons.router_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'SSID is required.';
                }
                if (value.trim().length > 32) {
                  return 'SSID must be 32 characters or fewer.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: passwordController,
              obscureText: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Password',
                hintText: 'Leave empty for open networks',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (value) {
                if (value != null && value.length > 64) {
                  return 'Password must be 64 characters or fewer.';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BlynkSetupStep extends StatelessWidget {
  const _BlynkSetupStep({
    super.key,
    required this.formKey,
    required this.authTokenController,
    required this.templateIdController,
    required this.templateNameController,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController authTokenController;
  final TextEditingController templateIdController;
  final TextEditingController templateNameController;

  @override
  Widget build(BuildContext context) {
    return _StepCard(
      title: 'Step 2 — Blynk setup',
      subtitle: 'Link your device to the Blynk cloud.',
      icon: Icons.cloud_outlined,
      child: Form(
        key: formKey,
        child: Column(
          children: [
            TextFormField(
              controller: authTokenController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Auth token *',
                hintText: 'Blynk device auth token',
                prefixIcon: Icon(Icons.vpn_key_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Auth token is required.';
                }
                if (value.trim().length < 20) {
                  return 'Auth token must be at least 20 characters.';
                }
                if (value.trim().length > 63) {
                  return 'Auth token must be 63 characters or fewer.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: templateIdController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Template ID',
                hintText: 'Optional',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (value) {
                if (value != null && value.trim().length > 23) {
                  return 'Template ID must be 23 characters or fewer.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: templateNameController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Template name',
                hintText: 'Optional',
                prefixIcon: Icon(Icons.label_outline),
              ),
              validator: (value) {
                if (value != null && value.trim().length > 31) {
                  return 'Template name must be 31 characters or fewer.';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    super.key,
    required this.ssid,
    required this.password,
    required this.authToken,
    required this.templateId,
    required this.templateName,
  });

  final String ssid;
  final String password;
  final String authToken;
  final String templateId;
  final String templateName;

  @override
  Widget build(BuildContext context) {
    return _StepCard(
      title: 'Step 3 — Review & confirm',
      subtitle: 'Verify your settings before provisioning the device.',
      icon: Icons.fact_check_outlined,
      child: Column(
        children: [
          _ReviewRow(label: 'SSID', value: ssid),
          _ReviewRow(
            label: 'Password',
            value: password.isEmpty ? '(open network)' : '••••••••',
          ),
          const Divider(height: 24),
          _ReviewRow(
            label: 'Auth token',
            value: _maskToken(authToken),
          ),
          _ReviewRow(
            label: 'Template ID',
            value: templateId.isEmpty ? '—' : templateId,
          ),
          _ReviewRow(
            label: 'Template name',
            value: templateName.isEmpty ? '—' : templateName,
          ),
        ],
      ),
    );
  }

  String _maskToken(String token) {
    if (token.length <= 8) return '••••••••';
    return '${token.substring(0, 4)}••••${token.substring(token.length - 4)}';
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
      ),
    );
  }
}

class _ProvisionStep extends StatelessWidget {
  const _ProvisionStep({
    super.key,
    required this.isProvisioning,
    required this.provisionSucceeded,
    required this.status,
    required this.rawMessage,
    this.errorMessage,
  });

  final bool isProvisioning;
  final bool provisionSucceeded;
  final ProvisioningStatus? status;
  final String? rawMessage;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = _provisionVisual(
      status,
      provisionSucceeded,
      scheme,
      errorMessage,
    );

    return _StepCard(
      title: 'Step 4 — Provision device',
      subtitle: 'Sending configuration to your TinkrNest switch.',
      icon: Icons.settings_bluetooth_rounded,
      child: Column(
        children: [
          if (isProvisioning || provisionSucceeded)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: provisionSucceeded
                  ? Icon(Icons.check_circle_rounded,
                      size: 64, color: scheme.primary)
                  : const SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(strokeWidth: 4),
                    ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: visual.backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(visual.icon, color: visual.foregroundColor),
                    const SizedBox(width: 10),
                    Text(
                      visual.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: visual.foregroundColor,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  visual.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: visual.foregroundColor,
                      ),
                ),
                if (rawMessage != null && rawMessage!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Response: $rawMessage',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: visual.foregroundColor.withValues(alpha: 0.85),
                          fontFamily: 'monospace',
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (provisionSucceeded) ...[
            const SizedBox(height: 16),
            Text(
              'Configuration saved. Device is rebooting.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Redirecting to dashboard…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  _ProvisionVisual _provisionVisual(
    ProvisioningStatus? status,
    bool succeeded,
    ColorScheme scheme,
    String? errorMessage,
  ) {
    if (succeeded || status == ProvisioningStatus.saved) {
      return _ProvisionVisual(
        title: 'OK:SAVED',
        message: 'Credentials accepted. The device will reboot shortly.',
        icon: Icons.verified_rounded,
        backgroundColor: scheme.primaryContainer.withValues(alpha: 0.55),
        foregroundColor: scheme.onPrimaryContainer,
      );
    }

    return switch (status) {
      ProvisioningStatus.testing => _ProvisionVisual(
          title: 'TESTING',
          message: 'Saving WiFi and Blynk credentials on the device…',
          icon: Icons.save_rounded,
          backgroundColor: scheme.tertiaryContainer.withValues(alpha: 0.55),
          foregroundColor: scheme.onTertiaryContainer,
        ),
      ProvisioningStatus.jsonError => _ProvisionVisual(
          title: 'ERR:JSON',
          message: 'Invalid JSON payload. Check your input and try again.',
          icon: Icons.error_outline,
          backgroundColor: scheme.errorContainer,
          foregroundColor: scheme.onErrorContainer,
        ),
      ProvisioningStatus.missingFields => _ProvisionVisual(
          title: 'ERR:MISSING',
          message: 'SSID and auth token are required by the device.',
          icon: Icons.error_outline,
          backgroundColor: scheme.errorContainer,
          foregroundColor: scheme.onErrorContainer,
        ),
      ProvisioningStatus.wifiFail => _ProvisionVisual(
          title: 'ERR:WIFI_FAIL',
          message: 'Device could not connect to WiFi. Verify SSID and password.',
          icon: Icons.wifi_off_rounded,
          backgroundColor: scheme.errorContainer,
          foregroundColor: scheme.onErrorContainer,
        ),
      ProvisioningStatus.unknown => _ProvisionVisual(
          title: 'ERROR',
          message: errorMessage ??
              'Provisioning failed. Flash firmware v7.0.4+ on the ESP32, '
              'factory-reset (10 s BOOT hold), then retry.',
          icon: Icons.error_outline,
          backgroundColor: scheme.errorContainer,
          foregroundColor: scheme.onErrorContainer,
        ),
      null => _ProvisionVisual(
          title: 'Waiting',
          message: 'Starting provisioning…',
          icon: Icons.hourglass_top_rounded,
          backgroundColor: scheme.surfaceContainerHighest,
          foregroundColor: scheme.onSurfaceVariant,
        ),
      ProvisioningStatus.saved => _ProvisionVisual(
          title: 'OK:SAVED',
          message: 'Configuration saved successfully.',
          icon: Icons.verified_rounded,
          backgroundColor: scheme.primaryContainer.withValues(alpha: 0.55),
          foregroundColor: scheme.onPrimaryContainer,
        ),
    };
  }
}

class _ProvisionVisual {
  const _ProvisionVisual({
    required this.title,
    required this.message,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.currentStep,
    required this.provisionStarted,
    required this.provisionSucceeded,
    required this.isProvisioning,
    required this.canProceed,
    required this.onBack,
    required this.onNext,
    required this.onRetry,
  });

  final int currentStep;
  final bool provisionStarted;
  final bool provisionSucceeded;
  final bool isProvisioning;
  final bool canProceed;
  final VoidCallback onBack;
  final Future<void> Function() onNext;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final isProvisionStep = currentStep == 3;
    final showRetry = isProvisionStep &&
        provisionStarted &&
        !isProvisioning &&
        !provisionSucceeded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 400;

          final backButton = OutlinedButton(
            onPressed: currentStep > 0 && !provisionStarted ? onBack : null,
            child: const Text('Back'),
          );

          Widget primaryButton;
          if (showRetry) {
            primaryButton = FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            );
          } else if (isProvisionStep) {
            primaryButton = FilledButton(
              onPressed: null,
              child: Text(isProvisioning ? 'Provisioning…' : 'Done'),
            );
          } else if (currentStep == 2) {
            primaryButton = FilledButton.icon(
              onPressed: canProceed && !isProvisioning ? onNext : null,
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text('Confirm & provision'),
            );
          } else {
            primaryButton = FilledButton(
              onPressed: onNext,
              child: const Text('Next'),
            );
          }

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                primaryButton,
                if (!isProvisionStep) ...[
                  const SizedBox(height: 10),
                  backButton,
                ],
              ],
            );
          }

          return Row(
            children: [
              if (!isProvisionStep) ...[
                backButton,
                const SizedBox(width: 12),
              ],
              Expanded(child: primaryButton),
            ],
          );
        },
      ),
    );
  }
}

class _ConnectionWarningBanner extends StatelessWidget {
  const _ConnectionWarningBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.bluetooth_disabled_rounded,
                color: scheme.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No BLE device connected. Scan and connect before provisioning.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onTertiaryContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
          ],
        ),
      ),
    );
  }
}
