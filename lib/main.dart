import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/repositories/timer_repository.dart';
import 'providers/auth_provider.dart';
import 'providers/ble_provider.dart';
import 'providers/smart_switch_provider.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timer repository
  final timerRepository = await TimerRepository.create();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => BleProvider()),
        ChangeNotifierProvider(
          create: (_) => SmartSwitchProvider(repository: timerRepository),
        ),
      ],
      child: const TinkrNestApp(),
    ),
  );
}
