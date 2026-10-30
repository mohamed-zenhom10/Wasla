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
        // Bottom inset is handled by the inner SafeArea around the button,
        // so don't apply it twice.
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Back',
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
                  ],
                ],
              ),
            ),
            Expanded(
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
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: WaslaButton(
                  text: actionLabel,
                  onPressed: isLoading ? null : onAction,
                  isLoading: isLoading,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LabeledInput extends StatefulWidget {
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
    this.focused = false,
    this.errorText,
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
      ],
    );
  }
}

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

class NoticePanel extends StatelessWidget {
  const NoticePanel({super.key, required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.darkGreen, size: 20),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: AppTypography.bodySm)),
        ],
      ),
    );
  }
}
