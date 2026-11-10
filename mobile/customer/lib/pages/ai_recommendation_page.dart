import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/pages/vehicle_small_page.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/theme/app_theme.dart';

class AiRecommendationPage extends StatelessWidget {
  const AiRecommendationPage({super.key, required this.draft});

  final CargoOrderDraft draft;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back, size: 24),
                  ),
                  const Spacer(),
                  Text('WASLA AI', style: AppTypography.eyebrow),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  const SizedBox(height: 32),
                  const Icon(
                    Icons.local_shipping_outlined,
                    size: 64,
                    color: AppColors.darkGreen,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No recommendation available',
                    style: AppTypography.headingSm,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The AI estimation service is not connected, so a vehicle cannot be recommended.',
                    style: AppTypography.bodyMd,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.light,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Select a vehicle preference manually. Availability and pricing are not confirmed.',
                      style: AppTypography.bodySm,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: WaslaButton(
                text: 'Choose vehicle manually',
                variant: WaslaButtonVariant.primary,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => VehiclesSmallPage(draft: draft),
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
