import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:main/pages/withdraw_balance_page.dart';
import 'package:main/services/auth_service.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'wasla_auth_token': 'test-token'});
    AuthService.replaceHttpClientForTesting(
      http_testing.MockClient((request) async {
        if (request.url.path.endsWith('/me/wallet')) {
          return http.Response(
            jsonEncode({
              'wallet': {
                'balance': '370.00',
                'available': '370.00',
                'pendingTopups': {'count': 0, 'amount': '0.00'},
                'pendingWithdrawal': null,
                'defaultPaymentMethod': 'wallet',
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/me/wallet/withdrawals')) {
          return http.Response(
            jsonEncode({'withdrawals': [], 'page': 1, 'hasMore': false}),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
  });

  testWidgets('WithdrawBalancePage builds its TextField without a missing Material ancestor', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WithdrawBalancePage()));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
