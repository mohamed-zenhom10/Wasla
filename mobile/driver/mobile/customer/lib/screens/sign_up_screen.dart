import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:main/components/auth_components.dart';
import 'package:main/screens/otp_screen.dart';
import 'package:main/theme/app_theme.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'Mariam Adel');
  final _phoneController = TextEditingController(text: '100 234 5678');
  final _emailController = TextEditingController(text: 'mariam.adel@email.com');
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_acceptedTerms || !_formKey.currentState!.validate()) {
      if (!_acceptedTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please accept the Terms and Privacy Policy.'),
          ),
        );
      }
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OtpScreen(phoneNumber: '+20 ${_phoneController.text.trim()}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      eyebrow: 'Create account',
      title: "Let's get moving",
      actionLabel: 'Continue',
      onAction: _continue,
      content: Form(
        key: _formKey,
        child: Column(
          children: [
            LabeledInput(
              label: 'Full name',
              controller: _nameController,
              icon: Icons.person_outline,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              validator: (value) => (value ?? '').trim().length < 2
                  ? 'Enter your full name'
                  : null,
            ),
            const SizedBox(height: 18),
            LabeledInput(
              label: 'Phone number',
              controller: _phoneController,
              icon: Icons.call_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                LengthLimitingTextInputFormatter(12),
              ],
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.length == 10 && digits.startsWith('1')
                    ? null
                    : 'Enter a valid 10-digit Egyptian mobile number';
              },
            ),
            const SizedBox(height: 18),
            LabeledInput(
              label: 'Email - optional',
              controller: _emailController,
              icon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              validator: (value) {
                if ((value ?? '').trim().isEmpty) return null;
                return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value!)
                    ? null
                    : 'Enter a valid email address';
              },
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _acceptedTerms,
              onChanged: (value) =>
                  setState(() => _acceptedTerms = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.darkGreen,
              title: const Text(
                'I agree to the Terms and Privacy Policy',
                style: TextStyle(color: AppColors.darkGreen, fontSize: 13),
              ),
            ),
            const SizedBox(height: 4),
            const NoticePanel(
              icon: Icons.info_outline,
              text: 'Your number is shared only with your assigned driver during a trip.',
            ),
          ],
        ),
      ),
    );
  }
}
