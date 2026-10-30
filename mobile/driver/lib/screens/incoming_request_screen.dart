import 'dart:async';

import 'package:driver/components/driver_components.dart';
import 'package:driver/screens/driver_home_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

class IncomingRequestScreen extends StatefulWidget {
  const IncomingRequestScreen({super.key});

  @override
  State<IncomingRequestScreen> createState() => _IncomingRequestScreenState();
}

class _IncomingRequestScreenState extends State<IncomingRequestScreen> {
  static const _requestWindow = 30;
  Timer? _timer;
  int _secondsRemaining = _requestWindow;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsRemaining <= 1) {
        _timer?.cancel();
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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
                    const _EarningsPanel(),
                    const SizedBox(height: 16),
                    const _AddressPanel(),
                    const SizedBox(height: 16),
                    const _CargoPanel(),
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
                      onPressed: () => _showPreviewNotice(context, 'decline'),
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
                    onPressed: expired
                        ? null
                        : () => _showPreviewNotice(context, 'accept'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPreviewNotice(BuildContext context, String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Request $action is a local preview; the backend has no request '
          'endpoint yet.',
        ),
      ),
    );
  }
}

class _EarningsPanel extends StatelessWidget {
  const _EarningsPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR NET EARNINGS',
            style: TextStyle(color: AppColors.white, fontSize: 10),
          ),
          SizedBox(height: 12),
          Text(
            'EGP 432',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'EGP 540 gross − EGP 108 commission',
            style: TextStyle(color: AppColors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AddressPanel extends StatelessWidget {
  const _AddressPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          _AddressLine(
            icon: Icons.radio_button_checked,
            label: '12 Abbas El Akkad, Nasr City',
            type: 'Pickup',
          ),
          SizedBox(height: 18),
          _AddressLine(
            icon: Icons.location_on_outlined,
            label: '18 Road 9, Maadi',
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
  const _CargoPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 23),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Cargo  ·  Furniture · 12 items',
        style: TextStyle(color: AppColors.ink, fontSize: 12),
      ),
    );
  }
}
