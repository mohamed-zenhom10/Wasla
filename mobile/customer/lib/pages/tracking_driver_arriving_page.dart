import 'dart:async';

import 'package:flutter/material.dart';
import 'package:main/components/customer_tracking_map.dart';
import 'package:main/components/main_button.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/tracking_in_transit_page.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/services/shipment_service.dart';
import 'package:main/theme/app_theme.dart';

class TrackingDriverArrivingPage extends StatefulWidget {
  const TrackingDriverArrivingPage({super.key, this.shipmentId});

  final String? shipmentId;

  @override
  State<TrackingDriverArrivingPage> createState() =>
      _TrackingDriverArrivingPageState();
}

class _TrackingDriverArrivingPageState
    extends State<TrackingDriverArrivingPage> {
  final _service = ShipmentService();
  Shipment? _shipment;
  ShipmentTracking? _tracking;
  String? _errorMessage;
  bool _isLoading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (widget.shipmentId == null || !mounted) return;
    if (!silent) setState(() => _isLoading = true);
    try {
      final shipment = await _service.getShipment(widget.shipmentId!);
      ShipmentTracking? tracking;
      try {
        tracking = await _service.getTracking(widget.shipmentId!);
      } on ShipmentApiException {
        tracking = null;
      }
      if (!mounted) return;
      setState(() {
        _shipment = shipment;
        _tracking = tracking;
        _errorMessage = null;
      });
      if (shipment.status == 'delivered' || shipment.status == 'cancelled') {
        _timer?.cancel();
      }
    } on ShipmentApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shipment = _shipment;
    final trip = shipment?.trip;
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading && shipment == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        const SizedBox(height: 16),
                        if (shipment != null)
                          CustomerTrackingMap(
                            shipment: shipment,
                            tracking: _tracking,
                            height: 260,
                          ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.light,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Driver is arriving',
                                style: AppTypography.headingSm,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                trip?.driverName ?? 'Waiting for driver',
                                style: AppTypography.bodyMd,
                                textAlign: TextAlign.center,
                              ),
                              if (trip?.vehicleTypeId != null)
                                Text(
                                  'Vehicle type ${trip!.vehicleTypeId}',
                                  style: AppTypography.bodyXs,
                                  textAlign: TextAlign.center,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.light,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _row('Pickup', shipment?.pickup?.address ?? '—'),
                              _row(
                                'Drop-off',
                                shipment?.dropoff?.address ?? '—',
                              ),
                              _row('Status', shipment?.status ?? '—'),
                            ],
                          ),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: AppColors.accent),
                          ),
                        ],
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: WaslaButton(
                text: 'Track live',
                variant: WaslaButtonVariant.primary,
                onPressed: () => Navigator.of(context).push(
                  TAMaterialRoute<void>(
                    builder: (_) =>
                        TrackingInTransitPage(shipmentId: widget.shipmentId),
                  ),
                ),
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

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 84, child: Text(label, style: AppTypography.bodyXs)),
        Expanded(child: Text(value, style: AppTypography.bodySm)),
      ],
    ),
  );
}
