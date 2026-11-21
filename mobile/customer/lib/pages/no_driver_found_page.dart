import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/shipment_details_page.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/theme/app_theme.dart';

class NoDriverFoundPage extends StatelessWidget {
  const NoDriverFoundPage({
    super.key,
    required this.shipment,
    required this.onTryAgain,
  });

  final Shipment shipment;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No driver found', style: AppTypography.headingLg),
              const SizedBox(height: 12),
              Text(
                'We could not find a driver for this shipment. It has been cancelled automatically without cancellation fees.',
                style: AppTypography.bodyMd,
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.light,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Shipment #${shipment.id}', style: AppTypography.bodyMd),
                    const SizedBox(height: 8),
                    Text(
                      'Cancellation reason: ${shipment.cancellationReason ?? 'no_driver_found'}',
                      style: AppTypography.bodySm,
                    ),
                    Text(
                      'Cancellation party: ${shipment.cancellationParty ?? 'platform'}',
                      style: AppTypography.bodySm,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No refund information was provided by the backend for this cancellation.',
                      style: AppTypography.bodySm,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              WaslaButton(
                text: 'Try Again',
                variant: WaslaButtonVariant.primary,
                onPressed: onTryAgain,
              ),
              const SizedBox(height: 8),
              WaslaButton(
                text: 'View details',
                variant: WaslaButtonVariant.secondary,
                onPressed: () => Navigator.of(context).push(
                  TAMaterialRoute<void>(
                    builder: (_) => ShipmentDetailsPage(
                      shipmentId: shipment.id,
                      readOnly: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
