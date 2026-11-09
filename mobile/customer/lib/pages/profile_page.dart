import 'package:flutter/material.dart';
import 'package:main/components/app_page_header.dart';
import 'package:main/components/main_button.dart';
import 'package:main/screens/login_screen.dart';
import 'package:main/screens/welcome_screen.dart';
import 'package:main/services/auth_service.dart';
import 'package:main/theme/app_theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.isActive = false});

  final bool isActive;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  AuthSession? _session;
  Object? _loadError;
  bool _isLoading = false;
  bool _isLoggingOut = false;
  bool _loadRequested = false;

  @override
  void initState() {
    super.initState();
    _scheduleInitialLoad();
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _scheduleInitialLoad();
    }
  }

  void _scheduleInitialLoad() {
    if (!widget.isActive || _loadRequested) return;
    _loadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadProfile();
    });
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final session = await AuthService.loadSession();
      if (!mounted) return;
      setState(() {
        _session = session;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _signIn() async {
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
    if (mounted) _loadProfile();
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);

    String? logoutNotice;
    try {
      final result = await AuthService.logout();
      if (!result.success) {
        logoutNotice =
            'You are signed out on this device. Server sign-out failed: ${result.message}';
      }
    } catch (error) {
      logoutNotice =
          'You are signed out on this device, but local session cleanup failed: $error';
    }

    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );

    if (logoutNotice != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(logoutNotice)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final isAuthenticated = session != null && session.token.trim().isNotEmpty;
    final user = session?.user ?? const <String, dynamic>{};
    final name = _displayName(user);
    final avatarUrl = _findValue(user, const [
      'avatarUrl',
      'profileImageUrl',
      'profileImage',
      'avatar',
      'photoUrl',
      'photo',
      'imageUrl',
    ]);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        children: [
          AppPageHeader(
            title: 'Profile',
            trailing: IconButton(
              tooltip: 'Refresh profile',
              onPressed: _isLoading ? null : _loadProfile,
              icon: const Icon(Icons.refresh, color: AppColors.darkGreen),
            ),
          ),
          const SizedBox(height: 22),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            )
          else if (_loadError != null)
            _ProfileLoadError(onRetry: _loadProfile)
          else if (!isAuthenticated)
            _SignedOutProfile(onSignIn: _signIn)
          else ...[
            _ProfileHeader(name: name, avatarUrl: avatarUrl),
            const SizedBox(height: 28),
            Text('Account information', style: AppTypography.headingSm),
            const SizedBox(height: 12),
            _ProfileDetails(fields: _profileFields(user)),
            const SizedBox(height: 24),
            WaslaButton(
              text: 'Log out',
              onPressed: _logout,
              isLoading: _isLoggingOut,
              variant: WaslaButtonVariant.secondary,
              icon: const Icon(Icons.logout, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.name, required this.avatarUrl});

  final String? name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final uri = avatarUrl == null ? null : Uri.tryParse(avatarUrl!);
    final imageUrl =
        uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty
        ? avatarUrl
        : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: AppColors.white,
            child: imageUrl == null
                ? const Icon(
                    Icons.person_outline,
                    color: AppColors.darkGreen,
                    size: 34,
                  )
                : ClipOval(
                    child: Image.network(
                      imageUrl,
                      width: 68,
                      height: 68,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.person_outline,
                        color: AppColors.darkGreen,
                        size: 34,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name != null)
                  Text(name!, style: AppTypography.headingSm)
                else
                  Text('Customer profile', style: AppTypography.headingSm),
                const SizedBox(height: 4),
                Text(
                  'Information from your account',
                  style: AppTypography.bodyXs.copyWith(color: AppColors.gray),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDetails extends StatelessWidget {
  const _ProfileDetails({required this.fields});

  final List<_ProfileField> fields;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Text(
          'No profile details were included in the sign-in response.',
          style: AppTypography.bodySm.copyWith(color: AppColors.gray),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          for (var index = 0; index < fields.length; index++) ...[
            _ProfileDetailRow(field: fields[index]),
            if (index != fields.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _ProfileDetailRow extends StatelessWidget {
  const _ProfileDetailRow({required this.field});

  final _ProfileField field;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              field.label,
              style: AppTypography.bodyXs.copyWith(color: AppColors.gray),
            ),
          ),
          Expanded(
            child: Text(
              field.value,
              style: AppTypography.bodySm,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileLoadError extends StatelessWidget {
  const _ProfileLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _ProfileMessage(
      icon: Icons.cloud_off_outlined,
      title: 'Profile unavailable',
      message: 'We could not load your saved account information.',
      action: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Try again'),
      ),
    );
  }
}

class _SignedOutProfile extends StatelessWidget {
  const _SignedOutProfile({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return _ProfileMessage(
      icon: Icons.person_outline,
      title: 'Sign in to view your profile',
      message: 'Your account details will appear here after you sign in.',
      action: WaslaButton(text: 'Sign in', onPressed: onSignIn, height: 50),
    );
  }
}

class _ProfileMessage extends StatelessWidget {
  const _ProfileMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, color: AppColors.gray, size: 42),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppTypography.headingSm,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTypography.bodySm.copyWith(color: AppColors.gray),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          action,
        ],
      ),
    );
  }
}

class _ProfileField {
  const _ProfileField(this.label, this.value);

  final String label;
  final String value;
}

String? _displayName(Map<String, dynamic> user) {
  final name = _findValue(user, const ['fullName', 'name']);
  if (name != null) return name;

  final first = _findValue(user, const ['firstName']);
  final last = _findValue(user, const ['lastName']);
  final combined = [first, last].whereType<String>().join(' ').trim();
  return combined.isEmpty ? null : combined;
}

List<_ProfileField> _profileFields(Map<String, dynamic> user) {
  const knownFields = <(String, List<String>)>[
    ('Full name', ['fullName', 'name']),
    ('Email', ['email']),
    ('Phone', ['phone', 'phoneNumber']),
    ('Account ID', ['accountId', 'customerId', 'userId', '_id', 'id']),
    ('Created', ['createdAt', 'created_at', 'createdOn']),
  ];

  final fields = <_ProfileField>[];
  final claimed = <String>{};

  for (final (label, aliases) in knownFields) {
    final value = label == 'Full name'
        ? _displayName(user)
        : _findValue(user, aliases);
    claimed.addAll(aliases.map(_normalizeKey));
    if (label == 'Full name') {
      claimed
        ..add('firstname')
        ..add('lastname');
    }
    if (value != null) fields.add(_ProfileField(label, value));
  }

  _appendAdditionalFields(user, fields, claimed, depth: 0);
  return fields;
}

void _appendAdditionalFields(
  Map<dynamic, dynamic> source,
  List<_ProfileField> fields,
  Set<String> claimed, {
  required int depth,
}) {
  if (depth > 2) return;

  for (final entry in source.entries) {
    final key = entry.key.toString();
    final normalizedKey = _normalizeKey(key);
    if (_isSensitiveKey(normalizedKey) ||
        _isExcludedProfileKey(normalizedKey) ||
        _isAvatarKey(normalizedKey) ||
        normalizedKey == '__v' ||
        claimed.contains(normalizedKey)) {
      continue;
    }

    final value = entry.value;
    if (value is Map) {
      _appendAdditionalFields(value, fields, claimed, depth: depth + 1);
      continue;
    }

    final displayValue = _stringValue(value);
    if (displayValue == null) continue;

    claimed.add(normalizedKey);
    fields.add(_ProfileField(_humanize(key), displayValue));
  }
}

String? _findValue(Map<dynamic, dynamic> source, List<String> aliases) {
  for (final alias in aliases) {
    final normalizedAlias = _normalizeKey(alias);
    for (final entry in source.entries) {
      if (_normalizeKey(entry.key.toString()) == normalizedAlias) {
        final value = _stringValue(entry.value);
        if (value != null) return value;
      }
    }
  }

  for (final value in source.values) {
    if (value is Map) {
      final nested = _findValue(value, aliases);
      if (nested != null) return nested;
    }
  }
  return null;
}

String? _stringValue(Object? value) {
  if (value == null) return null;
  if (value is String) return value.trim().isEmpty ? null : value.trim();
  if (value is num) return value.toString();
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is List) {
    final values = value.map(_stringValue).whereType<String>().toList();
    return values.isEmpty ? null : values.join(', ');
  }
  return null;
}

String _normalizeKey(String key) =>
    key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _humanize(String key) {
  final words = key
      .replaceAll(RegExp(r'([a-z0-9])([A-Z])'), r'$1 $2')
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .trim();
  if (words.isEmpty) return key;
  return words[0].toUpperCase() + words.substring(1);
}

bool _isSensitiveKey(String key) =>
    key.contains('password') ||
    key.contains('token') ||
    key.contains('secret') ||
    key.contains('credential') ||
    key.contains('salt') ||
    key.contains('hash');

bool _isExcludedProfileKey(String key) =>
    key == 'role' ||
    key == 'userrole' ||
    key == 'usertype' ||
    key.contains('language') ||
    key.contains('verified') ||
    (key.contains('needs') &&
        key.contains('polic') &&
        key.contains('accept')) ||
    key.contains('needsacceptance') ||
    key == 'acceptpolicies' ||
    key == 'acceptedpolicies' ||
    key == 'termsaccepted' ||
    key == 'policiesaccepted';

bool _isAvatarKey(String key) =>
    key == 'avatar' ||
    key.contains('avatarurl') ||
    key.contains('profileimage') ||
    key == 'photo' ||
    key.contains('photourl') ||
    key == 'image' ||
    key.contains('imageurl') ||
    key == 'picture';
