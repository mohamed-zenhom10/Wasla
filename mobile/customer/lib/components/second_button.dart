import 'package:flutter/material.dart';
import 'package:main/theme/app_theme.dart';

/// Same button as WaslaButton, but with a fixed background color (0xFF17281E).
class WaslaButtonTwo extends StatelessWidget {
  const WaslaButtonTwo({
    super.key,
    required this.text,
    required this.onPressed,
    this.borderRadius = 8,
    this.isLoading = false,
    this.icon,
    this.height = 56,
  });

  static const Color _bg = Color(0xFF17281E);
  static const Color _fg = AppColors.white;

  final String text;
  final VoidCallback? onPressed;
  final double borderRadius;
  final bool isLoading;
  final Widget? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: AppTypography.buttonLabel.copyWith(color: _fg),
    );

    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: _bg,
          foregroundColor: _fg,
          disabledBackgroundColor: isLoading ? _bg : _bg.withValues(alpha: 0.5),
          disabledForegroundColor: isLoading ? _fg : _fg.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: _fg, strokeWidth: 2),
              )
            : icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [icon!, const SizedBox(width: 8), label],
              )
            : label,
      ),
    );
  }
}
