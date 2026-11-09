import 'dart:async';

import 'package:driver/components/driver_components.dart';
import 'package:driver/components/national_id_ocr_status.dart';
import 'package:driver/data/driver_api.dart';
import 'package:driver/data/driver_application.dart';
import 'package:driver/data/national_id_ocr.dart';
import 'package:driver/screens/driver_auth_screen.dart';
import 'package:driver/screens/driver_verification_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class DriverApplicationFlow extends StatefulWidget {
  const DriverApplicationFlow({super.key, this.initialStep = 0});

  final int initialStep;

  @override
  State<DriverApplicationFlow> createState() => _DriverApplicationFlowState();
}

class _DriverApplicationFlowState extends State<DriverApplicationFlow> {
  final _api = DriverApi();
  final _picker = ImagePicker();
  final _nationalIdOcr = NationalIdOcrService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthDate = TextEditingController();
  final _nationalId = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _color = TextEditingController();
  final _plate = TextEditingController();
  final _holder = TextEditingController();
  final _bank = TextEditingController();
  final _accountNumber = TextEditingController();
  final Map<String, XFile> _pendingUploads = {};
  final Map<String, Future<Uint8List>> _pendingPreviewBytes = {};
  DriverApplication? _application;
  Map<String, dynamic> _catalog = const {};
  String? _cityId;
  String? _vehicleTypeId;
  String _licenseCategory = 'professional_3';
  String _payoutMethod = 'bank_account';
  String _fullName = '';
  String _email = '';
  String _phone = '';
  String? _nationalIdName;
  String? _drivingLicenseName;
  String? _birthGovernorate;
  String? _drivingLicenseExpiry;
  String? _vehicleLicenseExpiry;
  final Map<String, String> _documentOcrIssues = {};
  final Set<String> _ocrValidatedDocuments = {};
  bool _identityNameMismatch = false;
  String? _userId;
  int _maxHelpers = 0;
  int _step = 0;
  bool _loading = true;
  bool _busy = false;
  bool _confirm = false;
  bool _needsPolicyAcceptance = false;
  bool _policyChecked = false;
  bool _isReadingNationalId = false;
  bool _isReadingDocument = false;
  String? _recognizedNationalId;
  String? _nationalIdOcrError;
  String? _documentOcrError;
  List<Map<String, dynamic>> _policies = const [];
  Timer? _refreshTimer;
  String? _loadError;

  static const _titles = [
    'Let’s meet you · documents',
    'Your information',
    'Show your vehicle',
    'Where should we pay you?',
    'Ready for verification?',
  ];
  static const _docLabels = <String, String>{
    'profile_photo': 'Profile selfie',
    'national_id_front': 'National ID · front',
    'national_id_back': 'National ID · back',
    'driving_license_front': 'Driving license · front',
    'driving_license_back': 'Driving license · back',
    'vehicle_license_front': 'Vehicle license · front',
    'vehicle_license_back': 'Vehicle license · back',
    'vehicle_photo_front': 'Front with plate',
    'vehicle_photo_side': 'Side profile',
    'vehicle_photo_rear': 'Rear with plate',
    'vehicle_photo_cargo': 'Cargo area',
  };
  static const _firstPageDocumentTypes = <String>[
    'profile_photo',
    'national_id_front',
    'national_id_back',
    'driving_license_front',
    'driving_license_back',
    'vehicle_license_front',
    'vehicle_license_back',
  ];
  static const _ocrRequiredDocumentTypes = <String>[
    'national_id_front',
    'driving_license_front',
    'vehicle_license_front',
    'vehicle_license_back',
  ];

  @override
  void initState() {
    super.initState();
    _nationalId.addListener(_onNationalIdChanged);
    _step = widget.initialStep.clamp(0, 4);
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 55),
      (_) => _load(showSpinner: false),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _api.close();
    _nationalIdOcr.close();
    _nationalId.removeListener(_onNationalIdChanged);
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _birthDate.dispose();
    _nationalId.dispose();
    _make.dispose();
    _model.dispose();
    _year.dispose();
    _color.dispose();
    _plate.dispose();
    _holder.dispose();
    _bank.dispose();
    _accountNumber.dispose();
    super.dispose();
  }

  void _onNationalIdChanged() {
    if (mounted && _recognizedNationalId != null) setState(() {});
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) setState(() => _loading = true);
    try {
      final values = await Future.wait([
        _api.getApplication(),
        _api.getCatalog(),
        _api.getMe(),
      ]);
      final application = values[0] as DriverApplication;
      final catalog = values[1] as Map<String, dynamic>;
      final me = values[2] as Map<String, dynamic>;
      final user = (me['user'] as Map?)?.cast<String, dynamic>() ?? const {};
      final needsPolicyAcceptance =
          user['needsPolicyAcceptance'] == true ||
          application.missing.contains('accepted_terms');
      final policyResponse = needsPolicyAcceptance
          ? await _api.getPolicies()
          : null;
      final policies = (policyResponse?['policies'] as List? ?? const [])
          .whereType<Map>()
          .map((policy) => policy.cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        _application = application;
        _catalog = catalog;
        _fullName = user['fullName'] as String? ?? '';
        _email = user['email'] as String? ?? '';
        _phone = user['phone'] as String? ?? '';
        _userId = user['id']?.toString();
        _nameController.text = _fullName;
        _emailController.text = _email;
        _phoneController.text = _phone;
        _cityId = application.profile['cityId']?.toString();
        _birthDate.text = application.profile['dateOfBirth'] as String? ?? '';
        _maxHelpers = (application.profile['maxHelpers'] as num?)?.toInt() ?? 0;
        _licenseCategory =
            application.document('driving_license_front')?['licenseCategory']
                as String? ??
            _licenseCategory;
        _loadVehicle(application.activeVehicle);
        _loadPayout(application.payoutAccount);
        _step = application.nextStep;
        _needsPolicyAcceptance = needsPolicyAcceptance;
        _policies = policies;
        if (!needsPolicyAcceptance) _policyChecked = false;
        _loading = false;
        _loadError = null;
      });
      if (['pending', 'approved', 'rejected'].contains(application.status)) {
        _openStatus(application);
      }
    } catch (error) {
      if (!mounted) return;
      if (_isSessionEnded(error)) {
        _goToLogin();
        return;
      }
      setState(() {
        _loading = false;
        _loadError = _messageFor(error);
      });
    }
  }

  void _loadVehicle(Map<String, dynamic>? vehicle) {
    if (vehicle == null) return;
    _vehicleTypeId = vehicle['vehicleTypeId']?.toString();
    _make.text = vehicle['make']?.toString() ?? '';
    _model.text = vehicle['model']?.toString() ?? '';
    _year.text = vehicle['manufactureYear']?.toString() ?? '';
    _color.text = vehicle['color']?.toString() ?? '';
    _plate.text = vehicle['plateNumber']?.toString() ?? '';
  }

  void _loadPayout(Map<String, dynamic>? payout) {
    if (payout == null) return;
    _payoutMethod = payout['method'] as String? ?? 'bank_account';
    _holder.text = payout['holderName'] as String? ?? '';
    _bank.text = payout['bankName'] as String? ?? '';
  }

  void _openStatus(DriverApplication application) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DriverVerificationScreen(
            application: application,
            userId: _userId,
          ),
        ),
      );
    });
  }

  Future<void> _pickAndUpload(String type) async {
    final source = _firstPageDocumentTypes.contains(type)
        ? await _chooseDocumentImageSource(type)
        : ImageSource.gallery;
    if (source == null) return;
    final picked = await _picker.pickImage(source: source, imageQuality: 70);
    if (picked == null || !mounted) return;
    if (_firstPageDocumentTypes.contains(type)) {
      setState(() {
        _pendingUploads[type] = picked;
        _pendingPreviewBytes[type] = picked.readAsBytes();
        _documentOcrIssues.remove(type);
        if (_ocrRequiredDocumentTypes.contains(type)) {
          _ocrValidatedDocuments.remove(type);
          if (type == 'national_id_front') {
            _isReadingNationalId = true;
            _recognizedNationalId = null;
            _nationalId.clear();
            _nationalIdOcrError = null;
            _nationalIdName = null;
            _birthDate.clear();
            _birthGovernorate = null;
          } else {
            _isReadingDocument = true;
            _documentOcrError = null;
            if (type == 'driving_license_front') {
              _drivingLicenseName = null;
              _nameController.text = _fullName;
              _drivingLicenseExpiry = null;
            } else if (type == 'vehicle_license_front') {
              _vehicleLicenseExpiry = null;
            }
          }
          _identityNameMismatch = false;
        }
      });
      if (_ocrRequiredDocumentTypes.contains(type)) {
        await _analyzeDocument(type, picked);
      }
      return;
    }
    if (type.startsWith('vehicle_photo_')) {
      final vehicle = _application?.activeVehicle;
      if (vehicle == null) {
        if (!_formKey.currentState!.validate()) return;
        final saved = await _run(_saveVehicle);
        if (!saved) return;
      }
      final id = _application?.activeVehicle?['id']?.toString();
      if (id == null) {
        _showMessage('احفظ بيانات السيارة أولًا.');
        return;
      }
      await _run(() async {
        _application = await _api.uploadVehicleDocument(
          id,
          type,
          await _readBytes(picked),
          contentType: _contentType(picked.name),
        );
      });
      return;
    }
    await _run(() async {
      _application = await _api.uploadDriverDocument(
        type,
        await _readBytes(picked),
        licenseCategory: type == 'driving_license_front'
            ? _licenseCategory
            : null,
        contentType: _contentType(picked.name),
      );
    });
  }

  Future<void> _analyzeDocument(String type, XFile image) async {
    try {
      final text = await _nationalIdOcr.readDocumentText(
        imageBytes: await _readBytes(image),
        filename: image.name,
      );
      if (!mounted) return;

      final issues = <String>[];
      if (type == 'national_id_front') {
        final nationalId = NationalIdOcrService.extractNationalId(text);
        final birthDate = NationalIdOcrService.birthDateFromNationalId(
          nationalId,
        );
        final governorate = NationalIdOcrService.extractGovernorate(nationalId);
        final name = NationalIdOcrService.extractArabicName(text);
        _nationalId.value = TextEditingValue(
          text: nationalId,
          selection: TextSelection.collapsed(offset: nationalId.length),
        );
        _recognizedNationalId = nationalId;
        _birthDate.text = birthDate == null ? '' : _isoDate(birthDate);
        _nationalIdName = name;
        _birthGovernorate = governorate;
        if (name == null) issues.add('لم نتمكن من قراءة اسم البطاقة.');
        if (governorate == null) {
          issues.add('لم نتمكن من استخراج المحافظة من الرقم القومي.');
        }
      } else if (type == 'driving_license_front') {
        final name = NationalIdOcrService.extractDrivingLicenseArabicName(text);
        final englishName =
            NationalIdOcrService.extractDrivingLicenseEnglishName(text);
        final expiry = NationalIdOcrService.extractExpiryDate(text);
        _drivingLicenseName = name;
        if (englishName != null) _nameController.text = englishName;
        _drivingLicenseExpiry = expiry;
        if (name == null) issues.add('لم نتمكن من قراءة اسم رخصة القيادة.');
        if (expiry == null) {
          issues.add('لم نتمكن من قراءة تاريخ انتهاء رخصة القيادة.');
        } else if (NationalIdOcrService.isPastDate(expiry)) {
          issues.add('رخصة القيادة منتهية الصلاحية.');
        }
      } else if (type == 'vehicle_license_front') {
        final expiry = NationalIdOcrService.extractVehicleLicenseExpiryDate(
          text,
        );
        final details = NationalIdOcrService.extractVehicleDetails(text);
        _vehicleLicenseExpiry = expiry;
        if (expiry == null) {
          issues.add('لم نتمكن من قراءة تاريخ انتهاء رخصة السيارة.');
        } else if (NationalIdOcrService.isPastDate(expiry)) {
          issues.add('رخصة السيارة منتهية الصلاحية (تاريخ النهاية: $expiry).');
        }
        _applyVehicleDetails(details);
      } else {
        final details = NationalIdOcrService.extractVehicleDetails(text);
        _applyVehicleDetails(details);
        if (details.isEmpty) {
          issues.add(
            'لم نتمكن من قراءة بيانات واضحة من ظهر رخصة السيارة. أعد تصويرها.',
          );
        }
      }

      if (_nationalIdName == null &&
          type == 'driving_license_front' &&
          _pendingUploads.containsKey('national_id_front')) {
        issues.add('أعد فحص صورة البطاقة قبل مقارنة الاسم.');
      }
      _identityNameMismatch =
          _nationalIdName != null &&
          _drivingLicenseName != null &&
          !NationalIdOcrService.namesMatch(
            _nationalIdName!,
            _drivingLicenseName!,
          );
      if (issues.isEmpty) {
        _ocrValidatedDocuments.add(type);
        _documentOcrIssues.remove(type);
      } else {
        _documentOcrIssues[type] = issues.join(' ');
      }
      setState(() {
        _isReadingNationalId = false;
        _isReadingDocument = false;
        _nationalIdOcrError = _documentOcrIssues['national_id_front'];
        _documentOcrError = _documentOcrIssues[type];
      });
    } catch (error) {
      if (!mounted) return;
      final message = error is NationalIdOcrException
          ? error.message
          : error is StateError
          ? error.message
          : 'تعذر تحليل الصورة. تحقق من الاتصال واختر صورة أوضح.';
      setState(() {
        _isReadingNationalId = false;
        _isReadingDocument = false;
        _documentOcrIssues[type] = message;
        _ocrValidatedDocuments.remove(type);
        if (type == 'national_id_front') {
          _nationalIdOcrError = message;
        } else {
          _documentOcrError = message;
        }
      });
    }
  }

  void _applyVehicleDetails(Map<String, String> details) {
    _make.text = details['make'] ?? _make.text;
    _model.text = details['model'] ?? _model.text;
    _year.text =
        details['year']?.replaceAll(RegExp(r'[^0-9٠-٩۰-۹]'), '') ?? _year.text;
    _year.text = NationalIdOcrService.normalizeDigits(_year.text);
    _color.text = details['color'] ?? _color.text;
    _plate.text = details['plate'] ?? _plate.text;
  }

  String _contentType(String filename) {
    final extension = filename.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw StateError('الصورة لازم تكون JPEG أو PNG أو WEBP.'),
    };
  }

  Future<List<int>> _readBytes(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw StateError('حجم الصورة أكبر من 5 ميجابايت. اختر صورة أصغر.');
    }
    return bytes;
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() {});
      return true;
    } catch (error) {
      if (_isSessionEnded(error)) {
        _goToLogin();
      } else {
        if (error is DriverApiException &&
            error.code == 'APPLICATION_INCOMPLETE' &&
            error.missing?.contains('accepted_terms') == true) {
          _needsPolicyAcceptance = true;
          try {
            final response = await _api.getPolicies();
            _policies = (response['policies'] as List? ?? const [])
                .whereType<Map>()
                .map((policy) => policy.cast<String, dynamic>())
                .toList();
          } catch (_) {}
        }
        _showMessage(_messageFor(error));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ImageSource?> _chooseDocumentImageSource(String type) {
    final title = switch (type) {
      'profile_photo' => 'صوّر صورة سيلفي واضحة',
      'national_id_front' => 'صوّر الوجه الأمامي للبطاقة',
      'national_id_back' => 'صوّر ظهر البطاقة',
      'driving_license_front' => 'صوّر وجه رخصة القيادة',
      'driving_license_back' => 'صوّر ظهر رخصة القيادة',
      'vehicle_license_front' => 'صوّر وجه رخصة السيارة',
      _ => 'صوّر ظهر رخصة السيارة',
    };
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(title),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختيار صورة من المعرض'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  String _messageFor(Object error) {
    if (error is StateError) return error.message;
    if (error is DriverApiException) {
      if (error.code == 'APPLICATION_INCOMPLETE' && error.missing != null) {
        _application = _application == null
            ? null
            : DriverApplication(
                status: _application!.status,
                profile: _application!.profile,
                documents: _application!.documents,
                vehicles: _application!.vehicles,
                payoutAccount: _application!.payoutAccount,
                missing: error.missing!,
                id: _application!.id,
                submittedAt: _application!.submittedAt,
                reviewedAt: _application!.reviewedAt,
                rejectionReason: _application!.rejectionReason,
              );
        _step = _application!.nextStep;
        return 'لسه فيه بيانات أو مستندات ناقصة. أكمل الخطوة المحددة.';
      }
      if (error.code == 'APPLICATION_LOCKED') {
        return 'لا يمكن تعديل الطلب بعد إرساله للمراجعة.';
      }
      return error.message;
    }
    return 'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مجددًا.';
  }

  Future<void> _continue() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    if (_step == 0) {
      final missingDocuments = _firstPageDocumentTypes
          .where(
            (type) =>
                !_pendingUploads.containsKey(type) &&
                _application?.document(type) == null,
          )
          .toList();
      if (missingDocuments.isNotEmpty) {
        setState(() {
          for (final type in missingDocuments) {
            _documentOcrIssues[type] =
                'ارفع صورة ${_docLabels[type] ?? type} للمتابعة.';
          }
        });
        _showMessage('ارفع كل صور الهوية والرخص المطلوبة قبل المتابعة.');
        return;
      }
      if (_isReadingNationalId || _isReadingDocument) {
        _showMessage('انتظر حتى تنتهي قراءة الصور.');
        return;
      }
      final issue = _firstPageOcrIssue;
      if (issue != null) {
        _showMessage(issue);
        return;
      }
      final expiryProblem = _expiredDocumentMessage();
      if (expiryProblem != null) {
        _showMessage(expiryProblem);
        return;
      }
      if (!_ocrValidatedDocuments.containsAll(_ocrRequiredDocumentTypes)) {
        _showMessage(
          'لازم تعيد اختيار صور البطاقة والرخص لتحليل البيانات قبل المتابعة.',
        );
        return;
      }
      if (_identityNameMismatch) {
        _showMessage('اسم البطاقة مختلف عن اسم الرخصة.');
        return;
      }
      setState(() => _step = 1);
      return;
    }
    if (_step == 1) {
      if (!_ocrValidatedDocuments.containsAll(_ocrRequiredDocumentTypes)) {
        setState(() => _step = 0);
        _showMessage('حلّل صور المستندات في الصفحة الأولى قبل المتابعة.');
        return;
      }
      final nationalId = _latinDigits(_nationalId.text.trim());
      final profile = _application!.profile;
      final hasSavedNationalId = profile['nationalIdLast4'] != null;
      if (nationalId.isEmpty && !hasSavedNationalId) {
        _showMessage('أدخل الرقم القومي المكون من 14 رقمًا.');
        return;
      }
      if (nationalId.isNotEmpty && !_validateIdMatchesBirthDate(nationalId)) {
        _showMessage('تاريخ الميلاد لازم يطابق الرقم القومي.');
        return;
      }
      final expiryProblem = _expiredDocumentMessage();
      if (expiryProblem != null) {
        _showMessage(expiryProblem);
        return;
      }
      if (_nationalIdName != null &&
          _drivingLicenseName != null &&
          !NationalIdOcrService.namesMatch(
            _nationalIdName!,
            _drivingLicenseName!,
          )) {
        _showMessage('الاسم في البطاقة لا يطابق الاسم في رخصة القيادة.');
        return;
      }
      final dateChanged = profile['dateOfBirth'] != _birthDate.text;
      if (hasSavedNationalId && dateChanged && nationalId.isEmpty) {
        _showMessage('أعد إدخال الرقم القومي لتغيير تاريخ الميلاد.');
        return;
      }
      final saved = await _run(() async {
        final fields = <String, dynamic>{};
        if (!hasSavedNationalId) {
          fields.addAll({
            'cityId': _cityId,
            'dateOfBirth': _birthDate.text,
            'nationalId': nationalId,
            'maxHelpers': _maxHelpers,
          });
        } else {
          if (profile['cityId']?.toString() != _cityId) {
            fields['cityId'] = _cityId;
          }
          if ((profile['maxHelpers'] as num?)?.toInt() != _maxHelpers) {
            fields['maxHelpers'] = _maxHelpers;
          }
          if (nationalId.isNotEmpty || dateChanged) {
            fields['dateOfBirth'] = _birthDate.text;
            if (nationalId.isNotEmpty) fields['nationalId'] = nationalId;
          }
        }
        if (fields.isNotEmpty) {
          _application = await _api.saveProfile(fields);
        }
        final selfie = _pendingUploads['profile_photo'];
        if (selfie != null) {
          _application = await _api.uploadDriverDocument(
            'profile_photo',
            await _readBytes(selfie),
            contentType: _contentType(selfie.name),
          );
          _pendingUploads.remove('profile_photo');
          _pendingPreviewBytes.remove('profile_photo');
        }
        await _uploadPending([
          'national_id_front',
          'national_id_back',
          'driving_license_front',
          'driving_license_back',
        ]);
        await _saveVehicle();
        await _uploadPending(['vehicle_license_front', 'vehicle_license_back']);
      });
      if (saved &&
          _hasDocs([
            'profile_photo',
            'national_id_front',
            'national_id_back',
            'driving_license_front',
            'driving_license_back',
            'vehicle_license_front',
            'vehicle_license_back',
          ])) {
        setState(() => _step = 2);
      }
      return;
    }
    if (_step == 2) {
      final required = [
        'vehicle_photo_front',
        'vehicle_photo_side',
        'vehicle_photo_rear',
        'vehicle_photo_cargo',
      ];
      if (!_hasDocs(required)) {
        _showMessage('ارفع الصور الأربع للسيارة للمتابعة.');
        return;
      }
      setState(() => _step = 3);
      return;
    }
    if (_step == 3) {
      final saved = await _run(() async {
        final fields = <String, dynamic>{
          'method': _payoutMethod,
          'holderName': _holder.text.trim(),
          'accountNumber': _accountNumber.text.trim(),
        };
        if (_bank.text.trim().isNotEmpty) {
          fields['bankName'] = _bank.text.trim();
        }
        await _api.savePayoutAccount(fields);
        _application = await _api.getApplication();
      });
      if (saved && _application?.payoutAccount != null) {
        setState(() => _step = 4);
      }
      return;
    }
    await _submit();
  }

  Future<void> _uploadPending(List<String> types) async {
    for (final type in types) {
      final picked = _pendingUploads[type];
      if (picked == null) continue;
      if (type.startsWith('vehicle_')) {
        final id = _application?.activeVehicle?['id']?.toString();
        if (id == null) {
          throw StateError('احفظ بيانات السيارة قبل رفع رخصة السيارة.');
        }
        _application = await _api.uploadVehicleDocument(
          id,
          type,
          await _readBytes(picked),
          contentType: _contentType(picked.name),
        );
      } else {
        _application = await _api.uploadDriverDocument(
          type,
          await _readBytes(picked),
          licenseCategory: type == 'driving_license_front'
              ? _licenseCategory
              : null,
          contentType: _contentType(picked.name),
        );
      }
      _pendingUploads.remove(type);
      _pendingPreviewBytes.remove(type);
    }
  }

  Future<void> _saveVehicle() async {
    final fields = <String, dynamic>{
      'vehicleTypeId': _vehicleTypeId,
      'plateNumber': _plate.text.trim(),
      'make': _make.text.trim(),
      'model': _model.text.trim(),
      'manufactureYear': int.parse(_year.text),
      'color': _color.text.trim(),
    };
    final vehicleId = _application?.activeVehicle?['id']?.toString();
    _application = await _api.saveVehicle(fields, vehicleId: vehicleId);
  }

  bool _hasDocs(List<String> types) =>
      types.every((type) => _application?.document(type) != null);

  Future<void> _submit() async {
    if (_needsPolicyAcceptance) {
      _showMessage('اقبل أحدث الشروط وسياسة الخصوصية أولًا.');
      return;
    }
    if (!_confirm) {
      _showMessage('أكد أن المستندات تخصك قبل الإرسال.');
      return;
    }
    await _run(() async {
      final submitted = await _api.submitApplication();
      _application = submitted;
      _openStatus(submitted);
    });
  }

  Future<void> _pickBirthDate() async {
    final settings =
        (_catalog['settings'] as Map?)?.cast<String, dynamic>() ?? const {};
    final age = (settings['minDriverAge'] as num?)?.toInt() ?? 21;
    final now = DateTime.now();
    final latest = DateTime(now.year - age, now.month, now.day);
    final current = DateTime.tryParse(_birthDate.text);
    final date = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isAfter(latest)
          ? current
          : DateTime(latest.year - 4, latest.month, latest.day),
      firstDate: DateTime(1920),
      lastDate: latest,
    );
    if (date != null) {
      setState(() => _birthDate.text = _isoDate(date));
    }
  }

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _latinDigits(String value) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    return value.split('').map((character) {
      final arabicIndex = arabic.indexOf(character);
      if (arabicIndex >= 0) return '$arabicIndex';
      final persianIndex = persian.indexOf(character);
      if (persianIndex >= 0) return '$persianIndex';
      return character;
    }).join();
  }

  bool _validateIdMatchesBirthDate(String id) {
    if (!RegExp(r'^\d{14}$').hasMatch(id)) return false;
    final century = id[0] == '2'
        ? 1900
        : id[0] == '3'
        ? 2000
        : 0;
    if (century == 0) return false;
    final year = century + int.parse(id.substring(1, 3));
    final month = int.parse(id.substring(3, 5));
    final day = int.parse(id.substring(5, 7));
    final date = DateTime(year, month, day);
    return date.year == year &&
        date.month == month &&
        date.day == day &&
        _birthDate.text == _isoDate(date);
  }

  String? get _firstPageOcrIssue {
    for (final type in _ocrRequiredDocumentTypes) {
      final issue = _documentIssue(type);
      if (issue != null) return issue;
    }
    return null;
  }

  String? _documentIssue(String type) {
    if (_identityNameMismatch &&
        (type == 'national_id_front' || type == 'driving_license_front')) {
      return 'اسم البطاقة مختلف عن اسم الرخصة.';
    }
    if (type == 'vehicle_license_front' &&
        _vehicleLicenseExpiry != null &&
        NationalIdOcrService.isPastDate(_vehicleLicenseExpiry!)) {
      return 'رخصة السيارة منتهية الصلاحية '
          '(تاريخ النهاية: $_vehicleLicenseExpiry).';
    }
    final issue = _documentOcrIssues[type];
    if (issue != null) return issue;
    if (_step == 0 &&
        _ocrRequiredDocumentTypes.contains(type) &&
        _application?.document(type) != null &&
        !_pendingUploads.containsKey(type) &&
        !_ocrValidatedDocuments.contains(type)) {
      return 'أعد اختيار الصورة لتحليلها قبل المتابعة.';
    }
    return null;
  }

  bool _isScanningDocument(String type) => type == 'national_id_front'
      ? _isReadingNationalId
      : (type == 'driving_license_front' ||
                type == 'vehicle_license_front' ||
                type == 'vehicle_license_back') &&
            _isReadingDocument;

  String? _expiredDocumentMessage() {
    final expired = <String>[
      if (_drivingLicenseExpiry != null &&
          NationalIdOcrService.isPastDate(_drivingLicenseExpiry!))
        'رخصة القيادة',
      if (_vehicleLicenseExpiry != null &&
          NationalIdOcrService.isPastDate(_vehicleLicenseExpiry!))
        'رخصة السيارة',
    ];
    return expired.isEmpty
        ? null
        : 'انتهت صلاحية ${expired.join(' و')}. حدّث المستند قبل المتابعة.';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            DriverPageHeader(
              label: 'Driver application',
              progress: '${_step + 1} OF 5',
              onBack: () => setState(() => _step = (_step - 1).clamp(0, 4)),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(showSpinner: false),
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: [
                    Text(
                      _titles[_step],
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 27,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Form(key: _formKey, child: _stepContent()),
                    if (_application!.missing.contains('license_too_low')) ...[
                      const SizedBox(height: 16),
                      const NoticePanel(
                        text: 'رخصتك مش مناسبة لنوع العربية دي.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: PrimaryButton(
                  label: _busy
                      ? 'جارٍ الحفظ...'
                      : _step == 3
                      ? 'Save payment details'
                      : _step == 4
                      ? 'Send for review'
                      : 'Continue',
                  onPressed:
                      _busy ||
                          (_step == 4 &&
                              (_application!.missing.isNotEmpty || !_confirm))
                      ? null
                      : _continue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepContent() => switch (_step) {
    0 => _documentsStep(),
    1 => _detailsStep(),
    2 => _vehiclePhotosStep(),
    3 => _payoutStep(),
    _ => _reviewStep(),
  };

  Widget _documentsStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const NoticePanel(
        text:
            'ارفع الوش والظهر للبطاقة، السيلفي، ووش وظهر رخصة القيادة ورخصة السيارة. سنقرأ البيانات المتاحة تلقائيًا ثم تراجعها في الصفحة التالية.',
        icon: Icons.info_outline,
      ),
      const SizedBox(height: 18),
      for (final type in _firstPageDocumentTypes) ...[
        _photoButton(type),
        const SizedBox(height: 14),
      ],
      if (_isReadingNationalId || _isReadingDocument)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('جاري قراءة البيانات من الصور...'),
            ],
          ),
        ),
      if (_nationalIdOcrError != null || _documentOcrError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _nationalIdOcrError ?? _documentOcrError!,
            style: TextStyle(color: Colors.red.shade700),
          ),
        ),
    ],
  );

  Widget _detailsStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _readOnlyField('Full legal name', _nameController, Icons.person_outline),
      const SizedBox(height: 18),
      _readOnlyField('Email', _emailController, Icons.email_outlined),
      const SizedBox(height: 18),
      _readOnlyField('Mobile number', _phoneController, Icons.call_outlined),
      if (_nationalIdName != null) ...[
        const SizedBox(height: 18),
        _readOnlyValue('الاسم على البطاقة', _nationalIdName!),
      ],
      if (_drivingLicenseName != null) ...[
        const SizedBox(height: 12),
        _readOnlyValue('الاسم على رخصة القيادة', _drivingLicenseName!),
      ],
      if (_nationalIdName != null && _drivingLicenseName != null) ...[
        const SizedBox(height: 12),
        NoticePanel(
          text:
              NationalIdOcrService.namesMatch(
                _nationalIdName!,
                _drivingLicenseName!,
              )
              ? 'الاسم متطابق بين البطاقة ورخصة القيادة.'
              : 'الاسم في البطاقة لا يطابق الاسم في رخصة القيادة. راجع الصور والبيانات.',
          icon:
              NationalIdOcrService.namesMatch(
                _nationalIdName!,
                _drivingLicenseName!,
              )
              ? Icons.verified_outlined
              : Icons.error_outline,
        ),
      ],
      if (_nationalIdName == null || _drivingLicenseName == null) ...[
        const SizedBox(height: 12),
        const NoticePanel(
          text:
              'تعذّر على OCR استخراج الاسم من أحد المستندين، لذلك لم نتمكن من مقارنة الاسمين تلقائيًا. راجع تطابقهما يدويًا.',
          icon: Icons.warning_amber_outlined,
        ),
      ],
      const SizedBox(height: 18),
      DriverField(
        label: 'الرقم القومي',
        controller: _nationalId,
        icon: Icons.badge_outlined,
        hintText: '14 رقمًا',
        keyboardType: TextInputType.number,
        readOnly: true,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
        ],
        validator: (value) {
          final nationalId = _latinDigits(value ?? '');
          final alreadySaved = _application!.profile['nationalIdLast4'] != null;
          final hasNewFrontImage = _pendingUploads.containsKey(
            'national_id_front',
          );
          if (nationalId.length != 14 &&
              !(nationalId.isEmpty && alreadySaved && !hasNewFrontImage)) {
            return 'الرقم القومي يجب أن يتكون من 14 رقمًا.';
          }
          if (hasNewFrontImage) {
            if (_isReadingNationalId) return 'انتظر حتى تنتهي قراءة الصورة.';
            if (_nationalIdOcrError != null) return _nationalIdOcrError;
            if (_recognizedNationalId == null) {
              return 'ارفع صورة واضحة للوجه الأمامي للبطاقة.';
            }
            if (!NationalIdOcrService.matches(
              nationalId,
              _recognizedNationalId!,
            )) {
              return 'الرقم المكتوب لا يطابق الرقم الموجود في الصورة.';
            }
          }
          return null;
        },
      ),
      const SizedBox(height: 12),
      NationalIdOcrStatus(
        isReading: _isReadingNationalId,
        recognizedId: _recognizedNationalId,
        enteredId: _nationalId.text,
        error: _nationalIdOcrError,
      ),
      if (_birthGovernorate != null) ...[
        const SizedBox(height: 14),
        _readOnlyValue(
          'محافظة الميلاد المستخرجة من الرقم القومي',
          _birthGovernorate!,
        ),
      ],
      const SizedBox(height: 18),
      _dropdown<String>(
        label: 'مدينة العمل',
        value: _cityId,
        items: _list('cities').map((item) {
          return DropdownMenuItem(
            value: item['id'].toString(),
            child: Text(
              item['nameAr']?.toString() ?? item['nameEn'].toString(),
            ),
          );
        }).toList(),
        onChanged: (value) => setState(() => _cityId = value),
      ),
      const SizedBox(height: 18),
      DriverField(
        label: 'تاريخ الميلاد',
        controller: _birthDate,
        icon: Icons.calendar_month_outlined,
        readOnly: true,
        onTap: _pickBirthDate,
        validator: (value) {
          final date = DateTime.tryParse(value ?? '');
          if (date == null) return 'اختر تاريخ الميلاد.';
          final settings =
              (_catalog['settings'] as Map?)?.cast<String, dynamic>() ??
              const {};
          final age = (settings['minDriverAge'] as num?)?.toInt() ?? 21;
          final now = DateTime.now();
          final latest = DateTime(now.year - age, now.month, now.day);
          return date.isAfter(latest) ? 'الحد الأدنى للعمر $age سنة.' : null;
        },
      ),
      const SizedBox(height: 18),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('عدد العمال المساعدين'),
          Slider(
            value: _maxHelpers.toDouble(),
            min: 0,
            max: 20,
            divisions: 20,
            label: '$_maxHelpers',
            onChanged: (value) => setState(() => _maxHelpers = value.round()),
          ),
        ],
      ),
      if (_application!.profile['nationalIdLast4'] != null &&
          _nationalId.text.isEmpty) ...[
        const SizedBox(height: 12),
        Text(
          'رقم محفوظ: •••• •••• ••${_application!.profile['nationalIdLast4']}',
        ),
      ],
      const SizedBox(height: 22),
      _dropdown<String>(
        label: 'فئة رخصة القيادة',
        value: _licenseCategory,
        items: const [
          DropdownMenuItem(value: 'private', child: Text('خاصة')),
          DropdownMenuItem(
            value: 'professional_3',
            child: Text('مهنية · ثالثة'),
          ),
          DropdownMenuItem(
            value: 'professional_2',
            child: Text('مهنية · ثانية'),
          ),
          DropdownMenuItem(
            value: 'professional_1',
            child: Text('مهنية · أولى'),
          ),
        ],
        onChanged: (value) =>
            setState(() => _licenseCategory = value ?? _licenseCategory),
      ),
      const SizedBox(height: 22),
      _dropdown<String>(
        label: 'نوع السيارة',
        value: _vehicleTypeId,
        items: _list('vehicleTypes')
            .map(
              (item) => DropdownMenuItem(
                value: item['id'].toString(),
                child: Text(
                  item['nameEn']?.toString() ?? item['nameAr'].toString(),
                ),
              ),
            )
            .toList(),
        onChanged: (value) => setState(() => _vehicleTypeId = value),
      ),
      const SizedBox(height: 18),
      _textField('الشركة المصنعة', _make, Icons.local_shipping_outlined),
      const SizedBox(height: 18),
      _textField('الموديل', _model, Icons.local_shipping_outlined),
      const SizedBox(height: 18),
      DriverField(
        label: 'سنة التصنيع',
        controller: _year,
        icon: Icons.calendar_today_outlined,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        validator: (value) {
          final year = int.tryParse(value ?? '');
          return year != null && year >= 1980 && year <= DateTime.now().year
              ? null
              : 'أدخل سنة بين 1980 و${DateTime.now().year}.';
        },
      ),
      const SizedBox(height: 18),
      _textField('اللون أو الألوان', _color, Icons.palette_outlined),
      const SizedBox(height: 18),
      _textField('رقم اللوحة', _plate, Icons.tag),
      if (_drivingLicenseExpiry != null || _vehicleLicenseExpiry != null) ...[
        const SizedBox(height: 22),
        const Text(
          'تواريخ انتهاء المستندات المستخرجة',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_drivingLicenseExpiry != null)
          _expiryValue('رخصة القيادة', _drivingLicenseExpiry!),
        if (_vehicleLicenseExpiry != null)
          _expiryValue('رخصة السيارة', _vehicleLicenseExpiry!),
      ],
      if (_drivingLicenseExpiry == null || _vehicleLicenseExpiry == null) ...[
        const SizedBox(height: 12),
        const NoticePanel(
          text:
              'تعذّر على OCR قراءة تاريخ انتهاء رخصة أو أكثر. راجع التواريخ الظاهرة في الصور يدويًا قبل المتابعة.',
          icon: Icons.warning_amber_outlined,
        ),
      ],
      if (_documentOcrError != null) ...[
        const SizedBox(height: 12),
        Text(
          _documentOcrError!,
          style: TextStyle(color: Colors.orange.shade900),
        ),
      ],
    ],
  );

  Widget _vehiclePhotosStep() => Column(
    children: [
      for (final type in const [
        'vehicle_photo_front',
        'vehicle_photo_side',
        'vehicle_photo_rear',
        'vehicle_photo_cargo',
      ]) ...[_photoButton(type), const SizedBox(height: 14)],
    ],
  );

  Widget _payoutStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'bank_account', label: Text('Bank account')),
          ButtonSegment(value: 'wallet', label: Text('Digital wallet')),
        ],
        selected: {_payoutMethod},
        onSelectionChanged: (values) =>
            setState(() => _payoutMethod = values.first),
      ),
      const SizedBox(height: 18),
      _textField('Account holder', _holder, Icons.person_outline),
      const SizedBox(height: 18),
      DriverField(
        label: _payoutMethod == 'wallet' ? 'Wallet provider' : 'Bank name',
        controller: _bank,
        icon: Icons.account_balance_outlined,
        validator: (value) =>
            _payoutMethod == 'wallet' || (value ?? '').trim().isNotEmpty
            ? null
            : 'أدخل اسم البنك.',
      ),
      const SizedBox(height: 18),
      DriverField(
        label: _payoutMethod == 'wallet' ? 'Wallet number' : 'Account number',
        controller: _accountNumber,
        icon: Icons.tag,
        validator: (value) => (value ?? '').trim().length >= 6
            ? null
            : 'أدخل رقم الحساب أو المحفظة.',
      ),
      if (_application!.payoutAccount?['accountLast4'] != null) ...[
        const SizedBox(height: 12),
        Text(
          'Saved account: •••• ${_application!.payoutAccount!['accountLast4']}',
        ),
      ],
    ],
  );

  Widget _reviewStep() {
    final missing = _application!.missing;
    final needsPolicyAcceptance =
        _needsPolicyAcceptance || missing.contains('accepted_terms');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final type in _docLabels.keys.where(
          (type) => type != 'profile_photo',
        ))
          if (_application!.document(type) != null)
            SummaryRow(
              icon: Icons.description_outlined,
              label: _docLabels[type]!,
              value: 'Ready',
            ),
        const SizedBox(height: 16),
        if (missing.isNotEmpty)
          NoticePanel(
            text:
                'Complete what is missing: ${missing.map(_missingLabel).join(', ')}',
          )
        else
          const NoticePanel(
            text: 'Your application is complete and ready to submit.',
          ),
        if (needsPolicyAcceptance) ...[
          const SizedBox(height: 16),
          const NoticePanel(
            text: 'راجع الشروط وسياسة الخصوصية الحالية واقبلها للمتابعة.',
          ),
          for (final policy in _policies)
            ExpansionTile(
              title: Text(
                policy['type'] == 'terms'
                    ? 'الشروط والأحكام'
                    : 'سياسة الخصوصية',
              ),
              children: [
                SizedBox(
                  height: 180,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      (policy['contentAr'] ?? policy['contentEn'] ?? '')
                          .toString(),
                    ),
                  ),
                ),
              ],
            ),
          CheckboxListTile(
            value: _policyChecked,
            onChanged: (value) =>
                setState(() => _policyChecked = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('أوافق على أحدث الشروط وسياسة الخصوصية'),
          ),
          FilledButton.icon(
            onPressed: _busy || !_policyChecked ? null : _acceptCurrentPolicies,
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('حفظ الموافقة'),
          ),
        ],
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _confirm,
          onChanged: (value) => _setConfirm(value ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('I confirm these documents are mine'),
        ),
      ],
    );
  }

  void _setConfirm(bool value) {
    setState(() => _confirm = value);
  }

  Future<void> _acceptCurrentPolicies() async {
    if (!_policyChecked) return;
    final accepted = await _run(() async {
      final response = await _api.acceptPolicies();
      final user =
          (response['user'] as Map?)?.cast<String, dynamic>() ?? const {};
      _needsPolicyAcceptance = user['needsPolicyAcceptance'] == true;
      _application = await _api.getApplication();
      _step = _application!.nextStep;
    });
    if (accepted && mounted && !_needsPolicyAcceptance) {
      setState(() => _policyChecked = false);
    }
  }

  bool _isSessionEnded(Object error) =>
      error is DriverApiException && error.code == 'SESSION_ENDED';

  void _goToLogin() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const DriverAuthScreen(startInLogin: true),
      ),
      (_) => false,
    );
  }

  String _missingLabel(String value) => switch (value) {
    'license_too_low' => 'رخصتك مش مناسبة لنوع العربية دي',
    'payout_account' => 'بيانات الدفع',
    'vehicle_documents' => 'مستندات السيارة',
    'accepted_terms' => 'قبول أحدث الشروط وسياسة الخصوصية',
    'profile' => 'البيانات الشخصية',
    _ => _docLabels[value] ?? value,
  };

  Widget _photoButton(String type) {
    final document = _application?.document(type);
    final pending = _pendingUploads.containsKey(type);
    final url = document?['url'] as String?;
    final status = document?['status'] as String?;
    final issue = _documentIssue(type);
    final scanning = _isScanningDocument(type);
    final ocrComplete = _ocrValidatedDocuments.contains(type);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _documentPreview(type, url),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _docLabels[type] ?? type,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (status == 'rejected')
                      Text(
                        _rejectionText(document!),
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    if (pending) const Text('Selected'),
                  ],
                ),
              ),
              TextButton(
                onPressed: _busy || _isReadingNationalId || _isReadingDocument
                    ? null
                    : () => _pickAndUpload(type),
                child: Text(
                  document != null || pending ? 'Retake' : 'Add photo',
                ),
              ),
            ],
          ),
          if (scanning) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('جاري تحليل الصورة باستخدام OCR...'),
              ],
            ),
          ] else if (issue != null) ...[
            const SizedBox(height: 8),
            Text(
              issue,
              style: TextStyle(
                color: Colors.red.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else if (ocrComplete) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                SizedBox(width: 6),
                Text(
                  'تم تحليل الصورة والبيانات المطلوبة سليمة.',
                  style: TextStyle(color: Colors.green),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _documentPreview(String type, String? url) {
    final pendingBytes = _pendingPreviewBytes[type];
    if (pendingBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: FutureBuilder<Uint8List>(
          future: pendingBytes,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(
                width: 54,
                height: 54,
                child: Icon(
                  Icons.photo_camera_outlined,
                  color: AppColors.accent,
                ),
              );
            }
            return Image.memory(
              snapshot.data!,
              width: 54,
              height: 54,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined),
            );
          },
        ),
      );
    }
    if (url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          url,
          width: 54,
          height: 54,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        ),
      );
    }
    return const Icon(
      Icons.photo_camera_outlined,
      color: AppColors.accent,
      size: 25,
    );
  }

  String _rejectionText(Map<String, dynamic> document) {
    final code = document['rejectionCode'] as String?;
    final reason = document['rejectionReason'] as String?;
    final label = switch (code) {
      'blurry' => 'الصورة مش واضحة',
      'expiry_unreadable' => 'تاريخ الانتهاء مش باين',
      'expired' => 'المستند منتهي',
      'name_mismatch' => 'الاسم مش مطابق',
      'wrong_document' => 'مستند غلط',
      'other' => reason ?? 'سبب تاني',
      _ => reason ?? 'المستند يحتاج صورة جديدة',
    };
    return reason != null && code != 'other' ? '$label · $reason' : label;
  }

  List<Map<String, dynamic>> _list(String key) =>
      (_catalog[key] as List? ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();

  Widget _readOnlyField(
    String label,
    TextEditingController controller,
    IconData icon,
  ) => DriverField(
    label: label,
    controller: controller,
    icon: icon,
    readOnly: true,
  );

  Widget _readOnlyValue(String label, String value) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _expiryValue(String label, String date) {
    final expired = NationalIdOcrService.isPastDate(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            expired ? Icons.error_outline : Icons.verified_outlined,
            color: expired ? Colors.red : Colors.green,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('$label · $date')),
          Text(expired ? 'منتهي' : 'ساري'),
        ],
      ),
    );
  }

  Widget _textField(
    String label,
    TextEditingController controller,
    IconData icon,
  ) => DriverField(
    label: label,
    controller: controller,
    icon: icon,
    validator: (value) =>
        (value ?? '').trim().isNotEmpty ? null : 'هذا الحقل مطلوب.',
  );

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppColors.ink, fontSize: 12)),
      const SizedBox(height: 8),
      DropdownButtonFormField<T>(
        initialValue: items.any((item) => item.value == value) ? value : null,
        items: items,
        onChanged: onChanged,
        validator: (selected) => selected == null ? 'اختر $label.' : null,
        decoration: const InputDecoration(
          filled: true,
          fillColor: AppColors.surface,
        ),
      ),
    ],
  );
}
