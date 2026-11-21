import 'package:flutter/material.dart';
import 'package:main/components/app_page_header.dart';
import 'package:main/models/wallet.dart';
import 'package:main/services/wallet_service.dart';
import 'package:main/theme/app_theme.dart';

class WalletTransactionsPage extends StatefulWidget {
  const WalletTransactionsPage({super.key});

  @override
  State<WalletTransactionsPage> createState() => _WalletTransactionsPageState();
}

class _WalletTransactionsPageState extends State<WalletTransactionsPage> {
  final _service = WalletService();
  final List<WalletTransaction> _items = [];
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  String? _error;
  int _selectedTab = 0;

  final List<String> _tabs = const [
    'All',
    'Top-ups',
    'Shipment payments',
    'Refunds',
    'Cancellation fees',
    'Withdrawals',
    'Other adjustments',
  ];

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
      final result = await _service.getTransactions(page: _page);
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

  bool _matchesTab(WalletTransaction item) {
    switch (_selectedTab) {
      case 1:
        return item.type == 'top_up';
      case 2:
        return item.type == 'trip_payment';
      case 3:
        return item.type == 'refund';
      case 4:
        return item.type == 'cancellation_fee' || item.type == 'recipient_refused_charge';
      case 5:
        return item.type == 'withdrawal';
      case 6:
        return item.type == 'manual_adjustment';
      default:
        return true;
    }
  }

  String _typeLabel(String type) => switch (type) {
        'top_up' => 'Top-up',
        'trip_payment' => 'Shipment payment',
        'refund' => 'Refund',
        'cancellation_fee' => 'Cancellation fee',
        'recipient_refused_charge' => 'Recipient refused charge',
        'withdrawal' => 'Withdrawal',
        'manual_adjustment' => 'Manual adjustment',
        _ => type,
      };

  @override
  Widget build(BuildContext context) {
    final visible = _items.where(_matchesTab).toList();
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: AppPageHeader(title: 'Transactions'),
          ),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => ChoiceChip(
                label: Text(_tabs[index]),
                selected: _selectedTab == index,
                onSelected: (_) => setState(() => _selectedTab = index),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: AppColors.accent)),
                if (visible.isEmpty && !_isLoading)
                  const Text('No transactions found.'),
                for (final item in visible) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_typeLabel(item.type)),
                    subtitle: Text(
                      [
                        if (item.shipmentId != null) 'Shipment ${item.shipmentId}',
                        if (item.createdAt != null) item.createdAt!.toLocal().toString(),
                      ].join(' · '),
                    ),
                    trailing: Text(
                      item.amount,
                      style: TextStyle(
                        color: item.isPositive ? Colors.green : AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
    );
  }
}
