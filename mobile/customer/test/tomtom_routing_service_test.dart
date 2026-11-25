import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:main/services/tomtom_routing_service.dart';

void main() {
  test('parses TomTom route geometry and traffic-aware ETA', () {
    final route = TomTomRoute.fromJson({
      'routes': [
        {
          'summary': {
            'lengthInMeters': 12345,
            'travelTimeInSeconds': 1800,
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
        },
      ],
    });

    expect(route.points, const [LatLng(30.1, 31.2), LatLng(30.2, 31.3)]);
    expect(route.distanceMeters, 12345);
    expect(route.travelTimeSeconds, 1800);
    expect(route.trafficDelaySeconds, 240);
  });

  test('rejects responses without usable route geometry', () {
    expect(
      () => TomTomRoute.fromJson({
        'routes': [
          {
            'summary': {
              'lengthInMeters': 100,
              'travelTimeInSeconds': 30,
              'trafficDelayInSeconds': 0,
            },
            'legs': [
              {
                'points': [
                  {'latitude': 30.1, 'longitude': 31.2},
                ],
              },
            ],
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('rejects a route without traffic-aware ETA metrics', () {
    expect(
      () => TomTomRoute.fromJson({
        'routes': [
          {
            'summary': {'lengthInMeters': 100},
            'legs': [
              {
                'points': [
                  {'latitude': 30.1, 'longitude': 31.2},
                  {'latitude': 30.2, 'longitude': 31.3},
                ],
              },
            ],
          },
        ],
      }),
      throwsFormatException,
    );
  });
}
