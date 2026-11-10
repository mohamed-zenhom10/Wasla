import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ProfileDestination {
  personalInformation,
  savedLocations,
  paymentMethods,
  notifications,
  safety,
  helpCenter,
  language,
  privacy,
  terms,
}

class ProfileSubpage extends StatefulWidget {
  const ProfileSubpage({
    super.key,
    required this.destination,
    this.user = const {},
  });

  final ProfileDestination destination;
  final Map<String, dynamic> user;

  @override
  State<ProfileSubpage> createState() => _ProfileSubpageState();
}

class _ProfileSubpageState extends State<ProfileSubpage> {
  String _language = 'English';
  String _helpQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.destination == ProfileDestination.language) {
      _loadSavedLanguage();
    }
  }

  Future<void> _loadSavedLanguage() async {
    final preferences = await SharedPreferences.getInstance();
    final savedLanguage = preferences.getString('profile_language');
    if (!mounted || savedLanguage == null) return;
    setState(() => _language = savedLanguage);
  }

  String get _title => switch (widget.destination) {
    ProfileDestination.personalInformation => 'Personal information',
    ProfileDestination.savedLocations => 'Saved locations',
    ProfileDestination.paymentMethods => 'Payment methods',
    ProfileDestination.notifications => 'Notifications',
    ProfileDestination.safety => 'Every move, protected',
    ProfileDestination.helpCenter => 'How can we help?',
    ProfileDestination.language => 'Choose your language',
    ProfileDestination.privacy => 'Your privacy',
    ProfileDestination.terms => 'Terms of service',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back to profile',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppColors.darkGreen,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed:
                        widget.destination == ProfileDestination.notifications
                        ? null
                        : () => _open(ProfileDestination.notifications),
                    icon: const Icon(
                      Icons.notifications_none,
                      color: AppColors.darkGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(_title, style: AppTypography.headingMd),
              const SizedBox(height: 18),
              Expanded(child: SingleChildScrollView(child: _buildContent())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() => switch (widget.destination) {
    ProfileDestination.personalInformation => _personalInformation(),
    ProfileDestination.savedLocations => _emptyFeature(
      icon: Icons.location_on_outlined,
      message: 'No saved locations are available in your account.',
      detail: 'Saved addresses can be used as pickup or drop-off points.',
      action: 'Add location',
    ),
    ProfileDestination.paymentMethods => _emptyFeature(
      icon: Icons.credit_card_outlined,
      message: 'No payment methods are available.',
      detail: 'Payment methods are not connected to an account service yet.',
      action: 'Add payment method',
    ),
    ProfileDestination.notifications => _emptyFeature(
      icon: Icons.notifications_none,
      message: 'No notifications yet',
      detail: 'Updates about your account and trips will appear here.',
    ),
    ProfileDestination.safety => _safety(),
    ProfileDestination.helpCenter => _helpCenter(),
    ProfileDestination.language => _languageSettings(),
    ProfileDestination.privacy => _privacy(),
    ProfileDestination.terms => _terms(),
  };

  Widget _personalInformation() {
    final name = _userValue(const ['fullName', 'name']) ?? _joinedName();
    final phone = _userValue(const ['phone', 'phoneNumber']);
    final email = _userValue(const ['email']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _informationField('Full name', name),
        const SizedBox(height: 16),
        _informationField('Phone number', phone),
        const SizedBox(height: 16),
        _informationField('Email', email),
        const SizedBox(height: 16),
        _panel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: AppColors.darkGreen,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Account verification details are not available here.',
                  style: AppTypography.bodySm,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Profile details are read-only because account updates are not '
          'connected to a service.',
          style: AppTypography.bodyXs.copyWith(color: AppColors.gray),
        ),
      ],
    );
  }

  Widget _informationField(String label, String? value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelMd),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.light,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(value ?? 'Not provided', style: AppTypography.bodySm),
        ),
      ],
    );
  }

  Widget _safety() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.shield_outlined, color: AppColors.accent, size: 48),
        const SizedBox(height: 16),
        Text(
          'Verified drivers. Visible trips. Support when it matters.',
          style: AppTypography.bodyMd,
        ),
        const SizedBox(height: 20),
        _panel(
          child: Column(
            children: [
              _featureRow(Icons.share_outlined, 'Share live trip'),
              _featureRow(Icons.person_add_alt_1, 'Trusted contact'),
              _featureRow(Icons.call_outlined, 'Emergency assistance · 122'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Shipment protection', style: AppTypography.headingSm),
              const SizedBox(height: 10),
              Text(
                'Report loss or damage with delivery photos and trip details. '
                'Eligibility is reviewed by our support team.',
                style: AppTypography.bodySm,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _featureRow(Icons.warning_amber_outlined, 'Report an unsafe situation'),
        const SizedBox(height: 12),
        Text(
          'For immediate danger in Egypt, contact emergency services first.',
          style: AppTypography.bodyXs,
        ),
        const SizedBox(height: 20),
        WaslaButton(
          text: 'Contact safety team',
          onPressed: () => _showUnavailable('Safety support'),
        ),
      ],
    );
  }

  Widget _helpCenter() {
    const topics = <(IconData, String)>[
      (Icons.local_shipping_outlined, 'Help with a trip'),
      (Icons.credit_card_outlined, 'Payments and refunds'),
      (Icons.calendar_month_outlined, 'Changing a booking'),
      (Icons.inventory_2_outlined, 'Damaged or missing items'),
      (Icons.person_outline, 'Account and verification'),
    ];
    final matchingTopics = topics
        .where(
          (topic) => topic.$2.toLowerCase().contains(_helpQuery.toLowerCase()),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Search help', style: AppTypography.labelMd),
        const SizedBox(height: 8),
        TextField(
          onChanged: (value) => setState(() => _helpQuery = value.trim()),
          style: AppTypography.bodySm,
          decoration: InputDecoration(
            hintText: 'Search trips, payments, cargo...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: AppColors.light,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _panel(
          child: Column(
            children: [
              for (final topic in matchingTopics)
                _featureRow(topic.$1, topic.$2),
              if (matchingTopics.isEmpty)
                Text('No matching help topics.', style: AppTypography.bodySm),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Trip safety support is available through local emergency services.',
          style: AppTypography.bodySm,
        ),
        const SizedBox(height: 20),
        WaslaButton(
          text: 'Chat with support',
          onPressed: () => _showUnavailable('Customer support chat'),
        ),
      ],
    );
  }

  Widget _languageSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _languageOption('English'),
        const SizedBox(height: 16),
        _languageOption('العربية — مصر'),
        const SizedBox(height: 16),
        Text(
          'Language changes apply across the app. Your saved locations and '
          'bookings stay the same.',
          style: AppTypography.bodySm,
        ),
        const SizedBox(height: 16),
        _panel(
          child: const Text(
            'يمكنك اختيار اللغة العربية المناسبة.',
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(height: 20),
        WaslaButton(text: 'Save language', onPressed: _saveLanguage),
      ],
    );
  }

  Widget _languageOption(String value) {
    final selected = _language == value;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => setState(() => _language = value),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.light,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.borderLight,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(child: Text(value, style: AppTypography.bodySm)),
            if (selected) Text('Selected ✓', style: AppTypography.labelMd),
          ],
        ),
      ),
    );
  }

  Future<void> _saveLanguage() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('profile_language', _language);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Language preference saved. Full app translation is not available yet.',
        ),
      ),
    );
  }

  Widget _privacy() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text('UPDATED 1 OCT 2026', style: AppTypography.labelXs),
        ),
        const SizedBox(height: 14),
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your data, only where needed.',
                style: AppTypography.headingSm,
              ),
              const SizedBox(height: 12),
              Text(
                'We use your phone, pickup and drop-off locations to arrange '
                'a trip. Drivers see trip details only while assigned.',
                style: AppTypography.bodySm,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Cargo photos', style: AppTypography.headingSm),
        const SizedBox(height: 12),
        Text(
          'Photos help estimate vehicle fit and verify delivery. Avoid '
          'personal documents and people in your photos.',
          style: AppTypography.bodySm,
        ),
        const SizedBox(height: 20),
        Text('Your controls', style: AppTypography.headingSm),
        const SizedBox(height: 16),
        _featureRow(Icons.location_on_outlined, 'Manage location access'),
        _featureRow(Icons.download_outlined, 'Request a copy of your data'),
        _featureRow(Icons.delete_outline, 'Request account deletion'),
        const SizedBox(height: 16),
        Text(
          'Illustrative product privacy copy. Final legal policy requires '
          'local legal review.',
          style: AppTypography.bodyXs,
        ),
      ],
    );
  }

  Widget _terms() {
    const sections = <(String, String)>[
      (
        'Booking and changes',
        'Review the route, cargo, vehicle and price before requesting. '
            'Changes to the agreed service require approval.',
      ),
      (
        'Safe cargo',
        'Declare fragile items. Do not book prohibited or hazardous goods. '
            'Drivers confirm safe loading before departure.',
      ),
      (
        'Protection and disputes',
        'Keep delivery evidence and report a problem from the trip. Support '
            'reviews both customer and driver responses.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Clear expectations for every move.',
          style: AppTypography.headingSm,
        ),
        const SizedBox(height: 16),
        for (final section in sections) ...[
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(section.$1, style: AppTypography.labelMd),
                const SizedBox(height: 10),
                Text(section.$2, style: AppTypography.bodySm),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          'Illustrative service terms. Final policy requires local legal review.',
          style: AppTypography.bodyXs,
        ),
      ],
    );
  }

  Widget _emptyFeature({
    required IconData icon,
    required String message,
    required String detail,
    String? action,
  }) {
    return Column(
      children: [
        const SizedBox(height: 64),
        Icon(icon, size: 42, color: AppColors.gray),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.headingSm,
        ),
        const SizedBox(height: 8),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: AppTypography.bodySm.copyWith(color: AppColors.gray),
        ),
        if (action != null) ...[
          const SizedBox(height: 24),
          WaslaButton(text: action, onPressed: () => _showUnavailable(action)),
        ],
      ],
    );
  }

  Widget _featureRow(IconData icon, String label) {
    return InkWell(
      onTap: () => _showUnavailable(label),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: AppColors.darkGreen, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppTypography.bodySm)),
            const Icon(Icons.chevron_right, color: AppColors.gray, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: child,
    );
  }

  String? _userValue(List<String> aliases) {
    return _findUserValue(widget.user, aliases);
  }

  String? _findUserValue(Map<dynamic, dynamic> source, List<String> aliases) {
    for (final alias in aliases) {
      final expected = _normalize(alias);
      for (final entry in source.entries) {
        if (_normalize(entry.key.toString()) == expected &&
            entry.value is String &&
            (entry.value as String).trim().isNotEmpty) {
          return (entry.value as String).trim();
        }
      }
    }
    for (final value in source.values) {
      if (value is Map) {
        final nested = _findUserValue(value, aliases);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  String? _joinedName() {
    final first = _userValue(const ['firstName']);
    final last = _userValue(const ['lastName']);
    final combined = [first, last].whereType<String>().join(' ').trim();
    return combined.isEmpty ? null : combined;
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  void _open(ProfileDestination destination) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProfileSubpage(destination: destination, user: widget.user),
      ),
    );
  }

  void _showUnavailable(String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$feature is not connected yet.')));
  }
}
