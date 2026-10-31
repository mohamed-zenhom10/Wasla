import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/pages/driver_profile_page.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/theme/app_theme.dart';

class AvailableDriversPage extends StatefulWidget {
  const AvailableDriversPage({super.key});

  @override
  State<AvailableDriversPage> createState() => _AvailableDriversPageState();
}

class _AvailableDriversPageState extends State<AvailableDriversPage> {
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
                  _buildContextRow(),
                  const SizedBox(height: 8),
                  Text(
                    'Choose your driver',
                    style: AppTypography.headingSm,
                  ),
                  const SizedBox(height: 16),
                  ...DriverMock.available.map(_buildDriverCard),
                  const SizedBox(height: 16),
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

  Widget _buildContextRow() {
    return Row(
      children: [
        const Icon(Icons.verified_outlined, size: 14, color: AppColors.darkGreen),
        const SizedBox(width: 4),
        Text(
          '3 VERIFIED MATCHES',
          style: AppTypography.labelSm,
        ),
      ],
    );
  }

  Widget _buildDriverCard(DriverOption driver) {
    final selected = _selected == driver.id;
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
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.light,
          child: Icon(Icons.person, color: AppColors.darkGreen, size: 28),
        ),
        title: Text(driver.name, style: AppTypography.bodyMd),
        subtitle: Text(
          '${driver.vehicle} • ${driver.rating} ★',
          style: AppTypography.bodyXs,
        ),
        trailing: Column(
         mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              driver.price,
              style: AppTypography.labelSm.copyWith(color: AppColors.accent),
            ),
            const SizedBox(height: 4),
            Text(
              driver.available,
              style: AppTypography.bodyXs,
            ),
          ],
        ),
        onTap: () => setState(() => _selected = driver.id),
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: WaslaButton(
        text: 'Choose driver',
        variant: WaslaButtonVariant.primary,
        onPressed: _selected == null
            ? null
            : () => Navigator.of(context).push(
                  TAMaterialRoute<void>(
                    builder: (_) => const DriverProfilePage(),
                  ),
                ),
      ),
    );
  }
}