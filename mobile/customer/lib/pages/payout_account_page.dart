import 'package:flutter/material.dart';
import 'package:main/components/app_page_header.dart';
import 'package:main/models/wallet.dart';
import 'package:main/services/wallet_service.dart';
import 'package:main/theme/app_theme.dart';

class PayoutAccountPage extends StatefulWidget {
  const PayoutAccountPage({super.key});

  @override
  State<PayoutAccountPage> createState() => _PayoutAccountPageState();
}

class _PayoutAccountPageState extends State<PayoutAccountPage> {
  final _service = WalletService();
  final _holderNameController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final TextEditingController _methodController = TextEditingController(text: 'bank_account');

  WalletPayoutAccount? _account;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  bool _isFormOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _holderNameController.dispose();
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _methodController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final account = await _service.getPayoutAccount();
      if (!mounted) return;
      setState(() => _account = account);
    } catch (error) {
      if (mounted) setState(() => _error = WalletService.readableError(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    final method = _methodController.text.trim();
    final holderName = _holderNameController.text.trim();
    final bankName = _bankNameController.text.trim();
    final accountNumber = _accountNumberController.text.trim();
    if (holderName.isEmpty) {
      setState(() => _error = 'Holder name is required.');
      return;
    }
    if (method == 'bank_account' && bankName.isEmpty) {
      setState(() => _error = 'Bank name is required for bank accounts.');
      return;
    }
    if (method == 'bank_account' && accountNumber.isEmpty) {
      setState(() => _error = 'Account number is required.');
      return;
    }
    if (method == 'wallet' && accountNumber.isEmpty) {
      setState(() => _error = 'Wallet account number is required.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final account = await _service.savePayoutAccount(
        method: method,
        holderName: holderName,
        bankName: bankName,
        accountNumber: accountNumber,
      );
      if (!mounted) return;
      setState(() {
        _account = account;
        _isFormOpen = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = WalletService.readableError(error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
            const AppPageHeader(title: 'Payout account'),
            const SizedBox(height: 18),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppColors.accent)),
                const SizedBox(height: 12),
              ],
              if (_account == null) ...[
                const Text('No payout account is saved yet.'),
                const SizedBox(height: 12),
              ] else ...[
                Text('Method: ${_account!.method}', style: AppTypography.bodyMd),
                Text(
                  'Holder: ${_account!.holderName}',
                  style: AppTypography.bodyMd,
                ),
                Text(
                  'Bank: ${_account!.bankName}',
                  style: AppTypography.bodyMd,
                ),
                Text(
                  'Account: ${_account!.accountLast4}',
                  style: AppTypography.bodyMd,
                ),
                if (_account!.status != null && _account!.status!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Status: ${_account!.status}', style: AppTypography.bodySm),
                ],
              ],
              const SizedBox(height: 16),
              if (_isFormOpen) ...[
                TextField(
                  controller: _methodController,
                  decoration: const InputDecoration(labelText: 'Method'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _holderNameController,
                  decoration: const InputDecoration(labelText: 'Holder name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bankNameController,
                  decoration: const InputDecoration(
                    labelText: 'Bank / wallet provider',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _accountNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Account number',
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _isSaving ? null : _submit,
                  child: Text(_isSaving ? 'Saving...' : 'Save payout account'),
                ),
              ],
              ElevatedButton(
                onPressed: () => setState(() => _isFormOpen = true),
                child: const Text('Add payout account'),
              ),
              const SizedBox(height: 12),
              Text(
                'A new or replaced payout account must be reviewed and approved by the admin before withdrawals are allowed.',
                style: AppTypography.bodySm,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
