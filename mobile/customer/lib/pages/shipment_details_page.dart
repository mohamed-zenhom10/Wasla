import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/cargo_category_page.dart';
import 'package:main/pages/vehicle_small_page.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/services/shipment_service.dart';
import 'package:main/theme/app_theme.dart';

class ShipmentDetailsPage extends StatefulWidget {
  const ShipmentDetailsPage({
    super.key,
    required this.shipmentId,
    this.initialShipment,
  });

  final String shipmentId;
  final Shipment? initialShipment;

  @override
  State<ShipmentDetailsPage> createState() => _ShipmentDetailsPageState();
}

class _ShipmentDetailsPageState extends State<ShipmentDetailsPage> {
  final _service = ShipmentService();
  Shipment? _shipment;
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _shipment = widget.initialShipment;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      _shipment = await _service.getShipment(widget.shipmentId);
    } on ShipmentApiException catch (error) {
      _errorMessage = error.message;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _withdrawPrice() async {
    final shipment = _shipment;
    if (shipment == null || shipment.acceptedQuote == null || _isLoading) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw accepted price?'),
        content: const Text(
          'This cancels the accepted price. The shipment will become editable and require new quotes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep price'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Withdraw price'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      _shipment = await _service.withdrawPrice(shipment);
    } on ShipmentApiException catch (error) {
      _errorMessage = error.message;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editDraft(Shipment shipment) async {
    try {
      final catalog = await _service.getCatalog();
      final category = catalog.categories
          .where((item) => item.id == shipment.cargoCategoryId)
          .firstOrNull;
      final draft = CargoOrderDraft()
        ..catalog = catalog
        ..shipment = shipment
        ..categoryId = shipment.cargoCategoryId
        ..category = category?.nameEn ?? ''
        ..sizeOptionId = shipment.sizeOptionId
        ..description = shipment.cargoDescription ?? ''
        ..itemCount = shipment.itemCount ?? 1
        ..isFragile = shipment.isFragile ?? false
        ..weightKg = shipment.weightKg
        ..helpersCount = shipment.helpersCount ?? 0
        ..pickup = shipment.pickup?.address ?? ''
        ..pickupLatitude = shipment.pickup?.latitude
        ..pickupLongitude = shipment.pickup?.longitude
        ..pickupNotes = shipment.pickup?.notes ?? ''
        ..destination = shipment.dropoff?.address ?? ''
        ..dropoffLatitude = shipment.dropoff?.latitude
        ..dropoffLongitude = shipment.dropoff?.longitude
        ..dropoffNotes = shipment.dropoff?.notes ?? ''
        ..pickupType = shipment.pickupType ?? 'now'
        ..scheduledAt = shipment.pickupAt
        ..paymentMethod = shipment.paymentMethod ?? 'cash'
        ..farePaidBy = shipment.farePaidBy ?? 'sender'
        ..recipientName = shipment.recipientName ?? ''
        ..recipientPhone = shipment.recipientPhone ?? '';
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CargoCategoryPage(draft: draft),
        ),
      );
    } on ShipmentApiException catch (error) {
      setState(() => _errorMessage = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shipment = _shipment;
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text('Shipment #${widget.shipmentId}'),
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.darkGreen,
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _refresh,
            tooltip: 'Refresh shipment',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: shipment == null && _isLoading
          ? const Center(child: CircularProgressIndicator())
          : shipment == null
          ? _messageState(_errorMessage ?? 'Shipment details are unavailable.')
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_errorMessage != null) _messageState(_errorMessage!),
                _section('Status', [
                  Text(shipment.status, style: AppTypography.headingSm),
                  if (shipment.acceptedQuote != null)
                    Text(
                      'Price accepted · ${shipment.acceptedQuote!.customerAmount}',
                      style: AppTypography.bodyMd,
                    ),
                  if (shipment.acceptedQuote != null)
                    const Text(
                      'A driver has not been assigned by this action.',
                    ),
                ]),
                const SizedBox(height: 12),
                _section('Cargo', [
                  _row('Category ID', shipment.cargoCategoryId),
                  _row('Description', shipment.cargoDescription),
                  _row('Items', shipment.itemCount?.toString()),
                  _row('Helpers', shipment.helpersCount?.toString()),
                  _row('Fragile', shipment.isFragile?.toString()),
                ]),
                const SizedBox(height: 12),
                _section('Route', [
                  _row('Pickup', shipment.pickup?.address),
                  _row('Drop-off', shipment.dropoff?.address),
                  _row(
                    'Pickup time',
                    (shipment.pickupWindowStart ?? shipment.pickupAt)
                        ?.toLocal()
                        .toString(),
                  ),
                ]),
                if (shipment.acceptedQuote != null &&
                    shipment.deliveryCode != null) ...[
                  const SizedBox(height: 12),
                  _section('Delivery code', [
                    Text(
                      shipment.deliveryCode!,
                      style: AppTypography.headingSm,
                    ),
                    const Text(
                      'Share this code with the driver at delivery only.',
                    ),
                  ]),
                ],
                if (shipment.photos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _section('Cargo photos', [
                    for (final photo in shipment.photos)
                      ListTile(
                        leading: const Icon(Icons.photo_outlined),
                        title: Text('Photo ${photo.id}'),
                        subtitle: const Text(
                          'Photo link expires one hour after retrieval.',
                        ),
                        trailing: IconButton(
                          onPressed: () => _openPhoto(photo),
                          icon: const Icon(Icons.open_in_new),
                        ),
                      ),
                  ]),
                ],
                if (shipment.timeline.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _section('Timeline', [
                    for (final entry in shipment.timeline)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.circle, size: 10),
                        title: Text(entry.to),
                        subtitle: Text(
                          [
                            entry.by,
                            if (entry.at != null)
                              entry.at!.toLocal().toString(),
                          ].join(' · '),
                        ),
                      ),
                  ]),
                ],
                const SizedBox(height: 18),
                if (shipment.acceptedQuote != null)
                  WaslaButton(
                    text: 'Withdraw accepted price',
                    variant: WaslaButtonVariant.secondary,
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _withdrawPrice,
                  )
                else if (shipment.isEditable) ...[
                  WaslaButton(
                    text: 'Edit draft shipment',
                    variant: WaslaButtonVariant.primary,
                    onPressed: _isLoading ? null : () => _editDraft(shipment),
                  ),
                  const SizedBox(height: 8),
                  WaslaButton(
                    text: 'Request new quotes',
                    variant: WaslaButtonVariant.secondary,
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _requestQuotes,
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _requestQuotes() async {
    final shipment = _shipment;
    if (shipment == null || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      final catalog = await _service.getCatalog();
      final updatedShipment = await _service.requestQuotes(shipment);
      _shipment = updatedShipment;
      final category = catalog.categories
          .where((item) => item.id == updatedShipment.cargoCategoryId)
          .firstOrNull;
      final draft = CargoOrderDraft()
        ..catalog = catalog
        ..shipment = updatedShipment
        ..categoryId = updatedShipment.cargoCategoryId
        ..category = category?.nameEn ?? ''
        ..sizeOptionId = updatedShipment.sizeOptionId
        ..description = updatedShipment.cargoDescription ?? ''
        ..itemCount = updatedShipment.itemCount ?? 1
        ..isFragile = updatedShipment.isFragile ?? false
        ..weightKg = updatedShipment.weightKg
        ..helpersCount = updatedShipment.helpersCount ?? 0
        ..pickup = updatedShipment.pickup?.address ?? ''
        ..pickupLatitude = updatedShipment.pickup?.latitude
        ..pickupLongitude = updatedShipment.pickup?.longitude
        ..pickupNotes = updatedShipment.pickup?.notes ?? ''
        ..destination = updatedShipment.dropoff?.address ?? ''
        ..dropoffLatitude = updatedShipment.dropoff?.latitude
        ..dropoffLongitude = updatedShipment.dropoff?.longitude
        ..dropoffNotes = updatedShipment.dropoff?.notes ?? ''
        ..pickupType = updatedShipment.pickupType ?? 'now'
        ..scheduledAt = updatedShipment.pickupAt
        ..paymentMethod = updatedShipment.paymentMethod ?? 'cash'
        ..farePaidBy = updatedShipment.farePaidBy ?? 'sender'
        ..recipientName = updatedShipment.recipientName ?? ''
        ..recipientPhone = updatedShipment.recipientPhone ?? '';
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VehiclesSmallPage(draft: draft),
        ),
      );
    } on ShipmentApiException catch (error) {
      _errorMessage = error.message;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openPhoto(ShipmentPhoto photo) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Cargo photo')),
          body: Center(
            child: Image.network(
              photo.url,
              errorBuilder: (_, _, _) =>
                  const Text('This temporary photo link has expired.'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.light,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.labelSm),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );

  Widget _row(String label, String? value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 105, child: Text(label, style: AppTypography.bodyXs)),
        Expanded(child: Text(value?.isNotEmpty == true ? value! : '—')),
      ],
    ),
  );

  Widget _messageState(String message) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(message, style: AppTypography.bodySm),
  );
}
