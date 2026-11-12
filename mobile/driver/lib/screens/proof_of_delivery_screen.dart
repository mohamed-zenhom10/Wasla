import 'package:driver/components/driver_components.dart';
import 'package:driver/screens/delivery_success_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

enum _ProofMethod { otp, photo, signature }

class ProofOfDeliveryScreen extends StatefulWidget {
  const ProofOfDeliveryScreen({super.key});

  @override
  State<ProofOfDeliveryScreen> createState() => _ProofOfDeliveryScreenState();
}

class _ProofOfDeliveryScreenState extends State<ProofOfDeliveryScreen> {
  final _otpController = TextEditingController(text: '6248');
  final _picker = ImagePicker();
  _ProofMethod _method = _ProofMethod.otp;
  XFile? _deliveryPhoto;
  bool _cashCollected = true;
  bool _hasSignature = false;
  bool _isPickingPhoto = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DriverPageHeader(
                      label: 'Confirm a safe delivery',
                      progress: 'WS-20481',
                    ),
                    const Text(
                      'Confirm a safe delivery',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _ProofMethodSelector(
                      selected: _method,
                      onSelected: (method) => setState(() => _method = method),
                    ),
                    const SizedBox(height: 18),
                    _buildVerificationMethod(),
                    const SizedBox(height: 16),
                    _DeliverySummary(
                      cashCollected: _cashCollected,
                      onCashCollectedChanged: (value) =>
                          setState(() => _cashCollected = value),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Confirm every item is received before completing the delivery.',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: PrimaryButton(
                label: 'Complete delivery',
                onPressed: _canComplete ? _completeDelivery : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationMethod() {
    switch (_method) {
      case _ProofMethod.otp:
        return _OtpEntry(
          controller: _otpController,
          onChanged: (_) => setState(() {}),
        );
      case _ProofMethod.photo:
        return _PhotoProof(
          photo: _deliveryPhoto,
          isPickingPhoto: _isPickingPhoto,
          onPickPhoto: _pickDeliveryPhoto,
        );
      case _ProofMethod.signature:
        return _SignatureProof(
          hasSignature: _hasSignature,
          onChanged: (hasSignature) =>
              setState(() => _hasSignature = hasSignature),
        );
    }
  }

  bool get _canComplete {
    if (!_cashCollected) return false;
    switch (_method) {
      case _ProofMethod.otp:
        return _otpController.text.trim().length == 4;
      case _ProofMethod.photo:
        return _deliveryPhoto != null;
      case _ProofMethod.signature:
        return _hasSignature;
    }
  }

  Future<void> _pickDeliveryPhoto() async {
    setState(() => _isPickingPhoto = true);
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
      );
      if (!mounted) return;
      if (photo != null) {
        setState(() => _deliveryPhoto = photo);
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open photo gallery: ${error.message}')),
      );
    } finally {
      if (mounted) setState(() => _isPickingPhoto = false);
    }
  }

  void _completeDelivery() {
    if (!_canComplete) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const DeliverySuccessScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}

class _ProofMethodSelector extends StatelessWidget {
  const _ProofMethodSelector({
    required this.selected,
    required this.onSelected,
  });

  final _ProofMethod selected;
  final ValueChanged<_ProofMethod> onSelected;

  @override
  Widget build(BuildContext context) {
    const methods = [
      (_ProofMethod.otp, 'OTP'),
      (_ProofMethod.photo, 'Photo'),
      (_ProofMethod.signature, 'Signature'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          for (final method in methods)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(method.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected == method.$1
                        ? AppColors.ink
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    method.$2,
                    style: TextStyle(
                      color: selected == method.$1
                          ? AppColors.white
                          : AppColors.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OtpEntry extends StatelessWidget {
  const _OtpEntry({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recipient delivery OTP',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          onChanged: onChanged,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 16,
            letterSpacing: 6,
          ),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.verified_user_outlined),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotoProof extends StatelessWidget {
  const _PhotoProof({
    required this.photo,
    required this.isPickingPhoto,
    required this.onPickPhoto,
  });

  final XFile? photo;
  final bool isPickingPhoto;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            photo == null ? Icons.add_a_photo_outlined : Icons.task_outlined,
            size: 36,
            color: AppColors.ink,
          ),
          const SizedBox(height: 10),
          Text(
            photo == null ? 'Add delivered items photo' : 'Delivery photo added',
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            photo == null ? 'Choose a clear, readable photo' : photo!.name,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.ink, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: isPickingPhoto ? null : onPickPhoto,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(photo == null ? 'Choose photo' : 'Replace photo'),
            style: TextButton.styleFrom(foregroundColor: AppColors.ink),
          ),
          if (isPickingPhoto)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _SignatureProof extends StatefulWidget {
  const _SignatureProof({
    required this.hasSignature,
    required this.onChanged,
  });

  final bool hasSignature;
  final ValueChanged<bool> onChanged;

  @override
  State<_SignatureProof> createState() => _SignatureProofState();
}

class _SignatureProofState extends State<_SignatureProof> {
  final List<Offset> _points = [];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recipient signature',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onPanStart: (details) => _addPoint(details.localPosition),
          onPanUpdate: (details) => _addPoint(details.localPosition),
          child: Container(
            height: 170,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: CustomPaint(
                painter: _SignaturePainter(List.of(_points)),
              child: Center(
                child: widget.hasSignature
                    ? const SizedBox.shrink()
                    : const Text(
                        'Sign here',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _points.isEmpty
                ? null
                : () {
                    setState(() => _points.clear());
                    widget.onChanged(false);
                  },
            child: const Text('Clear signature'),
          ),
        ),
      ],
    );
  }

  void _addPoint(Offset point) {
    setState(() => _points.add(point));
    widget.onChanged(true);
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.points);

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.ink
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var index = 1; index < points.length; index++) {
      final start = points[index - 1];
      final end = points[index];
      if (start != Offset.zero && end != Offset.zero) {
        canvas.drawLine(start, end, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

class _DeliverySummary extends StatelessWidget {
  const _DeliverySummary({
    required this.cashCollected,
    required this.onCashCollectedChanged,
  });

  final bool cashCollected;
  final ValueChanged<bool> onCashCollectedChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recipient  ·  Mariam Adel',
            style: TextStyle(color: AppColors.ink, fontSize: 12),
          ),
          const SizedBox(height: 14),
          CheckboxListTile(
            value: cashCollected,
            onChanged: (value) => onCashCollectedChanged(value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.trailing,
            title: const Text(
              'Cash collected  ·  EGP 540',
              style: TextStyle(color: AppColors.ink, fontSize: 12),
            ),
            activeColor: AppColors.ink,
            dense: true,
          ),
          const SizedBox(height: 6),
          const Text(
            'Signature  ·  Required if OTP is unavailable',
            style: TextStyle(color: AppColors.ink, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
