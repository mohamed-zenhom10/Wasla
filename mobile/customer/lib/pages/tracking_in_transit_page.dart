import 'dart:async';

import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/tracking_shipment_stages_page.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/screens/home_screen.dart';
import 'package:main/services/shipment_service.dart';
import 'package:main/theme/app_theme.dart';

class TrackingInTransitPage extends StatefulWidget {
  const TrackingInTransitPage({super.key, this.shipmentId});

  final String? shipmentId;

  @override
  State<TrackingInTransitPage> createState() => _TrackingInTransitPageState();
}

class _TrackingInTransitPageState extends State<TrackingInTransitPage> {
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
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
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
      if (shipment.status == 'delivered') {
        if (mounted) {
          context.findAncestorStateOfType<HomeScreenState>()?.resetLocationSelection();
        }
      }
      final terminal = shipment.status == 'delivered' ||
          shipment.status == 'cancelled' ||
          shipment.trip == null && shipment.status == 'searching_driver';
      if (terminal) _timer?.cancel();
    } on ShipmentApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  String _driverName() => _shipment?.trip?.driverName ?? 'Driver not assigned';
  String _vehicle() {
    final trip = _shipment?.trip;
    if (trip == null) return 'Vehicle not assigned';
    return [
      if (trip.make != null) trip.make,
      if (trip.model != null) trip.model,
      if (trip.plateNumber != null) trip.plateNumber,
    ].whereType<String>().join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final shipment = _shipment;
    final tracking = _tracking;
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
                        _buildMapCard(tracking),
                        const SizedBox(height: 12),
                        _buildStatusCard(shipment, tracking),
                        const SizedBox(height: 12),
                        _buildTrackingCard(tracking),
                        const SizedBox(height: 12),
                        _buildDriverCard(shipment),
                        const SizedBox(height: 12),
                        _buildRouteCard(shipment),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(_errorMessage!, style: const TextStyle(color: AppColors.accent)),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
            _buildActions(shipment),
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

  Widget _buildMapCard(ShipmentTracking? tracking) {
    final location = tracking?.driverLocation;
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: location == null
            ? const Text('Driver location unavailable')
            : Text(
                'Driver: ${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}',
                style: AppTypography.bodySm,
              ),
      ),
    );
  }

  Widget _buildStatusCard(Shipment? shipment, ShipmentTracking? tracking) {
    final status = shipment?.status ?? 'unknown';
    final tripStatus = tracking?.tripStatus ?? shipment?.trip?.status ?? '—';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(status, style: AppTypography.headingSm, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Trip status: $tripStatus', style: AppTypography.bodyMd, textAlign: TextAlign.center),
          if (shipment?.trip == null && shipment?.status == 'searching_driver') ...[
            const SizedBox(height: 8),
            const Text('Driver cancelled or no driver assigned yet.', style: TextStyle(color: AppColors.accent)),
          ],
          if (shipment?.status == 'delivered') ...[
            const SizedBox(height: 8),
            const Text('Delivery completed.', style: TextStyle(color: AppColors.darkGreen)),
          ],
        ],
      ),
    );
  }

  Widget _buildTrackingCard(ShipmentTracking? tracking) {
    if (tracking == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.light, borderRadius: BorderRadius.circular(12)),
        child: Text('Tracking data is not available yet.', style: AppTypography.bodySm),
      );
    }
    final signal = tracking.signal ?? 'unknown';
    final lost = signal == 'lost';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
        border: lost ? Border.all(color: AppColors.accent) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Signal: $signal', style: AppTypography.bodyMd),
          if (lost) const Text('No recent driver signal.', style: TextStyle(color: AppColors.accent)),
          const SizedBox(height: 8),
          Text('Next stop: ${tracking.nextStop ?? '—'}', style: AppTypography.bodySm),
          Text('Distance to next stop: ${tracking.distanceToNextStopM?.toString() ?? '—'} m', style: AppTypography.bodySm),
          if (tracking.driverLocation != null)
            Text(
              'Location accuracy: ${tracking.driverAccuracyM?.toStringAsFixed(1) ?? '—'} m',
              style: AppTypography.bodySm,
            ),
        ],
      ),
    );
  }

  Widget _buildDriverCard(Shipment? shipment) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.light, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_driverName(), style: AppTypography.bodyMd),
          Text(_vehicle(), style: AppTypography.bodyXs),
          if (shipment?.trip?.driverPhone != null)
            Text(shipment!.trip!.driverPhone!, style: AppTypography.bodyXs),
        ],
      ),
    );
  }

  Widget _buildRouteCard(Shipment? shipment) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.light, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Pickup', shipment?.pickup?.address ?? '—'),
          _row('Drop-off', shipment?.dropoff?.address ?? '—'),
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

  Widget _buildActions(Shipment? shipment) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          WaslaButton(
            text: 'View shipment stages',
            variant: WaslaButtonVariant.primary,
            onPressed: () => Navigator.of(context).push(
              TAMaterialRoute<void>(
                builder: (_) => TrackingShipmentStagesPage(shipmentId: widget.shipmentId),
              ),
            ),
          ),
          const SizedBox(height: 8),
          WaslaButton(
            text: 'Refresh',
            variant: WaslaButtonVariant.secondary,
            onPressed: () => _load(),
          ),
        ],
      ),
    );
  }
}
