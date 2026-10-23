import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:main/components/auth_components.dart';
import 'package:main/screens/otp_screen.dart';
import 'package:main/screens/sign_up_screen.dart';
import 'package:main/theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController(text: '100 234 5678');

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    final phone = '+20 ${_phoneController.text.trim()}';
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => OtpScreen(phoneNumber: phone)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      eyebrow: 'Login',
      title: 'Welcome back',
      subtitle: "Sign in with your phone number. We'll send you a secure code.",
      actionLabel: 'Continue',
      onAction: _continue,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LabeledInput(
              label: 'Phone number',
              controller: _phoneController,
              icon: Icons.call_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                LengthLimitingTextInputFormatter(12),
              ],
              validator: _validateEgyptianPhone,
            ),
            const SizedBox(height: 16),
            const NoticePanel(
              icon: Icons.lock_outline,
              text: 'Phone-first. No password to remember.',
            ),
            const SizedBox(height: 24),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'New to Wasla?  ',
                  style: TextStyle(color: AppColors.darkGreen, fontSize: 13),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SignUpScreen(),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.darkGreen,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Create account'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Need help signing in? Contact support.',
              style: TextStyle(color: AppColors.darkGreen, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

String? _validateEgyptianPhone(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length != 10 || !digits.startsWith('1')) {
    return 'Enter a valid 10-digit Egyptian mobile number';
  }
  return null;
}
