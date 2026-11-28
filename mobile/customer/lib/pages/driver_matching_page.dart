import 'dart:async';

import 'package:flutter/material.dart';
import 'package:main/components/customer_tracking_map.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/cargo_category_page.dart';
import 'package:main/pages/no_driver_found_page.dart';
import 'package:main/pages/shipment_details_page.dart';
import 'package:main/pages/tracking_driver_arriving_page.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/services/shipment_service.dart';
import 'package:main/theme/app_theme.dart';

enum _ShipmentEditAction { withdraw, cancel, none }

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
  bool _isCancelling = false;
  bool _openedNoDriverScreen = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refresh(silent: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (widget.shipmentId == null || !mounted) return;
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
            builder: (_) =>
                TrackingDriverArrivingPage(shipmentId: widget.shipmentId),
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

    final action = _resolveEditAction(shipment);
    if (action == _ShipmentEditAction.none) {
      if (!mounted) return;
      setState(() => _errorMessage = 'This shipment can no longer be edited.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This shipment can no longer be edited.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel and edit?'),
        content: Text(
          action == _ShipmentEditAction.withdraw
              ? 'This accepted price will be withdrawn and a new booking will be created with the same details.'
              : 'This shipment will be cancelled and a new booking will be created with the same details.',
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

    if (action == _ShipmentEditAction.withdraw) {
      await _withdrawPriceAndEdit(shipment);
      return;
    }
    await _cancelShipment(shipment, acceptFee: false);
  }

  _ShipmentEditAction _resolveEditAction(Shipment shipment) {
    if (shipment.status == 'draft') {
      return shipment.acceptedQuote == null
          ? _ShipmentEditAction.none
          : _ShipmentEditAction.withdraw;
    }
    if (shipment.status == 'searching_driver') {
      return _ShipmentEditAction.cancel;
    }
    final trip = shipment.trip;
    final tripStatus = trip?.status;
    if (tripStatus == 'assigned' ||
        tripStatus == 'heading_to_pickup' ||
        tripStatus == 'arrived_at_pickup') {
      return _ShipmentEditAction.cancel;
    }
    if (tripStatus == 'cargo_loaded') {
      return _ShipmentEditAction.none;
    }
    return _ShipmentEditAction.none;
  }

  Future<void> _withdrawPriceAndEdit(Shipment shipment) async {
    setState(() => _isCancelling = true);
    try {
      await _service.withdrawPrice(shipment);
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shipment withdrawn for editing.')),
      );
      await _startNewBookingFrom(shipment);
    } on ShipmentApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  Future<void> _cancelShipment(
    Shipment shipment, {
    required bool acceptFee,
    bool feeResolved = false,
  }) async {
    setState(() => _isCancelling = true);
    try {
      await _service.cancelShipment(
        shipment,
        reason: 'Changed my mind',
        acceptFee: acceptFee,
      );
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shipment cancelled successfully.')),
      );
      await _startNewBookingFrom(shipment);
    } on ShipmentApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'CANCEL_FEE') {
        if (!feeResolved) {
          final fee = error.details?['fee']?.toString();
          final accepted = await _confirmCancelFee(fee);
          if (accepted == true) {
            await _cancelShipment(shipment, acceptFee: true, feeResolved: true);
          }
        }
        return;
      }
      if (error.code == 'CARGO_LOADED') {
        setState(() => _errorMessage = error.message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
        return;
      }
      setState(() => _errorMessage = error.message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  Future<bool?> _confirmCancelFee(String? fee) async {
    return await showDialog<bool>(
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

    final category = catalog.categories
        .where((item) => item.id == shipment.cargoCategoryId)
        .fold<ShipmentCargoCategory?>(null, (previous, item) => item);
    if (category != null) {
      draft.category = category.nameEn;
      if (shipment.sizeOptionId != null &&
          category.sizes.any((size) => size.id == shipment.sizeOptionId)) {
        draft.sizeOptionId = shipment.sizeOptionId;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => CargoCategoryPage(draft: draft)),
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back, size: 24),
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    shipment == null ? 'Shipment' : 'Shipment #${shipment.id}',
                    style: AppTypography.bodyMd.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Finding your driver',
                  style: AppTypography.headingMd,
                ),
              ),
            ),
            SizedBox(
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: shipment == null
                    ? const Center(child: CircularProgressIndicator())
                    : CustomerTrackingMap(shipment: shipment, height: 300),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Finding the best driver for you...',
                            style: AppTypography.headingSm,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Checking available verified trucks near the pickup location.',
                      style: AppTypography.bodyMd,
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppColors.accent),
                      ),
                    ],
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
                        _InfoRow(
                          label: 'Estimated match time',
                          value: 'Not available',
                        ),
                        const SizedBox(height: 10),
                        _InfoRow(
                          label: 'Saved total',
                          value: 'Not available',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _isCancelling ? null : _viewDetails,
                      child: const Text('Details'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _isCancelling ? null : _cancelAndEdit,
                      child: Text(
                        _isCancelling ? 'Cancelling...' : 'Cancel and edit',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.bodyMd)),
        Text(
          value,
          style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
