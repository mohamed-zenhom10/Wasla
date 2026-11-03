import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/theme/app_theme.dart';

class DriverMatchingPage extends StatefulWidget {
  const DriverMatchingPage({super.key});

  @override
  State<DriverMatchingPage> createState() => _DriverMatchingPageState();
}

class _DriverMatchingPageState extends State<DriverMatchingPage> {
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _runFlow();
  }

  Future<void> _runFlow() async {
    for (var i = 1; i <= 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() => _step = i);
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _showDriverSheet();
  }

  void _showDriverSheet() {
    showBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.light,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Driver found',
              style: AppTypography.headingSm,
            ),
            const SizedBox(height: 8),
            Text(
              'Your driver is on the way',
              style: AppTypography.bodySm,
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.light,
                child: Icon(Icons.person, color: AppColors.darkGreen),
              ),
              title: Text('Ahmed Hassan', style: AppTypography.bodyMd),
              subtitle: Text('Quarter Truck • 4.9 ★', style: AppTypography.bodyXs),
            ),
            const SizedBox(height: 24),
            WaslaButton(
              text: 'Track driver',
              variant: WaslaButtonVariant.primary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

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
                  const SizedBox(height: 32),
                  const Icon(Icons.local_shipping, size: 64, color: AppColors.accent),
                  const SizedBox(height: 24),
                  Text(
                    'Matching you with a driver...',
                    style: AppTypography.headingSm,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We are finding the best driver for your cargo.',
                    style: AppTypography.bodyMd,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _buildProgress(),
                  const SizedBox(height: 24),
                  _buildStatusList(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
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

  Widget _buildProgress() {
    return Row(
      children: List.generate(4, (index) {
        final done = index < _step;
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: index < 3 ? 8 : 0),
            decoration: BoxDecoration(
              color: done ? AppColors.accent : AppColors.light,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStatusList() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildStatusRow('Booking confirmed', _step > 0),
          const SizedBox(height: 12),
          _buildStatusRow('Driver assigned', _step > 1),
          const SizedBox(height: 12),
          _buildStatusRow('On the way', _step > 2),
          const SizedBox(height: 12),
          _buildStatusRow('Arrived', _step > 3),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, bool done) {
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_checked,
          size: 18,
          color: done ? AppColors.accent : AppColors.light,
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
}