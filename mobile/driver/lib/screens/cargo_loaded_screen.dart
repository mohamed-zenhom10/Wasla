import 'package:driver/components/driver_components.dart';
import 'package:driver/screens/proof_of_delivery_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

class CargoLoadedScreen extends StatelessWidget {
  const CargoLoadedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DriverPageHeader(
                      label: 'Ready to start the trip',
                      progress: 'WS-20481',
                    ),
                    const Text(
                      'Ready to start the trip',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Icon(
                      Icons.inventory_2_outlined,
                      color: AppColors.accent,
                      size: 56,
                    ),
                    const SizedBox(height: 24),
                    const _LoadingChecklist(),
                    const SizedBox(height: 16),
                    const _TripRouteCard(),
                    const SizedBox(height: 16),
                    const _TripTimeCard(),
                    const SizedBox(height: 16),
                    const Text(
                      'Starting the trip notifies Mariam and activates live tracking.',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: PrimaryButton(
                label: 'Start trip',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ProofOfDeliveryScreen(),
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

class _LoadingChecklist extends StatelessWidget {
  const _LoadingChecklist();

  @override
  Widget build(BuildContext context) {
    const checks = [
      'All 12 items loaded  ·  ✓',
      'Fragile items protected  ·  ✓',
      'Load secured and within capacity  ·  ✓',
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
          for (final check in checks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_box_outlined,
                    color: AppColors.ink,
                    size: 19,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      check,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 12,
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

class _TripRouteCard extends StatelessWidget {
  const _TripRouteCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          _TripAddress(
            icon: Icons.radio_button_checked,
            text: '12 Abbas El Akkad, Nasr City  ·  Pickup',
          ),
          SizedBox(height: 18),
          _TripAddress(
            icon: Icons.location_on_outlined,
            text: '18 Road 9, Maadi  ·  Drop-off',
          ),
        ],
      ),
    );
  }
}

class _TripAddress extends StatelessWidget {
  const _TripAddress({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: AppColors.ink),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.ink, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _TripTimeCard extends StatelessWidget {
  const _TripTimeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Loaded at  ·  14:16',
            style: TextStyle(color: AppColors.ink, fontSize: 12),
          ),
          SizedBox(height: 22),
          Text(
            'Estimated delivery  ·  15:10',
            style: TextStyle(color: AppColors.ink, fontSize: 12),
          ),
          SizedBox(height: 22),
          Text(
            'Cash to collect  ·  EGP 540',
            style: TextStyle(color: AppColors.ink, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
