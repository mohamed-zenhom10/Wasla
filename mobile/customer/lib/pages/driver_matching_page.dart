import 'dart:async';

import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/tracking_driver_arriving_page.dart';
import 'package:main/services/shipment_service.dart';
import 'package:main/theme/app_theme.dart';

class DriverMatchingPage extends StatefulWidget {
  const DriverMatchingPage({super.key, this.shipmentId});

  final String? shipmentId;

  @override
  State<DriverMatchingPage> createState() => _DriverMatchingPageState();
}

class _DriverMatchingPageState extends State<DriverMatchingPage> {
  final _service = ShipmentService();
  Shipment? _shipment;
  String? _errorMessage;
  bool _isLoading = false;
  Timer? _timer;
  bool _navigatedToTracking = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (widget.shipmentId == null || !mounted) return;
    if (!silent) setState(() => _isLoading = true);
    try {
      final shipment = await _service.getShipment(widget.shipmentId!);
      if (!mounted) return;
      setState(() {
        _shipment = shipment;
        _errorMessage = null;
      });
      if (shipment.trip != null && !_navigatedToTracking) {
        _navigatedToTracking = true;
        _timer?.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => TrackingDriverArrivingPage(shipmentId: widget.shipmentId),
          ),
        );
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
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.person_search_outlined,
                        size: 64,
                        color: AppColors.darkGreen,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        shipment == null
                            ? 'Searching for a driver'
                            : 'Status: ${shipment.status}',
                        style: AppTypography.headingSm,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage ??
                            'Waiting for a driver to accept your shipment.',
                        style: AppTypography.bodyMd,
                        textAlign: TextAlign.center,
                      ),
                      if (shipment?.trip != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Driver assigned: ${shipment!.trip!.driverName ?? 'Driver'}',
                          style: AppTypography.bodyMd,
                        ),
                      ],
                      if (_isLoading) ...[
                        const SizedBox(height: 20),
                        const CircularProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: [
                  WaslaButton(
                    text: 'Refresh',
                    variant: WaslaButtonVariant.secondary,
                    onPressed: _isLoading ? null : () => _refresh(),
                  ),
                  const SizedBox(height: 8),
                  WaslaButton(
                    text: 'Back',
                    variant: WaslaButtonVariant.primary,
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
}
