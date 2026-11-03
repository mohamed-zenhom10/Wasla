import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:main/components/auth_components.dart';
import 'package:main/screens/otp_screen.dart';
<<<<<<< HEAD
import 'package:main/theme/app_theme.dart';

=======
import 'package:main/services/auth_service.dart';
import 'package:main/theme/app_theme.dart';

final RegExp _signUpPasswordRegex = RegExp(
  r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d).{8,}$',
);

>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
<<<<<<< HEAD
  final _nameController = TextEditingController(text: 'Mariam Adel');
  final _phoneController = TextEditingController(text: '100 234 5678');
  final _emailController = TextEditingController(text: 'mariam.adel@email.com');
  bool _acceptedTerms = false;
=======
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _acceptedTerms = false;
  bool _isSubmitting = false;
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
<<<<<<< HEAD
    super.dispose();
  }

  void _continue() {
=======
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
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
<<<<<<< HEAD
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OtpScreen(phoneNumber: '+20 ${_phoneController.text.trim()}'),
=======

    setState(() => _isSubmitting = true);

    final result = await AuthService.register(
      fullName: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OtpScreen(
          email: _emailController.text.trim(),
          phoneNumber: '+20 ${_phoneController.text.trim()}',
        ),
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
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
<<<<<<< HEAD
=======
      isLoading: _isSubmitting,
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
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
<<<<<<< HEAD
              label: 'Email - optional',
              controller: _emailController,
              icon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              validator: (value) {
                if ((value ?? '').trim().isEmpty) return null;
                return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value!)
=======
              label: 'Email',
              controller: _emailController,
              icon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (value) {
                final email = (value ?? '').trim();
                if (email.isEmpty) {
                  return 'Enter your email address';
                }
                return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
                    ? null
                    : 'Enter a valid email address';
              },
            ),
<<<<<<< HEAD
=======
            const SizedBox(height: 18),
            LabeledInput(
              label: 'Password',
              controller: _passwordController,
              icon: Icons.lock_outline,
              obscureText: true,
              textInputAction: TextInputAction.next,
              validator: _signUpPasswordValidator,
            ),
            const SizedBox(height: 18),
            LabeledInput(
              label: 'Confirm password',
              controller: _confirmPasswordController,
              icon: Icons.lock_reset,
              obscureText: true,
              textInputAction: TextInputAction.done,
              validator: (value) {
                final confirm = (value ?? '').trim();
                if (confirm.isEmpty) {
                  return 'Confirm your password';
                }
                if (confirm != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
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
<<<<<<< HEAD
=======

String? _signUpPasswordValidator(String? value) {
  final password = value ?? '';
  if (password.isEmpty) {
    return 'Enter your password';
  }
  if (!_signUpPasswordRegex.hasMatch(password)) {
    return 'Use at least 8 characters, an uppercase letter, a lowercase letter, and a number';
  }
  return null;
}
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
