import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/pages/schedule_now_page.dart';
import 'package:main/pages/vehicle_small_page.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/theme/app_theme.dart';

class AiRecommendationPage extends StatefulWidget {
  const AiRecommendationPage({super.key});

  @override
  State<AiRecommendationPage> createState() => _AiRecommendationPageState();
}

class _AiRecommendationPageState extends State<AiRecommendationPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  const SizedBox(height: 16),
                  _buildStatusBadge(),
                  const SizedBox(height: 16),
                  _buildVehicleIllustration(),
                  const SizedBox(height: 16),
                  Text(
                    AiEstimateMock.recommendedVehicle,
                    style: AppTypography.headingSm,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  _buildDetailCard(),
                  const SizedBox(height: 12),
                  _buildDisclaimerCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back, size: 24),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const Spacer(),
          Text('WASLA AI', style: AppTypography.eyebrow),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.light,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              'High confidence',
              style: AppTypography.labelSm.copyWith(color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleIllustration() {
    return Container(
      width: double.infinity,
      height: 128,
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.darkGreen, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.local_shipping, size: 64, color: AppColors.darkGreen),
    );
  }

  Widget _buildDetailCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildDetailRow(Icons.inventory_2_outlined, 'Estimated volume', AiEstimateMock.estimatedVolume),
          const SizedBox(height: 12),
          _buildDetailRow(Icons.scale_outlined, 'Estimated weight', AiEstimateMock.estimatedWeight),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.darkGreen, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: AppTypography.bodySm),
        ),
        Text(
          value,
          style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildDisclaimerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Approximate estimate, not a certified load rating. Your driver confirms fit and safe loading before departure.',
        style: AppTypography.bodyXs,
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          WaslaButton(
            text: 'Choose another truck',
            variant: WaslaButtonVariant.secondary,
            onPressed: () => Navigator.of(context).push(
              TAMaterialRoute<void>(builder: (_) => const VehiclesSmallPage()),
            ),
          ),
          const SizedBox(height: 8),
          WaslaButton(
            text: 'Use recommendation',
            variant: WaslaButtonVariant.primary,
            onPressed: () => Navigator.of(context).push(
              TAMaterialRoute<void>(builder: (_) => const ScheduleNowPage()),
            ),
          ),
        ],
      ),
    );
  }
}