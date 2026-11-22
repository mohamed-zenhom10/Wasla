import 'dart:convert';

import 'package:driver/data/tomtom_routing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('parses route geometry, live traffic ETA and spoken instructions', () {
    final route = TomTomRoute.fromJson({
      'routes': [
        {
          'summary': {
            'lengthInMeters': 8200,
            'travelTimeInSeconds': 1020,
            'liveTrafficIncidentsTravelTimeInSeconds': 1260,
            'trafficDelayInSeconds': 240,
          },
          'legs': [
            {
              'points': [
                {'latitude': 30.1, 'longitude': 31.2},
                {'latitude': 30.2, 'longitude': 31.3},
              ],
            },
          ],
          'guidance': {
            'instructions': [
              {
                'message': 'Turn right',
                'point': {'latitude': 30.15, 'longitude': 31.25},
              },
            ],
          },
        },
      ],
    });

    expect(route.points, hasLength(2));
    expect(route.distanceMeters, 8200);
    expect(route.durationSeconds, 1260);
    expect(route.trafficDelaySeconds, 240);
    expect(route.instructions.single.message, 'Turn right');
    expect(route.instructions.single.point?.latitude, 30.15);
  });

  test('rejects an empty route response instead of simulating a route', () {
    expect(
      () => TomTomRoute.fromJson({'routes': []}),
      throwsA(isA<TomTomException>()),
    );
  });

  test('requests a live traffic-aware fastest route from TomTom', () async {
    final service = TomTomRoutingService(
      apiKey: 'test-key',
      client: MockClient((request) async {
        expect(request.url.host, 'api.tomtom.com');
        expect(
          request.url.path,
          '/routing/1/calculateRoute/30.0,31.0:30.1,31.1/json',
        );
        expect(request.url.queryParameters['key'], 'test-key');
        expect(request.url.queryParameters['traffic'], 'true');
        expect(request.url.queryParameters['departAt'], 'now');
        expect(request.url.queryParameters['routeType'], 'fastest');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'routes': [
                {
                  'summary': {'lengthInMeters': 500, 'travelTimeInSeconds': 60},
                  'legs': [
                    {
                      'points': [
                        {'latitude': 30.0, 'longitude': 31.0},
                        {'latitude': 30.1, 'longitude': 31.1},
                      ],
                    },
                  ],
                  'guidance': {
                    'instructions': [
                      {
                        'message': 'Continue',
                        'point': {'latitude': 30.0, 'longitude': 31.0},
                      },
                    ],
                  },
                },
              ],
            }),
          ),
          200,
        );
      }),
    );

    final route = await service.calculateFastestRoute(
      origin: const LatLng(30, 31),
      destination: const LatLng(30.1, 31.1),
    );

    expect(route.distanceMeters, 500);
    service.close();
  });

  test('surfaces TomTom HTTP errors', () async {
    final service = TomTomRoutingService(
      apiKey: 'test-key',
      client: MockClient((_) async => http.Response('denied', 403)),
    );

    await expectLater(
      service.calculateFastestRoute(
        origin: const LatLng(30, 31),
        destination: const LatLng(30.1, 31.1),
      ),
      throwsA(isA<TomTomException>()),
    );
    service.close();
  });

  test('searches Egyptian places and parses destination coordinates', () async {
    final service = TomTomRoutingService(
      apiKey: 'test-key',
      client: MockClient((request) async {
        expect(request.url.host, 'api.tomtom.com');
        expect(request.url.pathSegments.last, 'عين شمس.json');
        expect(request.url.queryParameters['countrySet'], 'EG');
        expect(request.url.queryParameters['language'], 'ar');
        expect(request.url.queryParameters['limit'], '6');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'results': [
                {
                  'poi': {'name': 'عين شمس'},
                  'address': {'freeformAddress': 'القاهرة، مصر'},
                  'position': {'lat': 30.13, 'lon': 31.32},
                },
                {
                  'address': {'freeformAddress': 'منطقة بدون إحداثيات'},
                  'position': {'lat': null, 'lon': null},
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final places = await service.searchPlaces('عين شمس');

    expect(places, hasLength(1));
    expect(places.single.name, 'عين شمس');
    expect(places.single.address, 'القاهرة، مصر');
    expect(places.single.point.latitude, 30.13);
    service.close();
  });
}
