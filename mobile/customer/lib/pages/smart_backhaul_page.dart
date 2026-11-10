import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/pages/booking_review_page.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/theme/app_theme.dart';

class SmartBackhaulPage extends StatelessWidget {
  const SmartBackhaulPage({super.key, required this.draft});

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
                    Icons.swap_horiz,
                    size: 56,
                    color: AppColors.darkGreen,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No backhaul offer available',
                    style: AppTypography.headingSm,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Return-load offers are not connected. No discount, route, or return cargo has been assumed.',
                    style: AppTypography.bodyMd,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: WaslaButton(
                text: 'Continue without backhaul',
                variant: WaslaButtonVariant.primary,
                onPressed: () {
                  draft.backhaulAccepted = false;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BookingReviewPage(draft: draft),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
