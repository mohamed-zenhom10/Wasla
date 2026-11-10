import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:main/models/shipment.dart';
import 'package:main/services/auth_service.dart';
import 'package:main/services/shipment_service.dart';

void main() {
  const token = 'customer-test-token';
  late ShipmentService service;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'wasla_auth_token': token,
      'wasla_user_data': jsonEncode({'role': 'customer'}),
    });
    service = ShipmentService();
  });

  tearDown(() {
    AuthService.replaceHttpClientForTesting(http.Client());
  });

  test(
    'loads the public catalog through the configured API base URL',
    () async {
      AuthService.replaceHttpClientForTesting(
        MockClient((request) async {
          expect(request.url.path, '/api/catalog');
          expect(request.headers.containsKey('authorization'), isFalse);
          return _response({
            'cargoCategories': [
              {
                'id': '1',
                'nameEn': 'Furniture',
                'sizes': [
                  {'id': '3', 'categoryId': '1', 'nameEn': 'Few items'},
                ],
              },
            ],
            'vehicleTypes': [
              {'id': '2', 'nameEn': 'Quarter Truck'},
            ],
            'settings': {'minScheduleLeadMinutes': 30},
          });
        }),
      );

      final catalog = await service.getCatalog();

      expect(catalog.categories.single.sizes.single.id, '3');
      expect(catalog.vehicleTypes.single.nameEn, 'Quarter Truck');
      expect(catalog.minScheduleLeadMinutes, 30);
    },
  );

  test(
    'creates an authenticated draft with only client-owned payload fields',
    () async {
      AuthService.replaceHttpClientForTesting(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/shipments');
          expect(request.headers['authorization'], 'Bearer $token');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['cargoCategoryId'], '1');
          expect(body['sizeOptionId'], '3');
          expect(body['itemCount'], 3);
          expect(body['helpersCount'], 1);
          expect(body['pickup']['lat'], 30.0444);
          expect(body['dropoff']['lng'], 31.2089);
          expect(body['pickupType'], 'now');
          expect(body['paymentMethod'], 'cash');
          expect(body.containsKey('routeDistanceM'), isFalse);
          expect(body.containsKey('routeDurationS'), isFalse);
          expect(body.containsKey('pickupAt'), isFalse);
          return _response({
            'shipment': {'id': '12', 'status': 'draft'},
          }, statusCode: 201);
        }),
      );

      final shipment = await service.createDraft(
        catalog: _catalog(),
        cargoCategoryId: '1',
        sizeOptionId: '3',
        cargoDescription: ' A sofa and 2 chairs ',
        itemCount: 3,
        helpersCount: 1,
        pickup: _pickup,
        dropoff: _dropoff,
        pickupType: 'now',
        paymentMethod: 'cash',
      );

      expect(shipment.id, '12');
      expect(shipment.status, 'draft');
    },
  );

  test(
    'validates schedule and recipient payment before making requests',
    () async {
      var requests = 0;
      AuthService.replaceHttpClientForTesting(
        MockClient((request) async {
          requests++;
          return _response({
            'shipment': {'id': '1', 'status': 'draft'},
          });
        }),
      );

      await expectLater(
        service.createDraft(
          catalog: _catalog(),
          cargoCategoryId: '1',
          cargoDescription: 'Boxes',
          itemCount: 1,
          pickup: _pickup,
          dropoff: _dropoff,
          pickupType: 'scheduled',
          pickupAt: DateTime.now().add(const Duration(minutes: 5)),
          paymentMethod: 'cash',
        ),
        throwsA(
          isA<ShipmentApiException>().having(
            (error) => error.code,
            'code',
            'SCHEDULE_TOO_SOON',
          ),
        ),
      );
      await expectLater(
        service.createDraft(
          catalog: _catalog(),
          cargoCategoryId: '1',
          cargoDescription: 'Boxes',
          itemCount: 1,
          pickup: _pickup,
          dropoff: _dropoff,
          pickupType: 'now',
          paymentMethod: 'wallet',
          farePaidBy: 'recipient',
          recipientName: 'Mona',
          recipientPhone: '+201012345678',
        ),
        throwsA(isA<ShipmentApiException>()),
      );
      expect(requests, 0);
    },
  );

  test('uploads raw photo bytes and removes uploaded photos', () async {
    final shipment = Shipment.fromJson({
      'id': '12',
      'status': 'draft',
      'photos': [
        {'id': '5', 'url': 'https://temporary/photo'},
      ],
    });
    final calls = <String>[];
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        expect(request.headers['authorization'], 'Bearer $token');
        if (request.method == 'PUT') {
          expect(request.headers['content-type'], 'image/png');
          expect(request.bodyBytes, [0x89, 0x50, 0x4e, 0x47]);
        }
        return _response({
          'shipment': {
            'id': '12',
            'status': 'draft',
            'photos': [
              {'id': '5', 'url': 'https://temporary/photo'},
            ],
          },
        }, statusCode: 201);
      }),
    );

    final uploaded = await service.uploadPhoto(
      shipment: Shipment.fromJson({'id': '12', 'status': 'draft'}),
      bytes: [0x89, 0x50, 0x4e, 0x47],
      contentType: 'image/png',
    );
    final removed = await service.removePhoto(shipment: uploaded, photoId: '5');

    expect(removed.photos.single.id, '5');
    expect(calls, [
      'PUT /api/shipments/12/photos',
      'DELETE /api/shipments/12/photos/5',
    ]);
    expect(shipment.photos.single.url, 'https://temporary/photo');
  });

  test(
    'requests quotes without a body and parses server customer amount',
    () async {
      AuthService.replaceHttpClientForTesting(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/shipments/12/quotes');
          expect(request.bodyBytes, isEmpty);
          return _response({
            'shipment': {
              'id': '12',
              'status': 'draft',
              'photos': [
                {'id': 'photo1', 'url': 'https://temporary/photo'},
              ],
              'quotes': [_quoteJson()],
            },
          }, statusCode: 201);
        }),
      );

      final shipment = await service.requestQuotes(
        Shipment.fromJson({
          'id': '12',
          'status': 'draft',
          'photos': [
            {'id': 'photo1', 'url': 'https://temporary/photo'},
          ],
        }),
      );

      expect(shipment.quotes.single.customerAmount, '630.18');
      expect(shipment.quotes.single.recommended, isTrue);
    },
  );

  test('accepts a quote only through explicit API request and parses accepted quote', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/shipments/12/quotes/30/accept');
        expect(request.method, 'POST');
        expect(request.bodyBytes, isEmpty);
        return _response({
          'shipment': {
            'id': '12',
            'status': 'draft',
            'acceptedQuote': {..._quoteJson(), 'status': 'accepted'},
          },
        });
      }),
    );
    final shipment = Shipment.fromJson({
      'id': '12',
      'status': 'draft',
      'quotes': [_quoteJson()],
    });

    final accepted = await service.acceptQuote(
      shipment: shipment,
      quote: shipment.quotes.single,
    );

    expect(accepted.acceptedQuote?.id, '30');
    expect(accepted.isEditable, isFalse);
  });

  test('expired quotes do not call the accept endpoint', () async {
    var requests = 0;
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        requests++;
        return _response({});
      }),
    );
    final quote = ShipmentQuote.fromJson({
      ..._quoteJson(),
      'expiresAt': '2020-01-01T00:00:00Z',
    });

    await expectLater(
      service.acceptQuote(
        shipment: Shipment.fromJson({'id': '12', 'status': 'draft'}),
        quote: quote,
      ),
      throwsA(
        isA<ShipmentApiException>().having(
          (error) => error.code,
          'code',
          'QUOTE_EXPIRED',
        ),
      ),
    );
    expect(requests, 0);
  });

  test(
    'patches only changed fields and rejects editing accepted prices',
    () async {
      AuthService.replaceHttpClientForTesting(
        MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/shipments/12');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body.keys, {'helpersCount'});
          expect(body['helpersCount'], 2);
          expect(body.containsKey('routeDistanceM'), isFalse);
          return _response({
            'shipment': {'id': '12', 'status': 'draft', 'helpersCount': 2},
          });
        }),
      );
      final updated = await service.updateDraft(
        Shipment.fromJson({'id': '12', 'status': 'draft'}),
        {'helpersCount': 2},
      );
      expect(updated.helpersCount, 2);

      await expectLater(
        service.updateDraft(
          Shipment.fromJson({
            'id': '12',
            'status': 'draft',
            'acceptedQuote': _quoteJson(),
          }),
          {'helpersCount': 3},
        ),
        throwsA(isA<ShipmentApiException>()),
      );
    },
  );

  test('withdraws an accepted price only through explicit endpoint', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/shipments/12/withdraw-price');
        return _response({
          'shipment': {'id': '12', 'status': 'draft'},
        });
      }),
    );
    final result = await service.withdrawPrice(
      Shipment.fromJson({
        'id': '12',
        'status': 'draft',
        'acceptedQuote': _quoteJson(),
      }),
    );
    expect(result.acceptedQuote, isNull);
    expect(result.isEditable, isTrue);
  });

  test('retrieves shipment details and paginated shipment lists', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path == '/api/shipments/12') {
          return _response({
            'shipment': {'id': '12', 'status': 'draft'},
          });
        }
        expect(request.url.path, '/api/shipments');
        expect(request.url.queryParameters, {'status': 'active', 'page': '2'});
        return _response({
          'shipments': [
            {
              'id': '12',
              'status': 'in_progress',
              'pickup': {'address': 'Nasr City'},
              'dropoff': {'address': 'Maadi'},
              'customerAmount': '630.18',
            },
          ],
          'page': 2,
          'hasMore': true,
        });
      }),
    );

    final shipment = await service.getShipment('12');
    final page = await service.getShipments(status: 'active', page: 2);

    expect(shipment.id, '12');
    expect(page.page, 2);
    expect(page.hasMore, isTrue);
    expect(page.shipments.single.pickupAddress, 'Nasr City');
    expect(page.shipments.single.customerAmount, '630.18');
  });

  test('maps field validation and ROLE_REQUIRED errors', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        return _response({
          'error': {
            'code': 'INVALID_INPUT',
            'message': 'Item count is required',
            'field': 'itemCount',
          },
        }, statusCode: 400);
      }),
    );
    await expectLater(
      service.getShipment('12'),
      throwsA(
        isA<ShipmentApiException>()
            .having((error) => error.field, 'field', 'itemCount')
            .having((error) => error.code, 'code', 'INVALID_INPUT'),
      ),
    );

    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        return _response({
          'error': {'code': 'ROLE_REQUIRED', 'message': 'Role required'},
        }, statusCode: 403);
      }),
    );
    await expectLater(
      service.getShipment('12'),
      throwsA(
        isA<ShipmentApiException>().having(
          (error) => error.message,
          'message',
          contains('Customer account'),
        ),
      ),
    );
  });

  test(
    'requires a customer token and prevents invalid photo uploads',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      var requests = 0;
      AuthService.replaceHttpClientForTesting(
        MockClient((request) async {
          requests++;
          return _response({});
        }),
      );

      await expectLater(
        service.getShipment('12'),
        throwsA(
          isA<ShipmentApiException>().having(
            (error) => error.code,
            'code',
            'UNAUTHENTICATED',
          ),
        ),
      );
      await expectLater(
        service.uploadPhoto(
          shipment: Shipment.fromJson({'id': '12', 'status': 'draft'}),
          bytes: [1, 2, 3],
          contentType: 'image/gif',
        ),
        throwsA(
          isA<ShipmentApiException>().having(
            (error) => error.code,
            'code',
            'UNSUPPORTED_IMAGE',
          ),
        ),
      );
      expect(requests, 0);
    },
  );
}

ShipmentCatalog _catalog() => const ShipmentCatalog(
  categories: [
    ShipmentCargoCategory(
      id: '1',
      nameEn: 'Furniture',
      sizes: [ShipmentSizeOption(id: '3', categoryId: '1', nameEn: 'Medium')],
    ),
  ],
  vehicleTypes: [],
  minScheduleLeadMinutes: 30,
);

const _pickup = ShipmentLocation(
  address: 'Nasr City',
  latitude: 30.0444,
  longitude: 31.2357,
);

const _dropoff = ShipmentLocation(
  address: 'Maadi',
  latitude: 30.0131,
  longitude: 31.2089,
);

Map<String, dynamic> _quoteJson() => {
  'id': '30',
  'vehicleTypeId': '2',
  'status': 'offered',
  'recommended': true,
  'customerAmount': '630.18',
  'helpersCount': 1,
  'helpersAmount': '50.00',
  'expiresAt': DateTime.now()
      .add(const Duration(minutes: 10))
      .toIso8601String(),
};

http.Response _response(Map<String, dynamic> body, {int statusCode = 200}) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );
