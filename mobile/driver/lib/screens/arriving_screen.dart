import 'package:driver/components/driver_components.dart';
import 'package:driver/screens/cargo_loaded_screen.dart';
import 'package:driver/screens/driver_home_screen.dart';
import 'package:driver/screens/requests_list_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

class ArrivingScreen extends StatelessWidget {
  const ArrivingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DriverPageHeader(
                      label: 'Navigate to pickup',
                      progress: 'WS-20481',
                    ),
                    const Text(
                      'Navigate to pickup',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const DriverMapPreview(height: 288),
                    const SizedBox(height: 16),
                    const _PickupDetails(),
                    const SizedBox(height: 16),
                    const _CargoDetails(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: PrimaryButton(
                label: "I've arrived",
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CargoLoadedScreen(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: DriverNavigationBar(
        currentIndex: 0,
        onDestinationSelected: (index) {
          if (index == 0) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          } else if (index == 1) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RequestsListScreen(),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'This section does not have a supplied design yet.',
                ),
              ),
            );
          }
        },
      ),
    );
  }
}

class _PickupDetails extends StatelessWidget {
  const _PickupDetails();

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
          _DetailLine(
            icon: Icons.near_me_outlined,
            text: '12 Abbas El Akkad, Nasr City  ·  Navigate',
          ),
          SizedBox(height: 14),
          _DetailLine(icon: Icons.phone_outlined, text: 'Mariam Adel  ·  Call / Chat'),
          SizedBox(height: 10),
          Text(
            '2nd floor · Lift available · Gate 2',
            style: TextStyle(color: AppColors.ink, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CargoDetails extends StatelessWidget {
  const _CargoDetails();

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
            'Cargo  ·  12 items · Furniture',
            style: TextStyle(color: AppColors.ink, fontSize: 12),
          ),
          SizedBox(height: 16),
          Text(
            'Payment to collect  ·  EGP 540 · Cash',
            style: TextStyle(color: AppColors.ink, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

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
