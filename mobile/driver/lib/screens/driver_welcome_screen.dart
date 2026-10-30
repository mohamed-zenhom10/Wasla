import 'package:driver/components/driver_components.dart';
import 'package:driver/screens/driver_application_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

class DriverWelcomeScreen extends StatelessWidget {
  const DriverWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const DriverPageHeader(label: 'Driver partner'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Drive with Wasla',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'W',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 72,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'More useful miles.\nMore earnings.',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 32,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: Image.asset(
                        'assets/images/vehicle.png',
                        height: 145,
                        fit: BoxFit.contain,
                        semanticLabel: 'Wasla delivery truck illustration',
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _BenefitsCard(),
                    const SizedBox(height: 18),
                    const Text(
                      'Have your ID, license and vehicle documents ready. '
                      'Verification keeps the marketplace safe.',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: PrimaryButton(
                  label: 'Become a driver',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DriverApplicationScreen(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitsCard extends StatelessWidget {
  const _BenefitsCard();

  @override
  Widget build(BuildContext context) {
    const benefits = [
      (Icons.location_on_outlined, 'Get local shipment requests'),
      (Icons.payments_outlined, 'Clear earnings before you accept'),
      (Icons.swap_horiz, 'Smart backhaul return trips'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final benefit in benefits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Icon(benefit.$1, color: AppColors.ink, size: 20),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      benefit.$2,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
