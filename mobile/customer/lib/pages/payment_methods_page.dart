import 'package:flutter/material.dart';
import 'package:main/components/app_page_header.dart';
import 'package:main/models/wallet.dart';
import 'package:main/services/wallet_service.dart';
import 'package:main/theme/app_theme.dart';

class PaymentMethodsPage extends StatefulWidget {
  const PaymentMethodsPage({super.key});

  @override
  State<PaymentMethodsPage> createState() => _PaymentMethodsPageState();
}

class _PaymentMethodsPageState extends State<PaymentMethodsPage> {
  final _service = WalletService();
  bool _isLoading = true;
  String? _error;
  String? _selectedMethod;
  Wallet? _wallet;
  bool _isSaving = false;

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
      setState(() {
        _wallet = wallet;
        _selectedMethod = wallet.defaultPaymentMethod;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = WalletService.readableError(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _select(String? method) async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final wallet = await _service.setPaymentMethod(method);
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _selectedMethod = wallet.defaultPaymentMethod;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = WalletService.readableError(error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        children: [
          const AppPageHeader(title: 'Payment Methods'),
          const SizedBox(height: 18),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else ...[
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: AppColors.accent)),
              const SizedBox(height: 12),
            ],
            _NegativeBalanceWarning(wallet: _wallet),
            const SizedBox(height: 12),
            _PaymentMethodCard(
              title: 'Wallet',
              subtitle: 'Pay from your Wasla wallet',
              selected: _selectedMethod == 'wallet',
              enabled: !_isSaving,
              onTap: () => _select('wallet'),
            ),
            const SizedBox(height: 10),
            _PaymentMethodCard(
              title: 'Cash',
              subtitle: 'Pay the driver directly',
              selected: _selectedMethod == 'cash',
              enabled: !_isSaving,
              onTap: () => _select('cash'),
            ),
            const SizedBox(height: 10),
            _PaymentMethodCard(
              title: 'No default',
              subtitle: 'Choose a method for each shipment',
              selected: _selectedMethod == null,
              enabled: !_isSaving,
              onTap: () => _select(null),
            ),
          ],
        ],
      ),
    );
  }
}

class _NegativeBalanceWarning extends StatelessWidget {
  const _NegativeBalanceWarning({this.wallet});

  final Wallet? wallet;

  @override
  Widget build(BuildContext context) {
    if (wallet == null || !wallet!.isNegative) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2EF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent),
      ),
      child: Text(
        'You owe ${wallet!.balance} EGP. Top up your wallet before requesting another shipment.',
        style: AppTypography.bodySm,
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF2EF) : AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.borderLight,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600)),
                  Text(subtitle, style: AppTypography.bodyXs),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? AppColors.accent : AppColors.gray,
            ),
          ],
        ),
      ),
    );
  }
}
