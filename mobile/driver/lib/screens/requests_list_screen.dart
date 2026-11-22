import 'dart:async';

import 'package:driver/components/driver_components.dart';
import 'package:driver/components/driver_navigation_map.dart';
import 'package:driver/components/driver_session.dart';
import 'package:driver/data/driver_api.dart';
import 'package:driver/screens/incoming_request_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

class RequestsListScreen extends StatefulWidget {
  const RequestsListScreen({super.key, this.api});

  final DriverApi? api;

  @override
  State<RequestsListScreen> createState() => _RequestsListScreenState();
}

class _RequestsListScreenState extends State<RequestsListScreen> {
  late final DriverApi _api = widget.api ?? DriverApi();
  Timer? _pollTimer;
  List<Map<String, dynamic>> _offers = const [];
  bool _online = false;
  bool _loading = true;
  bool _polling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOffers();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
      } else if (_online) {
        _loadOffers(showSpinner: false);
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _loadOffers({bool showSpinner = true}) async {
    if (_polling) return;
    _polling = true;
    if (showSpinner && mounted) setState(() => _loading = true);
    try {
      final status = await _api.getDriverStatus();
      final online = status['online'] == true;
      final offers = online ? await _api.getOffers() : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _online = online;
        _offers = offers;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (handleDriverSessionError(context, error)) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    } finally {
      _polling = false;
    }
  }

  String _message(Object error) => error is DriverApiException
      ? error.message
      : 'تعذر تحميل الطلبات. تحقق من اتصالك وحاول مجددًا.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              tooltip: 'Back',
                              icon: const Icon(Icons.arrow_back),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _online
                                  ? 'ONLINE · ${_offers.length} AVAILABLE'
                                  : 'OFFLINE',
                              style: TextStyle(
                                color: AppColors.ink,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Requests near you',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        if (_loading)
                          const Center(child: CircularProgressIndicator())
                        else if (!_online)
                          const _EmptyRequests(
                            message: 'Go online from Home to receive requests.',
                          )
                        else if (_offers.isEmpty)
                          const _EmptyRequests(
                            message: 'We’ll show new nearby requests here.',
                          )
                        else
                          for (var index = 0; index < _offers.length; index++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _RequestCard(
                                request: _offers[index],
                                isHighlighted: index == 0,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => IncomingRequestScreen(
                                      offer: _offers[index],
                                      api: widget.api,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      ]),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: DriverMapPreview(height: 180, isOnline: _online),
                    ),
                  ),
                ],
              ),
            ),
            DriverNavigationBar(
              currentIndex: 1,
              onDestinationSelected: (index) {
                if (index == 0) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                } else if (index != 1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'This section does not have a supplied design yet.',
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRequests extends StatelessWidget {
  const _EmptyRequests({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36),
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted),
      ),
    ),
  );
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.isHighlighted,
    required this.onTap,
  });

  final Map<String, dynamic> request;
  final bool isHighlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = isHighlighted
        ? Border.all(color: AppColors.accent, width: 1.5)
        : null;

    return Material(
      key: ValueKey('request-${request['id']}'),
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 17, 14, 16),
          decoration: BoxDecoration(
            border: border,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isHighlighted)
                    const Icon(
                      Icons.local_shipping_outlined,
                      size: 19,
                      color: AppColors.ink,
                    ),
                  if (isHighlighted) const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${request['pickup']?['address'] ?? 'Pickup'} → '
                      '${request['dropoff']?['address'] ?? 'Drop-off'}  ·  '
                      'EGP ${request['driverEarning'] ?? '0.00'} net',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${request['distanceToPickupM'] ?? 0} m to pickup · '
                '${request['itemCount'] ?? 0} items · '
                '${request['secondsLeft'] ?? 0}s to accept',
                style: const TextStyle(color: AppColors.ink, fontSize: 12),
              ),
              const SizedBox(height: 18),
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: AppColors.ink,
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'View request  ·  ›',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
