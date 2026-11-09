import 'package:flutter/material.dart';
import 'package:main/components/app_page_header.dart';
import 'package:main/theme/app_theme.dart';

class WalletPage extends StatelessWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        children: [
          const AppPageHeader(title: 'Wallet'),
          const SizedBox(height: 24),
          const _WalletBalanceCard(),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Transaction history',
                  style: AppTypography.headingSm,
                ),
              ),
              Icon(
                Icons.receipt_long_outlined,
                color: AppColors.darkGreen,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _EmptyTransactionsState(),
        ],
      ),
    );
  }
}

class _WalletBalanceCard extends StatelessWidget {
  const _WalletBalanceCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.darkGreen,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: AppColors.white,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Available balance',
                style: AppTypography.bodySm.copyWith(color: AppColors.white),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Unavailable',
            style: AppTypography.headingSm.copyWith(color: AppColors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Wallet balance is not provided by the current service.',
            style: AppTypography.bodyXs.copyWith(
              color: AppColors.white.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTransactionsState extends StatelessWidget {
  const _EmptyTransactionsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            color: AppColors.gray,
            size: 34,
          ),
          const SizedBox(height: 12),
          Text('No transactions yet', style: AppTypography.bodyMd),
          const SizedBox(height: 6),
          Text(
            'Your deposits, payments, and refunds will appear here.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyXs.copyWith(color: AppColors.gray),
          ),
        ],
      ),
    );
  }
}
