import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_routes.dart';
import '../core/router/app_router.dart';
import '../providers/auth_provider.dart';
import '../providers/ble_provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final auth = context.watch<AuthProvider>();
    final isDark = themeProvider.themeMode == ThemeMode.dark ||
        (themeProvider.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: AppRouter.pop,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const _SettingsSectionHeader(title: 'Appearance'),
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark theme'),
              subtitle: const Text('Use dark color scheme'),
              value: isDark,
              onChanged: themeProvider.toggleDarkMode,
            ),
            ListTile(
              leading: const Icon(Icons.brightness_auto_outlined),
              title: const Text('Follow system theme'),
              trailing: themeProvider.themeMode == ThemeMode.system
                  ? const Icon(Icons.check_circle, size: 20)
                  : null,
              onTap: () => themeProvider.setThemeMode(ThemeMode.system),
            ),
            const Divider(height: 32),
            const _SettingsSectionHeader(title: 'Account'),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Signed in as'),
              subtitle: Text(auth.userEmail ?? 'Not signed in'),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sign out'),
              onTap: () async {
                await auth.signOut();
                if (!context.mounted) return;
                await AppRouter.pushReplacementNamed(AppRoutes.login);
              },
            ),
            const Divider(height: 32),
            const _SettingsSectionHeader(title: 'Device setup'),
            const ListTile(
              leading: Icon(Icons.bluetooth_searching),
              title: Text('Factory reset → BLE setup'),
              subtitle: Text(
                'Hold the BOOT button on the ESP32 for 10 seconds. '
                'The device clears WiFi/Blynk settings and reboots into '
                'setup mode (LED blinks fast). Open Find Device in the app '
                'to configure WiFi and Blynk again.',
              ),
              isThreeLine: true,
            ),
            const ListTile(
              leading: Icon(Icons.touch_app_outlined),
              title: Text('Button guide'),
              subtitle: Text(
                'Short press: reboot · 3 s hold: restart BLE · '
                '10 s hold: factory reset',
              ),
              isThreeLine: true,
            ),
            ListTile(
              leading: const Icon(Icons.settings_input_antenna),
              title: const Text('Configure connected device'),
              subtitle: const Text('WiFi + Blynk provisioning wizard'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final ble = context.read<BleProvider>();
                if (!ble.isConnected) {
                  AppRouter.pushNamed(AppRoutes.bleScan);
                  return;
                }
                AppRouter.pushNamed(AppRoutes.provision);
              },
            ),
            const Divider(height: 32),
            const _SettingsSectionHeader(title: 'About'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('App name'),
              subtitle: Text('TinkrNest Smart Switch'),
            ),
            const ListTile(
              leading: Icon(Icons.tag),
              title: Text('Version'),
              subtitle: Text('1.0.0+1'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}
