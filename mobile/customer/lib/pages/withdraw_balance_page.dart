import 'package:flutter/material.dart';
import 'package:main/components/app_page_header.dart';
import 'package:main/models/wallet.dart';
import 'package:main/services/wallet_service.dart';
import 'package:main/theme/app_theme.dart';

class WithdrawBalancePage extends StatefulWidget {
  const WithdrawBalancePage({super.key});

  @override
  State<WithdrawBalancePage> createState() => _WithdrawBalancePageState();
}

class _WithdrawBalancePageState extends State<WithdrawBalancePage> {
  final _service = WalletService();
  final _amountController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  Wallet? _wallet;
  ({List<WalletWithdrawal> items, bool hasMore}) _withdrawals = (
    items: const <WalletWithdrawal>[],
    hasMore: false,
  );
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final wallet = await _service.getWallet();
      final result = await _service.getWithdrawals(page: 1);
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _withdrawals = result;
      });
    } catch (error) {
      if (mounted) setState(() => _error = WalletService.readableError(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    final available = double.tryParse(_wallet!.available.toString()) ?? 0;
    if (amount == null || amount <= 0 || amount > available) {
      setState(() => _error = 'Enter an amount up to $available.');
      return;
    }
    final account = await _service.getPayoutAccount();
    if (!mounted) return;
    if (account?.status == 'pending' || account?.status == 'rejected') {
      setState(() {
        _error = 'Your payout account must be approved before withdrawing.';
      });
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await _service.createWithdrawal(amount: amount.toStringAsFixed(2));
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = WalletService.readableError(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _cancel(String id) async {
    try {
      await _service.cancelWithdrawal(id);
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = WalletService.readableError(error));
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
          const AppPageHeader(title: 'Withdraw balance'),
          const SizedBox(height: 18),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.accent))
          else ...[
            Text('Available balance: ${_wallet?.available ?? '0.00'} EGP', style: AppTypography.bodyMd),
            const SizedBox(height: 8),
            Text(
              'Withdrawals are processed by the admin after payout account approval.',
              style: AppTypography.bodySm,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              child: Text(_isSubmitting ? 'Submitting...' : 'Request withdrawal'),
            ),
            const SizedBox(height: 24),
            Text('Withdrawal history', style: AppTypography.headingSm),
            const SizedBox(height: 8),
            for (final item in _withdrawals.items) ...[
              ListTile(
                title: Text('${item.amount} EGP'),
                subtitle: Text(item.status),
                trailing: item.status == 'requested'
                    ? TextButton(
                        onPressed: () => _cancel(item.id),
                        child: const Text('Cancel'),
                      )
                    : null,
              ),
            ],
          ],
        ],
      ),
    ),
  );
}
}
