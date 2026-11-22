import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:main/pages/shipment_details_page.dart';
import 'package:main/services/auth_service.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'wasla_auth_token': 'test-token'});
    AuthService.replaceHttpClientForTesting(
      http_testing.MockClient((request) async {
        if (request.url.path == '/api/shipments/12') {
          return http.Response(
            jsonEncode({
              'shipment': {
                'id': '12',
                'status': 'draft',
                'cargoCategoryId': '1',
                'cargoDescription': 'Chair',
                'itemCount': 1,
                'helpersCount': 0,
                'pickup': {'address': 'Pickup', 'lat': 30.0, 'lng': 31.0},
                'dropoff': {'address': 'Dropoff', 'lat': 30.1, 'lng': 31.1},
              },
            }),
            200,
          );
        }
        if (request.url.path == '/api/catalog') {
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
        }
        return http.Response('{}', 404);
      }),
    );
  });

  testWidgets('draft shipment edit button opens cargo category page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: ShipmentDetailsPage(shipmentId: '12')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit draft shipment'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('What are you moving?'), findsOneWidget);
  });

  testWidgets('cancelled shipments do not expose actionable quote actions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    AuthService.replaceHttpClientForTesting(
      http_testing.MockClient((request) async {
          return http.Response(
            jsonEncode({
              'shipment': {
                'id': '12',
                'status': 'cancelled',
                'cargoCategoryId': '1',
                'cargoDescription': 'Chair',
                'itemCount': 1,
                'helpersCount': 0,
                'pickup': {'address': 'Pickup', 'lat': 30.0, 'lng': 31.0},
                'dropoff': {'address': 'Dropoff', 'lat': 30.1, 'lng': 31.1},
                'acceptedQuote': {
                  'id': '30',
                  'vehicleTypeId': '2',
                  'status': 'accepted',
                  'recommended': true,
                  'customerAmount': '630.18',
                  'helpersCount': 1,
                  'helpersAmount': '50.00',
                  'expiresAt': DateTime.now()
                      .add(const Duration(minutes: 10))
                      .toIso8601String(),
                },
              },
            }),
            200,
          );
      }),
    );
    await tester.pumpWidget(
      const MaterialApp(home: ShipmentDetailsPage(shipmentId: '12')),
    );
    await tester.pumpAndSettle();

    expect(find.text('cancelled'), findsWidgets);
    expect(find.text('Withdraw accepted price'), findsNothing);
    expect(find.text('Confirm shipment'), findsNothing);
    expect(find.text('Edit draft shipment'), findsNothing);
    expect(find.text('Request new quotes'), findsNothing);
  });
}
