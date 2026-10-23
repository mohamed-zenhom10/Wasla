import 'package:flutter/material.dart';
import 'package:main/components/cargo_components.dart';
import 'package:main/pages/capture_cargo_page.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/theme/app_theme.dart';

class CargoDetailsPage extends StatefulWidget {
  const CargoDetailsPage({super.key, required this.draft});

  final CargoOrderDraft draft;

  @override
  State<CargoDetailsPage> createState() => _CargoDetailsPageState();
}

class _CargoDetailsPageState extends State<CargoDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descriptionController;
  late final TextEditingController _notesController;

  static const _sizes = ['Small', 'Medium', 'Large'];

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(
      text: widget.draft.description,
    );
    _notesController = TextEditingController(text: widget.draft.notes);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    widget.draft
      ..description = _descriptionController.text.trim()
      ..notes = _notesController.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CaptureCargoPage(draft: widget.draft),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CargoPageScaffold(
      title: 'Tell us about your cargo',
      step: 3,
      buttonText: 'Continue to photos',
      onContinue: _continue,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Category: ${widget.draft.category}',
              style: const TextStyle(
                color: AppColors.darkGreen,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            CargoTextField(
              label: 'What are you moving?',
              hint: 'e.g. Two-seat sofa and a coffee table',
              controller: _descriptionController,
              icon: Icons.inventory_2_outlined,
              maxLines: 3,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Describe the cargo you are moving'
                  : null,
            ),
            const SizedBox(height: 22),
            const CargoSectionLabel('Approximate cargo size'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _sizes.map((size) {
                final selected = widget.draft.size == size;
                return ChoiceChip(
                  label: Text(size),
                  selected: selected,
                  onSelected: (_) => setState(() => widget.draft.size = size),
                  selectedColor: const Color(0xFFFFE4DE),
                  labelStyle: TextStyle(
                    color: AppColors.darkGreen,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                  side: BorderSide(
                    color: selected ? AppColors.accent : const Color(0xFFE4E6E3),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 22),
            CargoTextField(
              label: 'Special instructions (optional)',
              hint: 'Fragile items, stairs, access notes...',
              controller: _notesController,
              icon: Icons.sticky_note_2_outlined,
              maxLines: 3,
            ),
            const SizedBox(height: 14),
            const Text(
              'Accurate details help us recommend the right vehicle.',
              style: TextStyle(
                color: AppColors.darkGreen,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
