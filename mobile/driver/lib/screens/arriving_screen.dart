import 'package:driver/components/driver_components.dart';
import 'package:driver/components/driver_session.dart';
import 'package:driver/data/driver_api.dart';
import 'package:driver/data/driver_location.dart';
import 'package:driver/data/driver_trip_location_reporter.dart';
import 'package:driver/screens/cargo_loaded_screen.dart';
import 'package:driver/screens/driver_home_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

class ArrivingScreen extends StatefulWidget {
  const ArrivingScreen({super.key, required this.trip, this.api});

  final Map<String, dynamic> trip;
  final DriverApi? api;

  @override
  State<ArrivingScreen> createState() => _ArrivingScreenState();
}

class _ArrivingScreenState extends State<ArrivingScreen> {
  late final DriverApi _api = widget.api ?? DriverApi();
  late Map<String, dynamic> _trip = widget.trip;
  late final DriverTripLocationReporter _locationReporter =
      DriverTripLocationReporter(_api, (error) {
        if (!mounted || handleDriverSessionError(context, error)) return;
        setState(() => _error = _message(error));
      });
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _locationReporter.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _advance() async {
    if (_busy) return;
    final id = _trip['id']?.toString();
    if (id == null) {
      setState(() => _error = 'Trip identifier is missing. Refresh the trip.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final location = await DriverLocation.current();
      if (_trip['status'] == 'assigned') {
        _trip = await _api.updateTrip(id, 'start', body: location);
        _locationReporter.start();
        if (mounted) setState(() {});
      } else if (_trip['status'] == 'heading_to_pickup') {
        _locationReporter.start();
        _trip = await _api.updateTrip(id, 'arrive-pickup', body: location);
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => CargoLoadedScreen(trip: _trip, api: widget.api),
          ),
        );
      }
    } catch (error) {
      if (!mounted || handleDriverSessionError(context, error)) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelTrip() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this trip?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep trip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Cancel trip'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    if (reason.isEmpty) {
      setState(() => _error = 'Enter a reason to cancel the trip.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.cancelTrip(_trip['id'].toString(), reason);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted || handleDriverSessionError(context, error)) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) => error is DriverApiException
      ? error.message
      : error is StateError
      ? error.message
      : 'تعذر تحديث حالة الرحلة. حاول مرة أخرى.';

  String _text(Object? value, [String fallback = '—']) =>
      value?.toString().trim().isNotEmpty == true ? value.toString() : fallback;

  @override
  Widget build(BuildContext context) {
    final status = _trip['status'] as String? ?? 'assigned';
    final headingToPickup = status == 'heading_to_pickup';
    final pickup =
        (_trip['pickup'] as Map?)?.cast<String, dynamic>() ?? const {};
    final dropoff =
        (_trip['dropoff'] as Map?)?.cast<String, dynamic>() ?? const {};
    final customer =
        (_trip['customer'] as Map?)?.cast<String, dynamic>() ?? const {};
    final recipient =
        (_trip['recipient'] as Map?)?.cast<String, dynamic>() ?? const {};
    final buttonLabel = _busy
        ? 'Updating trip...'
        : headingToPickup
        ? "I've arrived at pickup"
        : 'Start navigation to pickup';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DriverPageHeader(
                      label: headingToPickup
                          ? 'Navigate to pickup'
                          : 'Accepted shipment',
                      progress: 'Trip ${_text(_trip['id'])}',
                    ),
                    Text(
                      headingToPickup ? 'Navigate to pickup' : 'Pickup details',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const DriverMapPreview(height: 288),
                    const SizedBox(height: 16),
                    _InfoCard(
                      title: 'Pickup',
                      address: _text(pickup['address']),
                      notes: _text(pickup['notes'], ''),
                    ),
                    const SizedBox(height: 12),
                    _InfoCard(
                      title: 'Drop-off',
                      address: _text(dropoff['address']),
                      notes: _text(dropoff['notes'], ''),
                    ),
                    if (customer.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _InfoCard(
                        title: 'Customer',
                        address: _text(customer['name']),
                        notes: _text(customer['phone'], ''),
                      ),
                    ],
                    if (recipient.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _InfoCard(
                        title: 'Recipient',
                        address: _text(recipient['name']),
                        notes: _text(recipient['phone'], ''),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      '${_trip['itemCount'] ?? 0} items · '
                      '${_trip['weightKg'] ?? 0} kg · '
                      '${_trip['paymentMethod'] ?? '—'}',
                      style: const TextStyle(color: AppColors.ink),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PrimaryButton(
                    label: buttonLabel,
                    onPressed: _busy ? null : _advance,
                  ),
                  TextButton(
                    onPressed: _busy ? null : _cancelTrip,
                    child: const Text('Cancel trip'),
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.address,
    required this.notes,
  });

  final String title;
  final String address;
  final String notes;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(address),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(notes, style: const TextStyle(color: AppColors.muted)),
        ],
      ],
    ),
  );
}
