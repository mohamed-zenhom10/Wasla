import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:main/components/auth_components.dart';
import 'package:main/screens/home_screen.dart';
import 'package:main/theme/app_theme.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.phoneNumber});

  final String phoneNumber;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  Timer? _timer;
  int _secondsRemaining = 24;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((controller) => controller.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var digitIndex = 0; digitIndex < 6; digitIndex++) {
        _controllers[digitIndex].text = digitIndex < digits.length
            ? digits[digitIndex]
            : '';
      }
      _focusNodes[digits.length.clamp(0, 5)].requestFocus();
      setState(() {});
      return;
    }
    if (value.isNotEmpty && index < 5) _focusNodes[index + 1].requestFocus();
    setState(() {});
  }

  KeyEventResult _handleKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    return KeyEventResult.ignored;
  }

  void _resendCode() {
    if (_secondsRemaining > 0) return;
    setState(() => _secondsRemaining = 24);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('SMS delivery needs an authentication service.'),
      ),
    );
  }

  Future<void> _verify() async {
    if (_code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit verification code.')),
      );
      return;
    }
    final openPreview = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verification unavailable'),
        content: const Text(
          'No SMS or authentication service is connected. This code is only a format check; your account is not signed in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay here'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('View home preview'),
          ),
        ],
      ),
    );
    if (openPreview == true && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const HomeScreen(isPreview: true),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      eyebrow: '',
      title: 'Check your messages',
      subtitle: 'Enter the 6-digit code sent to ${widget.phoneNumber}.',
      actionLabel: 'Verify and continue',
      onAction: _verify,
      trailing: const Icon(Icons.notifications_none, size: 21),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(
              6,
              (index) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 5 ? 0 : 8),
                  child: Focus(
                    onKeyEvent: (_, event) => _handleKey(index, event),
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      onChanged: (value) => _onDigitChanged(index, value),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: AppColors.light,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 13,
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
                          borderSide: const BorderSide(
                            color: AppColors.accent,
                            width: 1.5,
                          ),
                        ),
                      ),
                      style: const TextStyle(
                        color: AppColors.darkGreen,
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Resend code in  ·  ', style: TextStyle(fontSize: 12)),
              TextButton(
                onPressed: _secondsRemaining == 0 ? _resendCode : null,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.darkGreen,
                ),
                child: Text(
                  _secondsRemaining == 0
                      ? 'Resend'
                      : '00:${_secondsRemaining.toString().padLeft(2, '0')}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Wrong number?  ·  ', style: TextStyle(fontSize: 12)),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.darkGreen,
                ),
                child: const Text('Edit phone'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const NoticePanel(
            icon: Icons.shield_outlined,
            text: 'Never share this code with anyone.',
          ),
        ],
      ),
    );
  }
}
