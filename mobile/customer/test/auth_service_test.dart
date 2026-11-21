import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:main/services/auth_service.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    AuthService.replaceHttpClientForTesting(http.Client());
  });

  test('login persists access and refresh tokens', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/auth/login');
        return http.Response(
          jsonEncode({
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
            'expiresIn': 900,
            'user': {'id': '12', 'fullName': 'Customer'},
          }),
          200,
        );
      }),
    );

    final result = await AuthService.login(
      email: 'customer@example.com',
      password: 'Password1',
    );

    expect(result.success, isTrue);
    expect(result.session?.token, 'access-1');
    expect(result.session?.refreshToken, 'refresh-1');

    final storage = const FlutterSecureStorage();
    expect(await storage.read(key: 'wasla_auth_token'), 'access-1');
    expect(await storage.read(key: 'wasla_refresh_token'), 'refresh-1');
    expect(await storage.read(key: 'wasla_token_expiry'), isNotNull);
  });

  test('registration persists access and refresh tokens', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/auth/register');
        return http.Response(
          jsonEncode({
            'accessToken': 'access-register',
            'refreshToken': 'refresh-register',
            'expiresIn': 900,
            'user': {'id': '13', 'fullName': 'New Customer'},
          }),
          200,
        );
      }),
    );

    final result = await AuthService.register(
      fullName: 'New Customer',
      email: 'new@example.com',
      phone: '+201000000000',
      password: 'Password1',
    );

    expect(result.success, isTrue);
    final storage = const FlutterSecureStorage();
    expect(await storage.read(key: 'wasla_auth_token'), 'access-register');
    expect(await storage.read(key: 'wasla_refresh_token'), 'refresh-register');
  });

  test('refresh rotates tokens and retries the original request', () async {
    const FlutterSecureStorage storage = FlutterSecureStorage();
    await storage.write(key: 'wasla_auth_token', value: 'expired-access');
    await storage.write(key: 'wasla_refresh_token', value: 'old-refresh');
    await storage.write(
      key: 'wasla_token_expiry',
      value: DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch
          .toString(),
    );

    var protectedCalls = 0;
    var refreshCalls = 0;
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          refreshCalls++;
          return http.Response(
            jsonEncode({
              'accessToken': 'new-access',
              'refreshToken': 'new-refresh',
              'expiresIn': 900,
            }),
            200,
          );
        }
        protectedCalls++;
        if (protectedCalls == 1) {
          return http.Response(
            jsonEncode({
              'error': {'code': 'TOKEN_EXPIRED', 'message': 'expired'},
            }),
            401,
          );
        }
        expect(request.headers['Authorization'], 'Bearer new-access');
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    );

    final result = await AuthService.apiRequest(
      method: 'GET',
      endpoint: '/protected',
    );

    expect(result['ok'], isTrue);
    expect(protectedCalls, 2);
    expect(refreshCalls, 1);
    expect(await storage.read(key: 'wasla_auth_token'), 'new-access');
    expect(await storage.read(key: 'wasla_refresh_token'), 'new-refresh');
  });

  test('simultaneous expired requests share one refresh operation', () async {
    const FlutterSecureStorage storage = FlutterSecureStorage();
    await storage.write(key: 'wasla_auth_token', value: 'expired-access');
    await storage.write(key: 'wasla_refresh_token', value: 'old-refresh');

    var refreshCalls = 0;
    var protectedCalls = 0;
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          refreshCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response(
            jsonEncode({
              'accessToken': 'shared-access',
              'refreshToken': 'shared-refresh',
              'expiresIn': 900,
            }),
            200,
          );
        }
        protectedCalls++;
        if (protectedCalls <= 2) {
          return http.Response(
            jsonEncode({
              'error': {'code': 'TOKEN_EXPIRED', 'message': 'expired'},
            }),
            401,
          );
        }
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    );

    final results = await Future.wait([
      AuthService.apiRequest(method: 'GET', endpoint: '/first'),
      AuthService.apiRequest(method: 'GET', endpoint: '/second'),
    ]);

    expect(results.every((result) => result['ok'] == true), isTrue);
    expect(refreshCalls, 1);
  });

  test('SESSION_ENDED clears the stored session', () async {
    const FlutterSecureStorage storage = FlutterSecureStorage();
    await storage.write(key: 'wasla_auth_token', value: 'expired-access');
    await storage.write(key: 'wasla_refresh_token', value: 'old-refresh');

    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          return http.Response(
            jsonEncode({
              'error': {'code': 'SESSION_ENDED', 'message': 'ended'},
            }),
            401,
          );
        }
        return http.Response(
          jsonEncode({
            'error': {'code': 'TOKEN_EXPIRED', 'message': 'expired'},
          }),
          401,
        );
      }),
    );

    await expectLater(
      AuthService.apiRequest(method: 'GET', endpoint: '/protected'),
      throwsA(
        isA<AuthenticatedApiException>().having(
          (error) => error.code,
          'code',
          'SESSION_ENDED',
        ),
      ),
    );

    expect(await storage.read(key: 'wasla_auth_token'), isNull);
    expect(await storage.read(key: 'wasla_refresh_token'), isNull);
  });

  test('refresh network failure does not clear a valid session', () async {
    const FlutterSecureStorage storage = FlutterSecureStorage();
    await storage.write(key: 'wasla_auth_token', value: 'expired-access');
    await storage.write(key: 'wasla_refresh_token', value: 'old-refresh');

    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          throw http.ClientException('offline');
        }
        return http.Response(
          jsonEncode({
            'error': {'code': 'TOKEN_EXPIRED', 'message': 'expired'},
          }),
          401,
        );
      }),
    );

    await expectLater(
      AuthService.apiRequest(method: 'GET', endpoint: '/protected'),
      throwsA(isA<AuthenticatedApiException>()),
    );

    expect(await storage.read(key: 'wasla_auth_token'), 'expired-access');
    expect(await storage.read(key: 'wasla_refresh_token'), 'old-refresh');
  });

  test('hasValidSession refreshes an expired session', () async {
    const FlutterSecureStorage storage = FlutterSecureStorage();
    await storage.write(key: 'wasla_auth_token', value: 'expired-access');
    await storage.write(key: 'wasla_refresh_token', value: 'old-refresh');
    await storage.write(
      key: 'wasla_token_expiry',
      value: DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch
          .toString(),
    );

    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/auth/refresh');
        return http.Response(
          jsonEncode({
            'accessToken': 'fresh-access',
            'refreshToken': 'fresh-refresh',
            'expiresIn': 900,
          }),
          200,
        );
      }),
    );

    expect(await AuthService.hasValidSession(), isTrue);
    expect(await storage.read(key: 'wasla_auth_token'), 'fresh-access');
  });

  test('logout sends the refresh token and clears local data', () async {
    const FlutterSecureStorage storage = FlutterSecureStorage();
    await storage.write(key: 'wasla_auth_token', value: 'access-1');
    await storage.write(key: 'wasla_refresh_token', value: 'refresh-1');

    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/auth/logout');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['refreshToken'], 'refresh-1');
        return http.Response('', 204);
      }),
    );

    final result = await AuthService.logout();

    expect(result.success, isTrue);
    expect(await storage.read(key: 'wasla_auth_token'), isNull);
    expect(await storage.read(key: 'wasla_refresh_token'), isNull);
  });

  test('logout clears local data when the network request fails', () async {
    const FlutterSecureStorage storage = FlutterSecureStorage();
    await storage.write(key: 'wasla_auth_token', value: 'access-1');
    await storage.write(key: 'wasla_refresh_token', value: 'refresh-1');

    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        throw http.ClientException('offline');
      }),
    );

    await AuthService.logout();

    expect(await storage.read(key: 'wasla_auth_token'), isNull);
    expect(await storage.read(key: 'wasla_refresh_token'), isNull);
  });
}
