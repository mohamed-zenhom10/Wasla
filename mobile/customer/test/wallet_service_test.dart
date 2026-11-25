import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:main/services/auth_service.dart';
import 'package:main/services/wallet_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WalletService service;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'wasla_auth_token': 'customer-access',
      'wasla_refresh_token': 'customer-refresh',
      'wasla_token_expiry': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch.toString(),
    });
    AuthService.replaceHttpClientForTesting(http.Client());
    service = WalletService();
  });

  tearDown(() {
    AuthService.replaceHttpClientForTesting(http.Client());
  });

  test('parses the wallet response with negative balance and pending data', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/me/wallet');
        return http.Response(
          jsonEncode({
            'wallet': {
              'balance': '-50.00',
              'available': '-50.00',
              'pendingTopups': {'count': 1, 'amount': '500.00'},
              'pendingWithdrawal': {'amount': '20.00'},
              'defaultPaymentMethod': 'wallet',
            },
          }),
          200,
        );
      }),
    );

    final wallet = await service.getWallet();

    expect(wallet.balance, '-50.00');
    expect(wallet.available, '-50.00');
    expect(wallet.isNegative, isTrue);
    expect(wallet.pendingTopups.count, 1);
    expect(wallet.pendingTopups.amount, '500.00');
    expect(wallet.pendingWithdrawal?.amount, '20.00');
    expect(wallet.defaultPaymentMethod, 'wallet');
  });

  test('fetches payout account and saves a replacement payout account', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path == '/api/me/payout-account') {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'payoutAccount': {
                  'method': 'bank_account',
                  'holderName': 'Ahmed Hassan',
                  'bankName': 'National Bank of Egypt',
                  'accountLast4': '2631',
                  'status': 'pending',
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'payoutAccount': {
                'method': 'wallet',
                'holderName': 'Mona Ali',
                'bankName': 'Vodafone Cash',
                'accountLast4': '4567',
                'status': 'pending',
              },
            }),
            200,
          );
        }
        throw Exception('Unexpected request: ${request.url}');
      }),
    );

    final account = await service.getPayoutAccount();
    expect(account?.method, 'bank_account');
    expect(account?.accountLast4, '2631');
    expect(account?.status, 'pending');

    final saved = await service.savePayoutAccount(
      method: 'wallet',
      holderName: 'Mona Ali',
      bankName: 'Vodafone Cash',
      accountNumber: 'EG380019000500000000263180002',
    );
    expect(saved?.method, 'wallet');
    expect(saved?.accountLast4, '4567');
  });

  test('fetches paginated top-ups with hasMore', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/me/wallet/topups');
        expect(request.url.queryParameters['page'], '1');
        return http.Response(
          jsonEncode({
            'topups': [
              {
                'id': '8',
                'amount': '500.00',
                'status': 'awaiting_verification',
                'reference': '123456789012',
                'rejectionReason': null,
                'proofUrl': 'https://example.com/receipt.png',
                'createdAt': '2026-11-22T10:00:00Z',
                'reviewedAt': null,
              },
            ],
            'page': 1,
            'hasMore': true,
          }),
          200,
        );
      }),
    );

    final result = await service.getTopups(page: 1);
    expect(result.items.length, 1);
    expect(result.items.single.status, 'awaiting_verification');
    expect(result.hasMore, isTrue);

    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/me/wallet/topups');
        expect(request.url.queryParameters['page'], '2');
        return http.Response(
          jsonEncode({
            'topups': <dynamic>[],
            'page': 2,
            'hasMore': false,
          }),
          200,
        );
      }),
    );

    final second = await service.getTopups(page: 2);
    expect(second.items, isEmpty);
    expect(second.hasMore, isFalse);
  });

  test('fetches paginated withdrawals with hasMore', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/me/wallet/withdrawals');
        expect(request.url.queryParameters['page'], '1');
        return http.Response(
          jsonEncode({
            'withdrawals': [
              {
                'id': '3',
                'amount': '200.00',
                'status': 'requested',
                'reference': null,
                'rejectionReason': null,
                'account': {
                  'method': 'wallet',
                  'holderName': 'Mona Ali',
                  'bankName': 'Vodafone Cash',
                  'accountLast4': '4567',
                },
                'createdAt': '2026-11-22T10:00:00Z',
                'processedAt': null,
              },
            ],
            'page': 1,
            'hasMore': false,
          }),
          200,
        );
      }),
    );

    final result = await service.getWithdrawals(page: 1);
    expect(result.items.length, 1);
    expect(result.items.single.status, 'requested');
    expect(result.hasMore, isFalse);
  });

  test('hasUsableBalance is false for a negative wallet balance', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/me/wallet');
        return http.Response(
          jsonEncode({
            'wallet': {
              'balance': '-50.00',
              'available': '-50.00',
              'pendingTopups': {'count': 0, 'amount': '0.00'},
              'pendingWithdrawal': null,
              'defaultPaymentMethod': 'cash',
            },
          }),
          200,
        );
      }),
    );

    expect(await service.hasUsableBalance(), isFalse);
  });

  test('hasUsableBalance is true for a positive wallet balance', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/me/wallet');
        return http.Response(
          jsonEncode({
            'wallet': {
              'balance': '120.00',
              'available': '120.00',
              'pendingTopups': {'count': 0, 'amount': '0.00'},
              'pendingWithdrawal': null,
              'defaultPaymentMethod': 'cash',
            },
          }),
          200,
        );
      }),
    );

    expect(await service.hasUsableBalance(), isTrue);
  });
}
