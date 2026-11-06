import 'package:driver/components/driver_components.dart';
import 'package:driver/data/driver_api.dart';
import 'package:driver/screens/driver_application_flow.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DriverAuthScreen extends StatefulWidget {
  const DriverAuthScreen({super.key, this.startInLogin = false});

  final bool startInLogin;

  @override
  State<DriverAuthScreen> createState() => _DriverAuthScreenState();
}

class _DriverAuthScreenState extends State<DriverAuthScreen> {
  final _api = DriverApi();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _isRegistering = true;
  bool _awaitingCode = false;
  bool _acceptedPolicies = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _isRegistering = !widget.startInLogin;
  }

  @override
  void dispose() {
    _api.close();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    if (_isRegistering && !_awaitingCode && !_acceptedPolicies) {
      _showMessage('وافق على الشروط وسياسة الخصوصية لإكمال التسجيل.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_awaitingCode) {
        await _api.verifyEmail(
          email: _email.text.trim(),
          code: _code.text.trim(),
        );
        await _openApplication();
      } else if (_isRegistering) {
        await _api.register(
          fullName: _name.text.trim(),
          email: _email.text.trim(),
          phone: _phone.text.trim(),
          password: _password.text,
          acceptPolicies: _acceptedPolicies,
        );
        if (mounted) setState(() => _awaitingCode = true);
      } else {
        await _api.login(email: _email.text.trim(), password: _password.text);
        await _openApplication();
      }
    } on DriverApiException catch (error) {
      if (error.code == 'EMAIL_NOT_VERIFIED' && !_isRegistering) {
        await _sendVerificationCode();
      } else {
        _showMessage(_authError(error));
      }
    } catch (_) {
      _showMessage('تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مجددًا.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openApplication() async {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const DriverApplicationFlow()),
    );
  }

  Future<void> _sendVerificationCode() async {
    try {
      await _api.resendVerificationCode(_email.text.trim());
      _showCodeEntry('تم إرسال رمز تأكيد جديد إلى بريدك.');
    } on DriverApiException catch (error) {
      if (error.code == 'CODE_RECENTLY_SENT') {
        _showCodeEntry('أدخل رمز التأكيد الموجود في بريدك الإلكتروني.');
      } else {
        _showMessage(_authError(error));
      }
    } catch (_) {
      _showMessage('تعذر إرسال الرمز. تحقق من الإنترنت وحاول مجددًا.');
    }
  }

  void _showCodeEntry(String message) {
    if (!mounted) return;
    setState(() => _awaitingCode = true);
    _showMessage(message);
  }

  String _authError(DriverApiException error) => switch (error.code) {
    'EMAIL_TAKEN' => 'البريد الإلكتروني مسجل بالفعل. جرّب تسجيل الدخول.',
    'WRONG_EMAIL_OR_PASSWORD' => 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
    'EMAIL_NOT_VERIFIED' => 'أكد بريدك الإلكتروني باستخدام الرمز المرسل إليك.',
    'CODE_RECENTLY_SENT' =>
      'تم إرسال رمز مؤخرًا. انتظر قليلًا قبل طلب رمز آخر.',
    'WRONG_CODE' => 'رمز التأكيد غير صحيح.',
    'CODE_EXPIRED' => 'انتهت صلاحية الرمز. اطلب رمزًا جديدًا.',
    'ROLE_REQUIRED' => 'هذا الحساب غير مسجل كسائق.',
    'POLICIES_NOT_ACCEPTED' => 'يلزم قبول الشروط لإكمال التسجيل.',
    'INVALID_INPUT' => 'راجع البيانات المدخلة وحاول مرة أخرى.',
    'TOO_MANY_REQUESTS' => 'محاولات كثيرة. انتظر قليلًا ثم حاول مجددًا.',
    _ => error.message,
  };

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final title = _awaitingCode
        ? 'أكد بريدك الإلكتروني'
        : _isRegistering
        ? 'إنشاء حساب سائق'
        : 'تسجيل الدخول';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DriverPageHeader(label: 'حساب السائق'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _awaitingCode
                            ? 'أدخل الرمز المرسل إلى ${_email.text.trim()}.'
                            : 'استخدم حسابًا بدور سائق للمتابعة إلى طلب الانضمام.',
                        style: const TextStyle(
                          color: AppColors.ink,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_isRegistering && !_awaitingCode) ...[
                        DriverField(
                          label: 'الاسم الكامل',
                          controller: _name,
                          icon: Icons.person_outline,
                          textInputAction: TextInputAction.next,
                          validator: _requiredValidator('أدخل الاسم الكامل.'),
                        ),
                        const SizedBox(height: 18),
                      ],
                      DriverField(
                        label: 'البريد الإلكتروني',
                        controller: _email,
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        readOnly: _awaitingCode,
                        textInputAction: TextInputAction.next,
                        validator: _validateEmail,
                      ),
                      if (_isRegistering && !_awaitingCode) ...[
                        const SizedBox(height: 18),
                        DriverField(
                          label: 'رقم الهاتف مع مفتاح الدولة',
                          controller: _phone,
                          icon: Icons.call_outlined,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+ ()-]'),
                            ),
                            LengthLimitingTextInputFormatter(18),
                          ],
                          textInputAction: TextInputAction.next,
                          validator: _validatePhone,
                        ),
                      ],
                      if (_awaitingCode) ...[
                        const SizedBox(height: 18),
                        DriverField(
                          label: 'رمز التأكيد',
                          controller: _code,
                          icon: Icons.password_outlined,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          validator: (value) => (value ?? '').trim().length == 6
                              ? null
                              : 'أدخل الرمز المكون من 6 أرقام.',
                        ),
                      ] else ...[
                        const SizedBox(height: 18),
                        DriverField(
                          label: 'كلمة المرور',
                          controller: _password,
                          icon: Icons.lock_outline,
                          textInputAction: TextInputAction.done,
                          validator: (value) => (value ?? '').length >= 8
                              ? null
                              : 'كلمة المرور يجب ألا تقل عن 8 أحرف.',
                        ),
                      ],
                      if (!_awaitingCode) ...[
                        if (_isRegistering)
                          CheckboxListTile(
                            value: _acceptedPolicies,
                            onChanged: (value) => setState(
                              () => _acceptedPolicies = value ?? false,
                            ),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text(
                              'أوافق على الشروط وسياسة الخصوصية',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        const SizedBox(height: 16),
                        NoticePanel(
                          text: _isRegistering
                              ? 'سيتم إنشاء الحساب بدور سائق وإرسال رمز تأكيد إلى بريدك.'
                              : 'يجب أن يكون الحساب مسجلًا بدور سائق.',
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(
                                  () => _isRegistering = !_isRegistering,
                                ),
                          child: Text(
                            _isRegistering
                                ? 'لديك حساب؟ سجّل الدخول'
                                : 'مستخدم جديد؟ أنشئ حساب سائق',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: PrimaryButton(
                  label: _busy
                      ? 'جارٍ الاتصال...'
                      : _awaitingCode
                      ? 'تأكيد البريد'
                      : 'متابعة',
                  onPressed: _busy ? null : _continue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? Function(String?) _requiredValidator(String message) =>
      (value) => (value ?? '').trim().length >= 3 ? null : message;

  String? _validateEmail(String? value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((value ?? '').trim())
      ? null
      : 'أدخل بريدًا إلكترونيًا صحيحًا.';

  String? _validatePhone(String? value) {
    final phone = (value ?? '').replaceAll(RegExp(r'[ ()-]'), '');
    return RegExp(r'^\+20\d{10}$').hasMatch(phone)
        ? null
        : 'اكتب رقم الهاتف بصيغة +20 ثم 10 أرقام.';
  }
}
