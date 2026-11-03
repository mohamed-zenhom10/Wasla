import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/pages/driver_matching_page.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/theme/app_theme.dart';

class BookingReviewPage extends StatefulWidget {
  const BookingReviewPage({super.key});

  @override
  State<BookingReviewPage> createState() => _BookingReviewPageState();
}

class _BookingReviewPageState extends State<BookingReviewPage> {
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
                  _buildSummaryCard(),
                  const SizedBox(height: 12),
                  _buildRouteCard(),
                  const SizedBox(height: 12),
                  _buildPriceCard(),
                  const SizedBox(height: 12),
                  _buildContactCard(),
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

  Widget _buildStatusBadge() {
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.light,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Booking review',
          style: AppTypography.labelSm,
        ),
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
          _buildSummaryRow(Icons.category_outlined, 'Category', BookingSummaryMock.category),
          const SizedBox(height: 12),
          _buildSummaryRow(Icons.local_shipping_outlined, 'Vehicle', BookingSummaryMock.vehicle),
          const SizedBox(height: 12),
          _buildSummaryRow(Icons.access_time_outlined, 'Pickup', BookingSummaryMock.pickupTime),
          const SizedBox(height: 12),
          _buildSummaryRow(Icons.receipt_outlined, 'Delivery', BookingSummaryMock.estimatedDelivery),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(IconData icon, String label, String value) {
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

  Widget _buildRouteCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildRouteRow(Icons.local_shipping_outlined, 'Pickup', BookingSummaryMock.pickup),
          const SizedBox(height: 12),
          _buildRouteRow(Icons.location_on_outlined, 'Drop-off', BookingSummaryMock.dropoff),
        ],
      ),
    );
  }

  Widget _buildRouteRow(IconData icon, String label, String address) {
    return Row(
      children: [
        Icon(icon, color: AppColors.darkGreen, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.labelSm),
              Text(address, style: AppTypography.bodySm),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.darkGreen, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text('Total', style: AppTypography.bodyMd),
          const Spacer(),
          Text(
            BookingSummaryMock.price,
            style: AppTypography.headingSm.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.darkGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Driver will call 15 min before arrival. Keep this number handy.',
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
            text: 'Confirm booking',
            variant: WaslaButtonVariant.primary,
            onPressed: () => Navigator.of(context).push(
              TAMaterialRoute<void>(builder: (_) => const DriverMatchingPage()),
            ),
          ),
          const SizedBox(height: 8),
          WaslaButton(
            text: 'Edit details',
            variant: WaslaButtonVariant.ghost,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}