import 'package:main/models/wallet.dart';
import 'package:main/services/auth_service.dart';

class WalletService {
  static String readableError(Object error) {
    if (error is AuthenticatedApiException) {
      switch (error.code) {
        case 'INVALID_INPUT':
          final min = error.details?['min']?.toString();
          final max = error.details?['max']?.toString();
          if (min != null && max != null) {
            return 'Enter an amount between $min and $max.';
          }
          return error.message.isNotEmpty
              ? error.message
              : 'The submitted information is invalid.';
        case 'TOO_MANY_PENDING':
          return 'You already have 3 pending top-up requests.';
        case 'TRANSFER_USED':
          return 'This transfer number has already been used.';
        case 'UNSUPPORTED_IMAGE':
          return 'Unsupported image format. Use JPEG, PNG, or WebP.';
        case 'INVALID_IMAGE':
          return 'The receipt image is invalid.';
        case 'STORAGE_FAILED':
          return 'The receipt could not be stored. Please try again.';
        case 'PAYOUT_ACCOUNT_REQUIRED':
          return 'An approved payout account is required before withdrawing.';
        case 'WITHDRAWAL_PENDING':
          return 'You already have a pending withdrawal request.';
        case 'ALREADY_REVIEWED':
          return 'This withdrawal request has already been reviewed.';
        case 'NOT_FOUND':
          return 'The requested item was not found.';
      }
      if (error.message.trim().isNotEmpty) return error.message;
    }
    return error.toString();
  }
  Future<Wallet> getWallet() async {
    final response = await AuthService.apiRequest(
      method: 'GET',
      endpoint: '/me/wallet',
    );
    final wallet = response['wallet'];
    if (wallet is Map) {
      return Wallet.fromJson(Map<String, dynamic>.from(wallet));
    }
    throw Exception('Wallet response is invalid.');
  }

  Future<Wallet> setPaymentMethod(String? method) async {
    final response = await AuthService.apiRequest(
      method: 'PUT',
      endpoint: '/me/wallet/payment-method',
      body: {'method': method},
    );
    final wallet = response['wallet'];
    if (wallet is Map) {
      return Wallet.fromJson(Map<String, dynamic>.from(wallet));
    }
    return getWallet();
  }

  Future<({List<WalletTransaction> items, bool hasMore})> getTransactions({
    int page = 1,
  }) async {
    final response = await AuthService.apiRequest(
      method: 'GET',
      endpoint: '/me/wallet/transactions',
      query: {'page': '$page'},
    );
    final items = response['transactions'];
    final list = items is List
        ? items
            .whereType<Map>()
            .map((item) => WalletTransaction.fromJson(Map<String, dynamic>.from(item)))
            .toList()
        : <WalletTransaction>[];
    return (items: list, hasMore: response['hasMore'] == true);
  }

  Future<List<WalletTopup>> getTopups({int page = 1}) async {
    final response = await AuthService.apiRequest(
      method: 'GET',
      endpoint: '/me/wallet/topups',
      query: {'page': '$page'},
    );
    final items = response['topups'];
    if (items is List) {
      return items
          .whereType<Map>()
          .map((item) => WalletTopup.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }
    return const [];
  }

  Future<bool> hasMoreTopups(int page) async {
    final response = await AuthService.apiRequest(
      method: 'GET',
      endpoint: '/me/wallet/topups',
      query: {'page': '$page'},
    );
    return response['hasMore'] == true;
  }

  Future<WalletTopup> createTopup({
    required String amount,
    String? reference,
    required List<int> bytes,
    required String contentType,
  }) async {
    final query = <String, String>{'amount': amount};
    if (reference != null && reference.trim().isNotEmpty) {
      query['reference'] = reference.trim();
    }
    final response = await AuthService.apiRequest(
      method: 'POST',
      endpoint: '/me/wallet/topups',
      query: query,
      bytes: bytes,
      contentType: contentType,
    );
    final topup = response['topup'];
    if (topup is Map) {
      return WalletTopup.fromJson(Map<String, dynamic>.from(topup));
    }
    throw Exception('Top-up response is invalid.');
  }

  Future<List<WalletWithdrawal>> getWithdrawals({int page = 1}) async {
    final response = await AuthService.apiRequest(
      method: 'GET',
      endpoint: '/me/wallet/withdrawals',
      query: {'page': '$page'},
    );
    final items = response['withdrawals'];
    if (items is List) {
      return items
          .whereType<Map>()
          .map((item) => WalletWithdrawal.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }
    return const [];
  }

  Future<bool> hasMoreWithdrawals(int page) async {
    final response = await AuthService.apiRequest(
      method: 'GET',
      endpoint: '/me/wallet/withdrawals',
      query: {'page': '$page'},
    );
    return response['hasMore'] == true;
  }

  Future<WalletWithdrawal> createWithdrawal({required String amount}) async {
    final response = await AuthService.apiRequest(
      method: 'POST',
      endpoint: '/me/wallet/withdrawals',
      body: {'amount': amount},
    );
    final withdrawal = response['withdrawal'];
    if (withdrawal is Map) {
      return WalletWithdrawal.fromJson(Map<String, dynamic>.from(withdrawal));
    }
    throw Exception('Withdrawal response is invalid.');
  }

  Future<void> cancelWithdrawal(String id) async {
    await AuthService.apiRequest(
      method: 'POST',
      endpoint: '/me/wallet/withdrawals/$id/cancel',
    );
  }
}
