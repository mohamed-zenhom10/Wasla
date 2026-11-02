import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/pages/ratings_page.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/theme/app_theme.dart';

class DeliveryProofPage extends StatelessWidget {
  const DeliveryProofPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  const SizedBox(height: 16),
                  _buildProofCard(),
                  const SizedBox(height: 12),
                  _buildTripCard(),
                  const SizedBox(height: 12),
                  _buildInfoCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
          Text('WASLA', style: AppTypography.eyebrow),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildProofCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  color: AppColors.darkGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Proof of delivery', style: AppTypography.headingSm),
                    const SizedBox(height: 2),
                    Text(
                      'Final delivery confirmation',
                      style: AppTypography.bodySm,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight, width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.image_outlined,
                  color: AppColors.darkGreen.withValues(alpha: 0.65),
                  size: 52,
                ),
                const SizedBox(height: 12),
                Text(
                  'Delivery photo attached',
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Received at destination',
                  style: AppTypography.bodySm,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildSummaryRow('Driver', RatingMock.driverName),
          const SizedBox(height: 12),
          _buildSummaryRow('Vehicle', RatingMock.vehicle),
          const SizedBox(height: 12),
          _buildSummaryRow('Route', RatingMock.route),
          const SizedBox(height: 12),
          _buildSummaryRow('Date', RatingMock.date),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.darkGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This confirms the move was received and completed successfully.',
              style: AppTypography.bodySm,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.bodySm)),
        Text(
          value,
          style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: WaslaButton(
        text: 'Continue to ratings',
        variant: WaslaButtonVariant.primary,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const RatingsPage()),
        ),
      ),
    );
  }
}
