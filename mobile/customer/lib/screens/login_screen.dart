import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:main/components/auth_components.dart';
import 'package:main/screens/home_screen.dart';
import 'package:main/screens/sign_up_screen.dart';
import 'package:main/services/auth_service.dart';
import 'package:main/theme/app_theme.dart';

final RegExp _emailRegex = RegExp(
  r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
);

final RegExp _passwordRegex = RegExp(
  r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d).{8,}$',
);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final result = await AuthService.login(
      email: _emailController.text.trim(),
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

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      eyebrow: 'Login',
      title: 'Welcome back',
      subtitle: 'Sign in with your email and password.',
      actionLabel: 'Continue',
      onAction: _continue,
      isLoading: _isSubmitting,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LabeledInput(
              label: 'Email',
              controller: _emailController,
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: _validateEmail,
            ),
            const SizedBox(height: 16),
            LabeledInput(
              label: 'Password',
              controller: _passwordController,
              icon: Icons.lock_outline,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              suffix: IconButton(
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.darkGreen,
                  size: 20,
                ),
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                splashRadius: 18,
              ),
              validator: _validatePassword,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ForgotPasswordEmailScreen(),
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.darkGreen,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 8),
            const NoticePanel(
              icon: Icons.lock_outline,
              text: 'Use your account email and password to continue.',
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

class ForgotPasswordEmailScreen extends StatefulWidget {
  const ForgotPasswordEmailScreen({super.key});

  @override
  State<ForgotPasswordEmailScreen> createState() =>
      _ForgotPasswordEmailScreenState();
}

class _ForgotPasswordEmailScreenState extends State<ForgotPasswordEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final result = await AuthService.forgotPassword(
      email: _emailController.text.trim(),
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
        builder: (_) => ForgotPasswordOtpScreen(
          email: _emailController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      eyebrow: 'Reset',
      title: 'Forgot password',
      subtitle: 'Enter the email address linked to your account.',
      actionLabel: 'Send code',
      onAction: _continue,
      isLoading: _isSubmitting,
      content: Form(
        key: _formKey,
        child: LabeledInput(
          label: 'Email',
          controller: _emailController,
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          validator: _validateEmail,
        ),
      ),
    );
  }
}

class ForgotPasswordOtpScreen extends StatefulWidget {
  const ForgotPasswordOtpScreen({super.key, required this.email});

  final String email;

  @override
  State<ForgotPasswordOtpScreen> createState() => _ForgotPasswordOtpScreenState();
}

class _ForgotPasswordOtpScreenState extends State<ForgotPasswordOtpScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  int _secondsRemaining = 30;
  bool _isResending = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        setState(() => _secondsRemaining = 0);
        return;
      }
      setState(() => _secondsRemaining--);
      _startTimer();
    });
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
      final nextIndex = digits.length.clamp(0, 5);
      if (nextIndex < _focusNodes.length) {
        _focusNodes[nextIndex].requestFocus();
      }
      setState(() {});
      return;
    }

    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
  }

  void _resendCode() {
    if (_secondsRemaining > 0 || _isResending) return;
    setState(() => _isResending = true);
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _secondsRemaining = 30;
        _isResending = false;
      });
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new 6-digit code has been sent.')),
      );
    });
  }

  Future<void> _continue() async {
    if (_code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit verification code.')),
      );
      return;
    }

    setState(() => _isVerifying = true);

    final result = await AuthService.verifyEmail(
      email: widget.email,
      code: _code,
    );

    if (!mounted) return;
    setState(() => _isVerifying = false);

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
        builder: (_) => ForgotPasswordNewPasswordScreen(
          email: widget.email,
          otp: _code,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      eyebrow: 'Verification',
      title: 'Check your email',
      subtitle: 'Enter the 6-digit code sent to ${widget.email}.',
      actionLabel: 'Verify and continue',
      onAction: _continue,
      isLoading: _isVerifying,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(
              6,
              (index) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 5 ? 0 : 8),
                  child: TextField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    onChanged: (value) => _onDigitChanged(index, value),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.light,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
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
          const SizedBox(height: 18),
          const NoticePanel(
            icon: Icons.info_outline,
            text: 'This reset flow is a prototype. No email service is connected.',
          ),
        ],
      ),
    );
  }
}

class ForgotPasswordNewPasswordScreen extends StatefulWidget {
  const ForgotPasswordNewPasswordScreen({
    super.key,
    required this.email,
    required this.otp,
  });

  final String email;
  final String otp;

  @override
  State<ForgotPasswordNewPasswordScreen> createState() =>
      _ForgotPasswordNewPasswordScreenState();
}

class _ForgotPasswordNewPasswordScreenState
    extends State<ForgotPasswordNewPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _isUpdating = false;

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isUpdating = true);

    final result = await AuthService.resetPassword(
      email: widget.email,
      otp: widget.otp,
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isUpdating = false);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      eyebrow: 'Security',
      title: 'Create new password',
      subtitle: 'Choose a strong password for ${widget.email}.',
      actionLabel: 'Update password',
      onAction: _continue,
      isLoading: _isUpdating,
      content: Form(
        key: _formKey,
        child: Column(
          children: [
            LabeledInput(
              label: 'New password',
              controller: _passwordController,
              icon: Icons.lock_outline,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              suffix: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.darkGreen,
                  size: 20,
                ),
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                splashRadius: 18,
              ),
              validator: _validatePassword,
            ),
            const SizedBox(height: 18),
            LabeledInput(
              label: 'Confirm password',
              controller: _confirmPasswordController,
              icon: Icons.lock_reset,
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              suffix: IconButton(
                onPressed: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                ),
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.darkGreen,
                  size: 20,
                ),
                tooltip: _obscureConfirmPassword
                    ? 'Show password'
                    : 'Hide password',
                splashRadius: 18,
              ),
              validator: (value) {
                final password = _passwordController.text.trim();
                final confirm = (value ?? '').trim();
                if (confirm.isEmpty) {
                  return 'Confirm your password';
                }
                if (confirm != password) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 18),
            const NoticePanel(
              icon: Icons.shield_outlined,
              text: 'Use at least 8 characters with upper, lower, and a number.',
            ),
          ],
        ),
      ),
    );
  }
}

String? _validateEmail(String? value) {
  final email = (value ?? '').trim();
  if (email.isEmpty) {
    return 'Enter your email address';
  }
  if (!_emailRegex.hasMatch(email)) {
    return 'Enter a valid email address';
  }
  return null;
}

String? _validatePassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) {
    return 'Enter your password';
  }
  if (!_passwordRegex.hasMatch(password)) {
    return 'Use at least 8 characters, an uppercase letter, a lowercase letter, and a number';
  }
  return null;
}
