import 'dart:async';

import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/models/shipment.dart';
import 'package:main/services/shipment_service.dart';
import 'package:main/theme/app_theme.dart';

class TrackingShipmentStagesPage extends StatefulWidget {
  const TrackingShipmentStagesPage({super.key, this.shipmentId});

  final String? shipmentId;

  @override
  State<TrackingShipmentStagesPage> createState() =>
      _TrackingShipmentStagesPageState();
}

class _TrackingShipmentStagesPageState
    extends State<TrackingShipmentStagesPage> {
  final _service = ShipmentService();
  Shipment? _shipment;
  String? _errorMessage;
  bool _isLoading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (widget.shipmentId == null || !mounted) return;
    if (!silent) setState(() => _isLoading = true);
    try {
      final shipment = await _service.getShipment(widget.shipmentId!);
      if (!mounted) return;
      setState(() {
        _shipment = shipment;
        _errorMessage = null;
      });
      if (shipment.status == 'delivered' || shipment.status == 'cancelled') {
        _timer?.cancel();
      }
    } on ShipmentApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shipment = _shipment;
    final timeline = shipment?.timeline ?? const <ShipmentTimelineEntry>[];
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading && shipment == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        const SizedBox(height: 16),
                        Text('Shipment stages', style: AppTypography.headingSm),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.light,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: timeline.isEmpty
                              ? Text('No timeline entries yet.', style: AppTypography.bodySm)
                              : Column(
                                  children: [
                                    for (var index = 0; index < timeline.length; index++) ...[
                                      _stageRow(timeline[index]),
                                      if (index < timeline.length - 1)
                                        Container(
                                          margin: const EdgeInsets.symmetric(vertical: 4),
                                          height: 24,
                                          width: 2,
                                          color: AppColors.accent,
                                        ),
                                    ],
                                  ],
                                ),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(_errorMessage!, style: const TextStyle(color: AppColors.accent)),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: WaslaButton(
                text: 'Refresh',
                variant: WaslaButtonVariant.secondary,
                onPressed: () => _load(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back, size: 24),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const Spacer(),
          Text('WASLA', style: AppTypography.eyebrow),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _stageRow(ShipmentTimelineEntry entry) {
    return Row(
      children: [
        const Icon(Icons.check_circle, size: 18, color: AppColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.to, style: AppTypography.bodySm),
              Text(
                [entry.by, if (entry.at != null) entry.at!.toLocal().toString()].join(' · '),
                style: AppTypography.bodyXs,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
