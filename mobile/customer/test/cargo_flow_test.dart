import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/shipment_details_page.dart';
import 'package:main/pages/vehicle_small_page.dart';
import 'package:main/screens/home_screen.dart';
import 'package:main/services/auth_service.dart';
import 'package:main/services/cargo_order_service.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'wasla_auth_token': 'customer-test-token',
      'wasla_user_data': jsonEncode({'role': 'customer'}),
    });
  });

  tearDown(() {
    AuthService.replaceHttpClientForTesting(http.Client());
  });

  testWidgets('booking draft survives tab changes and can be resumed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        expect(request.url.path, '/api/catalog');
        return _response(_catalogResponse());
      }),
    );
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(isPreview: true)),
    );

    await tester.tap(find.text('Move something'));
    await tester.pumpAndSettle();
    expect(find.text('What are you moving?'), findsOneWidget);
    await tester.tap(find.text('Furniture'));
    await tester.pump();
    expect(find.byIcon(Icons.chair_outlined), findsOneWidget);
    await tester.tap(find.text('Continue').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Resume move'), findsOneWidget);

    await tester.tap(find.text('Messages').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume move'));
    await tester.pumpAndSettle();

    expect(find.text('What are you moving?'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quote selection is not accepted until explicit confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var accepted = false;
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path == '/api/shipments/12/quotes/30/accept') {
          accepted = true;
          return _response({
            'shipment': {
              'id': '12',
              'status': 'draft',
              'acceptedQuote': {..._quoteJson(), 'status': 'accepted'},
            },
          });
        }
        if (request.url.path == '/api/shipments/12') {
          return _response({
            'shipment': {
              'id': '12',
              'status': 'draft',
              'cargoCategoryId': '1',
              'cargoDescription': 'Sofa',
              'acceptedQuote': {..._quoteJson(), 'status': 'accepted'},
              'deliveryCode': '4821',
            },
          });
        }
        fail('Unexpected API request: ${request.method} ${request.url}');
      }),
    );

    final draft = CargoOrderDraft()
      ..catalog = const ShipmentCatalog(
        categories: [],
        vehicleTypes: [ShipmentVehicleType(id: '2', nameEn: 'Quarter Truck')],
        minScheduleLeadMinutes: 30,
      )
      ..shipment = Shipment.fromJson({
        'id': '12',
        'status': 'draft',
        'photos': [
          {'id': 'photo1', 'url': 'https://temporary/photo'},
        ],
        'quotes': [_quoteJson()],
      });

    await tester.pumpWidget(MaterialApp(home: VehiclesSmallPage(draft: draft)));
    expect(find.text('630.18'), findsOneWidget);
    expect(accepted, isFalse);
    await tester.tap(find.text('Quarter Truck'));
    await tester.pump();
    expect(accepted, isFalse);
    await tester.tap(find.text('Confirm selected price'));
    await tester.pumpAndSettle();

    expect(accepted, isTrue);
    expect(find.text('Shipment #12'), findsOneWidget);
    expect(find.text('Price accepted · 630.18'), findsOneWidget);
    expect(
      find.text('A driver has not been assigned by this action.'),
      findsOneWidget,
    );
    expect(find.text('4821'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('requesting quotes from shipment details opens quote selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    AuthService.replaceHttpClientForTesting(
      MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/shipments/12') {
          return _response({
            'shipment': {
              'id': '12',
              'status': 'draft',
              'cargoCategoryId': '1',
              'cargoDescription': 'Sofa',
              'photos': [
                {'id': 'photo1', 'url': 'https://temporary/photo'},
              ],
              'pickup': {
                'address': 'Nasr City',
                'lat': 30.0444,
                'lng': 31.2357,
              },
              'dropoff': {'address': 'Maadi', 'lat': 30.0131, 'lng': 31.2089},
            },
          });
        }
        if (request.method == 'GET' && request.url.path == '/api/catalog') {
          return _response(_catalogResponse());
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/shipments/12/quotes') {
          return _response({
            'shipment': {
              'id': '12',
              'status': 'draft',
              'cargoCategoryId': '1',
              'cargoDescription': 'Sofa',
              'photos': [
                {'id': 'photo1', 'url': 'https://temporary/photo'},
              ],
              'quotes': [_quoteJson()],
            },
          });
        }
        fail('Unexpected API request: ${request.method} ${request.url}');
      }),
    );

    await tester.pumpWidget(
      const MaterialApp(home: ShipmentDetailsPage(shipmentId: '12')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Request new quotes'), findsOneWidget);

    await tester.ensureVisible(find.text('Request new quotes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request new quotes'));
    await tester.pumpAndSettle();

    expect(find.text('Available vehicle quotes'), findsOneWidget);
    expect(find.text('630.18'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> _catalogResponse() => {
  'cargoCategories': [
    {
      'id': '1',
      'code': 'furniture',
      'nameEn': 'Furniture',
      'sizes': [
        {'id': '3', 'categoryId': '1', 'nameEn': 'Medium'},
      ],
    },
  ],
  'vehicleTypes': [
    {'id': '2', 'nameEn': 'Quarter Truck'},
  ],
  'settings': {'minScheduleLeadMinutes': 30},
};

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

http.Response _response(Map<String, dynamic> data, {int statusCode = 200}) =>
    http.Response(
      jsonEncode(data),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );
