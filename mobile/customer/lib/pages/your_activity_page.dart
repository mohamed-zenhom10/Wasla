import 'package:flutter/material.dart';
import 'package:main/components/app_page_header.dart';
import 'package:main/components/main_button.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/shipment_details_page.dart';
import 'package:main/services/shipment_service.dart';
import 'package:main/theme/app_theme.dart';

class YourActivityPage extends StatefulWidget {
  const YourActivityPage({super.key, this.isPreview = false, this.onDone});

  final bool isPreview;
  final VoidCallback? onDone;

  @override
  State<YourActivityPage> createState() => _YourActivityPageState();
}

class _YourActivityPageState extends State<YourActivityPage> {
  final _service = ShipmentService();
  static const _statuses = [
    'active',
    'draft',
    'searching_driver',
    'driver_assigned',
    'in_progress',
    'delivered',
    'cancelled',
  ];

  String _status = 'active';
  List<ShipmentListItem> _items = [];
  int _page = 1;
  bool _hasMore = false;
  bool _isLoading = false;
  String? _errorMessage;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isPreview) _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final requestPage = reset ? 1 : _page + 1;
    try {
      final result = await _service.getShipments(
        status: _status,
        page: requestPage,
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? result.shipments : [..._items, ...result.shipments];
        _page = result.page;
        _hasMore = result.hasMore;
        _loaded = true;
      });
    } on ShipmentApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleDone(BuildContext context) {
    if (widget.onDone != null) {
      widget.onDone!.call();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                children: [
                  const AppPageHeader(title: 'Your Activity'),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Shipment status',
                    ),
                    items: [
                      for (final status in _statuses)
                        DropdownMenuItem(
                          value: status,
                          child: Text(_statusLabel(status)),
                        ),
                    ],
                    onChanged: widget.isPreview
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _status = value;
                              _items = [];
                              _loaded = false;
                            });
                            _load(reset: true);
                          },
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Recent moves',
                    style: TextStyle(
                      color: AppColors.darkGreen,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.isPreview)
                    const _EmptyActivity(
                      message: 'Preview only — shipment history is not loaded.',
                    )
                  else if (_errorMessage != null)
                    _ErrorActivity(
                      message: _errorMessage!,
                      onRetry: () => _load(reset: true),
                    )
                  else if (_loaded && _items.isEmpty)
                    const _EmptyActivity(message: 'No shipments found.')
                  else if (_isLoading && _items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    for (final item in _items) ...[
                      _ShipmentCard(item: item),
                      const SizedBox(height: 12),
                    ],
                  if (!widget.isPreview && _hasMore)
                    TextButton(
                      onPressed: _isLoading ? null : () => _load(reset: false),
                      child: Text(_isLoading ? 'Loading...' : 'Load more'),
                    ),
                  if (_errorMessage != null &&
                      _errorMessage!.contains('Customer account'))
                    const Text(
                      'Sign in with a Customer account to view shipments.',
                      style: TextStyle(color: AppColors.darkGreen),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: WaslaButton(
                text: 'Done',
                variant: WaslaButtonVariant.primary,
                onPressed: () => _handleDone(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
    'active' => 'Active',
    'searching_driver' => 'Searching driver',
    'driver_assigned' => 'Driver assigned',
    'in_progress' => 'In progress',
    _ => status[0].toUpperCase() + status.substring(1),
  };
}

class _ShipmentCard extends StatelessWidget {
  const _ShipmentCard({required this.item});

  final ShipmentListItem item;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShipmentDetailsPage(shipmentId: item.id),
      ),
    ),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E6E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                color: AppColors.darkGreen,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Shipment #${item.id}',
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(item.status, style: AppTypography.bodyXs),
            ],
          ),
          const SizedBox(height: 10),
          Text('From: ${item.pickupAddress ?? '—'}'),
          Text('To: ${item.dropoffAddress ?? '—'}'),
          if (item.pickupWindowStart != null)
            Text(
              'Pickup: ${item.pickupWindowStart!.toLocal()}',
              style: AppTypography.bodyXs,
            ),
          if (item.customerAmount != null)
            Text('Customer amount: ${item.customerAmount}'),
        ],
      ),
    ),
  );
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
    decoration: BoxDecoration(
      color: AppColors.light,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        const Icon(Icons.route_outlined, size: 36, color: AppColors.darkGreen),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}

class _ErrorActivity extends StatelessWidget {
  const _ErrorActivity({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.light,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.accent),
    ),
    child: Column(
      children: [
        Text(message, textAlign: TextAlign.center),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}
