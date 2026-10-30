import 'package:driver/components/driver_components.dart';
import 'package:driver/screens/driver_application_screen.dart';
import 'package:driver/screens/driver_home_screen.dart';
import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

enum VerificationStatus { pending, approved, rejected }

class VerificationScreen extends StatelessWidget {
  const VerificationScreen({super.key, required this.status});

  final VerificationStatus status;

  String get _title => switch (status) {
    VerificationStatus.pending => 'Your checks are underway',
    VerificationStatus.approved => 'You’re ready to move',
    VerificationStatus.rejected => 'Let’s fix one document',
  };

  String get _description => switch (status) {
    VerificationStatus.pending =>
      'We’re reviewing your documents. Most reviews are completed within 24 hours. We’ll notify you when you can go online.',
    VerificationStatus.approved =>
      'Your identity, license and vehicle are verified. Go online when you are ready for a request.',
    VerificationStatus.rejected =>
      'The expiry date on your driving license is not readable. Take a new photo with all four corners visible.',
  };

  String get _primaryAction => switch (status) {
    VerificationStatus.pending => 'View submitted documents',
    VerificationStatus.approved => 'Go to driver home',
    VerificationStatus.rejected => 'Resubmit driving license',
  };

  Color get _statusColor => switch (status) {
    VerificationStatus.pending => AppColors.accent,
    VerificationStatus.approved => const Color(0xFF24804A),
    VerificationStatus.rejected => AppColors.accent,
  };

  IconData get _statusIcon => switch (status) {
    VerificationStatus.pending => Icons.schedule_outlined,
    VerificationStatus.approved => Icons.verified_outlined,
    VerificationStatus.rejected => Icons.error_outline,
  };

  String get _statusLabel => switch (status) {
    VerificationStatus.pending => 'Pending',
    VerificationStatus.approved => 'Approved',
    VerificationStatus.rejected => 'Rejected',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const DriverPageHeader(label: 'Driver verification'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 27,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Icon(_statusIcon, color: _statusColor, size: 52),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_statusIcon, color: _statusColor, size: 15),
                          const SizedBox(width: 6),
                          Text(
                            _statusLabel,
                            style: TextStyle(
                              color: _statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _description,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _DocumentStatusPanel(status: status),
                    const SizedBox(height: 16),
                    const _ApplicationDetailsPanel(),
                    const SizedBox(height: 16),
                    const Text(
                      'Your other documents and payment information stay saved.',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    if (status == VerificationStatus.pending) ...[
                      const SizedBox(height: 14),
                      const NoticePanel(
                        text:
                            'Preview only · Your documents have not been uploaded or submitted.',
                        icon: Icons.info_outline,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: PrimaryButton(
                  label: _primaryAction,
                  onPressed: () => _handleAction(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleAction(BuildContext context) {
    switch (status) {
      case VerificationStatus.pending:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const DriverApplicationScreen(initialStep: 6),
          ),
        );
        break;
      case VerificationStatus.approved:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const DriverHomeScreen()),
        );
        break;
      case VerificationStatus.rejected:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const DriverApplicationScreen(initialStep: 2),
          ),
        );
        break;
    }
  }
}

class _DocumentStatusPanel extends StatelessWidget {
  const _DocumentStatusPanel({required this.status});

  final VerificationStatus status;

  @override
  Widget build(BuildContext context) {
    final licenseStatus = switch (status) {
      VerificationStatus.pending => 'Under review',
      VerificationStatus.approved => 'Verified',
      VerificationStatus.rejected => 'Needs new photo',
    };
    final vehicleStatus = status == VerificationStatus.approved
        ? 'Verified'
        : 'Under review';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          SummaryRow(
            icon: Icons.badge_outlined,
            label: 'National ID',
            value: 'Verified',
          ),
          SummaryRow(
            icon: Icons.badge_outlined,
            label: 'Driving license',
            value: licenseStatus,
          ),
          SummaryRow(
            icon: Icons.description_outlined,
            label: 'Vehicle registration',
            value: status == VerificationStatus.approved
                ? 'Verified'
                : 'Under review',
          ),
          SummaryRow(
            icon: Icons.account_balance_outlined,
            label: 'Payment details',
            value: 'Saved',
          ),
          if (status == VerificationStatus.rejected)
            SummaryRow(
              icon: Icons.info_outline,
              label: 'Vehicle photos',
              value: vehicleStatus,
            ),
        ],
      ),
    );
  }
}

class _ApplicationDetailsPanel extends StatelessWidget {
  const _ApplicationDetailsPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          SummaryRow(
            icon: Icons.confirmation_number_outlined,
            label: 'Application',
            value: 'DRV-1042',
          ),
          SummaryRow(
            icon: Icons.schedule,
            label: 'Submitted',
            value: '17 Oct · 16:20',
          ),
        ],
      ),
    );
  }
}
