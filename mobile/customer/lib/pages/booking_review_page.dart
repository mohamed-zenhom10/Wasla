import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/theme/app_theme.dart';

class BookingReviewPage extends StatelessWidget {
  const BookingReviewPage({super.key, required this.draft});

  final CargoOrderDraft draft;

  String _vehicleName() {
    final options = [
      ...VehicleMock.smallAndQuarter,
      ...VehicleMock.jumboAndHeavy,
    ];
    for (final option in options) {
      if (option.id == draft.vehicleId) return option.name;
    }
    return 'Not selected';
  }

  String _route() => [
    draft.pickup,
    ...draft.stops,
    draft.destination,
  ].where((part) => part.trim().isNotEmpty).join(' → ');

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
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.light,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Booking draft review',
                        style: AppTypography.labelSm,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _section('Cargo', [
                    _row('Category', draft.category),
                    _row('Description', draft.description),
                    _row('Size', draft.size),
                    _row('Notes', draft.notes),
                  ]),
                  const SizedBox(height: 12),
                  _section('Route', [
                    _row('Route', _route()),
                    if (draft.stops.isNotEmpty)
                      _row('Extra stops', '${draft.stops.length}'),
                  ]),
                  const SizedBox(height: 12),
                  _section('Preferences', [
                    _row('Vehicle', _vehicleName()),
                    _row(
                      'Schedule',
                      draft.scheduledAt?.toLocal().toString() ?? 'Not selected',
                    ),
                    _row(
                      'Backhaul',
                      draft.backhaulAccepted == false
                          ? 'No offer available'
                          : 'Not selected',
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.light,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'This is only a local draft. The booking, pricing, payment, and driver APIs are not configured. Nothing has been submitted or reserved.',
                      style: AppTypography.bodySm,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: [
                  WaslaButton(
                    text: 'Booking submission unavailable',
                    variant: WaslaButtonVariant.primary,
                    onPressed: null,
                  ),
                  const SizedBox(height: 8),
                  WaslaButton(
                    text: 'Back to previous step',
                    variant: WaslaButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.light,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.labelSm),
        const SizedBox(height: 12),
        ...rows,
      ],
    ),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 92, child: Text(label, style: AppTypography.bodyXs)),
        Expanded(
          child: Text(
            value.isEmpty ? 'Not provided' : value,
            style: AppTypography.bodySm,
          ),
        ),
      ],
    ),
  );
}
