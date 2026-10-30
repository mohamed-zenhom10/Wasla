import 'package:driver/components/driver_components.dart';
import 'package:driver/screens/driver_home_screen.dart';
import 'package:driver/screens/incoming_request_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

class RequestsListScreen extends StatefulWidget {
  const RequestsListScreen({super.key});

  @override
  State<RequestsListScreen> createState() => _RequestsListScreenState();
}

class _RequestsListScreenState extends State<RequestsListScreen> {
  bool _showBackhaul = false;

  static const _requests = [
    _ShipmentRequest(
      route: 'Nasr City → Maadi',
      earnings: 'EGP 432 net',
      distance: '18 km',
      cargo: 'Furniture',
      duration: '55 min',
      pickup: 'Pickup 14:00',
      isBackhaul: true,
    ),
    _ShipmentRequest(
      route: 'Heliopolis → New Cairo',
      earnings: 'EGP 560 net',
      distance: '24 km',
      cargo: 'Appliances',
      duration: '70 min',
      pickup: 'Pickup now',
    ),
    _ShipmentRequest(
      route: 'Nasr City → Downtown',
      earnings: 'EGP 360 net',
      distance: '12 km',
      cargo: 'Shop stock',
      duration: '45 min',
      pickup: 'Pickup now',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final visibleRequests = _showBackhaul
        ? _requests.where((request) => request.isBackhaul).toList()
        : _requests;

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
                            const Text(
                              'ONLINE · 3 AVAILABLE',
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
                        _RequestFilter(
                          showBackhaul: _showBackhaul,
                          onChanged: (value) =>
                              setState(() => _showBackhaul = value),
                        ),
                        const SizedBox(height: 16),
                        for (
                          var index = 0;
                          index < visibleRequests.length;
                          index++
                        ) ...[
                          _RequestCard(
                            request: visibleRequests[index],
                            isHighlighted: !_showBackhaul && index == 0,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const IncomingRequestScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ]),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: DriverMapPreview(height: 180),
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

class _RequestFilter extends StatelessWidget {
  const _RequestFilter({required this.showBackhaul, required this.onChanged});

  final bool showBackhaul;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          _FilterOption(
            label: 'Nearby',
            selected: !showBackhaul,
            onTap: () => onChanged(false),
          ),
          _FilterOption(
            label: 'Smart Backhaul',
            selected: showBackhaul,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _FilterOption extends StatelessWidget {
  const _FilterOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? AppColors.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.white : AppColors.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.isHighlighted,
    required this.onTap,
  });

  final _ShipmentRequest request;
  final bool isHighlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = isHighlighted
        ? Border.all(color: AppColors.accent, width: 1.5)
        : null;

    return Material(
      key: ValueKey('request-${request.route}'),
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
                      '${request.route}  ·  ${request.earnings}',
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
                '${request.distance} · ${request.cargo} · '
                '${request.duration} · ${request.pickup}',
                style: const TextStyle(color: AppColors.ink, fontSize: 12),
              ),
              if (request.isBackhaul) ...[
                const SizedBox(height: 17),
                const Row(
                  children: [
                    Icon(Icons.swap_horiz, color: AppColors.accent, size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Smart Backhaul · Returning your way',
                        style: TextStyle(color: AppColors.accent, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
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

class _ShipmentRequest {
  const _ShipmentRequest({
    required this.route,
    required this.earnings,
    required this.distance,
    required this.cargo,
    required this.duration,
    required this.pickup,
    this.isBackhaul = false,
  });

  final String route;
  final String earnings;
  final String distance;
  final String cargo;
  final String duration;
  final String pickup;
  final bool isBackhaul;
}
