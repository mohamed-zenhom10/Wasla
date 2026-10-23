import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:main/components/auth_components.dart';
import 'package:main/screens/otp_screen.dart';
import 'package:main/theme/app_theme.dart';

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController(text: '100 234 5678');
  String _dialCode = '+20';
  String _countryName = 'Egypt';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _sendCode() {
    if (!_formKey.currentState!.validate()) return;
    final phone = '$_dialCode ${_phoneController.text.trim()}';
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => OtpScreen(phoneNumber: phone)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      eyebrow: 'Secure verification',
      title: 'Your phone number',
      subtitle: 'Use a number you can receive messages on in Egypt.',
      actionLabel: 'Send verification code',
      onAction: _sendCode,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Country',
              style: TextStyle(
                color: AppColors.darkGreen,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            PopupMenuButton<String>(
              onSelected: (value) {
                final parts = value.split('|');
                setState(() {
                  _countryName = parts[0];
                  _dialCode = parts[1];
                });
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'Egypt|+20', child: Text('Egypt  +20')),
                PopupMenuItem(
                  value: 'Saudi Arabia|+966',
                  child: Text('Saudi Arabia  +966'),
                ),
                PopupMenuItem(
                  value: 'United Arab Emirates|+971',
                  child: Text('United Arab Emirates  +971'),
                ),
              ],
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.light,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.keyboard_arrow_down),
                    const SizedBox(width: 12),
                    Text('$_countryName  $_dialCode'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            LabeledInput(
              label: 'Mobile number',
              controller: _phoneController,
              icon: Icons.call_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                LengthLimitingTextInputFormatter(12),
              ],
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.length < 8 || digits.length > 12) {
                  return 'Enter a valid mobile number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.light,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, size: 15),
                  SizedBox(width: 6),
                  Text(
                    'Code expires in 5 minutes',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              "We'll never post or share your number publicly.",
              style: TextStyle(color: AppColors.darkGreen, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
