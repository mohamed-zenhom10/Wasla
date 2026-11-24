import 'package:driver/screens/driver_welcome_screen.dart';
import 'package:driver/components/driver_chat_overlay.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const WaslaDriverApp());
}

class WaslaDriverApp extends StatelessWidget {
  const WaslaDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wasla Driver',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: _rootNavigatorKey,
      builder: (context, child) => DriverChatLauncher(
        navigatorKey: _rootNavigatorKey,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const DriverWelcomeScreen(),
    );
  }
}
