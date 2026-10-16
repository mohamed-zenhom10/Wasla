import 'package:flutter/material.dart';
import 'package:main/screens/onboarding_screen.dart';
import 'package:main/screens/welcome_screen.dart';
import 'package:main/services/onboarding_service.dart';
import 'package:main/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _continueAfterSplash();
  }

  Future<void> _continueAfterSplash() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final onboardingCompleted = await OnboardingService.isCompleted();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => onboardingCompleted
            ? const WelcomeScreen()
            : const OnboardingScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkGreen,
      body: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/app_icon.png', width: 120, height: 120),
            const SizedBox(height: 24),
            const Text(
              'Wasla',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'MAKE LOGISTICS SIMPLE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w200,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
