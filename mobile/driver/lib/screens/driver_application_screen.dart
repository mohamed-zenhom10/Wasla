import 'package:driver/components/driver_components.dart';
import 'package:driver/screens/verification_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DriverApplicationScreen extends StatefulWidget {
  const DriverApplicationScreen({super.key, this.initialStep = 0});

  final int initialStep;

  @override
  State<DriverApplicationScreen> createState() =>
      _DriverApplicationScreenState();
}

class _DriverApplicationScreenState extends State<DriverApplicationScreen> {
  late int _step;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'Ahmed Hassan');
  final _phoneController = TextEditingController(text: '+20 100 555 0194');
  final _cityController = TextEditingController(text: 'Cairo');
  final _birthDateController = TextEditingController(text: '12 March 1992');
  final _nationalIdController = TextEditingController(text: '29203121234567');
  late final _licenseCategoryController = TextEditingController(
    text: _licenseCategory,
  );
  final _licenseExpiryController = TextEditingController(text: '12 March 2028');
  final _makeModelController = TextEditingController(
    text: 'Chevrolet N300 · 2021',
  );
  final _plateController = TextEditingController(text: 'NBR 4321');
  final _registrationExpiryController = TextEditingController(
    text: '30 June 2027',
  );
  final _accountHolderController = TextEditingController(text: 'Ahmed Hassan');
  final _bankController = TextEditingController(text: 'National Bank of Egypt');
  final _accountNumberController = TextEditingController(
    text: 'EG380019000500000000263180002',
  );
  final _walletProviderController = TextEditingController(
    text: 'Vodafone Cash',
  );
  final _walletNumberController = TextEditingController(
    text: '+20 100 555 0194',
  );
  final Set<String> _addedDocuments = {};
  String _vehicleType = 'Quarter Truck';
  String _licenseCategory = 'Professional · Transport';
  String _paymentType = 'Bank account';
  bool _confirmedDocuments = false;

  static const _stepTitles = [
    'Let’s meet you',
    'Verify your identity',
    'Your driving license',
    'Register your truck',
    'Show your vehicle',
    'Where should we pay you?',
    'Ready for verification?',
  ];

  static const _stepDescriptions = [
    '',
    '',
    '',
    '',
    'Photograph the vehicle in daylight. Include the plate and empty cargo area.',
    '',
    'Review each document before sending. Clear photos mean faster review.',
  ];

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep.clamp(0, _stepTitles.length - 1).toInt();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _birthDateController.dispose();
    _nationalIdController.dispose();
    _licenseCategoryController.dispose();
    _licenseExpiryController.dispose();
    _makeModelController.dispose();
    _plateController.dispose();
    _registrationExpiryController.dispose();
    _accountHolderController.dispose();
    _bankController.dispose();
    _accountNumberController.dispose();
    _walletProviderController.dispose();
    _walletNumberController.dispose();
    super.dispose();
  }

  void _goBack() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _step--);
    }
  }

  Future<void> _continue() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_validateStepDocuments()) return;

    if (_step < _stepTitles.length - 1) {
      setState(() => _step++);
      return;
    }

    if (!_confirmedDocuments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirm that these documents belong to you.'),
        ),
      );
      return;
    }

    final continueToPreview = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preview only'),
        content: const Text(
          'Document upload and review are not connected. You can preview the '
          'pending screen, but no documents will be sent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('View pending preview'),
          ),
        ],
      ),
    );
    if (continueToPreview == true && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              const VerificationScreen(status: VerificationStatus.pending),
        ),
      );
    }
  }

  bool _validateStepDocuments() {
    final requiredDocuments = switch (_step) {
      1 => ['nationalIdFront', 'nationalIdBack'],
      2 => ['license'],
      3 => ['registration'],
      4 => ['vehicleFront', 'vehicleSide', 'vehicleRear', 'vehicleCargo'],
      _ => const <String>[],
    };
    final missingDocuments = requiredDocuments
        .where((document) => !_addedDocuments.contains(document))
        .toList();
    if (missingDocuments.isEmpty) return true;

    final message = switch (_step) {
      1 => 'Add photos of the front and back of your National ID.',
      2 => 'Add a photo of your driving license.',
      3 => 'Add a photo of your vehicle registration.',
      4 => 'Add all four required vehicle photos.',
      _ => 'Complete the required information before continuing.',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    return false;
  }

  Future<void> _pickDate(
    TextEditingController controller, {
    bool isBirthDate = false,
  }) async {
    final now = DateTime.now();
    final initialDate = isBirthDate
        ? DateTime(now.year - 25, now.month, now.day)
        : DateTime(now.year + 1, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1950),
      lastDate: isBirthDate ? now : DateTime(now.year + 30),
    );
    if (date == null || !mounted) return;

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    controller.text = '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  void _toggleDocument(String key) {
    setState(() {
      if (!_addedDocuments.add(key)) {
        _addedDocuments.remove(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            DriverPageHeader(
              label: 'Driver application',
              progress: '${_step + 1} OF 7',
              onBack: _goBack,
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _stepTitles[_step],
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 27,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_stepDescriptions[_step].isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        _stepDescriptions[_step],
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: _buildStepContent(),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: PrimaryButton(label: _actionLabel, onPressed: _continue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _actionLabel => switch (_step) {
    5 => 'Save payment details',
    6 => 'Submit documents',
    _ => 'Continue',
  };

  Widget _buildStepContent() => switch (_step) {
    0 => _personalInformation(),
    1 => _nationalId(),
    2 => _drivingLicense(),
    3 => _vehicleRegistration(),
    4 => _vehiclePhotos(),
    5 => _paymentInformation(),
    _ => _documentReview(),
  };

  Widget _personalInformation() {
    return Column(
      children: [
        DriverField(
          label: 'Full legal name',
          controller: _nameController,
          icon: Icons.person_outline,
          keyboardType: TextInputType.name,
          textInputAction: TextInputAction.next,
          validator: _validateFullName,
        ),
        const SizedBox(height: 18),
        DriverField(
          label: 'Mobile number',
          controller: _phoneController,
          icon: Icons.call_outlined,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
            LengthLimitingTextInputFormatter(18),
          ],
          validator: _validateEgyptianPhone,
        ),
        const SizedBox(height: 18),
        DriverField(
          label: 'City',
          controller: _cityController,
          icon: Icons.location_on_outlined,
          textInputAction: TextInputAction.next,
          validator: (value) => _required(value, 'Enter your city.'),
        ),
        const SizedBox(height: 18),
        DriverField(
          label: 'Date of birth',
          controller: _birthDateController,
          icon: Icons.calendar_month_outlined,
          readOnly: true,
          onTap: () => _pickDate(_birthDateController, isBirthDate: true),
          validator: _validateBirthDate,
        ),
        const SizedBox(height: 16),
        const NoticePanel(
          text:
              'Your legal name must match your National ID and payout account.',
        ),
      ],
    );
  }

  Widget _nationalId() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DriverField(
          label: 'National ID number',
          controller: _nationalIdController,
          icon: Icons.badge_outlined,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: _validateNationalId,
        ),
        const SizedBox(height: 18),
        DocumentUploadCard(
          title: 'National ID · front',
          subtitle: 'Clear and readable',
          isAdded: _addedDocuments.contains('nationalIdFront'),
          onPressed: () => _toggleDocument('nationalIdFront'),
        ),
        const SizedBox(height: 16),
        DocumentUploadCard(
          title: 'National ID · back',
          subtitle: 'Capture the complete document.',
          isAdded: _addedDocuments.contains('nationalIdBack'),
          onPressed: () => _toggleDocument('nationalIdBack'),
          icon: Icons.document_scanner_outlined,
        ),
        const SizedBox(height: 16),
        const Text(
          'Sensitive identity information is private and only used for verification.',
          style: TextStyle(color: AppColors.ink, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  Widget _drivingLicense() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DriverField(
          label: 'License category',
          controller: _licenseCategoryController,
          icon: Icons.badge_outlined,
          readOnly: true,
          onTap: _chooseLicenseCategory,
          validator: (value) =>
              _required(value, 'Choose your license category.'),
        ),
        const SizedBox(height: 18),
        DriverField(
          label: 'Expiry date',
          controller: _licenseExpiryController,
          icon: Icons.calendar_month_outlined,
          readOnly: true,
          onTap: () => _pickDate(_licenseExpiryController),
          validator: _validateFutureDate,
        ),
        const SizedBox(height: 18),
        DocumentUploadCard(
          title: 'Driving license · front and back',
          subtitle: 'Make the category and expiry readable.',
          isAdded: _addedDocuments.contains('license'),
          onPressed: () => _toggleDocument('license'),
          icon: Icons.document_scanner_outlined,
        ),
        const SizedBox(height: 16),
        const NoticePanel(
          text:
              'Use a valid license suitable for your vehicle class. Expired or unreadable documents cannot be approved.',
        ),
      ],
    );
  }

  Future<void> _chooseLicenseCategory() async {
    const categories = [
      'Professional · Transport',
      'Professional · Heavy vehicle',
      'Private · Light vehicle',
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final category in categories)
              ListTile(
                title: Text(category),
                onTap: () => Navigator.pop(context, category),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _licenseCategory = selected;
        _licenseCategoryController.text = selected;
      });
    }
  }

  Widget _vehicleRegistration() {
    return Column(
      children: [
        _StaticField(
          label: 'Vehicle type',
          value: _vehicleType,
          icon: Icons.local_shipping_outlined,
          onTap: _chooseVehicleType,
        ),
        const SizedBox(height: 18),
        DriverField(
          label: 'Make and model',
          controller: _makeModelController,
          icon: Icons.local_shipping_outlined,
          validator: _validateMakeAndModel,
        ),
        const SizedBox(height: 18),
        DriverField(
          label: 'Plate',
          controller: _plateController,
          icon: Icons.tag,
          textInputAction: TextInputAction.next,
          validator: _validatePlate,
        ),
        const SizedBox(height: 18),
        DriverField(
          label: 'Registration expiry',
          controller: _registrationExpiryController,
          icon: Icons.calendar_month_outlined,
          readOnly: true,
          onTap: () => _pickDate(_registrationExpiryController),
          validator: _validateFutureDate,
        ),
        const SizedBox(height: 18),
        DocumentUploadCard(
          title: 'Vehicle registration',
          subtitle: 'Clear and readable',
          isAdded: _addedDocuments.contains('registration'),
          onPressed: () => _toggleDocument('registration'),
          icon: Icons.description_outlined,
        ),
      ],
    );
  }

  Future<void> _chooseVehicleType() async {
    const types = ['Quarter Truck', 'Pickup Truck', 'Box Truck'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in types)
              ListTile(
                title: Text(type),
                onTap: () => Navigator.pop(context, type),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _vehicleType = selected);
    }
  }

  Widget _vehiclePhotos() {
    const photoTypes = [
      ('vehicleFront', 'Front with plate'),
      ('vehicleSide', 'Side profile'),
      ('vehicleRear', 'Rear with plate'),
      ('vehicleCargo', 'Cargo area'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Image.asset(
            'assets/images/vehicle.png',
            height: 145,
            fit: BoxFit.contain,
            semanticLabel: 'Outline of a delivery truck',
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (final photo in photoTypes)
                _PhotoRow(
                  label: photo.$2,
                  isAdded: _addedDocuments.contains(photo.$1),
                  onPressed: () => _toggleDocument(photo.$1),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const NoticePanel(
          text:
              'Do not upload edited photos. Photos help confirm condition and cargo suitability.',
        ),
      ],
    );
  }

  Widget _paymentInformation() {
    final isWallet = _paymentType == 'Digital wallet';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Bank account', label: Text('Bank account')),
            ButtonSegment(
              value: 'Digital wallet',
              label: Text('Digital wallet'),
            ),
          ],
          selected: {_paymentType},
          onSelectionChanged: (selection) {
            setState(() => _paymentType = selection.first);
          },
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.ink,
            selectedForegroundColor: AppColors.white,
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.ink,
            side: BorderSide.none,
          ),
        ),
        const SizedBox(height: 18),
        DriverField(
          label: 'Account holder',
          controller: _accountHolderController,
          icon: Icons.person_outline,
          textInputAction: TextInputAction.next,
          validator: (value) {
            final error = _validateFullName(value);
            if (error != null) return error;
            if (value!.trim().toLowerCase() !=
                _nameController.text.trim().toLowerCase()) {
              return 'Account holder must match your legal name.';
            }
            return null;
          },
        ),
        const SizedBox(height: 18),
        DriverField(
          label: isWallet ? 'Wallet provider' : 'Bank',
          controller: isWallet ? _walletProviderController : _bankController,
          icon: isWallet
              ? Icons.account_balance_wallet_outlined
              : Icons.account_balance_outlined,
          textInputAction: TextInputAction.next,
          validator: (value) => _required(
            value,
            isWallet ? 'Enter your wallet provider.' : 'Enter your bank name.',
          ),
        ),
        const SizedBox(height: 18),
        DriverField(
          label: isWallet ? 'Wallet number' : 'Account / IBAN',
          controller: isWallet
              ? _walletNumberController
              : _accountNumberController,
          icon: Icons.tag,
          keyboardType: TextInputType.number,
          inputFormatters: isWallet
              ? [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
                  LengthLimitingTextInputFormatter(18),
                ]
              : [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 ]')),
                  LengthLimitingTextInputFormatter(34),
                ],
          validator: isWallet ? _validateEgyptianPhone : _validateEgyptianIban,
        ),
        const SizedBox(height: 16),
        NoticePanel(
          text: isWallet
              ? 'Payout schedule · Weekly · Sunday\n\n'
                    'The account name must match your verified ID. '
                    'Payment changes require verification.'
              : 'Payout schedule · Weekly · Sunday\n\n'
                    'The account name must match your verified ID. '
                    'Bank changes require verification.',
          icon: Icons.account_balance_outlined,
        ),
      ],
    );
  }

  Widget _documentReview() {
    final nationalIdReady =
        _addedDocuments.contains('nationalIdFront') &&
        _addedDocuments.contains('nationalIdBack');
    final vehiclePhotosReady = [
      'vehicleFront',
      'vehicleSide',
      'vehicleRear',
      'vehicleCargo',
    ].every(_addedDocuments.contains);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              SummaryRow(
                icon: Icons.badge_outlined,
                label: 'National ID · 2 photos',
                value: nationalIdReady ? 'Ready ✓' : 'Add photos',
              ),
              SummaryRow(
                icon: Icons.badge_outlined,
                label: 'Driving license · 2 photos',
                value: _addedDocuments.contains('license')
                    ? 'Ready ✓'
                    : 'Add photo',
              ),
              SummaryRow(
                icon: Icons.description_outlined,
                label: 'Registration · 2 photos',
                value: _addedDocuments.contains('registration')
                    ? 'Ready ✓'
                    : 'Add photo',
              ),
              SummaryRow(
                icon: Icons.local_shipping_outlined,
                label: 'Vehicle · 4 photos',
                value: vehiclePhotosReady ? 'Ready ✓' : 'Add photos',
              ),
              SummaryRow(
                icon: Icons.account_balance_outlined,
                label: 'Payment details',
                value: 'Saved ✓',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 4, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              CheckboxListTile(
                value: _confirmedDocuments,
                onChanged: (value) =>
                    setState(() => _confirmedDocuments = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.ink,
                title: const Text(
                  'I confirm these documents are mine',
                  style: TextStyle(color: AppColors.ink, fontSize: 13),
                ),
              ),
              const Text(
                'We may request an updated photo or document if details are unreadable.',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _ReviewTimeNotice(),
      ],
    );
  }

  String? _validateFullName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'Enter your full legal name.';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length < 2 || parts.any((part) => part.length < 2)) {
      return 'Enter your first and family names.';
    }
    if (!RegExp(
      r"^[\p{L}][\p{L}'-]*$",
      unicode: true,
    ).hasMatch(parts.join(''))) {
      return 'Use letters only for your legal name.';
    }
    return null;
  }

  String? _validateEgyptianPhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    final localNumber = digits.startsWith('20') && digits.length == 12
        ? digits.substring(2)
        : digits;
    if (!RegExp(r'^(?:01[0125]\d{8}|1[0125]\d{8})$').hasMatch(localNumber)) {
      return 'Enter a valid Egyptian mobile number.';
    }
    return null;
  }

  String? _validateNationalId(String? value) {
    final nationalId = (value ?? '').trim();
    if (!RegExp(r'^\d{14}$').hasMatch(nationalId)) {
      return 'National ID must contain exactly 14 digits.';
    }
    if (nationalId[0] != '2' && nationalId[0] != '3') {
      return 'Enter a valid Egyptian National ID.';
    }
    final century = nationalId[0] == '2' ? 1900 : 2000;
    final year = century + int.parse(nationalId.substring(1, 3));
    final month = int.parse(nationalId.substring(3, 5));
    final day = int.parse(nationalId.substring(5, 7));
    final idBirthDate = DateTime(year, month, day);
    if (idBirthDate.year != year ||
        idBirthDate.month != month ||
        idBirthDate.day != day ||
        nationalId.substring(7, 9) == '00') {
      return 'Enter a valid Egyptian National ID.';
    }
    final birthDate = _parseDisplayDate(_birthDateController.text);
    if (birthDate == null ||
        birthDate.year != year ||
        birthDate.month != month ||
        birthDate.day != day) {
      return 'National ID date of birth must match your date of birth.';
    }
    return null;
  }

  String? _validateBirthDate(String? value) {
    final birthDate = _parseDisplayDate(value);
    if (birthDate == null) return 'Choose your date of birth.';
    final now = DateTime.now();
    final adultOn = DateTime(
      birthDate.year + 18,
      birthDate.month,
      birthDate.day,
    );
    if (birthDate.isAfter(now) || adultOn.isAfter(now)) {
      return 'You must be at least 18 years old.';
    }
    return null;
  }

  String? _validateFutureDate(String? value) {
    final date = _parseDisplayDate(value);
    if (date == null) return 'Choose a valid expiry date.';
    final today = DateUtils.dateOnly(DateTime.now());
    if (!date.isAfter(today)) return 'Expiry date must be in the future.';
    return null;
  }

  String? _validateMakeAndModel(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter the vehicle make and model.';
    if (text.length < 3) return 'Enter a valid vehicle make and model.';
    return null;
  }

  String? _validatePlate(String? value) {
    final plate = (value ?? '').trim();
    if (plate.isEmpty) return 'Enter the vehicle plate number.';
    if (!RegExp(r'^[A-Za-z0-9\u0600-\u06FF -]{3,12}$').hasMatch(plate)) {
      return 'Enter a valid plate using 3–12 letters or numbers.';
    }
    return null;
  }

  String? _validateEgyptianIban(String? value) {
    final iban = (value ?? '').replaceAll(' ', '').toUpperCase();
    if (!RegExp(r'^EG\d{27}$').hasMatch(iban)) {
      return 'Enter a valid Egyptian IBAN (EG followed by 27 digits).';
    }
    final rearranged = '${iban.substring(4)}${iban.substring(0, 4)}';
    var remainder = 0;
    for (final codeUnit in rearranged.codeUnits) {
      if (codeUnit >= 48 && codeUnit <= 57) {
        remainder = (remainder * 10 + codeUnit - 48) % 97;
      } else {
        final letterValue = codeUnit - 55;
        remainder = (remainder * 10 + letterValue ~/ 10) % 97;
        remainder = (remainder * 10 + letterValue % 10) % 97;
      }
    }
    if (remainder != 1) return 'Check the IBAN digits and try again.';
    return null;
  }

  String? _required(String? value, String message) {
    if ((value ?? '').trim().isEmpty) return message;
    return null;
  }

  DateTime? _parseDisplayDate(String? value) {
    final parts = (value ?? '').trim().split(RegExp(r'\s+'));
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final year = int.tryParse(parts[2]);
    const months = [
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
    ];
    final month = months.indexOf(parts[1].toLowerCase()) + 1;
    if (day == null || year == null || month == 0) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }
}

class _StaticField extends StatelessWidget {
  const _StaticField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Icon(icon, color: AppColors.ink, size: 21),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, color: AppColors.ink),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.label,
    required this.isAdded,
    required this.onPressed,
  });

  final String label;
  final bool isAdded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.photo_camera_outlined, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.ink, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.ink,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              minimumSize: const Size(0, 40),
            ),
            child: Text(
              isAdded ? 'Added ✓' : 'Add photo +',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isAdded ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTimeNotice extends StatelessWidget {
  const _ReviewTimeNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 15),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              'Review usually within 24 hours',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
