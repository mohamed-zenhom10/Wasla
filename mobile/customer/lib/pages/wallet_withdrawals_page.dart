import 'package:flutter/material.dart';
import 'package:main/components/app_page_header.dart';
import 'package:main/models/wallet.dart';
import 'package:main/services/wallet_service.dart';
import 'package:main/theme/app_theme.dart';

class WalletWithdrawalsPage extends StatefulWidget {
  const WalletWithdrawalsPage({super.key});

  @override
  State<WalletWithdrawalsPage> createState() => _WalletWithdrawalsPageState();
}

class _WalletWithdrawalsPageState extends State<WalletWithdrawalsPage> {
  final _service = WalletService();
  final List<WalletWithdrawal> _items = [];
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _page = 1;
        _hasMore = true;
      }
    });
    try {
      final result = await _service.getWithdrawals(page: _page);
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _hasMore = result.hasMore;
        _page++;
      });
    } catch (error) {
      if (mounted) setState(() => _error = WalletService.readableError(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.darkGreen,
        elevation: 0,
        leading: BackButton(),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: const AppPageHeader(title: 'Withdrawal history'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: AppColors.accent)),
                  if (_items.isEmpty && !_isLoading)
                    const Text('No withdrawals found.'),
                  for (final item in _items) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${item.amount} EGP'),
                      subtitle: Text(item.status),
                      trailing: item.status == 'rejected'
                          ? Text(item.rejectionReason ?? '')
                          : null,
                    ),
                    const Divider(height: 1),
                  ],
                  if (_isLoading) const Center(child: CircularProgressIndicator()),
                  if (_hasMore && !_isLoading)
                    TextButton(
                      onPressed: () => _load(),
                      child: const Text('Load more'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
