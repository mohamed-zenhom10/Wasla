import 'package:flutter/material.dart';
import 'package:main/components/cargo_components.dart';
import 'package:main/pages/your_activity_page.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/theme/app_theme.dart';

class CaptureCargoPage extends StatefulWidget {
  const CaptureCargoPage({super.key, required this.draft});

  final CargoOrderDraft draft;

  @override
  State<CaptureCargoPage> createState() => _CaptureCargoPageState();
}

class _CaptureCargoPageState extends State<CaptureCargoPage> {
  bool _isSaving = false;

  void _addSamplePhoto() {
    setState(() => widget.draft.hasSamplePhoto = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sample preview added. Camera and gallery uploads are not connected.',
        ),
      ),
    );
  }

  Future<void> _saveDemoRequest() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final savedOrder = CargoOrderService.saveDemoOrder(widget.draft);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => YourActivityPage(savedOrder: savedOrder),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CargoPageScaffold(
      title: 'Add a cargo photo',
      step: 5,
      buttonText: _isSaving ? 'Saving demo request...' : 'Save demo request',
      onContinue: _saveDemoRequest,
      buttonEnabled: !_isSaving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A photo helps us understand your move. This step is optional.',
            style: TextStyle(
              color: AppColors.darkGreen,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          if (widget.draft.hasSamplePhoto)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/images/onboarding/onboarding_1.png',
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton.filled(
                    tooltip: 'Remove sample photo',
                    onPressed: () =>
                        setState(() => widget.draft.hasSamplePhoto = false),
                    icon: const Icon(Icons.close),
                  ),
                ),
                const Positioned(
                  left: 12,
                  bottom: 12,
                  child: _SamplePhotoLabel(),
                ),
              ],
            )
          else
            InkWell(
              onTap: _addSamplePhoto,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                height: 220,
                decoration: BoxDecoration(
                  color: AppColors.light,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFCDD1CE),
                    width: 1.5,
                  ),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_a_photo_outlined,
                      color: AppColors.darkGreen,
                      size: 38,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Add a photo',
                      style: TextStyle(
                        color: AppColors.darkGreen,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Tap to attach a sample preview',
                      style: TextStyle(
                        color: AppColors.darkGreen,
                        fontSize: 12,
                      ),
                    ),
                  ],
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
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 19),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This prototype uses a bundled sample image only. Camera, gallery, and backend upload are not connected.',
                    style: TextStyle(
                      color: AppColors.darkGreen,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const CargoSectionLabel('Move summary'),
          _SummaryRow(label: 'Cargo', value: widget.draft.category),
          _SummaryRow(label: 'From', value: widget.draft.pickup),
          _SummaryRow(label: 'To', value: widget.draft.destination),
          if (widget.draft.stops.isNotEmpty)
            _SummaryRow(
              label: 'Extra stops',
              value: '${widget.draft.stops.length}',
            ),
        ],
      ),
    );
  }
}

class _SamplePhotoLabel extends StatelessWidget {
  const _SamplePhotoLabel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.darkGreen,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Text(
          'Sample preview',
          style: TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.darkGreen, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Not provided' : value,
              style: const TextStyle(
                color: AppColors.darkGreen,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
