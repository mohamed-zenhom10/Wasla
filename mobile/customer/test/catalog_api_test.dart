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

  test('parses the documented catalog response safely', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/catalog');
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response(
          jsonEncode({
            'cargoCategories': [
              {
                'id': '2',
                'code': 'parcels',
                'nameAr': '\u0628\u0636\u0627\u0629',
                'nameEn': 'Parcels',
                'sortOrder': 2,
                'isActive': true,
                'sizes': [
                  {
                    'id': '9',
                    'categoryId': '2',
                    'code': 'few_items',
                    'nameAr': '\u0642\u0637\u0639 \u0642\u0644\u064a\u0644\u0629',
                    'nameEn': 'A few items',
                    'approxVolumeM3': 2,
                    'sortOrder': 2,
                    'isActive': true,
                  },
                  {
                    'id': '8',
                    'categoryId': '2',
                    'code': 'many_items',
                    'nameEn': 'Many items',
                    'approxVolumeM3': 8,
                    'sortOrder': 1,
                    'isActive': true,
                  },
                ],
              },
              {
                'id': '1',
                'code': 'furniture',
                'nameAr': '\u0623\u062B\u0627\u062B',
                'nameEn': 'Furniture',
                'sortOrder': 1,
                'isActive': true,
                'sizes': [],
              },
            ],
            'vehicleTypes': [
              {
                'id': '2',
                'code': 'quarter_truck',
                'nameAr': '\u0631\u0628\u0642 \u0646\u0644',
                'nameEn': 'Quarter Truck',
                'maxPayloadKg': 1500,
                'cargoVolumeM3': 6,
                'bedLengthM': 2.5,
                'bedWidthM': 1.6,
                'bedHeightM': 1.5,
                'suitableForAr': '\u063a\u0631\u0641\u0629 \u0623\u0648\u0634\u0642 \u0635\u063a\u0631\u064a\u0629',
                'suitableForEn': 'A room or a small flat',
                'baseFare': '300.00',
                'perKmRate': '15.00',
                'helperFee': '150.00',
                'minLicenseCategory': 'professional_3',
                'isActive': true,
                'sortOrder': 1,
              },
            ],
            'cities': [
              {
                'id': '1',
                'code': 'cairo',
                'nameAr': '\u0627\u0644\u0642\u0627\u0647\u0631\u0629',
                'nameEn': 'Cairo',
                'isActive': true,
                'zones': [
                  {
                    'id': '3',
                    'cityId': '1',
                    'code': 'nasr_city',
                    'nameAr': '\u0645\u062f\u064a\u0646\u0629 \u0646\u0635\u0631',
                    'nameEn': 'Nasr City',
                    'isActive': true,
                  },
                ],
              },
            ],
            'reviewTags': [
              {
                'id': '1',
                'code': 'professional',
                'nameAr': '\u0645\u062d\u0631\u0641',
                'nameEn': 'Professional',
                'sentiment': 'positive',
                'direction': 'customer_to_driver',
                'isActive': true,
              },
            ],
            'settings': {
              'commissionRate': 0.15,
              'cancellationFee': '50.00',
              'groupDiscountPct': 0.05,
              'maxGroupStops': 5,
              'minScheduleLeadMinutes': 30,
              'companyInstapayHandle': 'wasla@instapay',
              'minTopupAmount': '50.00',
              'maxTopupAmount': '10000.00',
              'minDriverAge': 21,
              'driverPayoutWeekday': 0,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final catalog = await service.getCatalog();

    final categories = catalog.activeCategories;
    expect(categories.length, 2);
    expect(categories.map((category) => category.id), ['1', '2']);
    expect(categories.first.nameAr, '\u0623\u062B\u0627\u062B');
    expect(categories.first.displayName('ar'), '\u0623\u062B\u0627\u062B');
    expect(categories.first.activeSizes, isEmpty);
    final sortedSizes = categories.last.activeSizes;
    expect(sortedSizes.length, 2);
    expect(sortedSizes.map((size) => size.id), ['8', '9']);
    expect(sortedSizes.first.approxVolumeM3, 8);
    expect(sortedSizes.first.displayName('ar'), 'Many items');

    expect(catalog.vehicleTypes.single.baseFare, '300.00');
    expect(catalog.vehicleTypes.single.perKmRate, '15.00');
    expect(catalog.vehicleTypes.single.helperFee, '150.00');
    expect(catalog.vehicleTypes.single.maxPayloadKg, 1500);
    expect(catalog.vehicleTypes.single.cargoVolumeM3, 6);
    expect(catalog.vehicleTypes.single.suitableForEn, 'A room or a small flat');

    expect(catalog.cities.single.nameAr, '\u0627\u0644\u0642\u0627\u0647\u0631\u0629');
    expect(catalog.cities.single.zones.single.nameEn, 'Nasr City');
    expect(catalog.reviewTags.single.sentiment, 'positive');

    expect(catalog.minScheduleLeadMinutes, 30);
    expect(catalog.commissionRate, 0.15);
    expect(catalog.cancellationFee, '50.00');
    expect(catalog.groupDiscountPct, 0.05);
    expect(catalog.maxGroupStops, 5);
    expect(catalog.minDriverAge, 21);
    expect(catalog.driverPayoutWeekday, 0);
    expect(catalog.minTopupAmount, 50);
    expect(catalog.maxTopupAmount, 10000);
    expect(catalog.companyInstapayHandle, 'wasla@instapay');
  });

  test('catalog failures surface an api exception without crashing', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'code': 'INTERNAL', 'message': 'Catalog unavailable'},
          }),
          500,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await expectLater(
      service.getCatalog(),
      throwsA(isA<ShipmentApiException>()),
    );
  });

  test('catalog responses are cached for the service instance', () async {
    var calls = 0;
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'cargoCategories': [
              {'id': '1', 'nameEn': 'Furniture', 'sizes': []},
            ],
            'vehicleTypes': [],
            'settings': {'minScheduleLeadMinutes': 30},
          }),
          200,
        );
      }),
    );

    final first = await service.getCatalog();
    final second = await service.getCatalog();
    final third = await service.getCatalog();

    expect(calls, 1);
    expect(identical(first, second), isTrue);
    expect(identical(second, third), isTrue);
    expect(first.categories.single.nameEn, 'Furniture');
  });

  test('zone endpoint returns the service zone for covered coordinates', () async {
    ShipmentZone? zone;
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/catalog/zone');
        expect(request.url.queryParameters['lat'], '30.05');
        expect(request.url.queryParameters['lng'], '31.33');
        return http.Response(
          jsonEncode({
            'zone': {
              'id': '3',
              'cityId': '1',
              'code': 'nasr_city',
              'nameAr': '\u0645\u062f\u064a\u0646\u0629 \u0646\u0635\u0631',
              'nameEn': 'Nasr City',
              'isActive': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    zone = await service.getZone(lat: 30.05, lng: 31.33);
    expect(zone?.id, '3');
    expect(zone?.nameEn, 'Nasr City');
  });

  test('zone endpoint returns null for uncovered coordinates', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'zone': null,
          }),
          200,
        );
      }),
    );
    final zone = await service.getZone(lat: 0, lng: 0);
    expect(zone, isNull);
  });

  test('zone endpoint rejects coordinates outside the supported range', () async {
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'code': 'INVALID_INPUT', 'message': 'Invalid coordinates'},
          }),
          400,
        );
      }),
    );
    await expectLater(
      service.getZone(lat: 95, lng: 31.33),
      throwsA(
        isA<ShipmentApiException>().having(
          (error) => error.code,
          'code',
          'INVALID_INPUT',
        ),
      ),
    );
  });
}
