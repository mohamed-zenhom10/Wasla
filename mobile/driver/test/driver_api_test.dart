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

  test(
    'driver availability, offers, and trip actions follow the API contract',
    () async {
      SharedPreferences.setMockInitialValues({
        'driver.accessToken': 'access-1',
      });
      final api = DriverApi(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], startsWith('Bearer '));
          switch ('${request.method} ${request.url.path}') {
            case 'GET /api/driver/status':
              return http.Response(
                jsonEncode({
                  'status': {'online': false, 'canGoOnline': true},
                }),
                200,
              );
            case 'POST /api/driver/online':
              expect(jsonDecode(request.body), {'lat': 30.05, 'lng': 31.33});
              return http.Response(
                jsonEncode({
                  'status': {'online': true, 'canGoOnline': true},
                }),
                200,
              );
            case 'POST /api/driver/offline':
              return http.Response(
                jsonEncode({
                  'status': {'online': false, 'canGoOnline': true},
                }),
                200,
              );
            case 'POST /api/driver/location':
              expect(jsonDecode(request.body), {
                'lat': 30.05,
                'lng': 31.33,
                'accuracyM': 12.5,
              });
              return http.Response(
                jsonEncode({
                  'status': {'online': true, 'canGoOnline': true},
                }),
                200,
              );
            case 'GET /api/driver/offers':
              return http.Response(
                jsonEncode({
                  'offers': [
                    {'id': 'offer-41', 'secondsLeft': 24},
                  ],
                }),
                200,
              );
            case 'POST /api/driver/offers/offer-41/accept':
              return http.Response(
                jsonEncode({
                  'trip': {'id': '7', 'status': 'assigned'},
                }),
                201,
              );
            case 'POST /api/driver/trips/7/start':
              expect(jsonDecode(request.body), {'lat': 30.05, 'lng': 31.33});
              return http.Response(
                jsonEncode({
                  'trip': {'id': '7', 'status': 'heading_to_pickup'},
                }),
                200,
              );
            case 'PUT /api/driver/trips/7/photos/pickup':
              expect(request.headers['Content-Type'], 'image/jpeg');
              expect(request.bodyBytes, [1, 2, 3]);
              return http.Response(
                jsonEncode({
                  'trip': {'id': '7', 'status': 'arrived_at_pickup'},
                }),
                201,
              );
            case 'GET /api/driver/trips/current':
              return http.Response(
                jsonEncode({
                  'trip': {'id': '7', 'status': 'assigned'},
                }),
                200,
              );
            case 'POST /api/driver/trips/7/cancel':
              expect(jsonDecode(request.body), {'reason': 'Flat tyre'});
              return http.Response(
                jsonEncode({
                  'trip': {'id': '7', 'status': 'cancelled'},
                }),
                200,
              );
            default:
              fail('Unexpected API request: ${request.method} ${request.url}');
          }
        }),
      );

      expect((await api.getDriverStatus())['online'], isFalse);
      expect(
        (await api.setOnline({
          'lat': 30.05,
          'lng': 31.33,
          'accuracyM': 12.5,
        }))['online'],
        isTrue,
      );
      expect((await api.setOffline())['online'], isFalse);
      expect(
        (await api.sendLocation({
          'lat': 30.05,
          'lng': 31.33,
          'accuracyM': 12.5,
        }))['online'],
        isTrue,
      );
      expect((await api.getOffers()).single['id'], 'offer-41');
      expect((await api.acceptOffer('offer-41'))['status'], 'assigned');
      expect(
        (await api.updateTrip(
          '7',
          'start',
          body: {'lat': 30.05, 'lng': 31.33},
        ))['status'],
        'heading_to_pickup',
      );
      expect(
        (await api.uploadTripPhoto('7', 'pickup', [1, 2, 3]))['status'],
        'arrived_at_pickup',
      );
      expect((await api.getCurrentTrip())?['id'], '7');
      expect((await api.cancelTrip('7', 'Flat tyre'))['status'], 'cancelled');
      api.close();
    },
  );

  test('trip navigation starts and confirms pickup arrival with GPS', () async {
    SharedPreferences.setMockInitialValues({'driver.accessToken': 'access-1'});
    final api = DriverApi(
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer access-1');
        expect(request.method, 'POST');
        expect(request.url.path, startsWith('/api/driver/trips/7/'));
        expect(jsonDecode(request.body), {
          'lat': 30.05,
          'lng': 31.33,
          'accuracyM': 12.5,
        });

        switch (request.url.path) {
          case '/api/driver/trips/7/start':
            return http.Response(
              jsonEncode({
                'trip': {'id': '7', 'status': 'heading_to_pickup'},
              }),
              200,
            );
          case '/api/driver/trips/7/arrive-pickup':
            return http.Response(
              jsonEncode({
                'trip': {'id': '7', 'status': 'arrived_at_pickup'},
              }),
              200,
            );
          default:
            fail('Unexpected trip action: ${request.url.path}');
        }
      }),
    );

    final location = {'lat': 30.05, 'lng': 31.33, 'accuracyM': 12.5};
    final started = await api.updateTrip('7', 'start', body: location);
    final arrived = await api.updateTrip('7', 'arrive-pickup', body: location);

    expect(started['status'], 'heading_to_pickup');
    expect(arrived['status'], 'arrived_at_pickup');
    api.close();
  });

  test(
    'logout revokes the refresh token and clears saved credentials',
    () async {
      SharedPreferences.setMockInitialValues({
        'driver.accessToken': 'access-1',
        'driver.refreshToken': 'refresh-1',
      });
      final api = DriverApi(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/auth/logout');
          expect(jsonDecode(request.body), {'refreshToken': 'refresh-1'});
          return http.Response('', 204);
        }),
      );

      await api.logout();

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('driver.accessToken'), isNull);
      expect(preferences.getString('driver.refreshToken'), isNull);
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
