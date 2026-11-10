import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/pages/smart_backhaul_page.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/theme/app_theme.dart';

class PriceEstimatePage extends StatelessWidget {
  const PriceEstimatePage({super.key, required this.draft});

  final CargoOrderDraft draft;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back, size: 24),
                  ),
                  const Spacer(),
                  Text('WASLA', style: AppTypography.eyebrow),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  const SizedBox(height: 32),
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 56,
                    color: AppColors.darkGreen,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Price estimate unavailable',
                    style: AppTypography.headingSm,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Pricing is not connected, so no fare or fee breakdown can be calculated.',
                    style: AppTypography.bodyMd,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.light,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Current draft', style: AppTypography.labelSm),
                        const SizedBox(height: 10),
                        _DraftRow(
                          label: 'Vehicle preference',
                          value: draft.vehicleId ?? 'Not selected',
                        ),
                        _DraftRow(
                          label: 'Schedule',
                          value:
                              draft.scheduledAt?.toLocal().toString() ??
                              'Not selected',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: WaslaButton(
                text: 'Continue without a price estimate',
                variant: WaslaButtonVariant.primary,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SmartBackhaulPage(draft: draft),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: AppTypography.bodyXs)),
          Expanded(child: Text(value, style: AppTypography.bodySm)),
        ],
      ),
    );
  }
}
