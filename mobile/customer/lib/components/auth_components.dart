import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:main/components/main_button.dart';
import 'package:main/theme/app_theme.dart';

class AuthPageScaffold extends StatelessWidget {
  const AuthPageScaffold({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.content,
    required this.actionLabel,
    required this.onAction,
    this.subtitle,
    this.trailing,
    this.isLoading = false,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget content;
  final String actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.white,
      body: SafeArea(
<<<<<<< HEAD
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 24, 18),
=======
        // Bottom inset is handled by the inner SafeArea around the button,
        // so don't apply it twice.
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Back',
<<<<<<< HEAD
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Spacer(),
                  Text(
                    eyebrow.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.darkGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
=======
                    icon: const Icon(Icons.arrow_back, size: 20),
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                  const Spacer(),
                  if (eyebrow.isNotEmpty)
                    Text(eyebrow.toUpperCase(), style: AppTypography.eyebrow),
                  // Independent of eyebrow so trailing isn't silently dropped.
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                    const SizedBox(width: 12),
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
                  ],
                ],
              ),
            ),
            Expanded(
<<<<<<< HEAD
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.darkGreen,
                        fontSize: 27,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: AppColors.darkGreen,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    content,
                  ],
                ),
=======
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  Text(title, style: AppTypography.headingMd),
                  if (subtitle != null) ...[
                    const SizedBox(height: 18),
                    Text(subtitle!, style: AppTypography.bodyMd),
                  ],
                  const SizedBox(height: 18),
                  content,
                  const SizedBox(height: 16),
                ],
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
<<<<<<< HEAD
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: MainButton(
                  text: actionLabel,
                  onPressed: onAction,
                  isLoading: isLoading,
                  borderRadius: 8,
=======
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: WaslaButton(
                  text: actionLabel,
                  onPressed: isLoading ? null : onAction,
                  isLoading: isLoading,
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

<<<<<<< HEAD
class LabeledInput extends StatelessWidget {
=======
class LabeledInput extends StatefulWidget {
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
  const LabeledInput({
    super.key,
    required this.label,
    required this.controller,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.suffix,
    this.validator,
    this.inputFormatters,
    this.onChanged,
    this.textCapitalization = TextCapitalization.none,
<<<<<<< HEAD
=======
    this.focused = false,
    this.errorText,
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
  });

  final String label;
  final TextEditingController controller;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;

<<<<<<< HEAD
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.darkGreen,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          obscureText: obscureText,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          textCapitalization: textCapitalization,
          style: const TextStyle(color: AppColors.darkGreen, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.light,
            prefixIcon: icon == null
                ? null
                : Icon(icon, color: AppColors.darkGreen, size: 21),
            suffixIcon: suffix,
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
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: AppColors.accent),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
            ),
          ),
        ),
=======
  /// Forces the focused look. Normally the field tracks its own focus.
  final bool focused;
  final String? errorText;

  @override
  State<LabeledInput> createState() => _LabeledInputState();
}

class _LabeledInputState extends State<LabeledInput> {
  late final FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _hasFocus = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: AppTypography.labelMd),
        const SizedBox(height: 8),
        _InputContainer(
          focused: widget.focused || _hasFocus,
          hasError: hasError,
          child: Row(
            children: [
              if (widget.icon != null) ...[
                const SizedBox(width: 16),
                Icon(widget.icon, color: AppColors.darkGreen, size: 20),
                const SizedBox(width: 12),
              ] else
                const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  obscureText: widget.obscureText,
                  obscuringCharacter: '*',
                  style: AppTypography.bodyMd,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  textCapitalization: widget.textCapitalization,
                  inputFormatters: widget.inputFormatters,
                  validator: widget.validator,
                  onChanged: widget.onChanged,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (widget.suffix != null) ...[
                const SizedBox(width: 8),
                widget.suffix!,
              ],
              const SizedBox(width: 16),
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            widget.errorText!,
            style: AppTypography.bodySm.copyWith(color: _errorColor),
          ),
        ],
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
      ],
    );
  }
}

<<<<<<< HEAD
=======
final Color _errorColor = Colors.red.shade600;

class _InputContainer extends StatelessWidget {
  const _InputContainer({
    required this.child,
    required this.focused,
    required this.hasError,
  });

  final Widget child;
  final bool focused;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final BorderSide? side = hasError
        ? BorderSide(color: _errorColor, width: 1.5)
        : focused
        ? const BorderSide(color: AppColors.accent, width: 2)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(8),
        border: side != null ? Border.fromBorderSide(side) : null,
      ),
      child: child,
    );
  }
}

>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
class NoticePanel extends StatelessWidget {
  const NoticePanel({super.key, required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
<<<<<<< HEAD
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
=======
      padding: const EdgeInsets.all(16),
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.darkGreen, size: 20),
          const SizedBox(width: 14),
<<<<<<< HEAD
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.darkGreen,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
=======
          Expanded(child: Text(text, style: AppTypography.bodySm)),
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
        ],
      ),
    );
  }
}
