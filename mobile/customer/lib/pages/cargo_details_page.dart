import 'package:flutter/material.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:flutter/services.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:main/components/cargo_components.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/capture_cargo_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/services/international_phone_number.dart';
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
  late final TextEditingController _itemCountController;
  late final TextEditingController _weightController;
  late final TextEditingController _recipientNameController;
  late final TextEditingController _recipientPhoneController;
  IsoCode _recipientPhoneCountry = IsoCode.EG;
  bool _isScheduled = false;
  DateTime? _scheduledAt;
  String _language = 'en';

  bool get _isArabic {
    final normalized = _language.trim().toLowerCase();
    return normalized.contains('عرب') || normalized.contains('arabic');
  }

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(
      text: widget.draft.cargoDescription,
    );
    _itemCountController = TextEditingController(
      text: '${widget.draft.itemCount}',
    );
    _weightController = TextEditingController(
      text: widget.draft.weightKg?.toString() ?? '',
    );
    _recipientNameController = TextEditingController(
      text: widget.draft.recipientName,
    );
    final recipientPhone = InternationalPhoneNumber.split(
      widget.draft.recipientPhone,
    );
    if (recipientPhone != null) {
      _recipientPhoneCountry = recipientPhone.country;
      _recipientPhoneController = TextEditingController(
        text: recipientPhone.nationalNumber,
      );
    } else {
      _recipientPhoneController = TextEditingController(
        text: widget.draft.recipientPhone,
      );
    }
    _isScheduled = widget.draft.pickupType == 'scheduled';
    _scheduledAt =
        widget.draft.scheduledAt ??
        DateTime.now().add(
          Duration(
            minutes: (widget.draft.catalog?.minScheduleLeadMinutes ?? 30) + 5,
          ),
        );
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedLanguage = preferences.getString('profile_language');
      if (!mounted) return;
      if (savedLanguage != null && savedLanguage.trim().isNotEmpty) {
        setState(() => _language = savedLanguage.trim());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _itemCountController.dispose();
    _weightController.dispose();
    _recipientNameController.dispose();
    _recipientPhoneController.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    widget.draft
      ..cargoDescription = _descriptionController.text.trim()
      ..itemCount = int.parse(_itemCountController.text.trim())
      ..weightKg = _weightController.text.trim().isEmpty
          ? null
          : double.parse(_weightController.text.trim())
      ..recipientName = _recipientNameController.text.trim()
      ..recipientPhone = widget.draft.farePaidBy == 'recipient'
          ? (InternationalPhoneNumber.toE164(
                _recipientPhoneController.text,
                _recipientPhoneCountry,
              ) ??
              '')
          : ''
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
    final sizeOptions = widget.draft.catalog?.activeCategories
            .where((item) => item.id == widget.draft.categoryId)
            .firstOrNull
            ?.activeSizes ??
        const <ShipmentSizeOption>[];
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
            if (sizeOptions.isNotEmpty) ...[
              const CargoSectionLabel('Approximate cargo size'),
              DropdownButtonFormField<String>(
                initialValue:
                    sizeOptions.any(
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
                style: AppTypography.bodyMd,
                hint: const Text('Choose a size'),
                items: [
                  for (final size in sizeOptions)
                    DropdownMenuItem(
                      value: size.id,
                      child: Text(size.displayName(_isArabic ? 'ar' : 'en')),
                    ),
                ],
                onChanged: (value) => setState(() {
                  widget.draft
                    ..sizeOptionId = value
                    ..size =
                        sizeOptions
                            .where((size) => size.id == value)
                            .firstOrNull
                            ?.displayName(_isArabic ? 'ar' : 'en') ??
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
              style: AppTypography.bodyMd,
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
  initialValue: widget.draft.paymentMethod ?? 'none',
  decoration: const InputDecoration(labelText: 'Payment method'),
  style: AppTypography.bodyMd,
  items: const [
    DropdownMenuItem(value: 'cash', child: Text('Cash')),
    DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
    DropdownMenuItem(value: 'none', child: Text('No default')),
  ],
  onChanged: (value) => setState(() {
    widget.draft.paymentMethod = value == 'none' ? null : (value ?? 'cash');
  }),
),
            DropdownButtonFormField<String>(
              initialValue: widget.draft.farePaidBy,
              decoration: const InputDecoration(labelText: 'Fare paid by'),
              style: AppTypography.bodyMd,
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
              Text('Recipient phone', style: AppTypography.labelMd),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.light,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(
                  children: [
                    CountryCodePicker(
                      initialSelection: _recipientPhoneCountry.name,
                      favorite: const ['+20', 'US'],
                      countryFilter: IsoCode.values
                          .map((isoCode) => isoCode.name)
                          .toList(growable: false),
                      showCountryOnly: false,
                      showOnlyCountryWhenClosed: false,
                      showDropDownButton: true,
                      showFlag: true,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: AppTypography.bodySm,
                      dialogTextStyle: AppTypography.bodySm,
                      searchStyle: AppTypography.bodySm,
                      dialogBackgroundColor: AppColors.white,
                      onChanged: (country) {
                        final isoCode = country.code;
                        if (isoCode == null) return;
                        final matchedCountries = IsoCode.values.where(
                          (iso) => iso.name == isoCode,
                        );
                        if (matchedCountries.isEmpty) return;
                        setState(() {
                          _recipientPhoneCountry = matchedCountries.first;
                        });
                        _formKey.currentState?.validate();
                      },
                    ),
                    Container(
                      width: 1,
                      height: 28,
                      color: AppColors.borderLight,
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _recipientPhoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        style: AppTypography.bodyMd,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9\s()-]'),
                          ),
                        ],
                        validator: (value) {
                          if (widget.draft.farePaidBy != 'recipient') {
                            return null;
                          }
                          if (InternationalPhoneNumber.parse(
                                value ?? '',
                                _recipientPhoneCountry,
                              ) ==
                              null) {
                            return 'Enter a valid phone number for the selected country';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: 'Phone number',
                          hintStyle: AppTypography.bodySm.copyWith(
                            color: AppColors.gray,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          errorText:
                              widget.draft.fieldErrors['recipientPhone'],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
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
