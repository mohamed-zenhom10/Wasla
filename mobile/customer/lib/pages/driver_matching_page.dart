import 'dart:async';

import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/cargo_category_page.dart';
import 'package:main/pages/no_driver_found_page.dart';
import 'package:main/pages/shipment_details_page.dart';
import 'package:main/pages/tracking_driver_arriving_page.dart';
import 'package:main/services/cargo_order_service.dart';
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
  bool _isLoading = true;
  bool _isCancelling = false;
  bool _openedNoDriverScreen = false;
  Timer? _timer;

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
      if (shipment.trip != null && !_openedNoDriverScreen) {
        _timer?.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => TrackingDriverArrivingPage(shipmentId: widget.shipmentId),
          ),
        );
        return;
      }
      if (_isNoDriverFound(shipment) && !_openedNoDriverScreen) {
        _openedNoDriverScreen = true;
        _timer?.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => NoDriverFoundPage(
              shipment: shipment,
              onTryAgain: () => _startNewBookingFrom(shipment),
            ),
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

  bool _isNoDriverFound(Shipment shipment) =>
      shipment.status == 'cancelled' &&
      shipment.cancellationParty == 'platform' &&
      shipment.cancellationReason == 'no_driver_found';

  Future<void> _viewDetails() async {
    final id = widget.shipmentId;
    if (id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShipmentDetailsPage(shipmentId: id, readOnly: true),
      ),
    );
  }

  Future<void> _cancelAndEdit() async {
    final shipment = _shipment;
    final id = widget.shipmentId;
    if (shipment == null || id == null || _isCancelling) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel and edit?'),
        content: const Text(
          'This shipment will be cancelled and a new booking will be created with the same details.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep searching'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel and edit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _cancelShipment(shipment, acceptFee: false);
  }

  Future<void> _cancelShipment(Shipment shipment, {required bool acceptFee}) async {
    setState(() => _isCancelling = true);
    try {
      await _service.cancelShipment(
        shipment,
        reason: 'Changed my mind',
        acceptFee: acceptFee,
      );
      if (!mounted) return;
      await _startNewBookingFrom(shipment);
    } on ShipmentApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'CANCEL_FEE') {
        final fee = error.details?['fee']?.toString();
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cancellation fee'),
            content: Text(
              fee == null
                  ? 'A cancellation fee applies. Do you want to continue?'
                  : 'A cancellation fee of $fee applies. Do you want to continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes'),
              ),
            ],
          ),
        );
        if (accepted == true && mounted) {
          await _cancelShipment(shipment, acceptFee: true);
        }
        return;
      }
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  Future<void> _startNewBookingFrom(Shipment shipment) async {
    final service = ShipmentService();
    final catalog = await service.getCatalog();
    final draft = CargoOrderDraft()
      ..catalog = catalog
      ..categoryId = shipment.cargoCategoryId
      ..sizeOptionId = shipment.sizeOptionId
      ..cargoDescription = shipment.cargoDescription ?? ''
      ..pickupAddress = shipment.pickup?.address ?? ''
      ..pickupLatitude = shipment.pickup?.latitude
      ..pickupLongitude = shipment.pickup?.longitude
      ..pickupNotes = shipment.pickup?.notes ?? ''
      ..dropoffAddress = shipment.dropoff?.address ?? ''
      ..dropoffLatitude = shipment.dropoff?.latitude
      ..dropoffLongitude = shipment.dropoff?.longitude
      ..dropoffNotes = shipment.dropoff?.notes ?? ''
      ..itemCount = shipment.itemCount ?? 1
      ..isFragile = shipment.isFragile ?? false
      ..weightKg = shipment.weightKg
      ..helpersCount = shipment.helpersCount ?? 0
      ..pickupType = shipment.pickupType ?? 'now'
      ..scheduledAt = shipment.pickupAt
      ..paymentMethod = shipment.paymentMethod ?? 'cash'
      ..farePaidBy = shipment.farePaidBy ?? 'sender'
      ..recipientName = shipment.recipientName ?? ''
      ..recipientPhone = shipment.recipientPhone ?? ''
      ..requestedVehicleTypeId = shipment.requestedVehicleTypeId
      ..useAiEstimate = false;

    ShipmentCargoCategory? category;
    for (final item in catalog.categories) {
      if (item.id == shipment.cargoCategoryId) {
        category = item;
        break;
      }
    }
    if (category != null) {
      draft.category = category.nameEn;
      if (shipment.sizeOptionId != null &&
          category.sizes.any((size) => size.id == shipment.sizeOptionId)) {
        draft.sizeOptionId = shipment.sizeOptionId;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CargoCategoryPage(draft: draft),
      ),
    );
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
                            ? 'Finding your driver'
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
                      if (_isLoading && shipment == null) ...[
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
                    text: 'View details',
                    variant: WaslaButtonVariant.secondary,
                    onPressed: _isCancelling ? null : _viewDetails,
                  ),
                  const SizedBox(height: 8),
                  WaslaButton(
                    text: _isCancelling ? 'Cancelling...' : 'Cancel and edit',
                    variant: WaslaButtonVariant.primary,
                    onPressed: _isCancelling ? null : _cancelAndEdit,
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
