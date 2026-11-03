import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/pages/delivery_complete_page.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/theme/app_theme.dart';

class TripDetailsPage extends StatefulWidget {
  const TripDetailsPage({super.key});

  @override
  State<TripDetailsPage> createState() => _TripDetailsPageState();
}

class _TripDetailsPageState extends State<TripDetailsPage> {
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
                  _buildStatusCard(),
                  const SizedBox(height: 12),
                  _buildRouteCard(),
                  const SizedBox(height: 12),
                  _buildItemsCard(),
                  const SizedBox(height: 12),
                  _buildSummaryCard(),
                  const SizedBox(height: 12),
                  _buildDriverCard(),
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

  Widget _buildStatusCard() {
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
          Text('Reference', style: AppTypography.labelSm),
          const Spacer(),
          Text(TripMock.reference, style: AppTypography.bodyMd),
        ],
      ),
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
          _buildRouteRow(Icons.local_shipping_outlined, 'Pickup', TripMock.pickup, TripMock.pickupTime),
          const SizedBox(height: 12),
          _buildRouteRow(Icons.location_on_outlined, 'Drop-off', TripMock.dropoff, TripMock.estimatedDelivery),
        ],
      ),
    );
  }

  Widget _buildRouteRow(IconData icon, String label, String address, String time) {
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
              Text(time, style: AppTypography.bodyXs),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItemsCard() {
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
          Text('Items', style: AppTypography.labelSm),
          const SizedBox(height: 8),
          for (final item in TripMock.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.accent, size: 16),
                  const SizedBox(width: 8),
                  Text(item, style: AppTypography.bodySm),
                ],
              ),
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
        Text(value, style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildDriverCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.white,
            child: Icon(Icons.person, color: AppColors.darkGreen, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(TripMock.driverName, style: AppTypography.bodyMd),
                Text(TripMock.driverRating, style: AppTypography.bodyXs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          WaslaButton(
            text: 'Continue to delivery',
            variant: WaslaButtonVariant.primary,
            onPressed: () => Navigator.of(context).push(
              TAMaterialRoute<void>(
                builder: (_) => const DeliveryCompletePage(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}