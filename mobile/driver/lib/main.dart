import 'package:driver/screens/driver_welcome_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

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
      home: const DriverWelcomeScreen(),
    );
  }
}
