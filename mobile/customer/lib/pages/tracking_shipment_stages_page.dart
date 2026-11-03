import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/pages/trip_details_page.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/theme/app_theme.dart';

class TrackingShipmentStagesPage extends StatefulWidget {
  const TrackingShipmentStagesPage({super.key});

  @override
  State<TrackingShipmentStagesPage> createState() =>
      _TrackingShipmentStagesPageState();
}

class _TrackingShipmentStagesPageState extends State<TrackingShipmentStagesPage> {
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
                  _buildTitle(),
                  const SizedBox(height: 16),
                  _buildStagesList(),
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

  Widget _buildTitle() {
    return Text(
      'Shipment stages',
      style: AppTypography.headingSm,
    );
  }

  Widget _buildStagesList() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: List.generate(TrackingMock.stages.length, (index) {
          final stage = TrackingMock.stages[index];
          return Column(
            children: [
              _buildStageRow(stage.$1, stage.$2, index),
              if (index < TrackingMock.stages.length - 1)
                _buildConnector(index),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildStageRow(String label, bool done, int index) {
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_checked,
          size: 18,
          color: done ? AppColors.accent : AppColors.darkGreen,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodySm,
          ),
        ),
      ],
    );
  }

  Widget _buildConnector(int index) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      height: 24,
      width: 2,
      color: index < 2 ? AppColors.accent : AppColors.light,
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: WaslaButton(
        text: 'View trip details',
        variant: WaslaButtonVariant.primary,
        onPressed: () => Navigator.of(context).push(
          TAMaterialRoute<void>(
            builder: (_) => const TripDetailsPage(),
          ),
        ),
      ),
    );
  }
}