import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/pages/chat_page.dart';
import 'package:main/pages/tracking_driver_arriving_page.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/theme/app_theme.dart';

class DriverProfilePage extends StatefulWidget {
  const DriverProfilePage({super.key});

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
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
                  _buildProfileCard(),
                  const SizedBox(height: 12),
                  _buildStatsCard(),
                  const SizedBox(height: 12),
                  _buildVehicleCard(),
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

  Widget _buildProfileCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.white,
            child: Icon(Icons.person, color: AppColors.darkGreen, size: 40),
          ),
          const SizedBox(height: 12),
          Text(
            DriverMock.ahmed.name,
            style: AppTypography.headingSm,
          ),
          const SizedBox(height: 4),
          Text(
            DriverMock.ahmed.rating,
            style: AppTypography.bodySm,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildStat('Trips', '${DriverMock.ahmed.completed}'),
          _buildStat('Rating', DriverMock.ahmed.rating),
          _buildStat('Vehicle', DriverMock.ahmed.vehicle),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(label, style: AppTypography.bodyXs),
        ],
      ),
    );
  }

  Widget _buildVehicleCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.local_shipping, color: AppColors.darkGreen, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vehicle', style: AppTypography.labelSm),
                Text(DriverMock.ahmed.vehicle, style: AppTypography.bodyMd),
              ],
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
      child: Row(
        children: [
          Icon(Icons.phone_outlined, color: AppColors.darkGreen, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Driver will call 15 min before arrival.',
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
      child: Column(
        children: [
          WaslaButton(
            text: 'Confirm and track',
            variant: WaslaButtonVariant.primary,
            onPressed: () => Navigator.of(context).push(
              TAMaterialRoute<void>(
                builder: (_) => const TrackingDriverArrivingPage(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          WaslaButton(
            text: 'Chat with driver',
            variant: WaslaButtonVariant.secondary,
            onPressed: () => Navigator.of(context).push(
              TAMaterialRoute<void>(
                builder: (_) => const ChatPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}