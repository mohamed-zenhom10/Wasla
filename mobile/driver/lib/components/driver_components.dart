import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DriverPageHeader extends StatelessWidget {
  const DriverPageHeader({
    super.key,
    required this.label,
    this.progress,
    this.onBack,
  });

  final String label;
  final String? progress;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 24, 14),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
          ),
          const Spacer(),
          Text(
            progress ?? label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.accent,
          disabledForegroundColor: AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: icon == null
            ? Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 19),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class DriverField extends StatelessWidget {
  const DriverField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.readOnly = false,
    this.onTap,
    this.hintText,
    this.validator,
    this.inputFormatters,
    this.textInputAction,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool readOnly;
  final VoidCallback? onTap;
  final String? hintText;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;

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
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          readOnly: readOnly,
          onTap: onTap,
          validator: validator,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          style: const TextStyle(color: AppColors.ink, fontSize: 14),
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: AppColors.surface,
            prefixIcon: Icon(icon, color: AppColors.ink, size: 21),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 17,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class NoticePanel extends StatelessWidget {
  const NoticePanel({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.ink, size: 19),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DocumentUploadCard extends StatelessWidget {
  const DocumentUploadCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isAdded,
    required this.onPressed,
    this.icon = Icons.photo_camera_outlined,
  });

  final String title;
  final String subtitle;
  final bool isAdded;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final borderColor = isAdded ? Colors.transparent : AppColors.accent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        children: [
          Icon(
            isAdded ? Icons.description_outlined : icon,
            color: isAdded ? AppColors.ink : AppColors.accent,
            size: 30,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isAdded ? 'Added · local preview only' : subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.ink, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onPressed,
            icon: Icon(
              isAdded ? Icons.delete_outline : Icons.photo_camera_outlined,
              size: 18,
            ),
            label: Text(isAdded ? 'Remove photo' : 'Take photo or upload'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.ink,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }
}

class SummaryRow extends StatelessWidget {
  const SummaryRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.ink, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
