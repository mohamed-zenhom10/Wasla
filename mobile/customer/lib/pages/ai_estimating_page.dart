import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/pages/vehicle_small_page.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/theme/app_theme.dart';

class AiEstimatingPage extends StatelessWidget {
  const AiEstimatingPage({super.key, required this.draft});

  final CargoOrderDraft draft;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
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
                  Text('WASLA AI', style: AppTypography.eyebrow),
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
                    Icons.auto_awesome,
                    size: 64,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'AI cargo estimates are not available yet',
                    style: AppTypography.headingSm.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your cargo details are saved in this booking draft. No estimate was requested.',
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
                    child: Text(
                      'The customer app has no AI estimation service configured. Choose a vehicle preference manually to continue; no AI result or recommendation will be shown.',
                      style: AppTypography.bodySm,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: WaslaButton(
                text: 'Choose vehicle manually',
                variant: WaslaButtonVariant.primary,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => VehiclesSmallPage(draft: draft),
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
