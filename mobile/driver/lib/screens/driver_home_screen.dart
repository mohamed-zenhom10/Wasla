import 'dart:async';

import 'package:driver/components/driver_components.dart';
import 'package:driver/components/driver_navigation_map.dart';
import 'package:driver/components/driver_session.dart';
import 'package:driver/data/driver_api.dart';
import 'package:driver/data/driver_location.dart';
import 'package:driver/screens/arriving_screen.dart';
import 'package:driver/screens/cargo_loaded_screen.dart';
import 'package:driver/screens/driver_route_planner_screen.dart';
import 'package:driver/screens/proof_of_delivery_screen.dart';
import 'package:driver/screens/requests_list_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key, this.api});

  final DriverApi? api;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  late final DriverApi _api = widget.api ?? DriverApi();
  Timer? _locationTimer;
  Map<String, dynamic> _status = const {};
  String _driverName = 'Driver';
  bool _loading = true;
  bool _busy = false;
  bool _tripOpened = false;
  String? _error;

  bool get _isOnline => _status['online'] == true;
  List<String> get _blockers => (_status['blockers'] as List? ?? const [])
      .map((item) => item.toString())
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _api.getDriverStatus(),
        _api.getMe(),
        _api.getCurrentTrip(),
      ]);
      final status = values[0] as Map<String, dynamic>;
      final user =
          ((values[1] as Map<String, dynamic>)['user'] as Map?)
              ?.cast<String, dynamic>() ??
          const {};
      final trip = values[2];
      if (!mounted) return;
      setState(() {
        _status = status;
        _driverName = user['fullName']?.toString().split(' ').first ?? 'Driver';
        _loading = false;
        _error = null;
      });
      final tripRunning =
          trip != null &&
          const [
            'heading_to_pickup',
            'arrived_at_pickup',
            'loaded',
            'heading_to_dropoff',
            'arrived_at_dropoff',
          ].contains(trip['status']);
      _configureLocationUpdates(tripRunning);
      if (trip != null) _openTrip(trip);
    } catch (error) {
      if (!mounted) return;
      if (handleDriverSessionError(context, error)) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _setOnline(bool value) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = value
          ? await _api.setOnline(await DriverLocation.current())
          : await _api.setOffline();
      if (!mounted) return;
      setState(() => _status = status);
      _configureLocationUpdates(false);
    } catch (error) {
      if (!mounted || handleDriverSessionError(context, error)) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _configureLocationUpdates(bool tripRunning) {
    _locationTimer?.cancel();
    if (tripRunning || !_isOnline) return;
    _locationTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _sendLocation(),
    );
  }

  Future<void> _sendLocation() async {
    try {
      final status = await _api.sendLocation(await DriverLocation.current());
      if (mounted) setState(() => _status = status);
    } on DriverApiException catch (error) {
      if (!mounted) return;
      if (handleDriverSessionError(context, error)) return;
      if (error.code == 'NOT_ONLINE') {
        _locationTimer?.cancel();
        if (mounted) setState(() => _status = {..._status, 'online': false});
      } else if (mounted) {
        setState(() => _error = _message(error));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  void _openTrip(Map<String, dynamic> trip) {
    if (_tripOpened || !mounted) return;
    _tripOpened = true;
    final status = trip['status'] as String?;
    final screen = switch (status) {
      'assigned' ||
      'heading_to_pickup' => ArrivingScreen(trip: trip, api: widget.api),
      'arrived_at_pickup' ||
      'loaded' => CargoLoadedScreen(trip: trip, api: widget.api),
      'heading_to_dropoff' || 'arrived_at_dropoff' => ProofOfDeliveryScreen(
        trip: trip,
        api: widget.api,
      ),
      _ => null,
    };
    if (screen == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => screen))
            .then((_) => _load());
      }
    });
  }

  String _message(Object error) => error is DriverApiException
      ? error.message
      : error is StateError
      ? error.message
      : 'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مجددًا.';

  String _blockerText() {
    if (_blockers.isEmpty) return '';
    return switch (_blockers.first) {
      'not_approved' => 'Application is still under review.',
      'no_active_vehicle' || 'vehicle_not_active' =>
        'An active vehicle is required before going online.',
      'policies_not_accepted' => 'Accept the latest policies to continue.',
      'license_expired' ||
      'vehicle_license_expired' => 'A vehicle or driver license has expired.',
      'license_too_low' => 'Your license category does not match this vehicle.',
      'debt_over_limit' =>
        'Your outstanding balance exceeds the allowed limit.',
      _ => 'You cannot go online yet.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _HomeHeader(),
                    const SizedBox(height: 12),
                    Text(
                      'Morning, $_driverName',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _AvailabilityCard(
                      isOnline: _isOnline,
                      onChanged: _setOnline,
                      enabled:
                          !_busy &&
                          (_isOnline || _status['canGoOnline'] == true),
                    ),
                    if (_loading) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (_error != null || _blockers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error ?? _blockerText(),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _DriverStats(status: _status),
                    const SizedBox(height: 16),
                    DriverMapPreview(isOnline: _isOnline),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DriverRoutePlannerScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.route_outlined),
                      label: const Text('خطط مشوارك'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: BorderSide(
                          color: AppColors.ink.withValues(alpha: 0.18),
                        ),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (_isOnline) ...[
                      const SizedBox(height: 16),
                      _RequestCard(
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    RequestsListScreen(api: widget.api),
                              ),
                            )
                            .then((_) => _load()),
                      ),
                    ],
                    if (!_isOnline) ...[
                      const SizedBox(height: 16),
                      PrimaryButton(
                        label: 'Go online',
                        icon: Icons.power_settings_new,
                        onPressed:
                            _busy || _loading || _status['canGoOnline'] != true
                            ? null
                            : () => _setOnline(true),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            DriverNavigationBar(
              currentIndex: 0,
              onDestinationSelected: (index) {
                if (index == 0) return;
                if (index == 1) {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute<void>(
                          builder: (_) => RequestsListScreen(api: widget.api),
                        ),
                      )
                      .then((_) => _load());
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'This section does not have a supplied design yet.',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'W',
          style: TextStyle(
            color: AppColors.accent,
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          'DRIVER OPERATIONS',
          style: TextStyle(color: AppColors.ink, fontSize: 10),
        ),
      ],
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({
    required this.isOnline,
    required this.onChanged,
    required this.enabled,
  });

  final bool isOnline;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isOnline ? 'You’re online' : 'You’re offline',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: isOnline,
                onChanged: enabled ? onChanged : null,
                activeThumbColor: AppColors.accent,
                activeTrackColor: AppColors.ink,
                inactiveThumbColor: AppColors.white,
                inactiveTrackColor: AppColors.ink,
                trackOutlineColor: WidgetStatePropertyAll(
                  isOnline ? AppColors.accent : AppColors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            isOnline
                ? 'Ready for requests in your area.'
                : 'Go online when you are ready to accept trips.',
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverStats extends StatelessWidget {
  const _DriverStats({required this.status});

  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('EGP ${status['balance'] ?? '0.00'}', 'Wallet balance'),
      (status['vehicle']?['plateNumber']?.toString() ?? '—', 'Active vehicle'),
      (status['canGoOnline'] == true ? 'Ready' : 'Review', 'Work status'),
    ];
    return Row(
      children: [
        for (var index = 0; index < stats.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stats[index].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stats[index].$2,
                    style: const TextStyle(color: AppColors.ink, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.accent, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_shipping_outlined, size: 19),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Requests are refreshing from Wasla',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                'Offers expire automatically. Review the details before accepting.',
                style: TextStyle(fontSize: 12),
              ),
              SizedBox(height: 12),
              Text(
                'View request  ·  ›',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
