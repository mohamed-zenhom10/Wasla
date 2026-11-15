import 'dart:async';

import 'package:driver/components/driver_components.dart';
import 'package:driver/components/driver_session.dart';
import 'package:driver/data/driver_api.dart';
import 'package:driver/screens/arriving_screen.dart';
import 'package:driver/screens/driver_home_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

class IncomingRequestScreen extends StatefulWidget {
  const IncomingRequestScreen({super.key, required this.offer, this.api});

  final Map<String, dynamic> offer;
  final DriverApi? api;

  @override
  State<IncomingRequestScreen> createState() => _IncomingRequestScreenState();
}

class _IncomingRequestScreenState extends State<IncomingRequestScreen> {
  late final DriverApi _api = widget.api ?? DriverApi();
  Timer? _timer;
  late int _secondsRemaining =
      (widget.offer['secondsLeft'] as num?)?.toInt() ?? 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsRemaining <= 1) {
        _timer?.cancel();
        if (mounted) setState(() => _secondsRemaining = 0);
      } else {
        if (mounted) setState(() => _secondsRemaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expired = _secondsRemaining == 0;
    final countdown = expired
        ? 'REQUEST EXPIRED'
        : 'ACCEPT WITHIN $_secondsRemaining SEC';

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
                      label: 'New shipment request',
                      progress: countdown,
                    ),
                    const Text(
                      'New shipment request',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const DriverMapPreview(height: 192),
                    const SizedBox(height: 16),
                    _EarningsPanel(offer: widget.offer),
                    const SizedBox(height: 16),
                    _AddressPanel(offer: widget.offer),
                    const SizedBox(height: 16),
                    _CargoPanel(offer: widget.offer),
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
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: _busy || expired ? null : _decline,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(color: AppColors.ink),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Decline',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  PrimaryButton(
                    label: expired ? 'Request expired' : 'Accept request',
                    onPressed: expired || _busy ? null : _accept,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final trip = await _api.acceptOffer(widget.offer['id'].toString());
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ArrivingScreen(trip: trip, api: widget.api),
        ),
      );
    } catch (error) {
      if (!mounted || handleDriverSessionError(context, error)) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.declineOffer(widget.offer['id'].toString());
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
      : 'تعذر تنفيذ الطلب. تحقق من اتصالك وحاول مجددًا.';
}

class _EarningsPanel extends StatelessWidget {
  const _EarningsPanel({required this.offer});

  final Map<String, dynamic> offer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR NET EARNINGS',
            style: TextStyle(color: AppColors.white, fontSize: 10),
          ),
          SizedBox(height: 12),
          Text(
            'EGP ${offer['driverEarning'] ?? '0.00'}',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 12),
          Text(
            '${offer['fareAmount'] ?? '0.00'} gross − '
            '${offer['commissionAmount'] ?? '0.00'} commission',
            style: TextStyle(color: AppColors.white, fontSize: 12),
          ),
          if (offer['cashToCollect'] != null) ...[
            SizedBox(height: 8),
            Text(
              'Cash to collect · EGP ${offer['cashToCollect']}',
              style: TextStyle(color: AppColors.white, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddressPanel extends StatelessWidget {
  const _AddressPanel({required this.offer});

  final Map<String, dynamic> offer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _AddressLine(
            icon: Icons.radio_button_checked,
            label:
                (offer['pickup'] as Map?)?['address']?.toString() ?? 'Pickup',
            type: 'Pickup',
          ),
          SizedBox(height: 18),
          _AddressLine(
            icon: Icons.location_on_outlined,
            label:
                (offer['dropoff'] as Map?)?['address']?.toString() ??
                'Drop-off',
            type: 'Drop-off',
          ),
        ],
      ),
    );
  }
}

class _AddressLine extends StatelessWidget {
  const _AddressLine({
    required this.icon,
    required this.label,
    required this.type,
  });

  final IconData icon;
  final String label;
  final String type;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.ink),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: '$label  ·  ',
              children: [
                TextSpan(
                  text: type,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            style: const TextStyle(color: AppColors.ink, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _CargoPanel extends StatelessWidget {
  const _CargoPanel({required this.offer});

  final Map<String, dynamic> offer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 23),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cargo  ·  ${offer['cargoDescription'] ?? 'Shipment'}',
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${offer['itemCount'] ?? 0} items · ${offer['weightKg'] ?? 0} kg · '
            '${offer['helpersCount'] ?? 0} helpers',
            style: const TextStyle(color: AppColors.ink, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            offer['pickupType'] == 'now'
                ? 'Pickup now'
                : 'Scheduled · ${offer['pickupWindowStart'] ?? 'time pending'}',
            style: const TextStyle(color: AppColors.ink, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
