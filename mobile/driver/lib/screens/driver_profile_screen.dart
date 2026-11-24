import 'package:driver/components/driver_components.dart';
import 'package:driver/components/driver_session.dart';
import 'package:driver/data/driver_api.dart';
import 'package:driver/screens/driver_welcome_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key, this.api});

  final DriverApi? api;

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  late final DriverApi _api = widget.api ?? DriverApi();
  Map<String, dynamic> _user = const {};
  Map<String, dynamic> _status = const {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([_api.getMe(), _api.getDriverStatus()]);
      if (!mounted) return;
      setState(() {
        _user =
            (values[0]['user'] as Map?)?.cast<String, dynamic>() ?? const {};
        _status = values[1];
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || handleDriverSessionError(context, error)) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const DriverWelcomeScreen()),
        (_) => false,
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) => error is DriverApiException
      ? error.message
      : 'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مجددًا.';

  String _value(Object? value) =>
      value?.toString().trim().isNotEmpty == true ? value.toString() : '—';

  String _vehicleName(Map<String, dynamic> vehicle) {
    final parts = [vehicle['make'], vehicle['model']]
        .where((part) => part?.toString().trim().isNotEmpty == true)
        .map((part) => part.toString())
        .toList();
    return parts.isEmpty ? '—' : parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = (_status['vehicle'] as Map?)?.cast<String, dynamic>();
    final name = _user['fullName']?.toString().trim() ?? '';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const DriverPageHeader(label: 'Profile'),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        children: [
                          const Text(
                            'Your profile',
                            style: TextStyle(
                              color: AppColors.ink,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _ProfileCard(
                            title: 'Account',
                            rows: [
                              ('Name', _value(_user['fullName'])),
                              ('Email', _value(_user['email'])),
                              ('Phone', _value(_user['phone'])),
                              ('Account ID', _value(_user['id'])),
                            ],
                            leading: CircleAvatar(
                              backgroundColor: AppColors.ink,
                              foregroundColor: AppColors.white,
                              child: Text(
                                name.isEmpty ? '—' : name[0].toUpperCase(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _ProfileCard(
                            title: 'Driver status',
                            rows: [
                              (
                                'Availability',
                                _status['online'] == true
                                    ? 'Online'
                                    : 'Offline',
                              ),
                              (
                                'Can accept trips',
                                _status['canGoOnline'] == true ? 'Yes' : 'No',
                              ),
                            ],
                            leading: const Icon(Icons.badge_outlined),
                          ),
                          const SizedBox(height: 14),
                          _ProfileCard(
                            title: 'Active vehicle',
                            rows: vehicle == null
                                ? [('Vehicle', 'No active vehicle')]
                                : [
                                    (
                                      'Plate number',
                                      _value(vehicle['plateNumber']),
                                    ),
                                    ('Make and model', _vehicleName(vehicle)),
                                    ('Color', _value(vehicle['color'])),
                                    (
                                      'Vehicle type ID',
                                      _value(vehicle['vehicleTypeId']),
                                    ),
                                  ],
                            leading: const Icon(Icons.local_shipping_outlined),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                          const SizedBox(height: 24),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _logout,
                            icon: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.logout),
                            label: Text(_busy ? 'Logging out…' : 'Log out'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              minimumSize: const Size.fromHeight(50),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.title,
    required this.rows,
    required this.leading,
  });

  final String title;
  final List<(String, String)> rows;
  final Widget leading;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
