import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:main/components/auth_components.dart';
import 'package:main/screens/otp_screen.dart';
import 'package:main/services/auth_service.dart';
import 'package:main/services/international_phone_number.dart';
import 'package:main/theme/app_theme.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

final RegExp _signUpPasswordRegex = RegExp(
  r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d).{8,}$',
);

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  IsoCode _selectedPhoneCountry = IsoCode.EG;
  bool _acceptedTerms = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
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

    setState(() => _isSubmitting = true);

    final normalizedPhone = InternationalPhoneNumber.toE164(
      _phoneController.text,
      _selectedPhoneCountry,
    );
    if (normalizedPhone == null) {
      setState(() => _isSubmitting = false);
      _formKey.currentState!.validate();
      return;
    }

    final result = await AuthService.register(
      fullName: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: normalizedPhone,
      password: _passwordController.text,
    );

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    if (!result.success) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OtpScreen(
          email: _emailController.text.trim(),
          phoneNumber: normalizedPhone,
        ),
      ),
    );
  }

  String? _validatePhoneNumber(String? value) {
    if (InternationalPhoneNumber.parse(value ?? '', _selectedPhoneCountry) ==
        null) {
      return 'Enter a valid phone number for the selected country';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      eyebrow: 'Create account',
      title: "Let's get moving",
      actionLabel: 'Continue',
      onAction: _continue,
      isLoading: _isSubmitting,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Phone number', style: AppTypography.labelMd),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.light,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    children: [
                      CountryCodePicker(
                        initialSelection: 'EG',
                        favorite: const ['+20', 'US'],
                        countryFilter: IsoCode.values
                            .map((isoCode) => isoCode.name)
                            .toList(growable: false),
                        showCountryOnly: false,
                        showOnlyCountryWhenClosed: false,
                        showDropDownButton: true,
                        showFlag: true,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: AppTypography.bodySm,
                        dialogTextStyle: AppTypography.bodySm,
                        searchStyle: AppTypography.bodySm,
                        dialogBackgroundColor: AppColors.white,
                        onChanged: (country) {
                          final isoCode = country.code;
                          if (isoCode == null) return;
                          final matchedCountries = IsoCode.values.where(
                            (iso) => iso.name == isoCode,
                          );
                          if (matchedCountries.isEmpty) return;
                          setState(() {
                            _selectedPhoneCountry = matchedCountries.first;
                          });
                          _formKey.currentState?.validate();
                        },
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: AppColors.borderLight,
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          style: AppTypography.bodyMd,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9\s()-]'),
                            ),
                          ],
                          validator: _validatePhoneNumber,
                          decoration: InputDecoration(
                            hintText: 'Phone number',
                            hintStyle: AppTypography.bodySm.copyWith(
                              color: AppColors.gray,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            LabeledInput(
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
                    ? null
                    : 'Enter a valid email address';
              },
            ),
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
