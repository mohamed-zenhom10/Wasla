import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/shipment_details_page.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/services/shipment_service.dart';
import 'package:main/theme/app_theme.dart';

class VehiclesSmallPage extends StatefulWidget {
  const VehiclesSmallPage({super.key, required this.draft});

  final CargoOrderDraft draft;

  @override
  State<VehiclesSmallPage> createState() => _VehiclesSmallPageState();
}

class _VehiclesSmallPageState extends State<VehiclesSmallPage> {
  final _service = ShipmentService();
  String? _selectedQuoteId;
  String? _errorMessage;
  String? _errorCode;
  bool _isLoading = false;

  Shipment? get _shipment => widget.draft.shipment;

  String _vehicleName(String id) {
    final catalog = widget.draft.catalog;
    for (final vehicle
        in catalog?.vehicleTypes ?? const <ShipmentVehicleType>[]) {
      if (vehicle.id == id) {
        return vehicle.nameEn.isNotEmpty
            ? vehicle.nameEn
            : vehicle.code ?? 'Vehicle';
      }
    }
    return 'Vehicle type $id';
  }

  Future<void> _refreshQuotes() async {
    final shipment = _shipment;
    if (shipment == null || _isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorCode = null;
    });
    try {
      widget.draft.shipment = await _service.requestQuotes(shipment);
      widget.draft.selectedQuote = null;
      _selectedQuoteId = null;
    } on ShipmentApiException catch (error) {
      _showError(error.message, code: error.code);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptSelectedQuote() async {
    final shipment = _shipment;
    if (shipment == null || _selectedQuoteId == null || _isLoading) return;
    ShipmentQuote? selected;
    for (final quote in shipment.quotes) {
      if (quote.id == _selectedQuoteId) selected = quote;
    }
    if (selected == null) {
      _showError('Select an available quote.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorCode = null;
    });
    try {
      final updated = await _service.acceptQuote(
        shipment: shipment,
        quote: selected,
      );
      widget.draft.shipment = updated;
      if (updated.acceptedQuote == null) {
        _showError(
          'The server response did not include an accepted quote. Refresh shipment details before continuing.',
        );
        return;
      }
      widget.draft.selectedQuote = updated.acceptedQuote;
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ShipmentDetailsPage(
            shipmentId: updated.id,
            initialShipment: updated,
          ),
        ),
      );
    } on ShipmentApiException catch (error) {
      if (error.code == 'QUOTE_EXPIRED' ||
          error.code == 'QUOTE_OUTDATED' ||
          error.code == 'QUOTE_NOT_AVAILABLE') {
        widget.draft.selectedQuote = null;
        _selectedQuoteId = null;
      }
      _showError(error.message, code: error.code);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message, {String? code}) {
    if (mounted) {
      setState(() {
        _errorMessage = message;
        _errorCode = code;
      });
    }
  }

  Future<void> _changePickupTime() async {
    final shipment = _shipment;
    if (shipment == null || _isLoading) return;
    final now = DateTime.now();
    final lead = widget.draft.catalog?.minScheduleLeadMinutes ?? 30;
    final earliest = now.add(Duration(minutes: lead + 2));
    final date = await showDatePicker(
      context: context,
      initialDate: earliest,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(earliest),
    );
    if (time == null || !mounted) return;
    final pickupAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorCode = null;
    });
    try {
      final updated = await _service.updateDraft(shipment, {
        'pickupType': 'scheduled',
        'pickupAt': pickupAt.toUtc().toIso8601String(),
      });
      widget.draft
        ..shipment = updated
        ..pickupType = 'scheduled'
        ..scheduledAt = pickupAt;
      widget.draft.shipment = await _service.requestQuotes(updated);
    } on ShipmentApiException catch (error) {
      _showError(error.message, code: error.code);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shipment = _shipment;
    final quotes = shipment?.quotes ?? const <ShipmentQuote>[];
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  const SizedBox(height: 16),
                  Text(
                    shipment?.acceptedQuote == null
                        ? 'Available vehicle quotes'
                        : 'Accepted vehicle quote',
                    style: AppTypography.headingSm,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Shipment #${shipment?.id ?? '—'} · ${shipment?.status ?? 'unknown'}',
                    style: AppTypography.bodySm,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (_errorMessage != null) ...[
                    _errorCard(_errorMessage!),
                    if (_errorCode == 'SCHEDULE_TOO_SOON')
                      TextButton.icon(
                        onPressed: _isLoading ? null : _changePickupTime,
                        icon: const Icon(Icons.schedule),
                        label: const Text('Choose a new pickup time'),
                      ),
                  ],
                  if (quotes.isEmpty)
                    _emptyQuotes()
                  else
                    for (final quote in quotes)
                      _quoteCard(quote, selected: _selectedQuoteId == quote.id),
                  if (shipment?.acceptedQuote != null)
                    _quoteCard(shipment!.acceptedQuote!, selected: true),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            if (shipment?.acceptedQuote == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  children: [
                    WaslaButton(
                      text: 'Confirm selected price',
                      variant: WaslaButtonVariant.primary,
                      isLoading: _isLoading,
                      onPressed: _selectedQuoteId == null || _isLoading
                          ? null
                          : _acceptSelectedQuote,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isLoading ? null : _refreshQuotes,
                      child: const Text('Request fresh quotes'),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: WaslaButton(
                  text: 'View shipment details',
                  variant: WaslaButtonVariant.primary,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ShipmentDetailsPage(
                        shipmentId: shipment!.id,
                        initialShipment: shipment,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Padding(
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
  );

  Widget _emptyQuotes() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.light,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      'There are no current quotes. Request quotes again when the shipment is ready.',
      style: AppTypography.bodySm,
      textAlign: TextAlign.center,
    ),
  );

  Widget _errorCard(String message) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.light,
      border: Border.all(color: AppColors.accent),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(message, style: AppTypography.bodySm),
  );

  Widget _quoteCard(ShipmentQuote quote, {required bool selected}) {
    final vehicle = widget.draft.catalog?.vehicleTypes
        .where((item) => item.id == quote.vehicleTypeId)
        .firstOrNull;
    final isAccepted =
        widget.draft.shipment?.acceptedQuote?.id == quote.id ||
        quote.status == 'accepted';
    return Card(
      color: selected ? const Color(0xFFFFF2EF) : AppColors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? AppColors.accent : AppColors.light,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap:
            _isLoading ||
                isAccepted ||
                quote.isExpired ||
                widget.draft.shipment?.acceptedQuote != null
            ? null
            : () => setState(() {
                _selectedQuoteId = quote.id;
                widget.draft.selectedQuote = quote;
              }),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (vehicle?.imageUrl case final imageUrl?)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _vehicleIcon(),
                      ),
                    )
                  else
                    _vehicleIcon(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _vehicleName(quote.vehicleTypeId),
                      style: AppTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (quote.recommended)
                    const Chip(
                      label: Text('Recommended'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                quote.customerAmount.isEmpty
                    ? 'Customer price unavailable'
                    : quote.customerAmount,
                style: AppTypography.headingSm.copyWith(
                  color: AppColors.darkGreen,
                ),
              ),
              if (quote.helpersCount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${quote.helpersCount} helper(s) · ${quote.helpersAmount}',
                  style: AppTypography.bodyXs,
                ),
              ],
              const SizedBox(height: 4),
              Text(
                quote.expiresAt == null
                    ? 'Expiry time unavailable'
                    : quote.isExpired
                    ? 'Expired'
                    : 'Valid until ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(quote.expiresAt!.toLocal()))}',
                style: AppTypography.bodyXs,
              ),
              if (isAccepted) ...[
                const SizedBox(height: 8),
                Text('Accepted by server', style: AppTypography.labelSm),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _vehicleIcon() => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      color: AppColors.light,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(
      Icons.local_shipping_outlined,
      color: AppColors.darkGreen,
    ),
  );
}
