import 'package:flutter/material.dart';
import 'package:main/theme/app_theme.dart';

<<<<<<< HEAD
class MainButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final double borderRadius;
  final bool isLoading;

  const MainButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.borderRadius = 12,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, 
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
=======
enum WaslaButtonVariant { primary, secondary, ghost, dark }

class WaslaButton extends StatelessWidget {
  const WaslaButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.variant = WaslaButtonVariant.primary,
    this.borderRadius = 8,
    this.isLoading = false,
    this.icon,
    this.height = 56,
  });

  final String text;
  final VoidCallback? onPressed;
  final WaslaButtonVariant variant;
  final double borderRadius;
  final bool isLoading;
  final Widget? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, BorderSide? border) = switch (variant) {
      WaslaButtonVariant.primary => (AppColors.accent, AppColors.white, null),
      WaslaButtonVariant.secondary => (
        AppColors.white,
        AppColors.darkGreen,
        const BorderSide(color: AppColors.darkGreen, width: 1),
      ),
      WaslaButtonVariant.ghost => (
        Colors.transparent,
        AppColors.darkGreen,
        null,
      ),
      WaslaButtonVariant.dark => (AppColors.darkGreen, AppColors.white, null),
    };

    final label = Text(
      text,
      style: AppTypography.buttonLabel.copyWith(color: fg),
    );

    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: bg,
          foregroundColor: fg,
          // Keep the same look while loading; only dim when truly disabled.
          disabledBackgroundColor: isLoading ? bg : bg.withValues(alpha: 0.5),
          disabledForegroundColor: isLoading ? fg : fg.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: border ?? BorderSide.none,
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: fg, strokeWidth: 2),
              )
            : icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [icon!, const SizedBox(width: 8), label],
              )
            : label,
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
      ),
    );
  }
}
<<<<<<< HEAD
=======

class MainButton extends WaslaButton {
  const MainButton({
    super.key,
    required super.text,
    required super.onPressed,
    super.borderRadius,
    super.isLoading,
    super.variant,
    super.icon,
    super.height,
  });
}
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
