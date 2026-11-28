import 'package:flutter/material.dart';
import 'package:main/components/app_page_header.dart';
import 'package:main/components/main_button.dart';
import 'package:main/models/wallet.dart';
import 'package:main/pages/add_money_page.dart';
import 'package:main/pages/payment_methods_page.dart';
import 'package:main/pages/wallet_transactions_page.dart';
import 'package:main/pages/payout_account_page.dart';
import 'package:main/pages/top_up_history_page.dart';
import 'package:main/pages/wallet_withdrawals_page.dart';
import 'package:main/pages/withdraw_balance_page.dart';
import 'package:main/services/wallet_service.dart';
import 'package:main/theme/app_theme.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final _service = WalletService();
  bool _isLoading = true;
  String? _error;
  Wallet? _wallet;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final wallet = await _service.getWallet();
      if (!mounted) return;
      setState(() => _wallet = wallet);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = WalletService.readableError(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        children: [
          const AppPageHeader(title: 'Wallet'),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.accent))
          else ...[
            _WalletBalanceCard(wallet: _wallet!),
            const SizedBox(height: 16),
            if (_wallet!.isNegative) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF2EF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent),
                ),
                child: Text(
                  'You owe ${_wallet!.balance} EGP. Top up your wallet before creating another shipment.',
                  style: AppTypography.bodySm,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: MainButton(
                    text: 'Add money',
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AddMoneyPage(onSubmitted: () => _load()),
                        ),
                      );
                      if (mounted) _load();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: WaslaButton(
                    text: 'Withdraw balance',
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const WithdrawBalancePage(),
                        ),
                      );
                      if (mounted) _load();
                    },
                    variant: WaslaButtonVariant.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const WalletTransactionsPage()),
                );
                if (mounted) _load();
              },
              child: const Text('View transactions'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PaymentMethodsPage()),
                );
                if (mounted) _load();
              },
              child: const Text('Payment methods'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const WalletTopUpsPage()),
                );
                if (mounted) _load();
              },
              child: const Text('Top-up history'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const WalletWithdrawalsPage()),
                );
                if (mounted) _load();
              },
              child: const Text('Withdrawal history'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PayoutAccountPage()),
                );
                if (mounted) _load();
              },
              child: const Text('Payout account'),
            ),
            const SizedBox(height: 24),
            if (_wallet!.pendingTopups.count > 0) ...[
              Text('Pending top-ups', style: AppTypography.headingSm),
              const SizedBox(height: 8),
              Text(
                '${_wallet!.pendingTopups.count} request(s) awaiting confirmation: ${_wallet!.pendingTopups.amount} EGP',
                style: AppTypography.bodyMd,
              ),
              const SizedBox(height: 16),
            ],
            if (_wallet!.pendingWithdrawal != null) ...[
              Text('Pending withdrawal', style: AppTypography.headingSm),
              const SizedBox(height: 8),
              Text(
                'Reserved: ${_wallet!.pendingWithdrawal!.amount} EGP. Available: ${_wallet!.available} EGP.',
                style: AppTypography.bodyMd,
              ),
            ],
          ],
        ],
      ),
      ),
    );
  }
}

class _WalletBalanceCard extends StatelessWidget {
  const _WalletBalanceCard({required this.wallet});

  final Wallet wallet;

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
          Text(
            'Available balance',
            style: AppTypography.bodySm.copyWith(color: AppColors.white),
          ),
          const SizedBox(height: 8),
          Text(
            '${wallet.available} EGP',
            style: AppTypography.headingSm.copyWith(color: AppColors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Balance: ${wallet.balance} EGP',
            style: AppTypography.bodyXs.copyWith(color: AppColors.white.withValues(alpha: 0.78)),
          ),
          const SizedBox(height: 4),
          Text(
            'Top-up method: InstaPay',
            style: AppTypography.bodyXs.copyWith(color: AppColors.white.withValues(alpha: 0.78)),
          ),
          const SizedBox(height: 4),
          Text(
            'Default payment method: ${wallet.defaultPaymentMethod ?? 'cash'}',
            style: AppTypography.bodyXs.copyWith(color: AppColors.white.withValues(alpha: 0.78)),
          ),
        ],
      ),
    );
  }
}
