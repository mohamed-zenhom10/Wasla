import 'dart:convert';

import 'package:driver/data/driver_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registration sends the driver role and policy choice', () async {
    SharedPreferences.setMockInitialValues({});
    final api = DriverApi(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/auth/register');
        expect(jsonDecode(request.body), {
          'fullName': 'Mona Adel',
          'email': 'mona@example.com',
          'phone': '+201001234567',
          'password': 'secret123',
          'role': 'driver',
          'language': 'ar',
          'acceptPolicies': true,
        });
        return http.Response('{}', 201);
      }),
    );

    await api.register(
      fullName: 'Mona Adel',
      email: 'mona@example.com',
      phone: '+201001234567',
      password: 'secret123',
      acceptPolicies: true,
    );
    api.close();
  });

  test('email verification does not save a non-driver session', () async {
    SharedPreferences.setMockInitialValues({});
    final api = DriverApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'accessToken': 'customer-access',
            'refreshToken': 'customer-refresh',
            'user': {
              'roles': ['customer'],
            },
          }),
          200,
        ),
      ),
    );

    await expectLater(
      api.verifyEmail(email: 'mona@example.com', code: '123456'),
      throwsA(
        isA<DriverApiException>().having(
          (error) => error.code,
          'code',
          'ROLE_REQUIRED',
        ),
      ),
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('driver.accessToken'), isNull);
    expect(preferences.getString('driver.refreshToken'), isNull);
    api.close();
  });

  test(
    'verification code and policy endpoints use the expected routes',
    () async {
      SharedPreferences.setMockInitialValues({
        'driver.accessToken': 'access-1',
      });
      final api = DriverApi(
        client: MockClient((request) async {
          if (request.url.path == '/api/auth/resend-code') {
            expect(request.method, 'POST');
            expect(jsonDecode(request.body), {'email': 'mona@example.com'});
            return http.Response('{}', 200);
          }
          if (request.url.path == '/api/policies') {
            expect(request.method, 'GET');
            return http.Response(
              jsonEncode({
                'policies': [
                  {'type': 'terms', 'contentAr': 'Terms'},
                ],
              }),
              200,
            );
          }
          expect(request.url.path, '/api/me/accept-policies');
          expect(request.method, 'POST');
          expect(request.headers['Authorization'], 'Bearer access-1');
          return http.Response(
            jsonEncode({
              'user': {'needsPolicyAcceptance': false},
            }),
            200,
          );
        }),
      );

      await api.resendVerificationCode('mona@example.com');
      expect((await api.getPolicies())['policies'], isA<List>());
      expect(
        (await api.acceptPolicies())['user']['needsPolicyAcceptance'],
        isFalse,
      );
      api.close();
    },
  );

  test(
    'image upload sends raw bytes with bearer auth and license category',
    () async {
      SharedPreferences.setMockInitialValues({
        'driver.accessToken': 'access-1',
      });
      final api = DriverApi(
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(
            request.url.path,
            '/api/driver/documents/driving_license_front',
          );
          expect(
            request.url.queryParameters['licenseCategory'],
            'professional_2',
          );
          expect(request.headers['Authorization'], 'Bearer access-1');
          expect(request.headers['Content-Type'], 'image/png');
          expect(request.bodyBytes, [137, 80, 78, 71]);
          return http.Response(jsonEncode(_emptyApplication()), 201);
        }),
      );

      final application = await api.uploadDriverDocument(
        'driving_license_front',
        [137, 80, 78, 71],
        licenseCategory: 'professional_2',
        contentType: 'image/png',
      );

      expect(application.status, 'draft');
      api.close();
    },
  );

  test(
    'expired access token is refreshed and the request is retried',
    () async {
      SharedPreferences.setMockInitialValues({
        'driver.accessToken': 'expired-access',
        'driver.refreshToken': 'refresh-1',
      });
      final api = DriverApi(
        client: MockClient((request) async {
          if (request.url.path == '/api/auth/refresh') {
            expect(jsonDecode(request.body), {'refreshToken': 'refresh-1'});
            return http.Response(
              jsonEncode({
                'accessToken': 'fresh-access',
                'refreshToken': 'refresh-2',
              }),
              200,
            );
          }
          if (request.url.path == '/api/driver/application' &&
              request.headers['Authorization'] == 'Bearer expired-access') {
            return http.Response(
              jsonEncode({
                'error': {'code': 'TOKEN_EXPIRED', 'message': 'expired'},
              }),
              401,
            );
          }
          expect(request.headers['Authorization'], 'Bearer fresh-access');
          return http.Response(jsonEncode(_emptyApplication()), 200);
        }),
      );

      final application = await api.getApplication();
      final preferences = await SharedPreferences.getInstance();

      expect(application.status, 'draft');
      expect(preferences.getString('driver.accessToken'), 'fresh-access');
      expect(preferences.getString('driver.refreshToken'), 'refresh-2');
      api.close();
    },
  );

  test('ended refresh session clears both stored tokens', () async {
    SharedPreferences.setMockInitialValues({
      'driver.accessToken': 'expired-access',
      'driver.refreshToken': 'expired-refresh',
    });
    final api = DriverApi(
      client: MockClient((request) async {
        if (request.url.path == '/api/driver/application') {
          return http.Response(
            jsonEncode({
              'error': {'code': 'TOKEN_EXPIRED', 'message': 'expired'},
            }),
            401,
          );
        }
        return http.Response(
          jsonEncode({
            'error': {'code': 'SESSION_ENDED', 'message': 'session ended'},
          }),
          401,
        );
      }),
    );

    await expectLater(
      api.getApplication(),
      throwsA(
        isA<DriverApiException>().having(
          (error) => error.code,
          'code',
          'SESSION_ENDED',
        ),
      ),
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('driver.accessToken'), isNull);
    expect(preferences.getString('driver.refreshToken'), isNull);
    api.close();
  });
}

Map<String, dynamic> _emptyApplication() => {
  'application': {
    'id': 'application-1',
    'status': 'draft',
    'profile': {},
    'documents': [],
    'vehicles': [],
    'payoutAccount': null,
    'missing': [],
  },
};
