import 'package:flutter/material.dart';
import 'package:main/components/cargo_components.dart';
import 'package:main/pages/cargo_details_page.dart';
import 'package:main/pages/multi_stop_route_page.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/theme/app_theme.dart';

class DropOffLocationPage extends StatefulWidget {
  const DropOffLocationPage({super.key, required this.draft});

  final CargoOrderDraft draft;

  @override
  State<DropOffLocationPage> createState() => _DropOffLocationPageState();
}

class _DropOffLocationPageState extends State<DropOffLocationPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pickupController;
  late final TextEditingController _destinationController;

  @override
  void initState() {
    super.initState();
    _pickupController = TextEditingController(text: widget.draft.pickup);
    _destinationController = TextEditingController(
      text: widget.draft.destination,
    );
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    widget.draft
      ..pickup = _pickupController.text.trim()
      ..destination = _destinationController.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CargoDetailsPage(draft: widget.draft),
      ),
    );
  }

  void _addStop() {
    if (!_formKey.currentState!.validate()) return;
    widget.draft
      ..pickup = _pickupController.text.trim()
      ..destination = _destinationController.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MultiStopRoutePage(draft: widget.draft),
      ),
    );
  }

  String? _validateLocation(String? value) =>
      (value ?? '').trim().isEmpty ? 'Enter a location' : null;

  @override
  Widget build(BuildContext context) {
    return CargoPageScaffold(
      title: 'Where should we go?',
      step: 2,
      buttonText: 'Continue',
      onContinue: _continue,
      footer: TextButton.icon(
        onPressed: _addStop,
        icon: const Icon(Icons.add_circle_outline, size: 18),
        label: const Text('Add another stop'),
        style: TextButton.styleFrom(foregroundColor: AppColors.darkGreen),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add your pickup and drop-off addresses.',
              style: TextStyle(
                color: AppColors.darkGreen,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            CargoTextField(
              label: 'Pickup location',
              hint: 'Enter pickup address',
              controller: _pickupController,
              icon: Icons.radio_button_checked,
              validator: _validateLocation,
            ),
            const SizedBox(height: 18),
            CargoTextField(
              label: 'Drop-off location',
              hint: 'Enter destination address',
              controller: _destinationController,
              icon: Icons.location_on_outlined,
              validator: _validateLocation,
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.light,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 19),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Address suggestions and map pins will be available when maps are connected.',
                      style: TextStyle(
                        color: AppColors.darkGreen,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
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
