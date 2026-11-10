import 'package:flutter/material.dart';
import 'package:main/components/app_page_header.dart';
import 'package:main/components/main_button.dart';
import 'package:main/pages/profile_subpages.dart';
import 'package:main/screens/login_screen.dart';
import 'package:main/screens/welcome_screen.dart';
import 'package:main/services/auth_service.dart';
import 'package:main/theme/app_theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.isActive = false, this.onNavigateToTab});

  final bool isActive;
  final ValueChanged<int>? onNavigateToTab;

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

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        children: [
          AppPageHeader(
            title: 'Your account',
            trailing: IconButton(
              tooltip: 'Notifications',
              onPressed: () => _openSubpage(ProfileDestination.notifications),
              icon: const Icon(
                Icons.notifications_none,
                color: AppColors.darkGreen,
              ),
            ),
          ),
          const SizedBox(height: 16),
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
            _AccountSummary(
              name: name,
              phone: _findValue(user, const ['phone', 'phoneNumber']),
            ),
            const SizedBox(height: 16),
            for (final item in _profileMenu)
              _AccountMenuItem(
                icon: item.icon,
                label: item.label,
                isLoading: item.isLogout && _isLoggingOut,
                onTap: () {
                  if (item.tabIndex != null) {
                    widget.onNavigateToTab?.call(item.tabIndex!);
                  } else if (item.destination != null) {
                    _openSubpage(item.destination!, user: user);
                  } else if (item.isLogout) {
                    _logout();
                  }
                },
              ),
          ],
        ],
      ),
    );
  }

  void _openSubpage(
    ProfileDestination destination, {
    Map<String, dynamic> user = const {},
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileSubpage(destination: destination, user: user),
      ),
    );
  }
}

class _AccountSummary extends StatelessWidget {
  const _AccountSummary({required this.name, required this.phone});

  final String? name;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name ?? 'Customer account', style: AppTypography.headingSm),
          if (phone != null) ...[
            const SizedBox(height: 4),
            Text(phone!, style: AppTypography.bodyXs),
          ],
        ],
      ),
    );
  }
}

class _AccountMenuItem extends StatelessWidget {
  const _AccountMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        child: Row(
          children: [
            Icon(icon, color: AppColors.darkGreen, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppTypography.bodySm)),
            if (isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: AppColors.accent,
                  strokeWidth: 2,
                ),
              )
            else
              const Text('·  ›', style: TextStyle(color: AppColors.darkGreen)),
          ],
        ),
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

String? _displayName(Map<String, dynamic> user) {
  final name = _findValue(user, const ['fullName', 'name']);
  if (name != null) return name;

  final first = _findValue(user, const ['firstName']);
  final last = _findValue(user, const ['lastName']);
  final combined = [first, last].whereType<String>().join(' ').trim();
  return combined.isEmpty ? null : combined;
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

const _profileMenu = <_ProfileMenuEntry>[
  _ProfileMenuEntry(
    Icons.person_outline,
    'Personal information',
    destination: ProfileDestination.personalInformation,
  ),
  _ProfileMenuEntry(
    Icons.location_on_outlined,
    'Saved locations',
    destination: ProfileDestination.savedLocations,
  ),
  _ProfileMenuEntry(
    Icons.credit_card_outlined,
    'Payment methods',
    destination: ProfileDestination.paymentMethods,
  ),
  _ProfileMenuEntry(
    Icons.account_balance_wallet_outlined,
    'Wallet',
    tabIndex: 3,
  ),
  _ProfileMenuEntry(Icons.alt_route, 'Trips', tabIndex: 1),
  _ProfileMenuEntry(
    Icons.notifications_none,
    'Notifications',
    destination: ProfileDestination.notifications,
  ),
  _ProfileMenuEntry(
    Icons.shield_outlined,
    'Safety',
    destination: ProfileDestination.safety,
  ),
  _ProfileMenuEntry(
    Icons.help_outline,
    'Help Center',
    destination: ProfileDestination.helpCenter,
  ),
  _ProfileMenuEntry(
    Icons.translate,
    'Language',
    destination: ProfileDestination.language,
  ),
  _ProfileMenuEntry(
    Icons.lock_outline,
    'Privacy',
    destination: ProfileDestination.privacy,
  ),
  _ProfileMenuEntry(
    Icons.description_outlined,
    'Terms',
    destination: ProfileDestination.terms,
  ),
  _ProfileMenuEntry(Icons.logout, 'Logout', isLogout: true),
];

class _ProfileMenuEntry {
  const _ProfileMenuEntry(
    this.icon,
    this.label, {
    this.destination,
    this.tabIndex,
    this.isLogout = false,
  });

  final IconData icon;
  final String label;
  final ProfileDestination? destination;
  final int? tabIndex;
  final bool isLogout;
}
