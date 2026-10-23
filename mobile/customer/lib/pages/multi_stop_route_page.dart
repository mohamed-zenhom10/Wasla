import 'package:flutter/material.dart';
import 'package:main/components/cargo_components.dart';
import 'package:main/pages/cargo_details_page.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/theme/app_theme.dart';

class MultiStopRoutePage extends StatefulWidget {
  const MultiStopRoutePage({super.key, required this.draft});

  final CargoOrderDraft draft;

  @override
  State<MultiStopRoutePage> createState() => _MultiStopRoutePageState();
}

class _MultiStopRoutePageState extends State<MultiStopRoutePage> {
  late final List<TextEditingController> _stopControllers;

  @override
  void initState() {
    super.initState();
    _stopControllers = widget.draft.stops
        .map((stop) => TextEditingController(text: stop))
        .toList();
    if (_stopControllers.isEmpty) _stopControllers.add(TextEditingController());
  }

  @override
  void dispose() {
    for (final controller in _stopControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _continue() {
    final stops = _stopControllers
        .map((controller) => controller.text.trim())
        .where((stop) => stop.isNotEmpty)
        .toList();
    widget.draft.stops
      ..clear()
      ..addAll(stops);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CargoDetailsPage(draft: widget.draft),
      ),
    );
  }

  void _addStop() {
    setState(() => _stopControllers.add(TextEditingController()));
  }

  void _removeStop(int index) {
    final controller = _stopControllers.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CargoPageScaffold(
      title: 'Add stops to your route',
      step: 4,
      buttonText: 'Continue',
      onContinue: _continue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add any extra addresses between pickup and delivery. You can skip this step.',
            style: TextStyle(
              color: AppColors.darkGreen,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          for (var index = 0; index < _stopControllers.length; index++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: CargoTextField(
                    label: 'Stop ${index + 1}',
                    hint: 'Enter stop address',
                    controller: _stopControllers[index],
                    icon: Icons.location_on_outlined,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove stop ${index + 1}',
                  onPressed: () => _removeStop(index),
                  icon: const Icon(Icons.remove_circle_outline),
                  color: AppColors.accent,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          OutlinedButton.icon(
            onPressed: _addStop,
            icon: const Icon(Icons.add),
            label: const Text('Add another stop'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.darkGreen,
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: AppColors.darkGreen),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.light,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'You can leave stops blank and continue with your pickup and destination only.',
              style: TextStyle(
                color: AppColors.darkGreen,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
