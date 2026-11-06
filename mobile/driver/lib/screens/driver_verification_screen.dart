import 'dart:async';

import 'package:driver/components/driver_components.dart';
import 'package:driver/data/driver_api.dart';
import 'package:driver/data/driver_application.dart';
import 'package:driver/screens/driver_auth_screen.dart';
import 'package:driver/screens/driver_home_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class DriverVerificationScreen extends StatefulWidget {
  const DriverVerificationScreen({
    super.key,
    required this.application,
    this.userId,
  });

  final DriverApplication application;
  final String? userId;

  @override
  State<DriverVerificationScreen> createState() =>
      _DriverVerificationScreenState();
}

class _DriverVerificationScreenState extends State<DriverVerificationScreen> {
  final _api = DriverApi();
  final _picker = ImagePicker();
  late DriverApplication _application = widget.application;
  Timer? _refreshTimer;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 55),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _api.close();
    super.dispose();
  }

  List<Map<String, dynamic>> get _rejectedDocuments => _application.allDocuments
      .where((document) => document['status'] == 'rejected')
      .toList();

  bool get _needsFix =>
      _application.status == 'pending' && _rejectedDocuments.isNotEmpty;

  String get _title => switch (_application.status) {
    'approved' => 'You’re ready to move',
    'rejected' => 'Application rejected',
    _ when _needsFix => 'Let’s fix one document',
    _ => 'Your checks are underway',
  };

  String get _description => switch (_application.status) {
    'approved' =>
      'Your identity, license and vehicle are verified. Go online when you are ready for a request.',
    'rejected' =>
      _application.rejectionReason ??
          'Your application was declined. Contact support if you need more information.',
    _ when _needsFix =>
      'Replace only the document listed below. The rest of your application stays saved.',
    _ =>
      'We’re reviewing your documents. We’ll notify you when the review is complete.',
  };

  Future<void> _refresh() async {
    setState(() => _error = null);
    try {
      final latest = await _api.getApplication();
      if (mounted) setState(() => _application = latest);
    } catch (error) {
      if (_isSessionEnded(error)) {
        _goToLogin();
      } else if (mounted) {
        setState(() => _error = _message(error));
      }
    }
  }

  Future<void> _retake(Map<String, dynamic> document) async {
    final type = document['type'] as String?;
    if (type == null) return;
    final photo = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (photo == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await photo.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        throw StateError('حجم الصورة أكبر من 5 ميجابايت. اختر صورة أصغر.');
      }
      final extension = photo.name.split('.').last.toLowerCase();
      final contentType = switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => throw StateError('الصورة لازم تكون JPEG أو PNG أو WEBP.'),
      };
      if (type.startsWith('vehicle_')) {
        final vehicleId = _application.activeVehicle?['id']?.toString();
        if (vehicleId == null) throw StateError('Vehicle not found');
        _application = await _api.uploadVehicleDocument(
          vehicleId,
          type,
          bytes,
          contentType: contentType,
        );
      } else {
        _application = await _api.uploadDriverDocument(
          type,
          bytes,
          licenseCategory: type == 'driving_license_front'
              ? document['licenseCategory'] as String? ?? 'professional_3'
              : null,
          contentType: contentType,
        );
      }
      await _refresh();
    } catch (error) {
      if (_isSessionEnded(error)) {
        _goToLogin();
      } else if (mounted) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) => error is DriverApiException
      ? error.message
      : error is StateError
      ? error.message
      : 'تعذر الاتصال بالخادم. حاول مرة أخرى.';

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

  String _reason(Map<String, dynamic> document) {
    final code = document['rejectionCode'] as String?;
    final reason = document['rejectionReason'] as String?;
    return switch (code) {
      'blurry' => 'الصورة مش واضحة',
      'expiry_unreadable' => 'تاريخ الانتهاء مش باين',
      'expired' => 'المستند منتهي',
      'name_mismatch' => 'الاسم مش مطابق',
      'wrong_document' => 'مستند غلط',
      'other' => 'سبب تاني',
      _ => reason ?? 'المستند يحتاج صورة جديدة',
    };
  }

  String _label(String type) => switch (type) {
    'profile_photo' => 'Profile selfie',
    'national_id_front' => 'National ID · front',
    'national_id_back' => 'National ID · back',
    'driving_license_front' => 'Driving license · front',
    'driving_license_back' => 'Driving license · back',
    'vehicle_license_front' => 'Vehicle license · front',
    'vehicle_license_back' => 'Vehicle license · back',
    'vehicle_photo_front' => 'Vehicle · front',
    'vehicle_photo_side' => 'Vehicle · side',
    'vehicle_photo_rear' => 'Vehicle · rear',
    'vehicle_photo_cargo' => 'Vehicle · cargo area',
    _ => type,
  };

  @override
  Widget build(BuildContext context) {
    final isApproved = _application.status == 'approved';
    final isFinalRejection = _application.status == 'rejected';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const DriverPageHeader(label: 'Driver verification'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 27,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Icon(
                      isApproved
                          ? Icons.verified_outlined
                          : isFinalRejection
                          ? Icons.error_outline
                          : _needsFix
                          ? Icons.error_outline
                          : Icons.schedule_outlined,
                      color: isApproved
                          ? const Color(0xFF24804A)
                          : AppColors.accent,
                      size: 52,
                    ),
                    const SizedBox(height: 18),
                    Text(_description, style: const TextStyle(height: 1.5)),
                    if (_needsFix) ...[
                      const SizedBox(height: 22),
                      for (final document in _rejectedDocuments) ...[
                        _rejectedDocument(document),
                        const SizedBox(height: 12),
                      ],
                    ],
                    const SizedBox(height: 18),
                    _applicationDetails(),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
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
                      ? 'Uploading...'
                      : isApproved
                      ? 'Go to driver home'
                      : 'Refresh status',
                  onPressed: _busy
                      ? null
                      : isApproved
                      ? () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => const DriverHomeScreen(),
                          ),
                        )
                      : _refresh,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rejectedDocument(Map<String, dynamic> document) {
    final type = document['type'] as String? ?? '';
    final url = document['url'] as String?;
    final reason = _reason(document);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (url != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                url,
                height: 170,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            _label(type),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(reason, style: const TextStyle(color: Colors.red)),
          if (document['rejectionReason'] != null)
            Text(document['rejectionReason'].toString()),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _retake(document),
              icon: const Icon(Icons.refresh),
              label: const Text('Retake document'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _applicationDetails() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      children: [
        if (widget.userId != null)
          SummaryRow(
            icon: Icons.confirmation_number_outlined,
            label: 'Driver account',
            value: widget.userId!,
          ),
        if (_application.submittedAt != null)
          SummaryRow(
            icon: Icons.schedule,
            label: 'Submitted',
            value: _application.submittedAt!.split('T').first,
          ),
      ],
    ),
  );
}
