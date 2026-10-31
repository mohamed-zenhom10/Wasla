import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/theme/app_theme.dart';

class DeliveryCompletePage extends StatefulWidget {
  const DeliveryCompletePage({super.key});

  @override
  State<DeliveryCompletePage> createState() => _DeliveryCompletePageState();
}

class _DeliveryCompletePageState extends State<DeliveryCompletePage> {
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
                  _buildSuccessCard(),
                  const SizedBox(height: 12),
                  _buildSummaryCard(),
                  const SizedBox(height: 12),
                  _buildProofCard(),
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
          Text('WASLA', style: AppTypography.eyebrow),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              color: AppColors.darkGreen,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          Text('Delivery complete', style: AppTypography.headingSm),
          const SizedBox(height: 4),
          Text(
            TripMock.actualDelivery,
            style: AppTypography.bodySm,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildSummaryRow('Reference', TripMock.reference),
          const SizedBox(height: 12),
          _buildSummaryRow('Route', TripMock.route),
          const SizedBox(height: 12),
          _buildSummaryRow('Distance', TripMock.distance),
          const SizedBox(height: 12),
          _buildSummaryRow('Duration', TripMock.duration),
          const SizedBox(height: 12),
          _buildSummaryRow('Price', TripMock.price),
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

  Widget _buildProofCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_outlined, color: AppColors.darkGreen, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Proof of delivery will be collected on the next screen.',
              style: AppTypography.bodySm,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: WaslaButton(
        text: 'Continue to delivery proof',
        variant: WaslaButtonVariant.primary,
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}