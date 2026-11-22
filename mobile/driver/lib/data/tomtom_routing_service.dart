import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

double? _number(Object? value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  return number != null && number.isFinite ? number : null;
}

class TomTomException implements Exception {
  const TomTomException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TomTomInstruction {
  const TomTomInstruction({required this.message, this.point});

  final String message;
  final LatLng? point;
}

class TomTomSearchResult {
  const TomTomSearchResult({
    required this.name,
    required this.address,
    required this.point,
  });

  final String name;
  final String address;
  final LatLng point;
}

class TomTomRoute {
  const TomTomRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.trafficDelaySeconds,
    required this.instructions,
  });

  final List<LatLng> points;
  final int distanceMeters;
  final int durationSeconds;
  final int trafficDelaySeconds;
  final List<TomTomInstruction> instructions;

  factory TomTomRoute.fromJson(Map<String, dynamic> json) {
    final routes = json['routes'] as List?;
    if (routes == null || routes.isEmpty || routes.first is! Map) {
      throw const TomTomException('TomTom returned no route for this trip.');
    }

    final route = (routes.first as Map).cast<String, dynamic>();
    final legs = route['legs'] as List? ?? const [];
    final points = <LatLng>[];
    for (final leg in legs.whereType<Map>()) {
      final legPoints = leg['points'] as List? ?? const [];
      for (final value in legPoints.whereType<Map>()) {
        final lat = _number(value['latitude']);
        final lng = _number(value['longitude']);
        if (lat != null && lng != null) points.add(LatLng(lat, lng));
      }
    }
    if (points.length < 2) {
      throw const TomTomException('TomTom returned an incomplete route.');
    }

    final summary = (route['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final guidance = (route['guidance'] as Map?)?.cast<String, dynamic>() ?? {};
    final instructionValues = guidance['instructions'] as List? ?? const [];
    final instructions = instructionValues
        .whereType<Map>()
        .map((value) {
          final instruction = value.cast<String, dynamic>();
          final point =
              (instruction['point'] as Map?) ??
              (instruction['maneuverPoint'] as Map?);
          final lat = _number(point?['latitude']);
          final lng = _number(point?['longitude']);
          return TomTomInstruction(
            message: instruction['message']?.toString() ?? '',
            point: lat == null || lng == null ? null : LatLng(lat, lng),
          );
        })
        .where((instruction) => instruction.message.isNotEmpty)
        .toList();

    final lengthMeters = _number(summary['lengthInMeters']);
    final liveDuration =
        _number(summary['liveTrafficIncidentsTravelTimeInSeconds']) ??
        _number(summary['travelTimeInSeconds']);
    if (lengthMeters == null ||
        lengthMeters <= 0 ||
        liveDuration == null ||
        liveDuration <= 0 ||
        instructions.isEmpty) {
      throw const TomTomException(
        'TomTom returned a route without usable distance, ETA, or directions.',
      );
    }
    return TomTomRoute(
      points: points,
      distanceMeters: lengthMeters.round(),
      durationSeconds: liveDuration.round(),
      trafficDelaySeconds: (_number(summary['trafficDelayInSeconds']) ?? 0)
          .round(),
      instructions: instructions,
    );
  }
}

class TomTomRoutingService {
  TomTomRoutingService({http.Client? client, String? apiKey})
    : _client = client ?? http.Client(),
      _apiKey = apiKey ?? TomTomRoutingService.apiKey;

  static const apiKey = String.fromEnvironment('TOMTOM_API_KEY');
  static const _routingEndpoint = 'api.tomtom.com';
  final http.Client _client;
  final String _apiKey;

  bool get isConfigured => _apiKey.trim().isNotEmpty;

  Future<List<TomTomSearchResult>> searchPlaces(String query) async {
    if (!isConfigured) {
      throw const TomTomException(
        'TomTom is not configured. Run with --dart-define=TOMTOM_API_KEY=<your-key>.',
      );
    }

    final uri = Uri(
      scheme: 'https',
      host: _routingEndpoint,
      pathSegments: ['search', '2', 'search', '$query.json'],
      queryParameters: {
        'key': _apiKey,
        'limit': '6',
        'countrySet': 'EG',
        'language': 'ar',
        'typeahead': 'true',
      },
    );
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw TomTomException(
        'TomTom place search failed (${response.statusCode}). Check the API key and connectivity.',
      );
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> || body['results'] is! List) {
      throw const TomTomException('TomTom returned invalid search results.');
    }
    return (body['results'] as List)
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .map((item) {
          final position = (item['position'] as Map?)?.cast<String, dynamic>();
          final lat = _number(position?['lat']);
          final lon = _number(position?['lon']);
          final address = ((item['address'] as Map?)?['freeformAddress'] ?? '')
              .toString();
          final poiName = (item['poi'] as Map?)?['name']?.toString();
          final name = poiName?.trim().isNotEmpty == true ? poiName! : address;
          if (lat == null || lon == null || name.trim().isEmpty) return null;
          return TomTomSearchResult(
            name: name,
            address: address,
            point: LatLng(lat, lon),
          );
        })
        .whereType<TomTomSearchResult>()
        .toList();
  }

  Future<TomTomRoute> calculateFastestRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (!isConfigured) {
      throw const TomTomException(
        'TomTom is not configured. Run with --dart-define=TOMTOM_API_KEY=<your-key>.',
      );
    }

    final path =
        '/routing/1/calculateRoute/'
        '${origin.latitude},${origin.longitude}:'
        '${destination.latitude},${destination.longitude}/json';
    final uri = Uri.https(_routingEndpoint, path, {
      'key': _apiKey,
      'traffic': 'true',
      'departAt': 'now',
      'routeType': 'fastest',
      'travelMode': 'car',
      'instructionsType': 'text',
      'language': 'ar',
      'computeTravelTimeFor': 'all',
      'routeRepresentation': 'polyline',
    });
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw TomTomException(
        'TomTom routing failed (${response.statusCode}). Check the API key and connectivity.',
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const TomTomException('TomTom returned an invalid route response.');
    }
    return TomTomRoute.fromJson(body);
  }

  void close() => _client.close();
}
