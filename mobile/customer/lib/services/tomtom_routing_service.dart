import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class TomTomRoute {
  const TomTomRoute({
    required this.points,
    required this.distanceMeters,
    required this.travelTimeSeconds,
    required this.trafficDelaySeconds,
  });

  final List<LatLng> points;
  final int distanceMeters;
  final int travelTimeSeconds;
  final int trafficDelaySeconds;

  factory TomTomRoute.fromJson(Map<String, dynamic> json) {
    final routes = json['routes'];
    if (routes is! List || routes.isEmpty || routes.first is! Map) {
      throw const FormatException('TomTom returned no route.');
    }
    final route = Map<String, dynamic>.from(routes.first as Map);
    final summary = route['summary'];
    if (summary is! Map) {
      throw const FormatException('TomTom route summary is missing.');
    }
    final legs = route['legs'];
    if (legs is! List) {
      throw const FormatException('TomTom route geometry is missing.');
    }
    final distanceMeters = _integer(
      summary['lengthInMeters'],
      'lengthInMeters',
    );
    final travelTimeSeconds = _integer(
      summary['travelTimeInSeconds'],
      'travelTimeInSeconds',
    );
    final trafficDelaySeconds = _integer(
      summary['trafficDelayInSeconds'],
      'trafficDelayInSeconds',
    );
    final points = <LatLng>[];
    for (final leg in legs.whereType<Map>()) {
      final legMap = Map<String, dynamic>.from(leg);
      final rawPoints = legMap['points'];
      if (rawPoints is! List) continue;
      for (final rawPoint in rawPoints.whereType<Map>()) {
        final point = Map<String, dynamic>.from(rawPoint);
        final lat = (point['latitude'] as num?)?.toDouble();
        final lng = (point['longitude'] as num?)?.toDouble();
        if (lat != null &&
            lng != null &&
            lat.isFinite &&
            lng.isFinite &&
            lat >= -90 &&
            lat <= 90 &&
            lng >= -180 &&
            lng <= 180) {
          points.add(LatLng(lat, lng));
        }
      }
    }
    if (points.length < 2) {
      throw const FormatException('TomTom route geometry is incomplete.');
    }
    return TomTomRoute(
      points: points,
      distanceMeters: distanceMeters,
      travelTimeSeconds: travelTimeSeconds,
      trafficDelaySeconds: trafficDelaySeconds,
    );
  }

  static int _integer(Object? value, String field) {
    if (value is! num || !value.isFinite || value < 0) {
      throw FormatException('TomTom route $field is missing or invalid.');
    }
    return value.round();
  }
}

class TomTomRoutingService {
  static const apiKey = String.fromEnvironment('TOMTOM_API_KEY');

  Future<TomTomRoute> calculateRoute({
    required LatLng start,
    required LatLng destination,
  }) async {
    if (apiKey.isEmpty) {
      throw StateError(
        'TomTom is not configured. Run with --dart-define=TOMTOM_API_KEY=<your-key>.',
      );
    }
    final path =
        '/routing/1/calculateRoute/'
        '${start.latitude},${start.longitude}:'
        '${destination.latitude},${destination.longitude}/json';
    final uri = Uri.https('api.tomtom.com', path, {
      'traffic': 'true',
      'routeType': 'fastest',
      'travelMode': 'car',
      'key': apiKey,
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('TomTom route request failed (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('TomTom returned an invalid route response.');
    }
    return TomTomRoute.fromJson(Map<String, dynamic>.from(decoded));
  }
}
