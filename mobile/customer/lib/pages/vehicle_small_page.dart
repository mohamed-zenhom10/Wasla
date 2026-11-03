import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/pages/schedule_now_page.dart';
import 'package:main/theme/app_theme.dart';

class VehiclesSmallPage extends StatefulWidget {
  const VehiclesSmallPage({super.key});

  @override
  State<VehiclesSmallPage> createState() => _VehiclesSmallPageState();
}

class _VehiclesSmallPageState extends State<VehiclesSmallPage> {
  String? _selected;

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
                  Text(
                    'Choose your truck',
                    style: AppTypography.headingSm,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Small & quarter ton',
                    style: AppTypography.bodySm,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ...VehicleMock.smallAndQuarter.map(_buildVehicleCard),
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

  Widget _buildVehicleCard(VehicleOption option) {
    final selected = _selected == option.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.light,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(Icons.local_shipping, color: AppColors.darkGreen, size: 32),
        title: Text(option.name, style: AppTypography.bodyMd),
        subtitle: Text(option.description, style: AppTypography.bodyXs),
        trailing: Text(
          option.price,
          style: AppTypography.labelSm.copyWith(color: AppColors.accent),
        ),
        onTap: () => setState(() => _selected = option.id),
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: WaslaButton(
        text: 'Continue',
        variant: WaslaButtonVariant.primary,
        onPressed: _selected == null
            ? null
            : () => Navigator.of(context).push(
                  TAMaterialRoute<void>(builder: (_) => const ScheduleNowPage()),
                ),
      ),
    );
  }
}