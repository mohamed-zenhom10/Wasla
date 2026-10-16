import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/screens/login_screen.dart';
import 'package:main/screens/phone_screen.dart';
import 'package:main/theme/app_theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'W',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 76,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                'One app. Every\nmove.',
                style: TextStyle(
                  color: AppColors.darkGreen,
                  fontSize: 36,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 34),
              const Text(
                'Welcome to Wasla. Move your world with trusted local drivers and the right truck for the job.',
                style: TextStyle(
                  color: AppColors.darkGreen,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: Image.asset(
                  'assets/images/vehicle.png',
                  width: double.infinity,
                  height: 140,
                  fit: BoxFit.contain,
                  semanticLabel: 'Wasla delivery truck illustration',
                ),
              ),
              const SizedBox(height: 26),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.light,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_outlined, size: 16),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Built for Egypt. Ready for your next move.',
                        style: TextStyle(
                          color: AppColors.darkGreen,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'By continuing, you agree to our Terms and Privacy Policy.',
                style: TextStyle(
                  color: AppColors.darkGreen,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.darkGreen,
                  minimumSize: const Size.fromHeight(54),
                  side: const BorderSide(color: AppColors.darkGreen),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('I already have an account'),
              ),
              const SizedBox(height: 8),
              MainButton(
                text: 'Continue with phone',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PhoneScreen()),
                ),
                borderRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
