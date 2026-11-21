class WalletPendingTopups {
  const WalletPendingTopups({required this.count, required this.amount});

  final int count;
  final String amount;

  factory WalletPendingTopups.fromJson(Map<String, dynamic> json) =>
      WalletPendingTopups(
        count: (json['count'] as num?)?.toInt() ?? 0,
        amount: json['amount']?.toString() ?? '0.00',
      );
}

class WalletPendingWithdrawal {
  const WalletPendingWithdrawal({required this.amount});

  final String amount;

  factory WalletPendingWithdrawal.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return WalletPendingWithdrawal(amount: json['amount']?.toString() ?? '0.00');
    }
    if (json is Map) {
      return WalletPendingWithdrawal(
        amount: Map<String, dynamic>.from(json)['amount']?.toString() ?? '0.00',
      );
    }
    return const WalletPendingWithdrawal(amount: '0.00');
  }
}

class Wallet {
  const Wallet({
    required this.balance,
    required this.available,
    required this.pendingTopups,
    this.pendingWithdrawal,
    this.defaultPaymentMethod,
  });

  final String balance;
  final String available;
  final WalletPendingTopups pendingTopups;
  final WalletPendingWithdrawal? pendingWithdrawal;
  final String? defaultPaymentMethod;

  bool get isNegative => (double.tryParse(balance) ?? 0) < 0;

  factory Wallet.fromJson(Map<String, dynamic> json) {
    final pendingWithdrawalJson = json['pendingWithdrawal'];
    return Wallet(
      balance: json['balance']?.toString() ?? '0.00',
      available: json['available']?.toString() ?? json['balance']?.toString() ?? '0.00',
      pendingTopups: json['pendingTopups'] is Map
          ? WalletPendingTopups.fromJson(
              Map<String, dynamic>.from(json['pendingTopups'] as Map),
            )
          : const WalletPendingTopups(count: 0, amount: '0.00'),
      pendingWithdrawal: pendingWithdrawalJson == null
          ? null
          : WalletPendingWithdrawal.fromJson(pendingWithdrawalJson),
      defaultPaymentMethod: json['defaultPaymentMethod']?.toString(),
    );
  }
}

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    this.balanceAfter,
    this.shipmentId,
    this.topupId,
    this.withdrawalId,
    this.note,
    this.createdAt,
  });

  final String id;
  final String type;
  final String amount;
  final String? balanceAfter;
  final String? shipmentId;
  final String? topupId;
  final String? withdrawalId;
  final String? note;
  final DateTime? createdAt;

  bool get isPositive => (double.tryParse(amount) ?? 0) >= 0;

  factory WalletTransaction.fromJson(Map<String, dynamic> json) =>
      WalletTransaction(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        amount: json['amount']?.toString() ?? '0.00',
        balanceAfter: json['balanceAfter']?.toString(),
        shipmentId: json['shipmentId']?.toString(),
        topupId: json['topupId']?.toString(),
        withdrawalId: json['withdrawalId']?.toString(),
        note: json['note']?.toString(),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      );
}

class WalletPageData {
  const WalletPageData({
    required this.items,
    required this.page,
    required this.hasMore,
  });

  final List<WalletTransaction> items;
  final int page;
  final bool hasMore;

  factory WalletPageData.fromJson(Map<String, dynamic> json, List<WalletTransaction> items) =>
      WalletPageData(
        items: items,
        page: (json['page'] as num?)?.toInt() ?? 1,
        hasMore: json['hasMore'] == true,
      );
}

class WalletTopup {
  const WalletTopup({
    required this.id,
    required this.amount,
    required this.status,
    this.reference,
    this.rejectionReason,
    this.proofUrl,
    this.createdAt,
    this.reviewedAt,
  });

  final String id;
  final String amount;
  final String status;
  final String? reference;
  final String? rejectionReason;
  final String? proofUrl;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  factory WalletTopup.fromJson(Map<String, dynamic> json) => WalletTopup(
        id: json['id']?.toString() ?? '',
        amount: json['amount']?.toString() ?? '0.00',
        status: json['status']?.toString() ?? '',
        reference: json['reference']?.toString(),
        rejectionReason: json['rejectionReason']?.toString(),
        proofUrl: json['proofUrl']?.toString(),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
        reviewedAt: DateTime.tryParse(json['reviewedAt']?.toString() ?? ''),
      );
}

class WalletWithdrawalAccount {
  const WalletWithdrawalAccount({
    this.method,
    this.holderName,
    this.bankName,
    this.accountLast4,
  });

  final String? method;
  final String? holderName;
  final String? bankName;
  final String? accountLast4;

  factory WalletWithdrawalAccount.fromJson(dynamic json) {
    if (json is! Map) return const WalletWithdrawalAccount();
    final map = Map<String, dynamic>.from(json);
    return WalletWithdrawalAccount(
      method: map['method']?.toString(),
      holderName: map['holderName']?.toString(),
      bankName: map['bankName']?.toString(),
      accountLast4: map['accountLast4']?.toString(),
    );
  }
}

class WalletWithdrawal {
  const WalletWithdrawal({
    required this.id,
    required this.amount,
    required this.status,
    this.reference,
    this.rejectionReason,
    this.account,
    this.createdAt,
    this.processedAt,
  });

  final String id;
  final String amount;
  final String status;
  final String? reference;
  final String? rejectionReason;
  final WalletWithdrawalAccount? account;
  final DateTime? createdAt;
  final DateTime? processedAt;

  factory WalletWithdrawal.fromJson(Map<String, dynamic> json) =>
      WalletWithdrawal(
        id: json['id']?.toString() ?? '',
        amount: json['amount']?.toString() ?? '0.00',
        status: json['status']?.toString() ?? '',
        reference: json['reference']?.toString(),
        rejectionReason: json['rejectionReason']?.toString(),
        account: json['account'] == null
            ? null
            : WalletWithdrawalAccount.fromJson(json['account']),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
        processedAt: DateTime.tryParse(json['processedAt']?.toString() ?? ''),
      );
}
