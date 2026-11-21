import 'package:flutter/material.dart';
import 'package:main/screens/login_screen.dart';
import 'package:main/screens/splash_screen.dart';
import 'package:main/services/auth_service.dart';
import 'package:main/theme/app_theme.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    AuthService.sessionExpired.addListener(_handleSessionExpired);
  }

  @override
  void dispose() {
    AuthService.sessionExpired.removeListener(_handleSessionExpired);
    super.dispose();
  }

  void _handleSessionExpired() {
    if (!AuthService.sessionExpired.value) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = appNavigatorKey.currentState;
      if (navigator == null) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      AuthService.clearSessionExpiredRedirect();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Wasla',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}

void main() {
  runApp(const MyApp());
}