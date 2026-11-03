import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/pages/booking_review_page.dart';
import 'package:main/theme/app_theme.dart';

class PriceEstimatePage extends StatefulWidget {
  const PriceEstimatePage({super.key});

  @override
  State<PriceEstimatePage> createState() => _PriceEstimatePageState();
}

class _PriceEstimatePageState extends State<PriceEstimatePage> {
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
                  _buildPriceBadge(),
                  const SizedBox(height: 16),
                  _buildPriceCard(),
                  const SizedBox(height: 12),
                  _buildBreakdownCard(),
                  const SizedBox(height: 12),
                  _buildNoteCard(),
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

  Widget _buildPriceBadge() {
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.light,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Estimated price',
          style: AppTypography.labelSm,
        ),
      ),
    );
  }

  Widget _buildPriceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.darkGreen, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            AiEstimateMock.estimatedPrice,
            style: AppTypography.headingSm.copyWith(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.darkGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Final price confirmed by driver',
            style: AppTypography.bodyXs,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildBreakdownRow(Icons.receipt_outlined, 'Base fare', AiEstimateMock.baseFare),
          const SizedBox(height: 12),
          _buildBreakdownRow(Icons.receipt_outlined, 'Distance', AiEstimateMock.distanceFee),
          const SizedBox(height: 12),
          _buildBreakdownRow(Icons.receipt_outlined, 'Tolls & fees', AiEstimateMock.tollsFee),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(IconData icon, String label, String value) {
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

  Widget _buildNoteCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Price may change based on actual route, traffic, and loading time. Driver will confirm before starting.',
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
            text: 'Continue to booking review',
            variant: WaslaButtonVariant.primary,
            onPressed: () => Navigator.of(context).push(
              TAMaterialRoute<void>(builder: (_) => const BookingReviewPage()),
            ),
          ),
          const SizedBox(height: 8),
          WaslaButton(
            text: 'Back to schedule',
            variant: WaslaButtonVariant.ghost,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}