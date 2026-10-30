import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/pages/booking_review_page.dart';
import 'package:main/theme/app_theme.dart';

class SmartBackhaulPage extends StatefulWidget {
  const SmartBackhaulPage({super.key});

  @override
  State<SmartBackhaulPage> createState() => _SmartBackhaulPageState();
}

class _SmartBackhaulPageState extends State<SmartBackhaulPage> {

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
                  _buildBadge(),
                  const SizedBox(height: 16),
                  _buildOfferCard(),
                  const SizedBox(height: 12),
                  _buildDetailCard(),
                  const SizedBox(height: 12),
                  _buildTermsCard(),
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

  Widget _buildBadge() {
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
              'Smart backhaul',
              style: AppTypography.labelSm.copyWith(color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferCard() {
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
            SmartBackhaulMock.offerTitle,
            style: AppTypography.headingSm,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            SmartBackhaulMock.offerDescription,
            style: AppTypography.bodyMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            SmartBackhaulMock.offerPrice,
            style: AppTypography.headingSm.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.darkGreen,
            ),
          ),
        ],
      ),
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
          _buildDetailRow(Icons.local_shipping_outlined, 'Return load', SmartBackhaulMock.returnLoad),
          const SizedBox(height: 12),
          _buildDetailRow(Icons.route_outlined, 'Return route', SmartBackhaulMock.returnRoute),
          const SizedBox(height: 12),
          _buildDetailRow(Icons.savings_outlined, 'Savings', SmartBackhaulMock.savings),
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

  Widget _buildTermsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Accepting this offer means your driver will pick up a return load on the way back. You can decline without penalty.',
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
            text: 'Accept and continue',
            variant: WaslaButtonVariant.primary,
            onPressed: () => Navigator.of(context).push(
              TAMaterialRoute<void>(builder: (_) => const BookingReviewPage()),
            ),
          ),
          const SizedBox(height: 8),
          WaslaButton(
            text: 'Decline',
            variant: WaslaButtonVariant.ghost,
            onPressed: () => Navigator.of(context).push(
              TAMaterialRoute<void>(builder: (_) => const BookingReviewPage()),
            ),
          ),
        ],
      ),
    );
  }
}