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
  late final TextEditingController _itemCountController;
  late final TextEditingController _weightController;
  late final TextEditingController _recipientNameController;
  late final TextEditingController _recipientPhoneController;
  bool _isScheduled = false;
  DateTime? _scheduledAt;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(
      text: widget.draft.description,
    );
    _notesController = TextEditingController(text: widget.draft.notes);
    _itemCountController = TextEditingController(
      text: '${widget.draft.itemCount}',
    );
    _weightController = TextEditingController(
      text: widget.draft.weightKg?.toString() ?? '',
    );
    _recipientNameController = TextEditingController(
      text: widget.draft.recipientName,
    );
    _recipientPhoneController = TextEditingController(
      text: widget.draft.recipientPhone,
    );
    _isScheduled = widget.draft.pickupType == 'scheduled';
    _scheduledAt =
        widget.draft.scheduledAt ??
        DateTime.now().add(
          Duration(
            minutes: (widget.draft.catalog?.minScheduleLeadMinutes ?? 30) + 5,
          ),
        );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _notesController.dispose();
    _itemCountController.dispose();
    _weightController.dispose();
    _recipientNameController.dispose();
    _recipientPhoneController.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    widget.draft
      ..description = _descriptionController.text.trim()
      ..notes = _notesController.text.trim()
      ..itemCount = int.parse(_itemCountController.text.trim())
      ..weightKg = _weightController.text.trim().isEmpty
          ? null
          : double.parse(_weightController.text.trim())
      ..recipientName = _recipientNameController.text.trim()
      ..recipientPhone = _recipientPhoneController.text.trim()
      ..pickupType = _isScheduled ? 'scheduled' : 'now'
      ..scheduledAt = _isScheduled ? _scheduledAt : null;
    widget.draft.fieldErrors.clear();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CaptureCargoPage(draft: widget.draft),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.draft.catalog?.categories
        .where((item) => item.id == widget.draft.categoryId)
        .firstOrNull;
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
              errorText: widget.draft.fieldErrors['cargoDescription'],
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Describe the cargo you are moving'
                  : null,
            ),
            const SizedBox(height: 18),
            const CargoSectionLabel('Pickup schedule'),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('As soon as possible')),
                ButtonSegment(value: true, label: Text('Schedule')),
              ],
              selected: {_isScheduled},
              onSelectionChanged: (selection) =>
                  setState(() => _isScheduled = selection.first),
            ),
            if (_isScheduled) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pickSchedule,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  _scheduledAt == null
                      ? 'Choose pickup date and time'
                      : _formatSchedule(_scheduledAt!),
                ),
              ),
              if (widget.draft.fieldErrors['pickupAt'] case final error?)
                Text(error, style: const TextStyle(color: AppColors.accent)),
            ],
            const SizedBox(height: 18),
            CargoTextField(
              label: 'Number of items',
              controller: _itemCountController,
              keyboardType: TextInputType.number,
              errorText: widget.draft.fieldErrors['itemCount'],
              validator: (value) {
                final count = int.tryParse((value ?? '').trim());
                return count == null || count < 1
                    ? 'Enter a number greater than zero'
                    : null;
              },
            ),
            const SizedBox(height: 18),
            if (category?.sizes.isNotEmpty == true) ...[
              const CargoSectionLabel('Approximate cargo size'),
              DropdownButtonFormField<String>(
                initialValue:
                    category!.sizes.any(
                      (size) => size.id == widget.draft.sizeOptionId,
                    )
                    ? widget.draft.sizeOptionId
                    : null,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.light,
                  errorText: widget.draft.fieldErrors['sizeOptionId'],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                hint: const Text('Choose a size'),
                items: [
                  for (final size in category.sizes)
                    DropdownMenuItem(value: size.id, child: Text(size.nameEn)),
                ],
                onChanged: (value) => setState(() {
                  widget.draft
                    ..sizeOptionId = value
                    ..size =
                        category.sizes
                            .where((size) => size.id == value)
                            .firstOrNull
                            ?.nameEn ??
                        '';
                  widget.draft.fieldErrors.remove('sizeOptionId');
                }),
              ),
              const SizedBox(height: 18),
            ],
            CargoTextField(
              label: 'Weight in kg (optional)',
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              errorText: widget.draft.fieldErrors['weightKg'],
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return null;
                final weight = double.tryParse(text);
                return weight == null || weight <= 0
                    ? 'Enter a valid weight'
                    : null;
              },
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<int>(
              initialValue: widget.draft.helpersCount,
              decoration: InputDecoration(
                labelText: 'Helpers',
                filled: true,
                fillColor: AppColors.light,
                errorText: widget.draft.fieldErrors['helpersCount'],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              items: [
                for (var count = 0; count <= 20; count++)
                  DropdownMenuItem(value: count, child: Text('$count')),
              ],
              onChanged: (value) => setState(() {
                if (value != null) widget.draft.helpersCount = value;
              }),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fragile cargo'),
              value: widget.draft.isFragile,
              onChanged: (value) =>
                  setState(() => widget.draft.isFragile = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: widget.draft.paymentMethod,
              decoration: const InputDecoration(labelText: 'Payment method'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
              ],
              onChanged: (value) => setState(() {
                if (value != null) widget.draft.paymentMethod = value;
              }),
            ),
            DropdownButtonFormField<String>(
              initialValue: widget.draft.farePaidBy,
              decoration: const InputDecoration(labelText: 'Fare paid by'),
              items: const [
                DropdownMenuItem(value: 'sender', child: Text('Sender')),
                DropdownMenuItem(value: 'recipient', child: Text('Recipient')),
              ],
              onChanged: (value) => setState(() {
                if (value != null) widget.draft.farePaidBy = value;
              }),
            ),
            if (widget.draft.farePaidBy == 'recipient') ...[
              const SizedBox(height: 12),
              CargoTextField(
                label: 'Recipient name',
                controller: _recipientNameController,
                errorText: widget.draft.fieldErrors['recipientName'],
                validator: (value) =>
                    widget.draft.farePaidBy == 'recipient' &&
                        (value ?? '').trim().isEmpty
                    ? 'Enter the recipient name'
                    : null,
              ),
              const SizedBox(height: 12),
              CargoTextField(
                label: 'Recipient phone',
                controller: _recipientPhoneController,
                keyboardType: TextInputType.phone,
                errorText: widget.draft.fieldErrors['recipientPhone'],
                validator: (value) =>
                    widget.draft.farePaidBy == 'recipient' &&
                        (value ?? '').trim().isEmpty
                    ? 'Enter the recipient phone'
                    : null,
              ),
            ],
            const SizedBox(height: 18),
            CargoTextField(
              label: 'Special instructions (optional)',
              hint: 'Fragile items, stairs, access notes...',
              controller: _notesController,
              icon: Icons.sticky_note_2_outlined,
              maxLines: 3,
            ),
            const SizedBox(height: 14),
            const Text(
              'Accurate details help us find a suitable vehicle.',
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

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final minLead = widget.draft.catalog?.minScheduleLeadMinutes ?? 30;
    final initial = _scheduledAt!.isBefore(now.add(Duration(minutes: minLead)))
        ? now.add(Duration(minutes: minLead + 5))
        : _scheduledAt!;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      widget.draft.fieldErrors.remove('pickupAt');
    });
  }

  String _formatSchedule(DateTime dateTime) =>
      '${dateTime.day}/${dateTime.month}/${dateTime.year} '
      '${TimeOfDay.fromDateTime(dateTime).format(context)}';
}
